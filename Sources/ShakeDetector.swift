import AppKit
import Foundation

final class ShakeDetector {
    var onShakeDetected: ((NSPoint) -> Void)?
    var shouldSuppress: (() -> Bool)?

    private var timer: Timer?

    // Tuning constants
    private let pollInterval: TimeInterval = 1.0 / 35.0
    private let minSegmentTravel: CGFloat = 35.0
    private let maxReversalDotProduct: CGFloat = -0.35
    private let reversalWindow: TimeInterval = 0.6
    private let requiredReversals: Int = 3
    private let cooldownInterval: TimeInterval = 1.2

    // Tracking state
    private var anchorPoint: NSPoint?
    private var extremePoint: NSPoint?
    private var currentDirection: CGVector?
    private var reversalTimestamps: [TimeInterval] = []
    private var lastTriggerTime: TimeInterval = 0

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetTracking()
    }

    deinit {
        stop()
    }

    private func resetTracking() {
        anchorPoint = nil
        extremePoint = nil
        currentDirection = nil
        reversalTimestamps.removeAll(keepingCapacity: true)
    }

    private func poll() {
        guard Preferences.shared.shakeToOpenEnabled else {
            resetTracking()
            return
        }

        if shouldSuppress?() == true {
            resetTracking()
            return
        }

        // Only active while primary (left) mouse button is held down (bit 0)
        guard (NSEvent.pressedMouseButtons & 1) != 0 else {
            resetTracking()
            return
        }

        let current = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime

        // Prune stale reversals outside the sliding window
        reversalTimestamps.removeAll { now - $0 > reversalWindow }

        guard let anchor = anchorPoint else {
            anchorPoint = current
            extremePoint = current
            return
        }

        guard let dir = currentDirection, let extreme = extremePoint else {
            let dx = current.x - anchor.x
            let dy = current.y - anchor.y
            let dist = hypot(dx, dy)
            if dist >= minSegmentTravel {
                currentDirection = CGVector(dx: dx / dist, dy: dy / dist)
                extremePoint = current
            }
            return
        }

        let vx = current.x - extreme.x
        let vy = current.y - extreme.y
        let forwardProjection = vx * dir.dx + vy * dir.dy

        if forwardProjection > 0 {
            // Continuing forward along the established direction
            extremePoint = current
            return
        }

        let backDist = hypot(vx, vy)
        guard backDist >= minSegmentTravel else {
            return
        }

        let newDir = CGVector(dx: vx / backDist, dy: vy / backDist)
        let dot = dir.dx * newDir.dx + dir.dy * newDir.dy

        if dot <= maxReversalDotProduct {
            reversalTimestamps.append(now)
            currentDirection = newDir
            extremePoint = current

            if reversalTimestamps.count >= requiredReversals,
               now - lastTriggerTime >= cooldownInterval {
                lastTriggerTime = now
                resetTracking()
                onShakeDetected?(current)
            }
        } else if backDist >= minSegmentTravel * 1.5 {
            // Smooth curve or orthogonal drag: adopt new direction without counting a reversal
            currentDirection = newDir
            extremePoint = current
        }
    }
}
