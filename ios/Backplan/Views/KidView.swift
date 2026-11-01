import SwiftUI
import UIKit

/// Full-screen mode for a small person following the armed routine: one step at
/// a time, a wedge that empties like a Time Timer, the step's name huge, and a
/// Done button too big to miss. It only reads the timer's frozen chain and only
/// ever calls `finishCurrentStep()`, so a kid can't change the plan from here.
///
/// Leaving takes a 2-second press-and-hold on a small corner control — a tap
/// (or a toddler's whole palm) can't do it. Presented by RootView whenever
/// `KidView.storageKey` is true; the `backplan://kid` deep link sets the same key.
struct KidView: View {
    /// Contract with the deep link (`backplan://kid`) and the `-BPKid` debug arg.
    static let storageKey = "backplan.kidView"

    @AppStorage(KidView.storageKey) private var kidView = false
    @Environment(TimerController.self) private var timer

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 60
    @ScaledMetric(relativeTo: .title) private var clockSize: CGFloat = 34

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.bpPaper.ignoresSafeArea()
            // The per-second clock lives in here; boundaries (a step ending)
            // are re-derived from `now` on every tick, so no extra schedule.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                content(now: ctx.date)
            }
            exitControl
        }
        .preferredColorScheme(.light)
    }

    // MARK: - State

    private enum Phase {
        case running(index: Int)
        /// Between steps (a gap, or before the first): nothing to press yet.
        case upNext(index: Int)
        case allDone
        case idle
    }

    private func phase(_ result: PlanResult?, now: Date) -> Phase {
        guard timer.armed, let result, !result.segments.isEmpty else { return .idle }
        if let i = result.runningIndex(at: now) { return .running(index: i) }
        if let n = result.segments.indices.filter({ result.segments[$0].start > now })
            .min(by: { result.segments[$0].start < result.segments[$1].start }) {
            return .upNext(index: n)
        }
        return .allDone
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let result = timer.armedResult
        switch phase(result, now: now) {
        case .idle:
            idle
        case .allDone:
            allDone(result?.segments.count ?? 0)
        case .running(let i):
            if let r = result { stepScreen(r, index: i, now: now, running: true) }
        case .upNext(let i):
            if let r = result { stepScreen(r, index: i, now: now, running: false) }
        }
    }

    // MARK: - Step

    private func stepScreen(_ result: PlanResult, index: Int, now: Date, running: Bool) -> some View {
        let seg = result.segments[index]
        let total = max(1, seg.end.timeIntervalSince(seg.start))
        // Before it starts, show a full wedge rather than a negative-elapsed one.
        let left = running ? max(0, seg.end.timeIntervalSince(now)) : total
        let fraction = min(1, left / total)
        let next = result.segments.indices.contains(index + 1) ? result.segments[index + 1] : nil
        return GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.15
            ScrollView {
                Group {
                    if wide {
                        HStack(spacing: 40) {
                            wedge(fraction: fraction, left: left, size: min(geo.size.height * 0.78, geo.size.width * 0.45))
                            VStack(spacing: 22) {
                                stepName(seg.name, running: running)
                                doneButton(running: running)
                                footer(result, index: index, next: next, now: now)
                            }
                        }
                    } else {
                        VStack(spacing: 22) {
                            wedge(fraction: fraction, left: left, size: min(geo.size.width * 0.72, geo.size.height * 0.34))
                            stepName(seg.name, running: running)
                            Spacer(minLength: 0)
                            doneButton(running: running)
                            footer(result, index: index, next: next, now: now)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 56)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// A pie that empties clockwise from 12 o'clock, like a Time Timer. The
    /// shape is a plain `Path` (not a Circle.trim) so it can be a true pie.
    private func wedge(fraction: Double, left: TimeInterval, size: CGFloat) -> some View {
        // Last minute turns coral: the one urgency cue a 3-year-old can read.
        let fill: Color = left <= 60 ? .bpCoral : .bpLime
        return ZStack {
            Circle().fill(Color.bpCard)
            PieShape(fraction: fraction).fill(fill)
            Circle().stroke(Color.bpInk, lineWidth: 5)
            VStack {
                Spacer()
                Text(Fmt.clock(Int(left.rounded(.up))))
                    .font(.system(size: clockSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.bpInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.bpPaper))
                    .overlay(Capsule().stroke(Color.bpInk, lineWidth: 2))
                    .padding(.bottom, size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 1), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("\(Int((left / 60).rounded(.up))) minutes left")
    }

    private func stepName(_ name: String, running: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: KidIcon.symbol(for: name))
                .font(.system(size: nameSize * 1.1, weight: .bold))
                .foregroundStyle(.bpPurpleElectric)
            if !running {
                Text("GET READY")
                    .font(.headline.weight(.bold))
                    .kerning(1)
                    .foregroundStyle(.bpMuted)
            }
            Text(name)
                .font(.display(nameSize))
                .foregroundStyle(.bpInk)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func doneButton(running: Bool) -> some View {
        if running {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task { await timer.finishCurrentStep() }
            } label: {
                Label("Done!", systemImage: "checkmark")
                    .font(.system(size: 44, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .neoPill(fill: .bpLime, offset: 5, lineWidth: 4)
                    .foregroundStyle(.bpInk)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Finish this step now")
        }
    }

    private func footer(_ result: PlanResult, index: Int, next: PlanSegment?, now: Date) -> some View {
        VStack(spacing: 12) {
            if let next {
                Label("next: \(next.name)", systemImage: KidIcon.symbol(for: next.name))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.bpMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            dots(result, now: now)
        }
    }

    /// Done = filled lime, now = big purple, still to do = hollow.
    private func dots(_ result: PlanResult, now: Date) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(result.segments.enumerated()), id: \.offset) { _, seg in
                let done = seg.end <= now
                let isNow = now >= seg.start && now < seg.end
                Circle()
                    .fill(done ? Color.bpLime : isNow ? Color.bpPurpleElectric : Color.clear)
                    .overlay(Circle().stroke(Color.bpInk, lineWidth: 2.5))
                    .frame(width: isNow ? 26 : 18, height: isNow ? 26 : 18)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Idle / finished

    private var idle: some View {
        bigMessage(symbol: "sun.max.fill", tint: .bpGold,
                   title: "Nothing running",
                   body: "Ask a grown-up to start the morning.")
    }

    private func allDone(_ count: Int) -> some View {
        bigMessage(symbol: "party.popper.fill", tint: .bpPurpleElectric,
                   title: "All done!",
                   body: "You did it. Great job!")
    }

    private func bigMessage(symbol: String, tint: Color, title: String, body: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: nameSize * 2.2))
                .foregroundStyle(tint)
            Text(title)
                .font(.display(nameSize))
                .foregroundStyle(.bpInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            Text(body)
                .font(.system(size: nameSize * 0.45, weight: .semibold))
                .foregroundStyle(.bpMuted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grown-up exit

    @State private var holding = false

    /// Small and plain on purpose; the 2 s hold is the lock, not the hiding.
    private var exitControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: holding ? "lock.open.fill" : "lock.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.bpCard))
                .overlay(Circle().stroke(Color.bpInk, lineWidth: 1.5))
            Text("Grown-ups: hold to exit")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.bpMuted)
        }
        .foregroundStyle(.bpInk)
        .padding(.leading, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 2, maximumDistance: 40) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            kidView = false
        } onPressingChanged: { holding = $0 }
        .accessibilityLabel("Exit kid view")
        .accessibilityHint("Press and hold for two seconds")
    }
}

// MARK: - Pie

/// `fraction` of a full turn, clockwise from 12 o'clock.
private struct PieShape: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let f = min(1, max(0, fraction))
        guard f > 0 else { return p }
        p.move(to: c)
        p.addArc(center: c, radius: min(rect.width, rect.height) / 2,
                 startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * f), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Icons

/// Step name -> SF Symbol. The one place to teach the app a new word; the first
/// matching keyword wins, and anything unknown gets a star. "a|b" = try a, then b.
enum KidIcon {
    private static let table: [(words: [String], symbol: String)] = [
        (["shoe", "sock", "boot"], "shoe|shoeprints.fill"),
        (["breakfast", "lunch", "dinner", "snack", "eat", "meal"], "fork.knife"),
        (["teeth", "tooth", "brush"], "mouth|comb"),
        (["bath", "shower"], "bathtub"),
        (["book", "story", "stories", "read"], "book"),
        (["dress", "clothes", "pajama", "jammies", "shirt"], "tshirt"),
        (["bag", "pack"], "backpack"),
        (["bike", "ride"], "bicycle"),
        (["car", "drive"], "car"),
        (["walk"], "figure.walk"),
        (["potty", "toilet", "pee"], "toilet"),
        (["hand", "wash"], "hands.sparkles"),
        (["bed", "sleep", "nap"], "bed.double"),
    ]

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        // Whole words, so "car" doesn't light up on "carpool" or "cart" — but a
        // routine says "Shoes on" and "Brush teeth", so a plural's singular counts.
        var tokens = Set(lower.split { !$0.isLetter }.map(String.init))
        for t in tokens where t.count > 3 && t.hasSuffix("s") { tokens.insert(String(t.dropLast())) }
        for (words, symbol) in table where words.contains(where: { tokens.contains($0) }) {
            // Not every symbol exists on every OS; try the next spelling, then give up.
            for candidate in symbol.split(separator: "|").map(String.init)
            where UIImage(systemName: candidate) != nil {
                return candidate
            }
        }
        return "star.fill"
    }
}
