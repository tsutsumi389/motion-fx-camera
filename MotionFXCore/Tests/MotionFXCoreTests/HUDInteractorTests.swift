import CoreGraphics
import XCTest
@testable import MotionFXCore

final class HUDInteractorTests: XCTestCase {
    private var interactor = HUDInteractor()
    private var time: Double = 0

    override func setUp() {
        interactor = HUDInteractor()
        time = 0
    }

    /// 同じ手の状態を `duration` 秒ぶん 30fps で流し、最後の状態を返す。
    @discardableResult
    private func hold(_ hands: [HandPose], for duration: Double = frame) -> HUDState {
        var state = interactor.update(hands: hands, at: time)
        let steps = max(1, Int((duration / frame).rounded()))
        for _ in 0..<steps {
            time += frame
            state = interactor.update(hands: hands, at: time)
        }
        return state
    }

    /// 手のひらを開いて静止し、パネルを出す。パネル中心を返す。
    private func summon(at wrist: CGPoint = CGPoint(x: 200, y: 600)) -> CGPoint {
        let state = hold([makeHand(wrist: wrist)], for: 0.6)
        return state.panel!.center
    }

    /// 親指と人差し指の中点が `point` に来るピンチの手。
    private func pinch(at point: CGPoint) -> HandPose {
        makeHand(wrist: CGPoint(x: point.x + 50, y: point.y + 120), shape: .pinch)
    }

    func testStartsHidden() {
        let state = interactor.update(hands: [], at: 0)
        XCTAssertNil(state.panel)
        XCTAssertEqual(state.phase, .hidden)
    }

    func testOpenPalmHeldStillSummonsPanelAbovePalm() {
        let hand = makeHand(wrist: CGPoint(x: 200, y: 600))
        let state = hold([hand], for: 0.6)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.panel?.scale, 1)
        XCTAssertEqual(state.panel!.center.x, hand.palmCenter.x, accuracy: 0.001)
        XCTAssertLessThan(state.panel!.center.y, hand.palmCenter.y)
    }

    func testOpenPalmShownBrieflyDoesNotSummon() {
        let state = hold([makeHand(wrist: CGPoint(x: 200, y: 600))], for: 0.2)
        XCTAssertNil(state.panel)
    }

    func testFistDoesNotSummon() {
        let state = hold([makeHand(wrist: CGPoint(x: 200, y: 600), shape: .fist)], for: 1.0)
        XCTAssertNil(state.panel)
    }

    func testPanelStaysAfterHandLeaves() {
        let center = summon()
        let state = hold([], for: 1.0)
        XCTAssertEqual(state.panel?.center, center)
        XCTAssertEqual(state.phase, .idle)
    }

    func testPinchOnPanelGrabsAndDragMovesIt() {
        let center = summon()
        hold([], for: 0.5)

        let grabbed = hold([pinch(at: center)])
        XCTAssertEqual(grabbed.phase, .grabbed)
        XCTAssertEqual(grabbed.panel!.center.x, center.x, accuracy: 0.001)

        let moved = hold([pinch(at: CGPoint(x: center.x + 20, y: center.y + 10))])
        XCTAssertEqual(moved.phase, .grabbed)
        XCTAssertEqual(moved.panel!.center.x, center.x + 20, accuracy: 0.001)
        XCTAssertEqual(moved.panel!.center.y, center.y + 10, accuracy: 0.001)
    }

    func testGrabKeepsOffsetBetweenPinchAndPanelCenter() {
        let center = summon()
        hold([], for: 0.5)
        let start = CGPoint(x: center.x + 60, y: center.y + 30)

        let grabbed = hold([pinch(at: start)])
        // 掴んだ瞬間にパネルが指へ飛びつかない。
        XCTAssertEqual(grabbed.panel!.center.x, center.x, accuracy: 0.001)
        XCTAssertEqual(grabbed.panel!.center.y, center.y, accuracy: 0.001)
    }

    func testReleasingPinchDropsPanelInPlace() {
        let center = summon()
        hold([], for: 0.5)
        hold([pinch(at: center)])
        let target = CGPoint(x: center.x + 30, y: center.y - 20)
        hold([pinch(at: target)])

        let released = hold([makeHand(wrist: CGPoint(x: target.x + 50, y: target.y + 120))])
        XCTAssertEqual(released.phase, .idle)
        XCTAssertEqual(released.panel!.center.x, target.x, accuracy: 0.001)
        XCTAssertEqual(released.panel!.center.y, target.y, accuracy: 0.001)
    }

    func testPinchAwayFromPanelDoesNotGrab() {
        let center = summon()
        hold([], for: 0.5)
        let state = hold([pinch(at: CGPoint(x: center.x + 400, y: center.y + 400))])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.panel?.center, center)
    }

    func testGrabSurvivesBriefDetectionGap() {
        let center = summon()
        hold([], for: 0.5)
        hold([pinch(at: center)])

        let gap = hold([], for: frame * 2)
        XCTAssertEqual(gap.phase, .grabbed)

        let resumed = hold([pinch(at: CGPoint(x: center.x + 10, y: center.y))])
        XCTAssertEqual(resumed.phase, .grabbed)
        XCTAssertEqual(resumed.panel!.center.x, center.x + 10, accuracy: 0.001)
    }

    func testGrabEndsWhenHandIsLost() {
        let center = summon()
        hold([], for: 0.5)
        hold([pinch(at: center)])
        let state = hold([], for: 1.0)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNotNil(state.panel)
    }

    func testTwoHandPinchSpreadScalesPanelUp() {
        let center = summon()
        hold([], for: 0.5)
        let y = center.y
        let started = hold([pinch(at: CGPoint(x: center.x - 100, y: y)), pinch(at: CGPoint(x: center.x + 100, y: y))])
        XCTAssertEqual(started.phase, .scaling)
        XCTAssertEqual(started.panel!.scale, 1, accuracy: 0.001)

        let spread = hold([pinch(at: CGPoint(x: center.x - 150, y: y)), pinch(at: CGPoint(x: center.x + 150, y: y))])
        XCTAssertEqual(spread.panel!.scale, 1.5, accuracy: 0.001)
        XCTAssertEqual(spread.panel!.center.x, center.x, accuracy: 0.001)
    }

    func testScaleIsClamped() {
        let center = summon()
        hold([], for: 0.5)
        let y = center.y
        hold([pinch(at: CGPoint(x: center.x - 20, y: y)), pinch(at: CGPoint(x: center.x + 20, y: y))])
        let huge = hold([pinch(at: CGPoint(x: center.x - 180, y: y)), pinch(at: CGPoint(x: center.x + 180, y: y))])
        XCTAssertEqual(huge.panel!.scale, interactor.config.maxScale, accuracy: 0.001)
    }

    func testReleasingOneHandWhileScalingContinuesAsGrab() {
        let center = summon()
        hold([], for: 0.5)
        let y = center.y
        let left = CGPoint(x: center.x - 100, y: y)
        let right = CGPoint(x: center.x + 100, y: y)
        hold([pinch(at: left), pinch(at: right)])
        hold([pinch(at: CGPoint(x: left.x - 50, y: y)), pinch(at: CGPoint(x: right.x + 50, y: y))])

        let oneHand = hold([pinch(at: CGPoint(x: left.x - 50, y: y))], for: 0.5)
        XCTAssertEqual(oneHand.phase, .grabbed)
        XCTAssertEqual(oneHand.panel!.scale, 1.5, accuracy: 0.001)
        XCTAssertEqual(oneHand.panel!.center.x, center.x, accuracy: 0.001)
    }

    func testSwipeDismissesPanel() {
        _ = summon()
        hold([], for: 0.5)
        var state = interactor.update(hands: [], at: time)
        for index in 0...6 {
            time += frame
            let wrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 600)
            state = interactor.update(hands: [makeHand(wrist: wrist)], at: time)
        }
        XCTAssertNil(state.panel)
        XCTAssertEqual(state.phase, .hidden)
    }

    func testPanelCannotBeSummonedDuringCooldownAfterDismiss() {
        _ = summon()
        hold([], for: 0.5)
        var lastWrist = CGPoint.zero
        for index in 0...6 {
            time += frame
            lastWrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 600)
            _ = interactor.update(hands: [makeHand(wrist: lastWrist)], at: time)
        }
        let duringCooldown = hold([makeHand(wrist: lastWrist)], for: 0.6)
        XCTAssertNil(duringCooldown.panel)

        let afterCooldown = hold([makeHand(wrist: lastWrist)], for: 1.0)
        XCTAssertNotNil(afterCooldown.panel)
    }

    func testHandRestingAfterSwipeDoesNotResummonUntilHeldAgainAfterCooldown() {
        _ = summon()
        hold([], for: 0.5)
        var lastWrist = CGPoint.zero
        var dismissedAt = 0.0
        for index in 0...6 {
            time += frame
            lastWrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 600)
            let state = interactor.update(hands: [makeHand(wrist: lastWrist)], at: time)
            if state.phase == .hidden, dismissedAt == 0 { dismissedAt = time }
        }
        // 払った手をそのまま止め続ける。クールダウンが明けた瞬間には出ない。
        let resting = makeHand(wrist: lastWrist)
        var state = HUDState()
        while time < dismissedAt + interactor.config.dismissCooldown + 0.2 {
            state = hold([resting])
        }
        XCTAssertNil(state.panel)

        // クールダウン明けからさらに止め続ければ出る。
        state = hold([resting], for: 0.5)
        XCTAssertNotNil(state.panel)
    }

    func testSummonProgressReachesOneExactlyWhenPanelAppears() {
        let hand = makeHand(wrist: CGPoint(x: 200, y: 600))
        let halfway = hold([hand], for: 0.2)
        XCTAssertNil(halfway.panel)
        XCTAssertEqual(halfway.summonProgress.values.first ?? 0, 0.5, accuracy: 0.001)

        let summoned = hold([hand], for: 0.3)
        XCTAssertNotNil(summoned.panel)
        XCTAssertTrue(summoned.summonProgress.isEmpty)
    }

    func testSummonProgressDoesNotFillDuringCooldown() {
        _ = summon()
        hold([], for: 0.5)
        var lastWrist = CGPoint.zero
        for index in 0...6 {
            time += frame
            lastWrist = CGPoint(x: 100 + CGFloat(index) * 34, y: 600)
            _ = interactor.update(hands: [makeHand(wrist: lastWrist)], at: time)
        }
        // 消した手を 0.7 秒止める。保持時間は足りているが、まだクールダウン中。
        let resting = hold([makeHand(wrist: lastWrist)], for: 0.7)
        XCTAssertNil(resting.panel)
        XCTAssertEqual(resting.summonProgress.values.first ?? 1, 0, accuracy: 0.001)
    }

    func testTwoHandPinchAwayFromPanelDoesNotScale() {
        let center = summon()
        hold([], for: 0.5)
        let far = CGPoint(x: center.x + 500, y: center.y + 500)
        hold([pinch(at: far), pinch(at: CGPoint(x: far.x + 200, y: far.y))])
        let state = hold([pinch(at: far), pinch(at: CGPoint(x: far.x + 400, y: far.y))])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.panel, HUDPanel(center: center, scale: 1))
    }

    func testGrabContinuesWhenHiddenFingersDropOut() {
        let center = summon()
        hold([], for: 0.5)
        hold([pinch(at: center)])

        var joints = pinch(at: CGPoint(x: center.x + 15, y: center.y)).joints
        for joint in [HandJoint.ringPIP, .ringTip, .littleMCP, .littlePIP, .littleTip] {
            joints[joint] = nil
        }
        let state = hold([HandPose(joints: joints)!], for: 0.5)
        XCTAssertEqual(state.phase, .grabbed)
        XCTAssertEqual(state.panel!.center.x, center.x + 15, accuracy: 0.001)
    }

    func testFastDragThenReleaseKeepsPanel() {
        let center = summon()
        hold([], for: 0.5)
        var state = hold([pinch(at: center)])
        var point = center
        for _ in 0..<6 {
            time += frame
            point.x += 34
            state = interactor.update(hands: [pinch(at: point)], at: time)
        }
        XCTAssertEqual(state.phase, .grabbed)

        // 離して、開いた手をその場に残す。
        state = hold([makeHand(wrist: CGPoint(x: point.x + 50, y: point.y + 120))], for: 0.5)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.panel!.center.x, point.x, accuracy: 0.001)
    }

    func testSwipeFarFromPanelDoesNotDismiss() {
        let center = summon()
        hold([], for: 0.5)
        var state = HUDState()
        for index in 0...6 {
            time += frame
            let wrist = CGPoint(x: 100 + CGFloat(index) * 34, y: center.y + 700)
            state = interactor.update(hands: [makeHand(wrist: wrist)], at: time)
        }
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNotNil(state.panel)
    }

    func testDistantPinchDoesNotTurnGrabIntoScaling() {
        let center = summon()
        hold([], for: 0.5)
        hold([pinch(at: center)])
        let far = CGPoint(x: center.x + 600, y: center.y + 600)

        let state = hold([pinch(at: CGPoint(x: center.x + 10, y: center.y)), pinch(at: far)])
        XCTAssertEqual(state.phase, .grabbed)
        XCTAssertEqual(state.panel!.scale, 1)
        XCTAssertEqual(state.panel!.center.x, center.x + 10, accuracy: 0.001)
    }

    func testScaleRespondsImmediatelyAfterOvershootingLimit() {
        let center = summon()
        hold([], for: 0.5)
        let y = center.y
        func hands(_ half: CGFloat) -> [HandPose] {
            [pinch(at: CGPoint(x: center.x - half, y: y)), pinch(at: CGPoint(x: center.x + half, y: y))]
        }
        hold(hands(50))
        // 上限（2.5 倍 = 間隔 250）を大きく超えて 360 まで広げる。
        for half in stride(from: CGFloat(70), through: 180, by: 20) {
            hold(hands(half))
        }
        XCTAssertEqual(interactor.update(hands: hands(180), at: time).panel!.scale, interactor.config.maxScale, accuracy: 0.001)

        // 少し戻しただけで、すぐ小さくなり始める。
        let shrunk = hold(hands(162))
        XCTAssertEqual(shrunk.panel!.scale, interactor.config.maxScale * 0.9, accuracy: 0.001)
    }

    func testPanelCenterIsClampedToBounds() {
        interactor.bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        let center = summon(at: CGPoint(x: 200, y: 600))
        hold([], for: 0.5)
        hold([pinch(at: center)])
        // 1 フレームで飛ばすと別の手と判定されるので、少しずつ画面外まで引っ張る。
        var dragged = HUDState()
        for step in 1...9 {
            let delta = CGFloat(step) * 100
            dragged = hold([pinch(at: CGPoint(x: center.x + delta, y: center.y - delta))])
        }
        XCTAssertEqual(dragged.phase, .grabbed)
        XCTAssertEqual(dragged.panel!.center.x, 400, accuracy: 0.001)
        XCTAssertEqual(dragged.panel!.center.y, 0, accuracy: 0.001)
    }

    func testStateReportsTrackedHands() {
        let state = hold([makeHand(wrist: CGPoint(x: 100, y: 500)), makeHand(wrist: CGPoint(x: 600, y: 500), shape: .pinch)])
        XCTAssertEqual(state.hands.count, 2)
        XCTAssertEqual(state.hands.filter(\.isPinching).count, 1)
    }

    func testResetHidesPanel() {
        _ = summon()
        interactor.reset()
        let state = interactor.update(hands: [], at: time + frame)
        XCTAssertNil(state.panel)
        XCTAssertEqual(state.phase, .hidden)
    }
}
