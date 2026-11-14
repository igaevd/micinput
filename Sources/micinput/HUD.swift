import AppKit
import SwiftUI

/// The pop-up that appears for a few seconds whenever micinput switches the microphone.
@MainActor
final class HUD {
    /// A click-through capsule of dark HUD material that floats above everything, on every Space.
    /// Always dark, like the system's own HUDs, so it reads the same over any window or wallpaper.
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.state = .active
        panel.contentView = material
        return panel
    }()
    private var dismissal: Task<Void, Never>?

    func show(_ event: Override) {
        // Appear where the user is looking: on the screen that has the pointer.
        let pointer = NSEvent.mouseLocation
        guard let material = panel.contentView as? NSVisualEffectView,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        else { return }

        let content = NSHostingView(rootView: HUDView(event: event))
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        material.subviews = [content]
        material.maskImage = .capsule(height: size.height)
        let frame = NSRect(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.maxY - size.height - 12,
                           width: size.width, height: size.height)

        if !panel.isVisible {
            // Drop in from just above the resting position.
            panel.alphaValue = 0
            panel.setFrame(frame.offsetBy(dx: 0, dy: 12), display: true)
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        panel.invalidateShadow()

        dismissal?.cancel()
        dismissal = Task { [panel] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                panel.animator().alphaValue = 0
            }
            // A newer pop-up may have taken over while this one was fading out.
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }
}

private struct HUDView: View {
    let event: Override
    // Plain colors rather than semantic ones: the material's vibrancy would otherwise restyle them.
    private let dimmed = Color.white.opacity(0.62)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: DeviceRef(event.output).symbol(mic: false))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30)
            VStack(spacing: 2) {
                Text("micinput")
                    .font(.subheadline)
                    .foregroundStyle(dimmed)
                HStack(spacing: 6) {
                    if let from = event.from {
                        Text(from.name)
                            .foregroundStyle(dimmed)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(dimmed)
                    }
                    Text(event.to.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
        .lineLimit(1)
        .padding(.leading, 16)
        .padding(.trailing, 24)
        .padding(.vertical, 10)
    }
}

private extension NSImage {
    /// A stretchable capsule, used to mask the HUD material (and with it the window shadow).
    static func capsule(height: CGFloat) -> NSImage {
        let radius = height / 2
        let image = NSImage(size: NSSize(width: height + 1, height: height), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 0, left: radius, bottom: 0, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
