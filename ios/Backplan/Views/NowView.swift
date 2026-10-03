import SwiftUI

/// The Now skin's home screen: the countdown *is* the app. One sentence for the
/// next thing you must do, the clock to it, whether you're OK, and the two
/// buttons that keep the countdown honest when reality drifts (Done / Running
/// late). Plan and Day are still where the chain is built; this only reads it.
///
/// Armed, everything comes from `TimerController`'s frozen snapshot — the same
/// one countdown Classic's arm bar shows. Disarmed, the same screen is computed
/// live from the chain that *would* be armed (the Day if it has anything left
/// today, else the open plan), with Start at the bottom.
struct NowView: View {
    /// Switch tabs ("plan" / "day") — the empty state's way out.
    var open: (String) -> Void

    @Environment(PlanStore.self) private var store
    @Environment(TimerController.self) private var timer

    var body: some View {
        NavigationStack {
            // 30s is for the preview: the candidate is re-derived from the store
            // (a Day with nothing pinned runs forward from now). The parts that
            // tick per second have their own TimelineView below.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                screen(candidate(now: ctx.date), now: ctx.date)
            }
            .background(.bpPaper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Backplan")
                        .font(.display(22))
                        .foregroundStyle(.bpPurple)
                }
                ToolbarItem(placement: .topBarTrailing) { SkinSwitchButton() }
            }
        }
        .tint(.bpPurpleElectric)
    }

    // MARK: - Which chain

    private func candidate(now: Date) -> NowCandidate {
        if timer.armed, let result = timer.armedResult {
            return .chain(NowChain(
                isDay: timer.armedIsDay, result: result,
                name: timer.armedIsDay ? TimerController.dayName : planName(timer.armedPlan),
                armed: true, armedAt: timer.armedAt,
                eventName: timer.armedIsDay ? "" : eventName(timer.armedPlan)
            ))
        }
        // Same candidate rule as the web: the Day when it still has something
        // armable today, else the open plan.
        let day = DayPlanner.armable(store.dayResult(now: now), now: now)
        if !day.segments.isEmpty && !day.isPast {
            return .chain(NowChain(isDay: true, result: day, name: TimerController.dayName,
                                   armed: false, armedAt: now))
        }
        // Track mode ends the plan at "asleep by", which moves with the clock —
        // Classic doesn't offer to arm it either (its arm bar is hidden there).
        if store.track.on {
            return .empty("Track to sleep is on, so your plan has no fixed time to count down to — and nothing on your day is still ahead.")
        }
        let plan = BackwardsPlanner.compute(store.plan, now: now)
        if !plan.segments.isEmpty && !plan.isPast {
            return .chain(NowChain(isDay: false, result: plan, name: planName(store.plan),
                                   armed: false, armedAt: now, eventName: eventName(store.plan)))
        }
        if plan.segments.isEmpty {
            return .empty("Your plan has no steps with a duration yet, and nothing on your day is still ahead.")
        }
        return .empty("Your plan’s target time has passed, and nothing on your day is still ahead.")
    }

    private func eventName(_ plan: Plan?) -> String {
        plan?.eventName.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private func planName(_ plan: Plan?) -> String {
        let n = eventName(plan)
        return n.isEmpty ? "your plan" : n
    }

    // MARK: - Screen

    @ViewBuilder
    private func screen(_ candidate: NowCandidate, now: Date) -> some View {
        switch candidate {
        case .empty(let why):
            ScrollView { emptyState(why).padding(16) }
        case .chain(let chain):
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        NowHero(chain: chain, now: ctx.date)
                    }
                    if chain.armed && planChanged { staleBanner }
                    // Buttons and rows only change at a boundary, so they wake
                    // exactly then rather than riding the per-second clock.
                    // `.id` restarts the schedule when Done / late move them.
                    if chain.armed {
                        TimelineView(BoundarySchedule(result: chain.result)) { ctx in
                            actions(chain, now: ctx.date)
                        }
                        .id(chain.result.segments)
                    }
                    TimelineView(BoundarySchedule(result: chain.result)) { ctx in
                        NowUpNextList(chain: chain, now: ctx.date)
                    }
                    .id(chain.result.segments)
                    nightLine(now: now)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { startStop(chain) }
        }
    }

    // MARK: - Done / Running late

    @ViewBuilder
    private func actions(_ chain: NowChain, now: Date) -> some View {
        let running = chain.result.runningIndex(at: now) != nil
        // Late applies while there is a current run: one running, or one still to come.
        let ahead = chain.result.currentRun(at: now) != nil
        // Two rows, so neither ever has to squeeze: Done full width, then
        // "Running late  [+5] [+10]".
        VStack(alignment: .leading, spacing: 10) {
            if running {
                Button {
                    Task { await timer.finishCurrentStep() }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .neoPill(fill: .bpLime)
                        .foregroundStyle(.bpInk)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Finish the current step now")
            }
            if ahead {
                HStack(spacing: 10) {
                    Text("Running late")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.bpInk)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    lateButton(5)
                    lateButton(10)
                }
            }
        }
    }

    private func lateButton(_ minutes: Int) -> some View {
        Button {
            Task { await timer.slip(minutes: minutes) }
        } label: {
            Text("+\(minutes)")
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .neoPill(fill: .bpCoralTint)
                .foregroundStyle(.bpInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Running late, add \(minutes) minutes")
    }

    // MARK: - Night line

    /// Only with the night pair on, and straight off the bridge's solve — no
    /// sleep math of our own.
    @ViewBuilder
    private func nightLine(now: Date) -> some View {
        if let bridge = store.bridge(now: now) {
            HStack(spacing: 8) {
                Image(systemName: "moon.fill").foregroundStyle(.bpPurpleElectric)
                Text("Lights out by \(Fmt.time(bridge.deadline)) for a \(Fmt.time(bridge.wake)) wake")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.bpInk)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Start / Stop

    private func startStop(_ chain: NowChain) -> some View {
        Group {
            if chain.armed {
                Button {
                    timer.disarm()
                } label: {
                    Text("Stop countdown")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .neoPill(fill: .bpCoralTint)
                        .foregroundStyle(.bpInk)
                        .font(.headline)
                }
            } else {
                Button {
                    Task {
                        if chain.isDay {
                            await timer.armDay(store.day, result: DayPlanner.armable(store.dayResult()))
                        } else {
                            await timer.arm(key: store.activeKey, plan: store.plan)
                        }
                    }
                } label: {
                    Label(chain.isDay ? "Start my day" : "Start countdown for \(chain.name)",
                          systemImage: "bell.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .neoPill(fill: .bpLime)
                        .foregroundStyle(.bpInk)
                        .font(.headline)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bpPaper)
        .overlay(alignment: .top) { Rectangle().fill(.bpRule).frame(height: 1) }
    }

    // MARK: - Empty

    private func emptyState(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing to count down")
                .font(.display(30))
                .foregroundStyle(.bpPurple)
            Text(why)
                .font(.body)
                .foregroundStyle(.bpInk)
            HStack(spacing: 10) {
                emptyButton("Open Plan", tab: "plan")
                emptyButton("Open Day", tab: "day")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard()
    }

    private func emptyButton(_ title: String, tab: String) -> some View {
        Button { open(tab) } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .neoPill(fill: .bpLime)
                .foregroundStyle(.bpInk)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stale

    /// Same question Classic's arm bar asks: the plan/day, not the segments, so
    /// Done / Running late never read as "changed".
    private var planChanged: Bool {
        guard timer.armed else { return false }
        if let armedDay = timer.armedDay { return store.day != armedDay }
        guard let armedPlan = timer.armedPlan else { return false }
        return store.pair[timer.armedKey] != armedPlan
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
            Text(timer.armedIsDay ? "Day changed since you started the countdown."
                                  : "Plan changed since you started the countdown.")
                .font(.caption)
            Spacer(minLength: 8)
            if canRearm {
                Button {
                    Task {
                        if timer.armedIsDay {
                            await timer.armDay(store.day, result: DayPlanner.armable(store.dayResult()))
                        } else {
                            await timer.arm(key: timer.armedKey, plan: store.pair[timer.armedKey])
                        }
                    }
                } label: {
                    Text("Re-arm")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .neoPill(fill: .bpLime)
                        .foregroundStyle(.bpInk)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.bpInk)
    }

    private var canRearm: Bool {
        let result = timer.armedIsDay ? DayPlanner.armable(store.dayResult())
                                      : store.result(for: timer.armedKey)
        return !result.isPast && !result.segments.isEmpty
    }
}

// MARK: - Model

/// The chain the Now screen is describing — armed, or the one Start would arm.
struct NowChain {
    let isDay: Bool
    let result: PlanResult
    /// Event name for a plan, "Your day" for a day.
    let name: String
    let armed: Bool
    let armedAt: Date
    /// Trimmed event name; empty for a Day or an unnamed plan.
    var eventName: String = ""

    /// What the last run is measured against in the slack line.
    var targetName: String {
        if isDay { return "the end of your day" }
        return eventName.isEmpty ? "your target" : eventName
    }
}

enum NowCandidate {
    case chain(NowChain)
    case empty(String)
}

/// The words at the top of the screen. Pure, so it reads the same armed or
/// previewed and can be checked without a view.
struct NowHeadline: Equatable {
    enum Tone { case normal, overrun, done }
    var title: String
    var sub: String?
    var tone: Tone = .normal

    static func make(_ chain: NowChain, now: Date) -> NowHeadline {
        let r = chain.result
        guard let first = r.segments.first, let end = r.chainEnd else {
            return NowHeadline(title: "No steps", sub: nil)
        }
        if now >= end {
            return NowHeadline(
                title: chain.isDay ? "That\u{2019}s the day." : "You\u{2019}re there.",
                sub: chain.isDay ? "Last block ended at \(Fmt.time(end))"
                                 : "\(chain.name) at \(Fmt.time(r.target))",
                tone: .done)
        }
        if now < first.start {
            return NowHeadline(title: "\(startPhrase(first.name)) in \(span(first.start.timeIntervalSince(now)))",
                               sub: "at \(Fmt.time(first.start))")
        }
        let over = now > r.target
        let overText = "Running \(Fmt.duration(max(1, Int((now.timeIntervalSince(r.target) / 60).rounded())))) over"
        let next = r.segments.filter { $0.start > now }.min { $0.start < $1.start }
        if let i = r.runningIndex(at: now) {
            let seg = r.segments[i]
            // Minute-grain: the big clock right below carries the seconds.
            let left = "\(span(seg.end.timeIntervalSince(now))) left · until \(Fmt.time(seg.end))"
            return over
                ? NowHeadline(title: overText, sub: "\(seg.name) · \(left)", tone: .overrun)
                : NowHeadline(title: seg.name, sub: left)
        }
        if let next {
            let nextLine = "Next: \(next.name) at \(Fmt.time(next.start))"
            return over
                ? NowHeadline(title: overText, sub: nextLine, tone: .overrun)
                : NowHeadline(title: "Free for \(span(next.start.timeIntervalSince(now)))", sub: nextLine)
        }
        return NowHeadline(title: "In progress", sub: nil)
    }

    /// "Bike to School in 12 min" reads; "Start Bike to School" doesn't.
    private static func startPhrase(_ name: String) -> String {
        let travel = TravelMode.allCases.contains { name.hasPrefix("\($0.label) to ") }
        return travel ? name : "Start \(name)"
    }

    /// Minute-grain, rounded up — the clock underneath carries the seconds, and
    /// "in 0 min" is never true while it's still counting.
    private static func span(_ interval: TimeInterval) -> String {
        Fmt.duration(max(1, Int((interval / 60).rounded(.up))))
    }
}

// MARK: - Hero

/// Headline, clock, phase pill and slack — the per-second part of the screen.
private struct NowHero: View {
    let chain: NowChain
    let now: Date

    var body: some View {
        let head = NowHeadline.make(chain, now: now)
        let countdown = PlanCountdown.make(result: chain.result, now: now, armedAt: chain.armedAt)
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(.bpMuted)
            VStack(alignment: .leading, spacing: 6) {
                Text(head.title)
                    .font(.display(38))
                    .foregroundStyle(head.tone == .overrun ? Color.bpCoral : .bpInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = head.sub {
                    Text(sub)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.bpMuted)
                }
            }
            if head.tone != .done, let countdown {
                clock(countdown)
            } else if head.tone == .done {
                pill("Done", fill: .bpLimeTint, ink: .bpLimeInk)
            }
            slackLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard()
        .accessibilityElement(children: .combine)
    }

    private var eyebrow: String {
        let r = chain.result
        let what = chain.isDay ? "YOUR DAY · ENDS \(Fmt.time(r.target))"
                               : "\(chain.name.uppercased()) · \(Fmt.time(r.target))"
        return chain.armed ? what : "PREVIEW · \(what)"
    }

    @ViewBuilder
    private func clock(_ c: PlanCountdown) -> some View {
        let r = chain.result
        // Past the target with a slipped step still to go, the honest clock is
        // the one to the next boundary, not one counting up from the target.
        let pending: (label: String, at: Date)? = {
            guard c.phase == .past else { return nil }
            if let i = r.runningIndex(at: now) { return ("Ends in", r.segments[i].end) }
            if let n = r.segments.filter({ $0.start > now }).min(by: { $0.start < $1.start }) {
                return ("Next up in", n.start)
            }
            return nil
        }()
        let label = pending?.label ?? c.label
        let seconds = pending.map { $0.at.timeIntervalSince(now) }
            ?? (c.phase == .past ? now.timeIntervalSince(c.boundary) : c.boundary.timeIntervalSince(now))
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.8)
                    .foregroundStyle(.bpMuted)
                // Monospaced digits: proportional figures jitter on every tick.
                Text(Fmt.clock(seconds))
                    .font(.system(size: 64, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ink(c.phase))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            pill(c.phaseWord, fill: pillFill(c.phase), ink: pillInk(c.phase))
        }
    }

    /// Armed: room between the end of the current run and the next fixed
    /// thing. Preview: just where the chain sits, since nothing has moved yet.
    @ViewBuilder
    private var slackLine: some View {
        let r = chain.result
        if chain.armed, let slack = r.slack(at: now) {
            // KEEP IN SYNC with the web slack copy — same words, same numbers.
            let before = slack.name ?? chain.targetName
            let (text, color): (String, Color) =
                slack.minutes > 0 ? ("\(slack.minutes) min to spare before \(before)", .bpLimeInk)
                : slack.minutes < 0 ? ("\(-slack.minutes) min behind for \(before)", .bpCoral)
                : ("On time", .bpLimeInk)
            Text(text)
                .font(.headline)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        } else if !chain.armed, let start = r.overallStart, let end = r.chainEnd {
            Text("Starts \(Fmt.time(start)) · ends \(Fmt.time(end))")
                .font(.subheadline)
                .foregroundStyle(.bpMuted)
        }
    }

    private func pill(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .kerning(0.6)
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .neoPill(fill: fill)
            .fixedSize()
    }

    // Same state colours as the arm bar.
    private func ink(_ p: PlanPhase) -> Color {
        switch p {
        case .future: return .bpPurple
        case .active: return .bpLimeInk
        case .past: return .bpCoral
        }
    }

    private func pillFill(_ p: PlanPhase) -> Color {
        switch p {
        case .future: return Color(hex: 0xF3EEFC)
        case .active: return .bpLimeTint
        case .past: return .bpCoralTint
        }
    }

    private func pillInk(_ p: PlanPhase) -> Color {
        switch p {
        case .future: return .bpPurple
        case .active: return .bpLimeInk
        case .past: return Color(hex: 0x9A2A16)
        }
    }
}

// MARK: - Up next

/// The whole chain as rows — `start · name · duration` — with the running one
/// marked and past ones receded, exactly as Overview mode draws a plan. Idle
/// stretches (a Day's, or the gap Done opens) show as "free".
private struct NowUpNextList: View {
    let chain: NowChain
    let now: Date

    private enum Row: Identifiable {
        case seg(PlanSegment)
        case gap(start: Date, minutes: Int)
        var id: String {
            switch self {
            case .seg(let s): return s.id.uuidString + "\(s.start.timeIntervalSince1970)"
            case .gap(let start, _): return "gap\(start.timeIntervalSince1970)"
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        var lastEnd: Date?
        for seg in chain.result.segments {
            if let lastEnd, seg.start > lastEnd {
                let mins = Int((seg.start.timeIntervalSince(lastEnd) / 60).rounded())
                if mins > 0 { out.append(.gap(start: lastEnd, minutes: mins)) }
            }
            out.append(.seg(seg))
            lastEnd = max(lastEnd ?? seg.end, seg.end)
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UP NEXT")
                .font(.caption.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(.bpMuted)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            ForEach(rows) { row in
                switch row {
                case .seg(let seg): segRow(seg)
                case .gap(let start, let minutes): gapRow(start: start, minutes: minutes)
                }
            }
            OverviewTargetRow(target: chain.result.target,
                              eventName: chain.isDay ? "Day done" : chain.name)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(padding: 0)
    }

    private func segRow(_ seg: PlanSegment) -> some View {
        let isNow = now >= seg.start && now < seg.end
        let done = now >= seg.end
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(Fmt.time(seg.start))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.bpLimeInk)
                .fixedSize()
            HStack(spacing: 8) {
                Text(seg.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.bpInk)
                    .lineLimit(1)
                if isNow {
                    Text("NOW")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(.bpInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .neoPill(fill: .bpLime, offset: 0, lineWidth: 1.5)
                }
            }
            Spacer(minLength: 8)
            Text(Fmt.duration(seg.minutes))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.bpMuted)
                .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(isNow ? Color.bpLimeTint : .clear)
        .opacity(done ? 0.45 : 1)
    }

    private func gapRow(start: Date, minutes: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(Fmt.time(start))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.bpMuted)
                .fixedSize()
            Text("free · \(Fmt.duration(minutes))")
                .font(.subheadline)
                .italic()
                .foregroundStyle(.bpMuted)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .opacity(now >= start.addingTimeInterval(TimeInterval(minutes * 60)) ? 0.45 : 1)
    }
}

/// Wakes once now and then just after each moment the chain changes state — a
/// segment starting or ending, or the target — instead of polling.
struct BoundarySchedule: TimelineSchedule {
    let marks: [Date]

    init(result: PlanResult) {
        var m = result.segments.flatMap { [$0.start, $0.end] }
        m.append(result.target)
        marks = Array(Set(m)).sorted()
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        // +0.2s so each wake lands just past the boundary, not on its edge.
        [startDate] + marks.filter { $0 > startDate }.map { $0.addingTimeInterval(0.2) }
    }
}
