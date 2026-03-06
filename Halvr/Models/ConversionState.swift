import Foundation

struct QueueItem: Identifiable, Equatable {
    let id: UUID
    let inputURL: URL
    let status: QueueItemStatus

    var filename: String { inputURL.lastPathComponent }

    init(id: UUID = UUID(), inputURL: URL, status: QueueItemStatus = .pending) {
        self.id = id
        self.inputURL = inputURL
        self.status = status
    }

    func with(status: QueueItemStatus) -> QueueItem {
        QueueItem(id: id, inputURL: inputURL, status: status)
    }
}

enum QueueItemStatus: Equatable {
    case pending
    case converting(progress: Double)
    case completed(outputURL: URL)
    case skipped(ErrorInfo)
}

struct ErrorInfo: Equatable {
    let title: String
    let message: String
}
