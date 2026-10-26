import SwiftUI

/// The island itself: collapsed it hugs the notch and shows two small gauges,
/// hovered it drops down to show both windows with reset timers.
struct NotchView: View {
    @EnvironmentObject var store: UsageStore
    @ObservedObject private var music = NowPlayingMonitor.shared
    @ObservedObject private var dog = DogMonitor.shared
    @ObservedObject private var resets = ResetTracker.shared
    let geometry: NotchGeometry

    @State private var hovering = ProcessInfo.processInfo.environment["TIBODOG_EXPANDED"] == "1"
    @State private var collapseTask: Task<Void, Never>?
    /// When the island opened: open long enough, the dog's post counts as read when it closes.
    @State private var openedAt: Date?

    private let expandedWidth: CGFloat = 440
    // Beside the notch, each side is the gauge and what's next to it (the barking dog, the album art, the
    // equalizer, the dog's woof), all the same gap apart. Both sides are as wide as the wider one, so the
    // island stays centred over the notch and never leaves part of it uncovered.
    private let gap: CGFloat = 8
    private let edge: CGFloat = 12      // from the island's rounded edge
    private let toNotch: CGFloat = 10   // from the notch
    private var gaugeWidth: CGFloat { hovering ? 84 : 54 }
    private var leftItemWidths: [CGFloat] { [dog.alert != nil ? BarkingDog.width : 0, music.current != nil ? 20 : 0].filter { $0 > 0 } }
    private var rightItemWidths: [CGFloat] { [music.current != nil ? 23 : 0, dog.alert != nil ? Woof.width : 0].filter { $0 > 0 } }
    private func sideContent(_ items: [CGFloat]) -> CGFloat { gaugeWidth + items.reduce(0) { $0 + $1 + gap } }
    private var sideWidth: CGFloat { max(sideContent(leftItemWidths), sideContent(rightItemWidths)) + edge + toNotch }
    private var collapsedWidth: CGFloat { geometry.notchWidth + sideWidth * 2 }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        VStack(spacing: 0) {
            gaugeRow
                .frame(height: geometry.notchHeight)
            if hovering {
                detail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: hovering ? max(expandedWidth, collapsedWidth) : collapsedWidth)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: hovering ? 22 : 12,
                                   bottomTrailingRadius: hovering ? 22 : 12)
                .fill(.black)
                .shadow(color: .black.opacity(hovering ? 0.45 : 0), radius: 14, y: 6)
        )
        .contentShape(Rectangle())
        .contextMenu { TiboDogMenu() }
        .onHover { over in
            collapseTask?.cancel()
            if over {
                if !hovering { openedAt = Date() }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { hovering = true }
            } else {
                collapseTask = Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    // A quick brush doesn't count: the dog keeps barking until the post was open for a moment.
                    let read = openedAt.map { Date().timeIntervalSince($0) >= 1 } ?? false
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        hovering = false
                        if read { dog.markRead() }
                    }
                    openedAt = nil
                }
            }
        }
    }

    // MARK: Collapsed row (also the header when expanded)

    private var gaugeRow: some View {
        let failed = store.errorMessage != nil && store.usage == nil
        return HStack(spacing: 0) {
            HStack(spacing: gap) {
                MiniGauge(label: store.primaryLabel, window: store.usage?.fiveHour, error: failed, showReset: hovering).fixedSize()
                if dog.alert != nil { BarkingDog().transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity)) }
                if let m = music.current { Artwork(image: m.artwork, size: 20, radius: 5).transition(.scale.combined(with: .opacity)) }
            }
            .padding(.leading, edge)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: geometry.notchWidth)
            HStack(spacing: gap) {
                if let m = music.current { EqualizerBars(playing: m.playing).transition(.opacity) }
                if let a = dog.alert { Woof(text: a.woof).transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity)) }
                MiniGauge(label: store.secondaryLabel, window: store.usage?.sevenDay, error: failed, showReset: hovering).fixedSize()
            }
            .padding(.trailing, edge)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: music.current?.itemID)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dog.alert?.id)
    }

    // MARK: Expanded detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = dog.alert {
                DogSection(alert: a, dog: dog)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            Picker("Usage Provider", selection: $store.provider) {
                ForEach(UsageProvider.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if let u = store.usage {
                UsageRow(title: store.primaryTitle, window: u.fiveHour)
                UsageRow(title: store.secondaryTitle, window: u.sevenDay)
                if let o = u.sevenDayOpus { UsageRow(title: "Weekly · Opus", window: o) }
                if let s = u.sevenDaySonnet { UsageRow(title: "Weekly · Sonnet", window: s) }
                if store.provider == .codex, resets.credits != nil { ResetCreditRow(tracker: resets, usage: u) }
            } else if store.isLoading {
                Text("Loading usage…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.04))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let m = music.current {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                NowPlayingRow(item: m, monitor: music)
            }
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.planText)
            if let src = store.sourceName { Text("·").opacity(0.4); Text(src) }
            Spacer()
            if let t = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Updated \(relativeText(until: ctx.date, from: t)) ago")
                }
            }
            Button {
                store.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Pieces

func usageColor(_ fraction: Double?) -> Color {
    guard let f = fraction else { return .gray }
    if f < 0.5 { return Color(red: 0.20, green: 0.78, blue: 0.35) }   // green
    if f < 0.8 { return Color(red: 1.00, green: 0.62, blue: 0.04) }   // orange
    return Color(red: 1.00, green: 0.27, blue: 0.23)                  // red
}

struct MiniGauge: View {
    let label: String
    let window: UsageWindow?
    let error: Bool
    /// The time to the reset beside the label: only when hovered, so the closed island stays narrow.
    var showReset = true

    var body: some View {
        HStack(spacing: 6) {
            Ring(fraction: window?.fraction, color: error ? .red : usageColor(window?.fraction))
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: -1) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    HStack(spacing: 3) {
                        Text(label)
                        if showReset, let r = window?.resetsAt {
                            Text("·").opacity(0.5)
                            Text(relativeText(until: r, from: ctx.date)).fontWeight(.medium)
                        }
                    }
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                }
                Text(window?.percentText ?? (error ? "!" : "–"))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Five bars that dance while music plays (procedural — macOS gives us no audio levels).
struct EqualizerBars: View {
    let playing: Bool
    var bars = 5
    var height: CGFloat = 16
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: height * (playing ? level(i, t) : 0.16))
                }
            }
            .frame(height: height, alignment: .bottom)
            .animation(.easeOut(duration: 0.25), value: playing)
        }
    }

    private func level(_ i: Int, _ t: Double) -> CGFloat {
        let freqs: [Double] = [2.3, 3.1, 2.7, 3.6, 2.0, 3.3, 2.5]
        let f = freqs[i % freqs.count]
        let p = Double(i) * 1.7
        let a = sin(t * f + p)
        let b = sin(t * f * 0.37 + p * 2.1)
        let v = abs(a * 0.7 + b * 0.3)
        return CGFloat(0.16 + 0.84 * v)
    }
}

struct NowPlayingRow: View {
    let item: NowPlaying
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 12) {
            Artwork(image: item.artwork, size: 40, radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.artist.isEmpty ? "Now Playing" : item.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                progress
            }
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                control("backward.fill") { monitor.send(.previousTrack) }
                control(item.playing ? "pause.fill" : "play.fill", size: 15) { monitor.send(.togglePlayPause) }
                control("forward.fill") { monitor.send(.nextTrack) }
            }
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = item.elapsedNow(at: ctx.date) ?? 0
            let total = item.duration ?? 0
            HStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.white.opacity(0.75))
                            .frame(width: total > 0 ? g.size.width * min(now / total, 1) : 0)
                    }
                }
                .frame(height: 3)
                Text("\(mmss(now))\(total > 0 ? " / " + mmss(total) : "")")
                    .font(.system(size: 9.5)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func control(_ symbol: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mmss(_ s: Double) -> String {
        let v = max(0, Int(s))
        return String(format: "%d:%02d", v / 60, v % 60)
    }
}

struct Ring: View {
    let fraction: Double?
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
        }
    }
}

struct UsageRow: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(window?.percentText ?? "–")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(usageColor(window?.fraction))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(usageColor(window?.fraction))
                        .frame(width: g.size.width * (window?.fraction ?? 0))
                        .animation(.easeOut(duration: 0.6), value: window?.fraction)
                }
            }
            .frame(height: 6)
            if let r = window?.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Resets in \(relativeText(until: r, from: ctx.date)) · \(clockText(r))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}


// MARK: - The dog

/// Two quick barks, then a pause: how hard the dog barks right now, 0...1. The dog and its woof on the
/// other side of the notch read the same clock, so they bark together.
func barkStrength(_ t: TimeInterval) -> Double {
    let phase = (t / 0.9).truncatingRemainder(dividingBy: 1)
    func pulse(_ start: Double, _ len: Double) -> Double {
        let p = (phase - start) / len
        return (0..<1).contains(p) ? sin(p * .pi) : 0
    }
    return max(pulse(0, 0.2), pulse(0.27, 0.2))
}

/// The dog, facing the notch: it rears up on each bark with sound waves in front of it.
struct BarkingDog: View {
    static let width: CGFloat = 30
    var size: CGFloat = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let bark = barkStrength(ctx.date.timeIntervalSinceReferenceDate)
            HStack(spacing: 0) {
                Text("🐕")
                    .font(.system(size: size))
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(-18 * bark), anchor: .bottomTrailing)
                    .offset(y: -2.5 * bark)
                Canvas { g, s in
                    guard bark > 0 else { return }
                    for i in 0..<3 {
                        let r = s.height * (0.18 + 0.16 * Double(i)) * (0.7 + 0.5 * bark)
                        var arc = Path()
                        arc.addArc(center: CGPoint(x: 0, y: s.height / 2), radius: r,
                                   startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: false)
                        g.stroke(arc, with: .color(.yellow.opacity(bark * (1 - Double(i) * 0.25))), lineWidth: 1.4)
                    }
                }
                .frame(width: Self.width - size - 2, height: size)
            }
            .frame(width: Self.width, alignment: .leading)
        }
    }
}

/// "멍!" / "WOOF!", popping on each bark.
struct Woof: View {
    static let width: CGFloat = 24
    let text: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let bark = barkStrength(ctx.date.timeIntervalSinceReferenceDate)
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(0.8 + 0.45 * bark)
                .rotationEffect(.degrees(8 * bark))
                .opacity(0.55 + 0.45 * bark)
                .frame(width: Self.width)
        }
    }
}

/// The dog, opened: Tibo's post, when it came, and a link to it on X.
struct DogSection: View {
    let alert: DogAlert
    @ObservedObject var dog: DogMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BarkingDog(size: 22).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(alert.title).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer(minLength: 6)
                    Text(clockText(alert.at))
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
                }
                Text(alert.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !alert.isCredit { ResetCheck(alert: alert, tracker: ResetTracker.shared) }
                if alert.url != nil {
                    Button { dog.openPost() } label: {
                        Text(alert.open + " ↗").font(.system(size: 11, weight: .semibold)).foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


// MARK: - Reset credits

/// Did Tibo's reset reach this account? Checked against the Codex history the tracker keeps.
struct ResetCheck: View {
    let alert: DogAlert
    @ObservedObject var tracker: ResetTracker

    var body: some View {
        let (text, color): (String, Color) = {
            switch tracker.verdict(after: alert.postedAt ?? alert.at) {
            case .windowRestarted(let start):
                return (L("✅ 우리 계정에도 들어왔어요 · 주간 사용량이 \(clockText(start))에 새로 시작",
                          "✅ It reached your account · weekly usage started over at \(clockText(start))"), usageColor(0))
            case .creditAdded(let from, let to):
                return (L("🎟️ 리셋권으로 들어왔어요 · \(from)개 → \(to)개", "🎟️ It came as a reset credit · \(from) → \(to)"), usageColor(0))
            case .pending:
                return (L("⏳ 우리 계정엔 아직이에요 · 몇 분마다 확인해요", "⏳ Not on your account yet · checking every few minutes"), .white.opacity(0.5))
            case .unknown:
                return (L("Codex에 로그인돼 있지 않아 확인할 수 없어요", "Can't check: Codex isn't signed in"), .white.opacity(0.5))
            }
        }()
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(color)
    }
}

/// The Codex tab's reset credits, and a button to spend one (after a second, explicit confirm).
struct ResetCreditRow: View {
    @ObservedObject var tracker: ResetTracker
    let usage: Usage
    @State private var confirming = false

    private var count: Int { tracker.credits ?? 0 }
    /// Both windows barely used: a credit would be wasted now.
    private var barelyUsed: Bool { max(usage.fiveHour?.utilization ?? 0, usage.sevenDay?.utilization ?? 0) < 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("🎟️").font(.system(size: 12))
                Text(L("리셋권 \(count)개", count == 1 ? "1 reset credit" : "\(count) reset credits"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                if tracker.redeeming {
                    ProgressView().controlSize(.small)
                } else if confirming {
                    pill(L("취소", "Cancel"), primary: false) { confirming = false }
                    pill(L("리셋", "Reset"), primary: true) { confirming = false; tracker.useCredit() }
                } else {
                    Button { confirming = true } label: {
                        Text(L("리셋하러 가기 →", "Use a reset →"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(count > 0 ? Color.yellow : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                }
            }
            if confirming {
                Text(L("리셋권 1개를 써서 지금 Codex 사용량(5시간·주간)을 처음으로 되돌려요. 쓴 리셋권은 돌아오지 않아요.",
                       "Spends 1 credit to set your Codex usage (5-hour and weekly) back to zero. It can't be undone."))
                    .font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.04))
                    .fixedSize(horizontal: false, vertical: true)
                if barelyUsed {
                    Text(L("지금은 사용량이 거의 없어서 아껴 두는 게 좋아요.", "You've barely used anything; better to save it."))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
            } else if let o = tracker.lastOutcome {
                Text(outcomeText(o)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .animation(.easeOut(duration: 0.2), value: confirming)
    }

    private func outcomeText(_ o: String) -> String {
        switch o {
        case "reset": return L("✅ 리셋했어요. 사용량이 처음으로 돌아갔어요.", "✅ Reset. Your usage is back to zero.")
        case "nothingToReset": return L("Codex가 지금은 리셋할 사용량이 없다고 해요.", "Codex says there's nothing to reset right now.")
        case "noCredit": return L("쓸 수 있는 리셋권이 없어요.", "No reset credits left.")
        case "alreadyRedeemed": return L("이미 처리된 리셋이에요.", "That reset already went through.")
        default: return L("Codex에 연결하지 못했어요. 잠시 뒤 다시 해 보세요.", "Couldn't reach Codex. Try again in a moment.")
        }
    }

    private func pill(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(primary ? .black : .white)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(primary ? Color.yellow : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
