import SwiftUI

/// Bottom bar that turns the passive plan into a tracked one.
///
/// Disarmed it is a single button; arming promotes it to a real status surface —
/// a clock to the next boundary, a phase word, the step you're on and the one
/// after it. Same shape and the same words as the web arm strip, because the
/// copy comes from the same place (`PlanStatus` / `PlanCountdown`) rather than
/// being written twice.
struct ArmBar: View {
    /// What this bar arms. There is still only one countdown: a bar whose
    /// source isn't the armed one shows that countdown and offers to swap.
    enum Source { case plan, day }
    var source: Source = .plan

    @Environment(PlanStore.self) private var store
    @Environment(TimerController.self) private var timer

    /// Is the running countdown the one this bar would start?
    private var armedHere: Bool { timer.armed && timer.armedIsDay == (source == .day) }

    /// The chain this bar would arm right now.
    private func candidate() -> PlanResult {
        switch source {
        case .plan: return store.result()
        case .day: return DayPlanner.armable(store.dayResult())
        }
    }

    private func armHere() async {
        switch source {
        case .plan: await timer.arm(key: store.activeKey, plan: store.plan)
        case .day: await timer.armDay(store.day, result: DayPlanner.armable(store.dayResult()))
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if timer.armed {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    liveBlock(now: context.date)
                }
                if planChanged {
                    staleBanner
                }
            }
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bpPaper)
        .overlay(alignment: .top) {
            Rectangle().fill(.bpRule).frame(height: 1)
        }
    }

    // MARK: - Live status

    @ViewBuilder
    private func liveBlock(now: Date) -> some View {
        if let countdown = timer.countdown(now: now) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(countdown.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .kerning(0.8)
                        .foregroundStyle(.bpMuted)
                    // Monospaced digits are not optional: proportional figures
                    // make a one-second clock jitter sideways on every tick.
                    Text(Fmt.clock(clockInterval(countdown, now: now)))
                        .font(.system(size: 30, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(clockInk(countdown.phase))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(countdown.phaseWord.uppercased())
                        .font(.caption2.weight(.bold))
                        .kerning(0.6)
                        .foregroundStyle(pillInk(countdown.phase))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .neoPill(fill: pillFill(countdown.phase))
                    Text(countdown.detail)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.bpInk)
                    // Before the plan starts, `next` *is* the first step, which
                    // the detail line above already names.
                    if countdown.phase != .future && !countdown.status.next.isEmpty {
                        HStack(spacing: 8) {
                            Text("NEXT")
                                .font(.caption2.weight(.bold))
                                .kerning(0.8)
                                .opacity(0.75)
                            Text(countdown.status.next).font(.caption)
                        }
                        .foregroundStyle(.bpMuted)
                    }
                    Text(metaLine(countdown))
                        .font(.caption)
                        .foregroundStyle(.bpMuted)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Counting down to the boundary, except once the target is blown — then the
    /// same clock counts *up*, which is what "over by" means.
    private func clockInterval(_ countdown: PlanCountdown, now: Date) -> TimeInterval {
        countdown.phase == .past
            ? now.timeIntervalSince(countdown.boundary)
            : countdown.boundary.timeIntervalSince(now)
    }

    private func metaLine(_ countdown: PlanCountdown) -> String {
        var parts: [String] = []
        if timer.armedIsDay {
            parts.append(TimerController.dayName)
        } else if store.link.enabled || source == .day {
            // Only worth naming which half is armed when there are two of them —
            // or when this bar is on the Day tab and the plan is what's running.
            parts.append(store.link.enabled ? timer.armedKey.label : (timer.armedPlan.map(planName) ?? "Plan"))
        }
        parts.append("\(countdown.stepCount) step\(countdown.stepCount == 1 ? "" : "s")")
        parts.append("\(timer.scheduledCount) alert\(timer.scheduledCount == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func clockInk(_ phase: PlanPhase) -> Color {
        switch phase {
        case .future: return .bpPurple
        case .active: return .bpLimeInk
        case .past: return .bpCoral
        }
    }

    private func pillFill(_ phase: PlanPhase) -> Color {
        switch phase {
        case .future: return Color(hex: 0xF3EEFC)
        case .active: return .bpLimeTint
        case .past: return .bpCoralTint
        }
    }

    private func pillInk(_ phase: PlanPhase) -> Color {
        switch phase {
        case .future: return .bpPurple
        case .active: return .bpLimeInk
        case .past: return Color(hex: 0x9A2A16)
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionButton: some View {
        if timer.armed {
            HStack(spacing: 10) {
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
                .buttonStyle(.plain)
                if !armedHere && blockedReason(candidate()) == nil {
                    Button {
                        Task { await armHere() }
                    } label: {
                        Text(source == .day ? "Count down the day" : "Count down this plan")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .neoPill(fill: .bpLime)
                            .foregroundStyle(.bpInk)
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            let result = candidate()
            let blocked = blockedReason(result)
            VStack(spacing: 6) {
                if let blocked {
                    Text(blocked)
                        .font(.caption)
                        .foregroundStyle(.bpCoral)
                }
                Button {
                    Task { await armHere() }
                } label: {
                    Label(source == .day ? "Start day countdown" : "Start countdown", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .neoPill(fill: .bpLime)
                        .foregroundStyle(.bpInk)
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .disabled(blocked != nil)
                .opacity(blocked == nil ? 1 : 0.5)
            }
        }
    }

    /// Mirrors the web arm note. `nil` means the plan can be armed.
    private func blockedReason(_ result: PlanResult) -> String? {
        switch source {
        case .plan:
            if result.segments.isEmpty { return "Add a step with a duration first." }
            if result.isPast { return "Target time has passed — pick a later time." }
        case .day:
            if result.segments.isEmpty { return "Add a block with a duration first." }
            if result.isPast { return "Everything on this day is already over." }
        }
        return nil
    }

    private func planName(_ plan: Plan) -> String {
        let n = plan.eventName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Plan" : n
    }

    // MARK: - Stale

    /// True when the live plan no longer matches the snapshot that was armed —
    /// the scheduled notifications, the countdown and the Live Activity are all
    /// stale until the user re-arms. Compared against the armed *half*, not the
    /// one being edited: switching tabs is not a change to the armed plan.
    private var planChanged: Bool {
        guard timer.armed else { return false }
        if let armedDay = timer.armedDay { return store.day != armedDay }
        guard let armedPlan = timer.armedPlan else { return false }
        return store.pair[timer.armedKey] != armedPlan
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
            Text(timer.armedIsDay ? "Day changed since you started the countdown."
                                  : "Plan changed since you started the countdown.")
                .font(.caption)
            Spacer(minLength: 8)
            // Nothing to re-arm onto if the armed half is itself unarmable.
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
        .padding(.horizontal, 4)
    }

    private var canRearm: Bool {
        let result = timer.armedIsDay ? DayPlanner.armable(store.dayResult())
                                      : store.result(for: timer.armedKey)
        return !result.isPast && !result.segments.isEmpty
    }
}
