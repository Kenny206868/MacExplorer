import AppKit

/// The source application owns materialization. The inbox owns validation,
/// cancellation policy and installation; those stages can be tested separately
/// from WindowServer's live drag-and-drop transport.
@MainActor protocol PromisedFileSource: AnyObject {
    var expectedCount: Int { get }
    func receive(into directory: URL, queue: OperationQueue,
                 completion: @escaping @Sendable (URL, String?) -> Void)
}

@MainActor final class AppKitPromiseSource: PromisedFileSource {
    private let receiver: NSFilePromiseReceiver
    init(_ receiver: NSFilePromiseReceiver) { self.receiver = receiver }
    var expectedCount: Int { max(1, max(receiver.fileTypes.count, receiver.fileNames.count)) }
    func receive(into directory: URL, queue: OperationQueue,
                 completion: @escaping @Sendable (URL, String?) -> Void) {
        receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { url, error in
            completion(url, error?.localizedDescription)
        }
    }
}
