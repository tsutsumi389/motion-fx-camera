import CoreGraphics
import Foundation

public enum SwipeDirection: Equatable, Sendable {
    case left, right
}

/// フレームをまたいで同一と判定された手と、その時点のジェスチャー状態。
public struct TrackedHand: Equatable, Sendable, Identifiable {
    public let id: Int
    public let pose: HandPose
    public let isPinching: Bool
    /// 指を伸ばして開いている（ピンチ中は false）。
    public let isOpen: Bool
    /// 開いたまま静止し続けている秒数。
    public let stillOpenDuration: TimeInterval
    /// このフレームで成立したスワイプ。成立した 1 フレームだけ値が入る。
    public let swipe: SwipeDirection?
}

/// 検出された手に安定した ID を割り当て、ピンチ・静止・スワイプを判定する。
public struct HandTracker: Sendable {
    private struct Sample: Sendable {
        let time: TimeInterval
        let point: CGPoint
    }

    private struct Track: Sendable {
        let id: Int
        var pose: HandPose
        var lastSeen: TimeInterval
        var isPinching = false
        /// 静止判定用。直近 `stillWindow` 秒ぶんの手のひらの位置。
        var recent: [Sample] = []
        /// スワイプ判定用。手を開いたまま途切れずに動いた軌跡だけを持つ。
        var swipePath: [Sample] = []
        var openStillSince: TimeInterval?
    }

    public let config: GestureConfig
    private var tracks: [Track] = []
    private var nextID = 0

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    /// 検出が途切れていても、タイムアウト前ならまだ同じ手として待っている。
    public func isTracking(_ id: Int) -> Bool {
        tracks.contains { $0.id == id }
    }

    public mutating func reset() {
        tracks.removeAll()
    }

    public mutating func update(hands: [HandPose], at time: TimeInterval) -> [TrackedHand] {
        tracks.removeAll { time - $0.lastSeen > config.trackTimeout }

        let assignment = matchTracks(to: hands)
        return hands.enumerated().map { index, pose in
            let trackIndex: Int
            if let existing = assignment[index] {
                trackIndex = existing
            } else {
                tracks.append(Track(id: nextID, pose: pose, lastSeen: time))
                nextID += 1
                trackIndex = tracks.count - 1
            }
            return advance(trackIndex: trackIndex, pose: pose, time: time)
        }
    }

    /// 手首が近い順に、既存トラックと検出結果を 1 対 1 で対応付ける。
    private func matchTracks(to hands: [HandPose]) -> [Int: Int] {
        var pairs: [(distance: CGFloat, track: Int, hand: Int)] = []
        for (trackIndex, track) in tracks.enumerated() {
            for (handIndex, hand) in hands.enumerated() {
                let distance = track.pose.wrist.distance(to: hand.wrist)
                let limit = config.matchDistance * max(track.pose.handSize, hand.handSize)
                if distance <= limit {
                    pairs.append((distance, trackIndex, handIndex))
                }
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var trackForHand: [Int: Int] = [:]
        var usedTracks: Set<Int> = []
        for pair in pairs where trackForHand[pair.hand] == nil && !usedTracks.contains(pair.track) {
            trackForHand[pair.hand] = pair.track
            usedTracks.insert(pair.track)
        }
        return trackForHand
    }

    private mutating func advance(trackIndex: Int, pose: HandPose, time: TimeInterval) -> TrackedHand {
        var track = tracks[trackIndex]
        let handSize = pose.handSize
        let palm = pose.palmCenter

        let ratio = pose.pinchRatio
        if track.isPinching {
            if ratio > config.pinchEndRatio { track.isPinching = false }
        } else if ratio < config.pinchStartRatio {
            track.isPinching = true
        }
        let isOpen = !track.isPinching && pose.areFingersExtended(ratio: config.fingerExtensionRatio)

        let sample = Sample(time: time, point: palm)
        let gap = time - track.lastSeen

        track.recent.append(sample)
        track.recent.removeAll { time - $0.time > config.stillWindow }
        let stillRadius = config.stillRadius * handSize
        let isStill = track.recent.allSatisfy { $0.point.distance(to: palm) <= stillRadius }
        if isOpen && isStill {
            track.openStillSince = track.openStillSince ?? time
        } else {
            track.openStillSince = nil
        }

        // スワイプは「開いた手が途切れずに動いた区間」だけで判定する。
        // つまんでドラッグした動きや、検出が途切れたあとの位置飛びを数えると、
        // パネルを置いた直後に「払った」と誤判定して消してしまう。
        var swipe: SwipeDirection?
        if isOpen {
            if gap > config.swipeMaxGap {
                track.swipePath.removeAll()
            }
            track.swipePath.append(sample)
            track.swipePath.removeAll { time - $0.time > config.swipeWindow }
            if let first = track.swipePath.first, time - first.time >= config.swipeMinDuration {
                let dx = palm.x - first.point.x
                let dy = palm.y - first.point.y
                if abs(dx) >= config.swipeDistance * handSize && abs(dx) >= 2 * abs(dy) {
                    swipe = dx > 0 ? .right : .left
                    // 同じ動きで連続して成立しないよう、軌跡を現在位置からやり直す。
                    track.swipePath = [sample]
                }
            }
        } else {
            track.swipePath.removeAll()
        }

        track.pose = pose
        track.lastSeen = time
        tracks[trackIndex] = track

        return TrackedHand(
            id: track.id,
            pose: pose,
            isPinching: track.isPinching,
            isOpen: isOpen,
            stillOpenDuration: track.openStillSince.map { time - $0 } ?? 0,
            swipe: swipe
        )
    }
}
