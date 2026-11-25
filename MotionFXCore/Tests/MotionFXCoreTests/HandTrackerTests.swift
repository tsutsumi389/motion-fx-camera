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
        // 握ったまま猶予（openGrace）より長く経つと、保持は 0 に戻る。
        var closed: TrackedHand?
        for index in 11...17 {
            closed = tracker.update(hands: [makeHand(wrist: wrist, shape: .fist)], at: Double(index) * frame)[0]
        }
        XCTAssertEqual(closed?.isOpen, false)
        XCTAssertEqual(closed?.stillOpenDuration, 0)
    }

    func testStillOpenDurationSurvivesOneFrameOfMissingFinger() {
        var tracker = HandTracker()
        let wrist = CGPoint(x: 100, y: 500)
        var last: TrackedHand?
        for index in 0...15 {
            var joints = makeHand(wrist: wrist).joints
            if index == 8 {
                // 小指の先端が 1 フレームだけ検出から落ちる。
                joints[.littleTip] = nil
            }
            last = tracker.update(hands: [HandPose(joints: joints)!], at: Double(index) * frame)[0]
        }
        XCTAssertEqual(last?.stillOpenDuration ?? 0, 0.5, accuracy: 0.001)
    }

    func testPinchResetsStillOpenDurationImmediately() {
        var tracker = HandTracker()
        let wrist = CGPoint(x: 100, y: 500)
        for index in 0...10 {
            _ = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)
        }
        let pinched = tracker.update(hands: [makeHand(wrist: wrist, shape: .pinch)], at: 11 * frame)[0]
        XCTAssertEqual(pinched.stillOpenDuration, 0)
    }

    func testSwipeIsDetectedAtLowFrameRate() {
        var tracker = HandTracker()
        var swipes: [SwipeDirection] = []
        // 約 8fps（1 フレーム 0.12 秒）。フレーム間隔が長いだけで、手は見失っていない。
        for index in 0...3 {
            let wrist = CGPoint(x: 100 + CGFloat(index) * 80, y: 500)
            let tracked = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * 0.12)[0]
            if let swipe = tracked.swipe { swipes.append(swipe) }
        }
        XCTAssertEqual(swipes, [.right])
    }

    func testStillOpenDurationSurvivesDetectionJitter() {
        var tracker = HandTracker()
        var last: TrackedHand?
        for index in 0...15 {
            // 1 フレームごとに 6pt（手の大きさの 6%）揺れる。
            let jitter: CGFloat = index.isMultiple(of: 2) ? 3 : -3
            let wrist = CGPoint(x: 100 + jitter, y: 500 - jitter)
            last = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)[0]
        }
        XCTAssertEqual(last?.stillOpenDuration ?? 0, 0.5, accuracy: 0.001)
    }

    func testSlowDriftIsNotStill() {
        var tracker = HandTracker()
        var last: TrackedHand?
        for index in 0...30 {
            // 毎秒 手 2 つ分の速さで動き続ける。
            let wrist = CGPoint(x: 100 + CGFloat(index) * 200 * CGFloat(frame), y: 500)
            last = tracker.update(hands: [makeHand(wrist: wrist)], at: Double(index) * frame)[0]
        }
        XCTAssertEqual(last?.stillOpenDuration, 0)
    }

    func testReleasingPinchAfterFastDragIsNotSwipe() {
        var tracker = HandTracker()
        var time = 0.0
        var wrist = CGPoint(x: 100, y: 500)
        for _ in 0...6 {
            _ = tracker.update(hands: [makeHand(wrist: wrist, shape: .pinch)], at: time)
            wrist.x += 34
            time += frame
        }
        // 離したあと、その場で手を開いたままにする。
        for _ in 0...6 {
            let tracked = tracker.update(hands: [makeHand(wrist: wrist)], at: time)[0]
            XCTAssertNil(tracked.swipe)
            time += frame
        }
    }

    func testFistMovingFastIsNotSwipe() {
        var tracker = HandTracker()
        for index in 0...6 {
            let wrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 500)
            let tracked = tracker.update(hands: [makeHand(wrist: wrist, shape: .fist)], at: Double(index) * frame)[0]
            XCTAssertNil(tracked.swipe)
        }
    }

    func testPositionJumpAfterDetectionGapIsNotSwipe() {
        var tracker = HandTracker()
        _ = tracker.update(hands: [makeHand(wrist: CGPoint(x: 100, y: 500))], at: 0)
        _ = tracker.update(hands: [makeHand(wrist: CGPoint(x: 100, y: 500))], at: frame)
        // 0.2 秒検出が途切れ（その間もフレームは来ている）、手 1.8 個分離れた場所で再検出される。
        _ = tracker.update(hands: [], at: frame + 0.1)
        let resumed = tracker.update(hands: [makeHand(wrist: CGPoint(x: 280, y: 500))], at: frame + 0.2)[0]
        XCTAssertNil(resumed.swipe)
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
