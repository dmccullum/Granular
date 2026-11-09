import Testing
@testable import GranularCore

@Test func detentIsCrossedFromEitherSide() {
    #expect(SliderDetent.crosses(from: -0.2, to: 0.1, detent: 0))
    #expect(SliderDetent.crosses(from: 0.2, to: -0.1, detent: 0))
}

@Test func landingOnADetentCounts() {
    #expect(SliderDetent.crosses(from: 0.3, to: 0, detent: 0))
    #expect(SliderDetent.crosses(from: 0.9, to: 1, detent: 1))
}

@Test func leavingOrRestingOnADetentDoesNotCount() {
    #expect(!SliderDetent.crosses(from: 0, to: 0.4, detent: 0))
    #expect(!SliderDetent.crosses(from: 0, to: 0, detent: 0))
    #expect(!SliderDetent.crosses(from: 1, to: 1, detent: 1))
}

@Test func movingOnOneSideOfADetentDoesNotCount() {
    #expect(!SliderDetent.crosses(from: 0.2, to: 0.6, detent: 0))
    #expect(!SliderDetent.crosses(from: -0.6, to: -0.2, detent: 0))
}

@Test func anyOfSeveralDetentsCounts() {
    #expect(SliderDetent.crossesAny(from: 0.4, to: 1, detents: [0, -1, 1]))
    #expect(!SliderDetent.crossesAny(from: 0.4, to: 0.8, detents: [0, -1, 1]))
}
