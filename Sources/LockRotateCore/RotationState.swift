import CryptoKit
import Foundation

public struct RotationState: Codable, Equatable, Sendable {
    /// Content hash of the list this state belongs to; nil before the first pick.
    public var fingerprint: String?
    public var mode: PlaybackMode?
    /// Random mode: the current shuffled bag (indices into the list). Empty in sequential mode.
    public var order: [Int]
    /// Sequential: index of the next item. Random: position of the next item inside `order`.
    public var position: Int
    public var lastText: String?

    public init(
        fingerprint: String? = nil,
        mode: PlaybackMode? = nil,
        order: [Int] = [],
        position: Int = 0,
        lastText: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.mode = mode
        self.order = order
        self.position = position
        self.lastText = lastText
    }

    /// First 16 hex chars of SHA256 over the items. Length-prefixed so ["ab","c"] != ["a","bc"].
    public static func fingerprint(of items: [String]) -> String {
        var hasher = SHA256()
        for item in items {
            let bytes = Data(item.utf8)
            withUnsafeBytes(of: UInt64(bytes.count).littleEndian) { hasher.update(bufferPointer: $0) }
            hasher.update(data: bytes)
        }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Guards against hand-edited or truncated state files that still carry a matching fingerprint.
    func isConsistent(mode: PlaybackMode, count: Int) -> Bool {
        switch mode {
        case .sequential:
            return order.isEmpty && (0..<count).contains(position)
        case .random:
            guard position >= 0, position <= order.count else { return false }
            return order.isEmpty || (order.count == count && Set(order) == Set(0..<count))
        }
    }
}
