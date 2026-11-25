import CoreGraphics
import XCTest
@testable import MotionFXCore

final class HandTrackerTests: XCTestCase {
    func testKeepsIdentityWhileHandMoves() {
        var tracker = HandTracker()
        let first = tracker.update(hands: [makeHand(wrist: CGPoint(x: 100, y: 500))], at: 0)
        let second = tracker.update(hands: [makeHand(wrist: CGPoint(x: 120, y: 510))], at: frame)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].id, second[0].id)
    }

    func testTwoHandsGetDistinctStableIdentities() {
        var tracker = HandTracker()
        let left = makeHand(wrist: CGPoint(x: 100, y: 500))
        let right = makeHand(wrist: CGPoint(x: 600, y: 500))
        let first = tracker.update(hands: [left, right], at: 0)
        // 検出順が入れ替わっても同じ手には同じ ID が付く。
        let second = tracker.update(hands: [right, left], at: frame)
        XCTAssertNotEqual(first[0].id, first[1].id)
        XCTAssertEqual(first[0].id, second[1].id)
        XCTAssertEqual(first[1].id, second[0].id)
    }

    func testHandReappearingAfterTimeoutGetsNewIdentity() {
        var tracker = HandTracker()
        let hand = makeHand(wrist: CGPoint(x: 100, y: 500))
        let first = tracker.update(hands: [hand], at: 0)
        _ = tracker.update(hands: [], at: 1.0)
        XCTAssertFalse(tracker.isTracking(first[0].id))
        let second = tracker.update(hands: [hand], at: 1.0 + frame)
        XCTAssertNotEqual(first[0].id, second[0].id)
    }

    func testTrackSurvivesBriefDetectionGap() {
        var tracker = HandTracker()
        let hand = makeHand(wrist: CGPoint(x: 100, y: 500))
        let first = tracker.update(hands: [hand], at: 0)
        _ = tracker.update(hands: [], at: frame)
        XCTAssertTrue(tracker.isTracking(first[0].id))
        let second = tracker.update(hands: [hand], at: frame * 2)
        XCTAssertEqual(first[0].id, second[0].id)
    }

    func testPinchUsesHysteresis() {
        var tracker = HandTracker()
        let wrist = CGPoint(x: 100, y: 500)
        func step(_ gap: CGFloat, _ index: Int) -> Bool {
            tracker.update(hands: [makeHand(wrist: wrist, shape: .pinch(gap: gap))], at: Double(index) * frame)[0].isPinching
        }
        // しきい値の中間（0.4）は直前の状態を維持する。
        XCTAssertFalse(step(0.4, 0))
        XCTAssertTrue(step(0.1, 1))
        XCTAssertTrue(step(0.4, 2))
        XCTAssertFalse(step(0.7, 3))
        XCTAssertFalse(step(0.4, 4))
    }

    func testStillOpenDurationAccumulatesWhileHandIsOpenAndStill() {
        var tracker = HandTracker()
        let hand = makeHand(wrist: CGPoint(x: 100, y: 500))
        var last: TrackedHand?
        for index in 0...15 {
            last = tracker.update(hands: [hand], at: Double(index) * frame)[0]
        }
        XCTAssertEqual(last?.isOpen, true)
        XCTAssertEqual(last?.stillOpenDuration ?? 0, 0.5, accuracy: 0.001)
    }

    func testStillOpenDurationResetsWhenHandCloses() {
        var tracker = HandTracker()
        let wrist = CGPoint(x: 100, y: 500)
        for index in 0...10 {
            _ = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)
        }
        let closed = tracker.update(hands: [makeHand(wrist: wrist, shape: .fist)], at: 11 * frame)[0]
        XCTAssertFalse(closed.isOpen)
        XCTAssertEqual(closed.stillOpenDuration, 0)
    }

    func testFastHorizontalMoveIsReportedAsSwipe() {
        var tracker = HandTracker()
        var swipes: [SwipeDirection] = []
        // 6 フレーム（0.2 秒）で手 2 つ分右へ動かす。
        for index in 0...6 {
            let wrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 500)
            let tracked = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)[0]
            if let swipe = tracked.swipe { swipes.append(swipe) }
        }
        XCTAssertEqual(swipes, [.right])
    }

    func testSlowMoveIsNotSwipe() {
        var tracker = HandTracker()
        for index in 0...60 {
            let wrist = CGPoint(x: 100 + CGFloat(index) * 4, y: 500)
            let tracked = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)[0]
            XCTAssertNil(tracked.swipe)
        }
    }

    func testVerticalMoveIsNotSwipe() {
        var tracker = HandTracker()
        for index in 0...6 {
            let wrist = CGPoint(x: 100, y: 200 + CGFloat(index) * 34)
            let tracked = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)[0]
            XCTAssertNil(tracked.swipe)
        }
    }

    func testPinchingHandDoesNotSwipe() {
        var tracker = HandTracker()
        for index in 0...6 {
            let wrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 500)
            let tracked = tracker.update(hands: [makeHand(wrist: wrist, shape: .pinch)], at: Double(index) * frame)[0]
            XCTAssertNil(tracked.swipe)
        }
    }
}
