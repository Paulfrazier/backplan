import SwiftUI

struct StepRowView: View {
    @Environment(PlanStore.self) private var store
    @Binding var step: Step
    let startTime: Date?
    let overflow: Bool

    @FocusState private var durationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Step name", text: $step.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.bpInk)
                    .submitLabel(.done)

                Button {
                    store.toggleTravel(stepID: step.id)
                } label: {
                    Image(systemName: step.travel?.mode.symbol ?? "car.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(step.travel != nil ? .bpInk : .bpMuted)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(step.travel != nil ? Color.bpLimeTint : Color.bpCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(step.travel != nil ? Color.bpInk : Color.bpRule, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(step.travel != nil ? "Turn off travel lookup" : "Look up real travel time")
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField("0", value: $step.duration, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($durationFocused)
                        // Typing over an auto-filled number claims it; refreshes
                        // stop overwriting from here on.
                        .onChange(of: step.duration) { _, _ in
                            if durationFocused, step.travel != nil { step.travel?.manual = true }
                        }
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.bpRule, lineWidth: 1.5)
                        )
                        .toolbar {
                            if durationFocused {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { durationFocused = false }
                                }
                            }
                        }

                    Picker("Unit", selection: $step.unit) {
                        ForEach(DurationUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }

                Spacer()

                if let t = startTime {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("start")
                            .font(.caption2)
                            .foregroundStyle(.bpMuted)
                            .textCase(.uppercase)
                        Text(Fmt.time(t))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(overflow ? .bpCoral : .bpLimeInk)
                    }
                }
            }

            if step.travel != nil {
                TravelDetailView(stepID: step.id)
            }
        }
        .padding(.vertical, 6)
    }
}
