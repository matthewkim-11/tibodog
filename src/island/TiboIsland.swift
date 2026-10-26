// tibo-island: a barking dog that lives in the notch until you look at it.
//
// Usage: tibo-island '{"title":"...","body":"...","url":"...","woof":"WOOF!","open":"Open on X","lang":"en"}'
// Hover to read the post. Move the mouse away after reading and the dog goes back into the notch.

import AppKit
import SwiftUI

struct Payload: Decodable {
    var title: String
    var body: String
    var url: String?
    var woof: String
    var open: String
    var lang: String?
}

let payload: Payload = {
    let args = CommandLine.arguments
    if args.count > 1, let data = args[1].data(using: .utf8),
       let p = try? JSONDecoder().decode(Payload.self, from: data) {
        return p
    }
    return Payload(title: "Tibo reset the limits!", body: "", url: nil, woof: "WOOF!", open: "Open on X", lang: "en")
}()

let receivedAt = Date()

// MARK: - Geometry

struct Geometry {
    let screen: NSScreen
    let notchWidth: CGFloat
    let barHeight: CGFloat
    let side: CGFloat = 50

    var collapsed: CGSize { CGSize(width: notchWidth + side * 2, height: barHeight) }
    var expanded: CGSize { CGSize(width: max(notchWidth + side * 2, 420), height: barHeight + 112) }
    var hidden: CGSize { CGSize(width: notchWidth, height: barHeight) }

    func frame(_ size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    static func current() -> Geometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.safeAreaInsets.top
        var notch: CGFloat = 0
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notch = screen.frame.width - l.width - r.width
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let bar = top > 0 ? top : (menuBar > 0 ? menuBar : 24)
        return Geometry(screen: screen, notchWidth: notch, barHeight: bar)
    }
}

// MARK: - State

final class IslandState: ObservableObject {
    @Published var appeared = false
    @Published var expanded = false
    @Published var leaving = false
}

// Two quick barks, then a pause. Returns 0...1 for how hard the dog is barking right now.
func barkStrength(_ t: TimeInterval) -> Double {
    let phase = (t / 0.9).truncatingRemainder(dividingBy: 1)
    func pulse(_ start: Double, _ len: Double) -> Double {
        let p = (phase - start) / len
        return (0..<1).contains(p) ? sin(p * .pi) : 0
    }
    return max(pulse(0, 0.2), pulse(0.27, 0.2))
}

// MARK: - Views

struct IslandShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in r: CGRect) -> Path {
        let rad = min(radius, r.height / 2, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Dog: View {
    var size: CGFloat
    var bark: Double

    var body: some View {
        HStack(spacing: 0) {
            Text("🐕")
                .font(.system(size: size))
                .scaleEffect(x: -1, y: 1) // face the notch
                .rotationEffect(.degrees(-18 * bark), anchor: .bottomTrailing)
                .offset(y: -4 * bark)
            Canvas { ctx, s in
                guard bark > 0 else { return }
                for i in 0..<3 {
                    let r = s.height * (0.18 + 0.16 * Double(i)) * (0.7 + 0.5 * bark)
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: 0, y: s.height / 2), radius: r,
                               startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: false)
                    ctx.stroke(arc, with: .color(.yellow.opacity(bark * (1 - Double(i) * 0.25))), lineWidth: 1.5)
                }
            }
            .frame(width: size * 0.7, height: size)
        }
    }
}

struct IslandView: View {
    @ObservedObject var state: IslandState
    let geo: Geometry

    var size: CGSize {
        if state.leaving || !state.appeared { return geo.hidden }
        return state.expanded ? geo.expanded : geo.collapsed
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let bark = barkStrength(ctx.date.timeIntervalSinceReferenceDate)
            ZStack(alignment: .top) {
                IslandShape(radius: state.expanded ? 24 : geo.barHeight * 0.45)
                    .fill(Color.black)
                if state.expanded {
                    expanded(bark: bark, now: ctx.date)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                } else {
                    collapsed(bark: bark)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(geo.notchWidth == 0 && (state.leaving || !state.appeared) ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    func collapsed(bark: Double) -> some View {
        HStack(spacing: 0) {
            Dog(size: geo.barHeight * 0.62, bark: bark)
                .frame(width: geo.side, height: geo.barHeight)
            Spacer().frame(width: geo.notchWidth)
            Text(payload.woof)
                .font(.system(size: geo.barHeight * 0.36, weight: .heavy, design: .rounded))
                .foregroundColor(.yellow)
                .scaleEffect(0.8 + 0.45 * bark)
                .rotationEffect(.degrees(8 * bark))
                .opacity(0.55 + 0.45 * bark)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: geo.side, height: geo.barHeight)
        }
        .opacity(state.leaving || !state.appeared ? 0 : 1)
    }

    func expanded(bark: Double, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: geo.barHeight)
            HStack(alignment: .top, spacing: 12) {
                Dog(size: 34, bark: bark).frame(width: 54)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(payload.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer(minLength: 8)
                        Text(relative(now))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Text(payload.body)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = payload.url, !url.isEmpty, let link = URL(string: url) {
                        Button(payload.open + " ↗") { NSWorkspace.shared.open(link) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.yellow)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
    }

    func relative(_ now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: payload.lang ?? "en")
        f.unitsStyle = .short
        f.dateTimeStyle = .named // "now" / "지금" instead of "in 0 sec"
        return now.timeIntervalSince(receivedAt) < 60 ? f.localizedString(fromTimeInterval: 0) : f.localizedString(for: receivedAt, relativeTo: now)
    }
}

// MARK: - Window

final class IslandPanel: NSPanel {
    // Keep AppKit from pushing the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

@MainActor
final class Controller {
    let state = IslandState()
    let geo = Geometry.current()
    var panel: IslandPanel!
    var enteredAt: Date?
    var pending: DispatchWorkItem?

    // How long the post has to stay open before it counts as read.
    let readTime: TimeInterval = 0.8

    func start() {
        panel = IslandPanel(contentRect: geo.frame(geo.collapsed),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar and other notch apps (NotchNook, Islet, ...), so a reset is never hidden.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true

        let host = HoverHostingView(rootView: IslandView(state: state, geo: geo))
        host.onHover = { [weak self] inside in self?.hover(inside) }
        panel.contentView = host
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { self.state.appeared = true }
        }
    }

    func hover(_ inside: Bool) {
        guard !state.leaving else { return }
        pending?.cancel()
        if inside {
            enteredAt = Date()
            panel.setFrame(geo.frame(geo.expanded), display: true)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { state.expanded = true }
            return
        }
        let read = enteredAt.map { Date().timeIntervalSince($0) >= readTime } ?? false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            state.expanded = false
            state.leaving = read
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if read {
                NSApp.terminate(nil)
            } else {
                self.panel.setFrame(self.geo.frame(self.geo.collapsed), display: true)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = Controller()
    controller.start()
    signal(SIGTERM) { _ in exit(0) }
    app.run()
}
