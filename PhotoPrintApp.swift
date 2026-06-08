import SwiftUI
import AppKit

@main
struct PhotoPrintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowAccessor { window in
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.styleMask.insert(.fullSizeContentView)
                    window.isMovableByWindowBackground = false
                    window.hasShadow = true

                    // Custom 36pt window corner radius.
                    let radius: CGFloat = 36
                    if let contentView = window.contentView {
                        contentView.wantsLayer = true
                        contentView.layer?.cornerRadius = radius
                        contentView.layer?.cornerCurve = .continuous
                        contentView.layer?.masksToBounds = true
                        contentView.layer?.borderWidth = 0

                        // The native window frame view (NSThemeFrame) paints its own
                        // backing + 1px border. Round + clip it AND clear its fill/border
                        // so it doesn't draw the bright ring around our content.
                        if let frameView = contentView.superview {
                            frameView.wantsLayer = true
                            frameView.layer?.cornerRadius = radius
                            frameView.layer?.cornerCurve = .continuous
                            frameView.layer?.masksToBounds = true
                            frameView.layer?.backgroundColor = NSColor.clear.cgColor
                            frameView.layer?.borderWidth = 0
                        }
                    }
                    window.invalidateShadow()

                    // Explicitly show the three standard buttons (traffic lights).
                    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                        if let btn = window.standardWindowButton(kind) {
                            btn.isHidden = false
                            btn.superview?.wantsLayer = true
                            btn.superview?.layer?.zPosition = 100
                        }
                    }

                    // Reposition them inside the floating left panel and keep them
                    // there across window resizes.
                    TrafficLightPositioner.shared.attach(to: window)
                })
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Repositions the standard window buttons so they sit inside our floating left panel.
// The panel is inset 12pt from the window edges; we place the buttons 22pt from the
// window's top-left so they nest cleanly inside the panel's rounded corner.
final class TrafficLightPositioner: NSObject {
    static let shared = TrafficLightPositioner()
    private var observers: [NSWindow: NSObjectProtocol] = [:]

    func attach(to window: NSWindow) {
        guard observers[window] == nil else {
            reposition(in: window)
            return
        }
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.reposition(in: window)
        }
        observers[window] = token
        DispatchQueue.main.async { [weak self] in
            self?.reposition(in: window)
        }
    }

    private func reposition(in window: NSWindow) {
        let leftInset: CGFloat = 22
        let topInset: CGFloat = 22
        let spacing: CGFloat = 6

        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var x = leftInset
        for kind in kinds {
            guard let btn = window.standardWindowButton(kind),
                  let parent = btn.superview else { continue }
            let h = btn.frame.height
            // AppKit's themeFrame is non-flipped, so y=0 is bottom. Convert "topInset from top".
            let y = parent.bounds.height - topInset - h
            btn.setFrameOrigin(NSPoint(x: x, y: y))
            x += btn.frame.width + spacing
        }
    }
}
