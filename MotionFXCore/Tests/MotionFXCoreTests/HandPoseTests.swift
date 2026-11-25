import CoreGraphics
import XCTest
@testable import MotionFXCore

final class HandPoseTests: XCTestCase {
    func testInitFailsWhenRequiredJointIsMissing() {
        var joints = makeHand(wrist: .zero).joints
        joints[.indexTip] = nil
        XCTAssertNil(HandPose(joints: joints))
    }

    func testInitSucceedsWithoutOptionalJoints() {
        var joints = makeHand(wrist: .zero).joints
        joints[.thumbCMC] = nil
        joints[.ringDIP] = nil
        XCTAssertNotNil(HandPose(joints: joints))
    }

    func testPinchWithHiddenFingersIsStillUsable() {
        var joints = makeHand(wrist: CGPoint(x: 100, y: 500), shape: .pinch).joints
        for joint in [HandJoint.ringPIP, .ringTip, .littleMCP, .littlePIP, .littleTip, .indexMCP] {
            joints[joint] = nil
        }
        let hand = HandPose(joints: joints)
        XCTAssertNotNil(hand)
        XCTAssertEqual(hand?.pinchRatio ?? 1, 0.1, accuracy: 0.001)
        XCTAssertEqual(hand?.areFingersExtended(ratio: 1.1), false)
    }

    func testOpenHandWithMissingFingerIsNotTreatedAsOpen() {
        var joints = makeHand(wrist: .zero, shape: .open).joints
        joints[.littleTip] = nil
        XCTAssertEqual(HandPose(joints: joints)?.areFingersExtended(ratio: 1.1), false)
    }

    func testHandSizeIsWristToMiddleKnuckle() {
        let hand = makeHand(wrist: CGPoint(x: 50, y: 400), size: 80)
        XCTAssertEqual(hand.handSize, 80, accuracy: 0.001)
    }

    func testPinchRatioIsIndependentOfHandSize() {
        let small = makeHand(wrist: .zero, size: 40, shape: .pinch(gap: 0.2))
        let large = makeHand(wrist: .zero, size: 200, shape: .pinch(gap: 0.2))
        XCTAssertEqual(small.pinchRatio, 0.2, accuracy: 0.001)
        XCTAssertEqual(large.pinchRatio, 0.2, accuracy: 0.001)
    }

    func testPinchPointIsBetweenThumbAndIndexTips() {
        let hand = makeHand(wrist: CGPoint(x: 100, y: 500), size: 100, shape: .pinch(gap: 0.1))
        XCTAssertEqual(hand.pinchPoint.x, 50, accuracy: 0.001)
        XCTAssertEqual(hand.pinchPoint.y, 380, accuracy: 0.001)
    }

    func testOpenHandHasExtendedFingers() {
        XCTAssertTrue(makeHand(wrist: .zero, shape: .open).areFingersExtended(ratio: 1.1))
    }

    func testFistDoesNotHaveExtendedFingers() {
        XCTAssertFalse(makeHand(wrist: .zero, shape: .fist).areFingersExtended(ratio: 1.1))
    }

    func testPinchDoesNotHaveExtendedFingers() {
        XCTAssertFalse(makeHand(wrist: .zero, shape: .pinch).areFingersExtended(ratio: 1.1))
    }
}
