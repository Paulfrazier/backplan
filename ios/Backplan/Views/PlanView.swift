import SwiftUI

struct PlanView: View {
    @Environment(PlanStore.self) private var store
    @State private var showingClearConfirm = false
    /// Edit vs. Overview for the Steps section. Persisted because checking the
    /// schedule is what most sessions open the app for.
    @AppStorage("backplan.view") private var overviewMode = false
    /// Drives the List's edit mode from `reorderButton`.
    @State private var editMode: EditMode = .inactive

    var body: some View {
        @Bindable var store = store
        let result = store.result()

        NavigationStack {
            List {
                header
                resultSection(result)
                targetSection(store: $store)
                stepsSection(store: $store, result: result)
                placesSection
                templatesSection
            }
            .listStyle(.plain)
            .listSectionSpacing(16)
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(.bpPaper)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { ArmBar() }
            // A List is lazy, so a travel row below the fold never gets to fetch
            // its own leg — which would leave the plan's start time wrong until
            // the user happened to scroll to it. Resolve every leg up front.
            .task { await store.refreshAllTravel() }
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
            if overviewMode {
                overviewRows(store: store, result: result)
            } else {
                editorRows(store: store, result: result)
            }
        } header: {
            HStack {
                sectionTitle("Steps")
                Spacer()
                viewToggle
                if !overviewMode && store.wrappedValue.plan.steps.count > 1 {
                    // Not EditButton(): it labels itself "Edit", which collides with
                    // the toggle's own EDIT half right beside it — two controls
                    // reading the same and doing different things. This one is about
                    // reordering and deleting rows, so it says so.
                    reorderButton
                }
            }
        }
        .confirmationDialog("Clear all steps?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) { store.wrappedValue.clearSteps() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Enters the List's own edit mode for drag-reorder and swipe-delete.
    private var reorderButton: some View {
        Button {
            withAnimation { editMode = editMode == .active ? .inactive : .active }
        } label: {
            Text(editMode == .active ? "Done" : "Reorder")
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(.bpPurpleElectric)
        }
        .buttonStyle(.plain)
    }

    /// Segmented Edit / Overview control, matching the web `.view-toggle`.
    private var viewToggle: some View {
        HStack(spacing: 0) {
            toggleHalf("Edit", active: !overviewMode) { overviewMode = false }
            Rectangle().fill(.bpInk).frame(width: 2)
            toggleHalf("Overview", active: overviewMode) { overviewMode = true }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.bpInk, lineWidth: 2))
        .textCase(nil)
    }

    private func toggleHalf(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(active ? Color.white : .bpInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(active ? Color.bpPurpleElectric : .bpCard)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    @ViewBuilder
    private func overviewRows(store: Bindable<PlanStore>, result: PlanResult) -> some View {
        let steps = store.wrappedValue.plan.steps
        if steps.isEmpty {
            Text("No steps yet. Switch to Edit to add some.")
                .font(.subheadline)
                .foregroundStyle(.bpMuted)
                .plainRow()
        } else {
            let now = Date()
            let dayStart = Calendar.current.startOfDay(for: result.target)
            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                let start = idx < result.startTimes.count ? result.startTimes[idx] : nil
                OverviewRowView(
                    step: step,
                    start: start,
                    overflow: (start.map { $0 < dayStart }) ?? false,
                    state: rowState(start: start, minutes: step.minutes, now: now),
                    origin: store.wrappedValue.resolveOrigin(for: step.id)?.place
                )
                .plainRow()
            }
            OverviewTargetRow(target: result.target,
                              eventName: store.wrappedValue.plan.eventName)
                .plainRow()
        }
    }

    private func rowState(start: Date?, minutes: Int, now: Date) -> OverviewRowView.RowState {
        guard let start else { return .upcoming }
        let end = start.addingTimeInterval(TimeInterval(minutes) * 60)
        if now >= end { return .done }
        if now >= start { return .now }
        return .upcoming
    }

    @ViewBuilder
    private func editorRows(store: Bindable<PlanStore>, result: PlanResult) -> some View {
            // Iterate the *binding* so each row holds an identity-resolved
            // binding. `store.plan.steps[idx]` looked equivalent but captured a
            // fixed index: a row that outlived its element by even one frame —
            // a swipe-delete, Clear all, a starter swapping the list — read
            // past the end and trapped with "Index out of range". The position
            // still comes from the array, but only to look up a start time,
            // and only when it's in range.
            ForEach(store.plan.steps) { $step in
                let idx = store.wrappedValue.plan.steps.firstIndex { $0.id == step.id }
                let start: Date? = idx.flatMap { $0 < result.startTimes.count ? result.startTimes[$0] : nil }
                StepRowView(
                    step: $step,
                    startTime: step.minutes > 0 ? start : nil,
                    overflow: (start.map { $0 < Calendar.current.startOfDay(for: result.target) }) ?? false
                )
                // A bordered card per row, inset to the same gutter as the cards
                // above. Edge-to-edge white slabs on paper read as floating.
                .listRowBackground(stepRowBackground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 20))
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

                Button {
                    store.wrappedValue.addTravelStep()
                } label: {
                    Label("Travel", systemImage: "car.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.bpInk)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .neoPill(fill: .bpCard)
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

            QuickAddBar()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 12))
    }

    private var placesSection: some View {
        Section {
            PlacesView()
                .plainRow()
        } header: {
            sectionTitle("Places")
        }
    }

    private var templatesSection: some View {
        Section {
            TemplatesView()
                .plainRow()
        } header: {
            sectionTitle("Templates")
        }
    }

    // MARK: Helpers

    /// The card surface behind a step row. Drawn as a row background rather than
    /// wrapping the steps in one `VStack` card, because `.onMove` / `.onDelete`
    /// / `EditButton` only work on real `List` rows.
    private var stepRowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.bpCard)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.bpInk, lineWidth: 2)
            )
    }

    /// Section title: purple like the web `h2`, with the same rule trailing off
    /// the end so sections read as anchored rather than free-floating.
    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.display(17))
                .foregroundStyle(.bpPurple)
                .textCase(nil)
            Rectangle()
                .fill(.bpRule)
                .frame(height: 1.5)
        }
    }

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
