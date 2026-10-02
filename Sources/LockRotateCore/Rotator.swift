import Foundation

/// Pure playback logic: no UI, no I/O, randomness injected by the caller.
public struct Rotator: Sendable {
    public private(set) var state: RotationState

    public init(state: RotationState = RotationState()) {
        self.state = state
    }

    /// Returns nil for an empty list. State is reset whenever the list content or mode changed.
    public mutating func next(
        items: [String],
        mode: PlaybackMode,
        using rng: inout some RandomNumberGenerator
    ) -> String? {
        guard !items.isEmpty else {
            state = RotationState()
            return nil
        }

        let fingerprint = RotationState.fingerprint(of: items)
        if state.fingerprint != fingerprint
            || state.mode != mode
            || !state.isConsistent(mode: mode, count: items.count) {
            state = RotationState(fingerprint: fingerprint, mode: mode)
        }

        let index: Int
        switch mode {
        case .sequential:
            index = state.position
            state.position = (index + 1) % items.count
        case .random:
            if state.position >= state.order.count {
                state.order = Self.makeBag(count: items.count, avoidingFirst: state.order.last, using: &rng)
                state.position = 0
            }
            index = state.order[state.position]
            state.position += 1
        }

        let text = items[index]
        state.lastText = text
        return text
    }

    public mutating func next(items: [String], mode: PlaybackMode) -> String? {
        var rng = SystemRandomNumberGenerator()
        return next(items: items, mode: mode, using: &rng)
    }

    /// A fresh bag must not start with the item that ended the previous bag, or it would repeat back to back.
    static func makeBag(count: Int, avoidingFirst last: Int?, using rng: inout some RandomNumberGenerator) -> [Int] {
        var bag = Array(0..<count)
        bag.shuffle(using: &rng)
        if count > 1, let last, bag[0] == last {
            bag.swapAt(0, Int.random(in: 1..<count, using: &rng))
        }
        return bag
    }
}
