import Foundation
import Testing
@testable import LockRotateCore

struct RotatorTests {
    let items = ["a", "b", "c", "d", "e"]

    private func draw(_ rotator: inout Rotator, _ items: [String], _ mode: PlaybackMode, _ n: Int, rng: inout SplitMix64) -> [String] {
        (0..<n).compactMap { _ in rotator.next(items: items, mode: mode, using: &rng) }
    }

    @Test func sequentialCycles() {
        var rng = SplitMix64(seed: 1)
        var rotator = Rotator()
        let out = draw(&rotator, items, .sequential, 12, rng: &rng)
        #expect(out == ["a", "b", "c", "d", "e", "a", "b", "c", "d", "e", "a", "b"])
    }

    @Test func emptyListReturnsNil() {
        var rng = SplitMix64(seed: 1)
        var rotator = Rotator()
        #expect(rotator.next(items: [], mode: .sequential, using: &rng) == nil)
        #expect(rotator.next(items: [], mode: .random, using: &rng) == nil)
        #expect(rotator.state == RotationState())
    }

    @Test func singleItemAlwaysReturned() {
        var rng = SplitMix64(seed: 1)
        for mode in PlaybackMode.allCases {
            var rotator = Rotator()
            for _ in 0..<10 {
                #expect(rotator.next(items: ["only"], mode: mode, using: &rng) == "only")
            }
        }
    }

    @Test func randomBagHasNoRepeatsWithinRound() {
        var rng = SplitMix64(seed: 42)
        var rotator = Rotator()
        for _ in 0..<50 {
            let round = draw(&rotator, items, .random, items.count, rng: &rng)
            #expect(Set(round) == Set(items))
            #expect(round.count == items.count)
        }
    }

    @Test(arguments: [2, 3, 5, 8])
    func randomNeverRepeatsConsecutivelyAcrossRounds(count: Int) {
        let list = (0..<count).map(String.init)
        for seed in UInt64(0)..<40 {
            var rng = SplitMix64(seed: seed)
            var rotator = Rotator()
            let out = draw(&rotator, list, .random, count * 30, rng: &rng)
            for (x, y) in zip(out, out.dropFirst()) {
                #expect(x != y, "seed \(seed) count \(count)")
            }
        }
    }

    @Test func randomIsReproducibleWithSameSeed() {
        var r1 = SplitMix64(seed: 7), r2 = SplitMix64(seed: 7)
        var a = Rotator(), b = Rotator()
        #expect(draw(&a, items, .random, 20, rng: &r1) == draw(&b, items, .random, 20, rng: &r2))
    }

    @Test func randomActuallyShuffles() {
        var rng = SplitMix64(seed: 3)
        var rotator = Rotator()
        let rounds = (0..<10).map { _ in draw(&rotator, items, .random, items.count, rng: &rng) }
        #expect(Set(rounds).count > 1)
        #expect(rounds.contains { $0 != items })
    }

    @Test func listChangeResetsSequentialState() {
        var rng = SplitMix64(seed: 1)
        var rotator = Rotator()
        _ = draw(&rotator, items, .sequential, 3, rng: &rng)
        let changed = ["x", "y", "z"]
        #expect(rotator.next(items: changed, mode: .sequential, using: &rng) == "x")
        #expect(rotator.state.fingerprint == RotationState.fingerprint(of: changed))
    }

    @Test func listChangeResetsRandomBag() {
        var rng = SplitMix64(seed: 1)
        var rotator = Rotator()
        _ = draw(&rotator, items, .random, 2, rng: &rng)
        let changed = ["x", "y", "z"]
        let round = draw(&rotator, changed, .random, 3, rng: &rng)
        #expect(Set(round) == Set(changed))
    }

    @Test func reorderingItemsCountsAsListChange() {
        #expect(RotationState.fingerprint(of: ["a", "b"]) != RotationState.fingerprint(of: ["b", "a"]))
    }

    @Test func modeSwitchResets() {
        var rng = SplitMix64(seed: 1)
        var rotator = Rotator()
        _ = draw(&rotator, items, .sequential, 3, rng: &rng)
        _ = rotator.next(items: items, mode: .random, using: &rng)
        #expect(rotator.state.mode == .random)
        #expect(rotator.state.order.count == items.count)
        #expect(rotator.state.position == 1)

        _ = draw(&rotator, items, .random, 2, rng: &rng)
        // Back to sequential starts from the beginning again.
        #expect(rotator.next(items: items, mode: .sequential, using: &rng) == "a")
        #expect(rotator.state.order.isEmpty)
    }

    @Test func stateTracksLastTextAndRoundTripsThroughCodable() throws {
        var rng = SplitMix64(seed: 9)
        var rotator = Rotator()
        let first = rotator.next(items: items, mode: .random, using: &rng)
        #expect(rotator.state.lastText == first)

        let data = try JSONEncoder().encode(rotator.state)
        let restored = try JSONDecoder().decode(RotationState.self, from: data)
        #expect(restored == rotator.state)

        var resumed = Rotator(state: restored)
        var rngA = SplitMix64(seed: 100), rngB = SplitMix64(seed: 100)
        #expect(draw(&resumed, items, .random, 8, rng: &rngA) == draw(&rotator, items, .random, 8, rng: &rngB))
    }

    @Test func resumedSequentialContinuesWhereItStopped() {
        var rng = SplitMix64(seed: 1)
        var rotator = Rotator()
        _ = draw(&rotator, items, .sequential, 2, rng: &rng)
        var resumed = Rotator(state: rotator.state)
        #expect(resumed.next(items: items, mode: .sequential, using: &rng) == "c")
    }

    @Test func inconsistentStateWithMatchingFingerprintIsReset() {
        var rng = SplitMix64(seed: 1)
        let bad = RotationState(
            fingerprint: RotationState.fingerprint(of: items),
            mode: .sequential,
            order: [],
            position: 99
        )
        var rotator = Rotator(state: bad)
        #expect(rotator.next(items: items, mode: .sequential, using: &rng) == "a")

        let badBag = RotationState(
            fingerprint: RotationState.fingerprint(of: items),
            mode: .random,
            order: [0, 0, 1],
            position: 1
        )
        var r2 = Rotator(state: badBag)
        let round = draw(&r2, items, .random, items.count, rng: &rng)
        #expect(Set(round) == Set(items))
    }

    @Test func fingerprintFormat() {
        let fp = RotationState.fingerprint(of: ["hello"])
        #expect(fp.count == 16)
        #expect(fp.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(RotationState.fingerprint(of: ["ab", "c"]) != RotationState.fingerprint(of: ["a", "bc"]))
        #expect(RotationState.fingerprint(of: ["hello"]) == fp)
    }

    @Test func playbackModeRawValuesAreStable() throws {
        #expect(PlaybackMode.sequential.rawValue == "sequential")
        #expect(PlaybackMode.random.rawValue == "random")
        #expect(try JSONDecoder().decode(PlaybackMode.self, from: Data(#""random""#.utf8)) == .random)
    }

    @Test func systemRNGOverloadWorks() {
        var rotator = Rotator()
        #expect(rotator.next(items: items, mode: .random) != nil)
        #expect(rotator.next(items: [], mode: .random) == nil)
    }
}
