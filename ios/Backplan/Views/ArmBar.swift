import SwiftUI

/// Bottom bar to arm/disarm the plan as a live timer with local notifications.
/// When armed, shows a per-second countdown to the next boundary.
struct ArmBar: View {
    @Environment(PlanStore.self) private var store
    @Environment(TimerController.self) private var timer

    var body: some View {
        VStack(spacing: 8) {
            if timer.armed {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownRow(now: context.date)
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

    @ViewBuilder
    private var actionButton: some View {
        if timer.armed {
            Button {
                timer.disarm()
            } label: {
                Text("Disarm")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .neoPill(fill: .bpCoralTint)
                    .foregroundStyle(.bpInk)
                    .font(.headline)
            }
            .buttonStyle(.plain)
        } else {
            let result = store.result()
            let canArm = result.hasSteps && !result.isPast
            VStack(spacing: 6) {
                if result.isPast && result.hasSteps {
                    Text("Target time has passed — pick a later time.")
                        .font(.caption)
                        .foregroundStyle(.bpCoral)
                }
                Button {
                    Task { await timer.arm(plan: store.plan) }
                } label: {
                    Label("Arm plan", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .neoPill(fill: .bpLime)
                        .foregroundStyle(.bpInk)
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .disabled(!canArm)
                .opacity(canArm ? 1 : 0.5)
            }
        }
    }

    /// True when the live plan no longer matches the snapshot that was armed —
    /// the scheduled notifications and countdown are stale until the user re-arms.
    private var planChanged: Bool {
        timer.armed && timer.armedPlan != nil && store.plan != timer.armedPlan
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
            Text("Plan changed since you armed it.")
                .font(.caption)
            Spacer(minLength: 8)
            if !store.result().isPast {
                Button {
                    Task { await timer.arm(plan: store.plan) }
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

    @ViewBuilder
    private func countdownRow(now: Date) -> some View {
        if let result = timer.armedResult {
            let text = ArmBar.countdownText(result: result, now: now)
            HStack(spacing: 8) {
                Circle().fill(.bpCoral).frame(width: 8, height: 8)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.bpInk)
                Spacer()
                Text("\(timer.scheduledCount) alert\(timer.scheduledCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
            }
        }
    }

    static func countdownText(result: PlanResult, now: Date) -> String {
        // Shared with the timeline's Now/Next block so the two can't drift.
        // `precise` keeps the arm bar's H:MM:SS clock.
        PlanStatus.make(result: result, now: now, precise: true).headline
    }
}
