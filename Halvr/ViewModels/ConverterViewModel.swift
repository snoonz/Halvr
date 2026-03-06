import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ConverterViewModel {
    private(set) var queueItems: [QueueItem] = []
    private(set) var isProcessing = false
    var settings: ConversionSettings = .load()
    var compareItem: CompareItem?

    private let converter: any VideoConverting
    private let metadataReader: any VideoMetadataReading
    private var isCancelled = false

    init(
        converter: any VideoConverting = FFmpegConverter(),
        metadataReader: any VideoMetadataReading = VideoMetadataReader()
    ) {
        self.converter = converter
        self.metadataReader = metadataReader
    }

    // MARK: - Public

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        let typeIdentifier = UTType.fileURL.identifier

        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadURL(from: provider, typeIdentifier: typeIdentifier) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            addToQueue(urls: urls)
        }

        return true
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SupportedFormats.inputTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }

        addToQueue(urls: urls)
    }

    func cancelConversion() {
        isCancelled = true
        converter.cancel()

        let cancelError = ErrorInfo(title: String(localized: "Cancel"), message: String(localized: "Cancelled by user."))
        queueItems = queueItems.map { item in
            switch item.status {
            case .pending, .converting:
                return item.with(status: .skipped(cancelError))
            case .completed, .skipped:
                return item
            }
        }
    }

    func removeItem(id: UUID) {
        queueItems = queueItems.filter { $0.id != id }
    }

    func clearCompleted() {
        queueItems = queueItems.filter { item in
            switch item.status {
            case .pending, .converting:
                return true
            case .completed, .skipped:
                return false
            }
        }
    }

    func reset() {
        queueItems = []
        isProcessing = false
        isCancelled = false
    }

    func revealInFinder(urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func requestCompare(for item: QueueItem) {
        guard case .completed(let outputURL) = item.status else { return }
        compareItem = CompareItem(from: item, outputURL: outputURL)
    }

    // MARK: - Private

    private func addToQueue(urls: [URL]) {
        let validURLs = urls.filter { SupportedFormats.isSupported($0) }
        let unsupportedURLs = urls.filter { !SupportedFormats.isSupported($0) }

        let newItems = validURLs.map { QueueItem(inputURL: $0) }
        let skippedItems = unsupportedURLs.map {
            QueueItem(inputURL: $0, status: .skipped(ErrorInfo(
                title: String(localized: "Unsupported Format"),
                message: String(localized: "\($0.pathExtension.uppercased()) format is not supported.")
            )))
        }
        queueItems = queueItems + newItems + skippedItems

        if !isProcessing {
            Task {
                await processNext()
            }
        }
    }

    private func loadURL(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    private func processNext() async {
        isProcessing = true
        isCancelled = false

        while let index = queueItems.firstIndex(where: { $0.status == .pending }) {
            guard !isCancelled else { break }

            let item = queueItems[index]
            let itemId = item.id

            updateItemStatus(id: itemId, status: .converting(progress: 0))

            let result = await readMetadata(for: item)

            if let errorInfo = result.error {
                updateItemStatus(id: itemId, status: .skipped(errorInfo))
                continue
            }

            guard let meta = result.metadata else { continue }

            if meta.isAlreadyHEVC {
                updateItemStatus(id: itemId, status: .skipped(ErrorInfo(
                    title: String(localized: "Conversion Not Needed"),
                    message: String(localized: "Already encoded in HEVC.")
                )))
                continue
            }

            await convertItem(item, metadata: meta)
        }

        isProcessing = false
    }

    private func readMetadata(
        for item: QueueItem
    ) async -> (metadata: VideoMetadata?, error: ErrorInfo?) {
        do {
            let metadata = try await metadataReader.read(from: item.inputURL)
            return (metadata, nil)
        } catch {
            return (nil, ErrorInfo(
                title: String(localized: "Load Failed"),
                message: error.localizedDescription
            ))
        }
    }

    private func convertItem(_ item: QueueItem, metadata: VideoMetadata) async {
        let itemId = item.id
        let outputURL = OutputPathResolver.resolve(
            inputURL: item.inputURL,
            outputDirectory: settings.outputDirectory
        )

        do {
            let result = try await converter.convert(
                inputURL: item.inputURL,
                outputURL: outputURL,
                settings: settings,
                metadata: metadata,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateItemStatus(id: itemId, status: .converting(progress: progress))
                    }
                }
            )
            if settings.preserveTimestamp {
                copyTimestamp(from: item.inputURL, to: result)
            }
            updateItemStatus(id: itemId, status: .completed(outputURL: result))
        } catch let error as ConversionError {
            updateItemStatus(id: itemId, status: .skipped(ErrorInfo(
                title: String(localized: "Conversion Failed"),
                message: error.errorDescription ?? String(localized: "Unknown error")
            )))
        } catch {
            updateItemStatus(id: itemId, status: .skipped(ErrorInfo(
                title: String(localized: "Conversion Failed"),
                message: error.localizedDescription
            )))
        }
    }

    private func copyTimestamp(from sourceURL: URL, to destinationURL: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            var newAttributes: [FileAttributeKey: Any] = [:]
            if let creationDate = attributes[.creationDate] {
                newAttributes[.creationDate] = creationDate
            }
            if let modificationDate = attributes[.modificationDate] {
                newAttributes[.modificationDate] = modificationDate
            }
            if !newAttributes.isEmpty {
                try FileManager.default.setAttributes(newAttributes, ofItemAtPath: destinationURL.path)
            }
        } catch {
            // Timestamp preservation is best-effort; do not fail conversion
        }
    }

    private func updateItemStatus(id: UUID, status: QueueItemStatus) {
        queueItems = queueItems.map { item in
            guard item.id == id else { return item }
            return item.with(status: status)
        }
    }
}
