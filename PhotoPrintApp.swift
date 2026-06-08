import SwiftUI
import AppKit

@main
struct PhotoPrintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup: the main window is created manually (borderless) in the
        // AppDelegate. Settings provides a no-op scene so the App has a Scene but
        // doesn't spawn its own window at launch.
        Settings { EmptyView() }
    }
}

/// Holds a weak reference to the app window so SwiftUI controls (custom traffic
/// lights) can drive close/minimize/zoom.
final class WindowRef: ObservableObject {
    static let shared = WindowRef()
    weak var window: NSWindow?
}

/// A borderless window that can still become key/main so text fields and
/// controls work normally. Born borderless — no native frame border ever exists,
/// so we fully own the window shape (custom corner radius, no double border).
final class LiquidGlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: LiquidGlassWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let win = LiquidGlassWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovable = true                 // required for WindowDragArea drag regions
        win.isMovableByWindowBackground = false
        win.minSize = NSSize(width: 1100, height: 700)
        win.center()

        // Container holds the SwiftUI content plus an edge-resize overlay, clipped
        // to a continuous corner radius matching the native Tahoe window shape.
        let container = NSView(frame: win.frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = 27
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: ContentView())
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        // Borderless windows have no native resize edges; this overlay adds them.
        let resizer = BorderlessResizeView(frame: container.bounds)
        resizer.autoresizingMask = [.width, .height]
        container.addSubview(resizer)

        win.contentView = container

        win.makeKeyAndOrderFront(nil)
        win.invalidateShadow()

        WindowRef.shared.window = win
        self.window = win

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Transparent overlay that adds edge/corner resize behavior to a borderless
/// window. It only intercepts clicks within `margin` of an edge; everything
/// else passes through to the SwiftUI content beneath it.
final class BorderlessResizeView: NSView {
    private let margin: CGFloat = 10
    var cornerRadius: CGFloat = 27

    private enum Edge {
        case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    }

    private var activeEdge: Edge?
    private var initialFrame: NSRect = .zero
    private var initialMouse: NSPoint = .zero
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    // Pass through unless near an edge.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return edge(at: local) != nil ? self : nil
    }

    private func edge(at p: NSPoint) -> Edge? {
        guard bounds.contains(p) else { return nil }

        let w = bounds.width
        let h = bounds.height
        let r = cornerRadius

        // 1. Check corner regions (dist is distance from corner center of the arc)
        if p.x < r && p.y < r {
            // Bottom-Left
            let dx = p.x - r
            let dy = p.y - r
            let dist = sqrt(dx*dx + dy*dy)
            if dist <= r && r - dist <= margin {
                return .bottomLeft
            }
            return nil
        } else if p.x > w - r && p.y < r {
            // Bottom-Right
            let dx = p.x - (w - r)
            let dy = p.y - r
            let dist = sqrt(dx*dx + dy*dy)
            if dist <= r && r - dist <= margin {
                return .bottomRight
            }
            return nil
        } else if p.x < r && p.y > h - r {
            // Top-Left
            let dx = p.x - r
            let dy = p.y - (h - r)
            let dist = sqrt(dx*dx + dy*dy)
            if dist <= r && r - dist <= margin {
                return .topLeft
            }
            return nil
        } else if p.x > w - r && p.y > h - r {
            // Top-Right
            let dx = p.x - (w - r)
            let dy = p.y - (h - r)
            let dist = sqrt(dx*dx + dy*dy)
            if dist <= r && r - dist <= margin {
                return .topRight
            }
            return nil
        }

        // 2. Check straight edges
        if p.x <= margin {
            return .left
        } else if p.x >= w - margin {
            return .right
        } else if p.y <= margin {
            return .bottom
        } else if p.y >= h - margin {
            return .top
        }

        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch edge(at: p) {
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight:
            NSCursor.windowResizeNorthWestSouthEast.set()
        case .topRight, .bottomLeft:
            NSCursor.windowResizeNorthEastSouthWest.set()
        case nil:
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let p = convert(event.locationInWindow, from: nil)
        activeEdge = edge(at: p)
        initialFrame = window.frame
        initialMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let edge = activeEdge, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - initialMouse.x
        let dy = now.y - initialMouse.y

        var f = initialFrame
        let minW = window.minSize.width
        let minH = window.minSize.height

        switch edge {
        case .left, .topLeft, .bottomLeft:
            f.origin.x = initialFrame.origin.x + dx
            f.size.width = initialFrame.size.width - dx
        case .right, .topRight, .bottomRight:
            f.size.width = initialFrame.size.width + dx
        default: break
        }
        switch edge {
        case .top, .topLeft, .topRight:
            f.size.height = initialFrame.size.height + dy
        case .bottom, .bottomLeft, .bottomRight:
            f.origin.y = initialFrame.origin.y + dy
            f.size.height = initialFrame.size.height - dy
        default: break
        }

        // Clamp to min size while keeping the opposite edge anchored.
        if f.size.width < minW {
            if edge == .left || edge == .topLeft || edge == .bottomLeft {
                f.origin.x = initialFrame.maxX - minW
            }
            f.size.width = minW
        }
        if f.size.height < minH {
            if edge == .bottom || edge == .bottomLeft || edge == .bottomRight {
                f.origin.y = initialFrame.maxY - minH
            }
            f.size.height = minH
        }

        window.setFrame(f, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        activeEdge = nil
    }
}

// MARK: - Custom traffic lights (borderless windows have no standard buttons)

struct WindowControls: View {
    @State private var hovering = false

    private let closeColor = Color(red: 1.00, green: 0.37, blue: 0.34)
    private let minColor   = Color(red: 1.00, green: 0.74, blue: 0.18)
    private let zoomColor  = Color(red: 0.24, green: 0.79, blue: 0.25)

    var body: some View {
        HStack(spacing: 8) {
            trafficButton(color: closeColor, symbol: "xmark") {
                WindowRef.shared.window?.performClose(nil)
            }
            trafficButton(color: minColor, symbol: "minus") {
                WindowRef.shared.window?.miniaturize(nil)
            }
            trafficButton(color: zoomColor, symbol: "arrow.up.left.and.arrow.down.right") {
                WindowRef.shared.window?.zoom(nil)
            }
        }
        .onHover { hovering = $0 }
    }

    private func trafficButton(color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(hovering ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }
}

extension NSCursor {
    static var windowResizeNorthWestSouthEast: NSCursor {
        let sel = Selector(("_windowResizeNorthWestSouthEastCursor"))
        if NSCursor.responds(to: sel),
           let cursor = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return NSCursor.arrow
    }

    static var windowResizeNorthEastSouthWest: NSCursor {
        let sel = Selector(("_windowResizeNorthEastSouthWestCursor"))
        if NSCursor.responds(to: sel),
           let cursor = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return NSCursor.arrow
    }
}
