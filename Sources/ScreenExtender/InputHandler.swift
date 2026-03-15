import Foundation
import CoreGraphics

struct TouchEvent: Decodable {
    let t: String   // "d"=down, "m"=move, "u"=up, "s"=scroll, "r"=right-click, "h"=hover
    let x: Double   // 0-1 normalized
    let y: Double   // 0-1 normalized
    let dx: Double? // scroll delta x
    let dy: Double? // scroll delta y
}

final class InputHandler: @unchecked Sendable {
    /// Bounds of the target display in global screen coordinates
    var displayBounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func handleTouch(_ event: TouchEvent) {
        // Map normalized (0-1) coords to global screen coordinates
        let screenX = displayBounds.origin.x + event.x * displayBounds.width
        let screenY = displayBounds.origin.y + event.y * displayBounds.height
        let point = CGPoint(x: screenX, y: screenY)

        switch event.t {
        case "d":
            moveMouse(to: point)
            postMouse(.leftMouseDown, at: point, button: .left)
        case "m":
            postMouse(.leftMouseDragged, at: point, button: .left)
        case "u":
            postMouse(.leftMouseUp, at: point, button: .left)
        case "h":
            moveMouse(to: point)
        case "r":
            moveMouse(to: point)
            postMouse(.rightMouseDown, at: point, button: .right)
            postMouse(.rightMouseUp, at: point, button: .right)
        case "s":
            postScroll(dx: event.dx ?? 0, dy: event.dy ?? 0)
        default:
            break
        }
    }

    private func moveMouse(to point: CGPoint) {
        guard let ev = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        ev.post(tap: .cghidEventTap)
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let ev = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }
        ev.post(tap: .cghidEventTap)
    }

    private func postScroll(dx: Double, dy: Double) {
        guard let ev = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) else { return }
        ev.post(tap: .cghidEventTap)
    }
}
