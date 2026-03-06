import Foundation

struct CompareItem: Identifiable, Equatable {
    let id: UUID
    let originalURL: URL
    let convertedURL: URL

    var originalFilename: String { originalURL.lastPathComponent }
    var convertedFilename: String { convertedURL.lastPathComponent }

    init(from queueItem: QueueItem, outputURL: URL) {
        self.id = queueItem.id
        self.originalURL = queueItem.inputURL
        self.convertedURL = outputURL
    }
}
