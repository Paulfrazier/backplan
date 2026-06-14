import SwiftUI

struct PlanView: View {
    @Environment(PlanStore.self) private var store
    @State private var showingClearConfirm = false

    var body: some View {
        @Bindable var store = store
        let result = store.result()

        NavigationStack {
            List {
                header
                resultSection(result)
                targetSection(store: $store)
                stepsSection(store: $store, result: result)
                templatesSection
            }
            .listStyle(.plain)
            .listSectionSpacing(16)
            .scrollContentBackground(.hidden)
            .background(.bpPaper)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { ArmBar() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Backplan")
                        .font(.display(22))
                        .foregroundStyle(.bpPurple)
                }
            }
        }
        .tint(.bpPurpleElectric)
    }

    // MARK: Sections

    private var header: some View {
        Section {
            Text("Work backwards from when you need to be ready.")
                .font(.subheadline)
                .foregroundStyle(.bpMuted)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
        }
    }

    private func resultSection(_ result: PlanResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                ResultHeaderView(result: result, eventName: store.plan.eventName)
                if result.isPast {
                    pastTargetNotice
                } else if result.hasSteps {
                    PlanTimeline()
                }
            }
            .neoCard()
            .plainRow()
        }
    }

    /// Shown when the resolved target time has already passed. Offers a one-tap
    /// jump to Tomorrow rather than leaving the user with a dead, all-past plan.
    private var pastTargetNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bpCoral)
            Text("That time has already passed today.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.bpInk)
            Spacer(minLength: 8)
            if store.plan.day == .today {
                Button {
                    store.plan.day = .tomorrow
                } label: {
                    Text("Tomorrow")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .neoPill(fill: .bpLime)
                        .foregroundStyle(.bpInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.bpCoralTint))
    }

    private func targetSection(store: Bindable<PlanStore>) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("What's it for?")
                    TextField("Optional event name", text: store.plan.eventName)
                        .font(.body)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Target time")
                        DatePicker("", selection: targetBinding(store), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Day")
                        Picker("Day", selection: store.plan.day) {
                            ForEach(TargetDay.allCases) { d in
                                Text(d.label).tag(d)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .neoCard()
            .plainRow()
        }
    }

    private func stepsSection(store: Bindable<PlanStore>, result: PlanResult) -> some View {
        Section {
            ForEach(Array(store.wrappedValue.plan.steps.enumerated()), id: \.element.id) { idx, _ in
                StepRowView(
                    step: store.plan.steps[idx],
                    startTime: idx < result.startTimes.count && store.wrappedValue.plan.steps[idx].minutes > 0 ? result.startTimes[idx] : nil,
                    overflow: idx < result.startTimes.count && result.startTimes[idx] < Calendar.current.startOfDay(for: result.target)
                )
                .listRowBackground(Color.bpCard)
                .listRowSeparatorTint(.bpBorder)
            }
            .onMove { store.wrappedValue.moveStep(from: $0, to: $1) }
            .onDelete { store.wrappedValue.removeStep(at: $0) }

            HStack(spacing: 10) {
                Button {
                    store.wrappedValue.addStep()
                } label: {
                    Label("Add step", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.bpInk)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .neoPill(fill: .bpLime)
                }
                .buttonStyle(.plain)

                if !store.wrappedValue.plan.steps.isEmpty {
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Text("Clear all")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.bpMuted)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .neoPill(fill: .bpCard)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            HStack {
                Text("Steps")
                    .font(.display(16))
                    .foregroundStyle(.bpInk)
                    .textCase(nil)
                Spacer()
                if store.wrappedValue.plan.steps.count > 1 {
                    EditButton()
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .tint(.bpPurpleElectric)
                }
            }
        }
        .confirmationDialog("Clear all steps?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) { store.wrappedValue.clearSteps() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var templatesSection: some View {
        Section {
            TemplatesView()
                .plainRow()
        } header: {
            Text("Templates")
                .font(.display(16))
                .foregroundStyle(.bpInk)
                .textCase(nil)
        }
    }

    // MARK: Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.bpMuted)
            .textCase(.uppercase)
    }

    /// Bridge the "HH:mm" string in the model to a DatePicker Date binding.
    private func targetBinding(_ store: Bindable<PlanStore>) -> Binding<Date> {
        Binding(
            get: { store.wrappedValue.plan.targetDate() },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.wrappedValue.plan.target = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }
}

private extension View {
    /// Make a List row borderless/transparent with comfortable horizontal insets.
    func plainRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 20))
    }
}
