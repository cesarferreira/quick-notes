import AppKit

private final class RequestReceipt: NSObject {
    var received = false
    @objc func acknowledge(_ notification: Notification) { received = true }
}

enum AppRequest {
    case show, toggle
    static let acknowledgement = Notification.Name("dev.cesar.quicknotes.acknowledge")

    init(arguments: [String]) {
        self = arguments.contains("--toggle") ? .toggle : .show
    }

    var notificationName: Notification.Name {
        Notification.Name(self == .toggle ? "dev.cesar.quicknotes.toggle" : "dev.cesar.quicknotes.show")
    }

    @discardableResult func send() -> Bool {
        let center = DistributedNotificationCenter.default()
        let id = UUID().uuidString
        let receipt = RequestReceipt()
        center.addObserver(receipt, selector: #selector(RequestReceipt.acknowledge(_:)),
            name: Self.acknowledgement, object: id)
        defer { center.removeObserver(receipt) }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            center.postNotificationName(notificationName, object: nil,
                userInfo: ["requestID": id], deliverImmediately: true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while !receipt.received && Date() < deadline
        return receipt.received
    }
}
