import SwiftUI

struct StepRowView: View {
    @Binding var step: Step
    let startTime: Date?
    let overflow: Bool

    @FocusState private var durationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Step name", text: $step.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.bpInk)
                .submitLabel(.done)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField("0", value: $step.duration, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($durationFocused)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.bpBorder, lineWidth: 1.5)
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
        }
        .padding(.vertical, 6)
    }
}
