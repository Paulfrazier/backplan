import SwiftUI

/// The wake-up sheet: the three inputs every night surface counts from — when
/// you wake, how much sleep, and whose. Opened from the moon button (both
/// skins) and from the Sleep Left / Tonight widgets (`backplan://sleep`), whose
/// empty state is an invitation to exactly this.
///
/// A draft with Save / Cancel, but over the store's own fields: Save writes
/// `pair.morning.target`, `link.sleepNeed` and `link.sleeper` (see
/// `PlanStore.saveSleep`) — the same ones the night controls, the bridge and
/// the tracker read. Nothing here is a second copy of them.
struct SleepSheet: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The morning target as a time of day. With an empty morning that *is*
    /// the wake time; with a routine it is the obligation wake is derived from.
    @State private var target = Date()
    @State private var hours: Double = 11
    @State private var sleeper = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.wakeIsDerived { derivedWake } else { bareWake }
                } header: {
                    header("Wake-up")
                }

                Section {
                    Stepper(value: $hours, in: 1...16, step: 0.25) {
                        HStack {
                            Text("Sleep needed")
                            Spacer()
                            Text(Fmt.duration(needMinutes))
                                .monospacedDigit()
                                .foregroundStyle(.bpInk)
                                .fontWeight(.semibold)
                        }
                    }
                    HStack {
                        Text("Who\u{2019}s sleeping")
                        Spacer()
                        TextField("Optional", text: $sleeper)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    header("Sleep")
                }

                Section {
                    summary
                }
                .listRowBackground(Color.bpPurple.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(.bpPaper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Sleep", systemImage: "moon.zzz.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.display(20))
                        .foregroundStyle(.bpPurple)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.bpPurpleElectric)
        .onAppear(perform: load)
    }

    // MARK: Wake

    /// Empty morning: waking is the whole of it, so the time is set directly.
    private var bareWake: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Wake at", selection: $target, displayedComponents: .hourAndMinute)
            Text("Add a morning routine on the Tomorrow AM tab and wake will be worked back from when you have to be out.")
                .font(.caption)
                .foregroundStyle(.bpMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A morning routine exists, so wake is derived and the time you edit is
    /// the obligation, labelled as that. Never a "Wake at" field that would
    /// silently move the school bell.
    private var derivedWake: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(morningName.map { "Be at \($0) by" } ?? "Out the door by", selection: $target, displayedComponents: .hourAndMinute)
            HStack(alignment: .firstTextBaseline) {
                Text("Wake at")
                Spacer()
                Text(Fmt.time(wake))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(.bpInk)
            }
            Text("\(Fmt.duration(store.pair.morning.totalMinutes)) of morning routine before \(morningName ?? "you\u{2019}re out the door"). Change the routine on the Tomorrow AM tab.")
                .font(.caption)
                .foregroundStyle(.bpMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lights out by \(Fmt.time(deadline))")
                .font(.display(20))
                .foregroundStyle(.bpPurple)
            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.bpMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var summaryText: String {
        let who = sleeper.trimmingCharacters(in: .whitespaces)
        let need = who.isEmpty ? "\(Fmt.duration(needMinutes)) of sleep" : "\(who)\u{2019}s \(Fmt.duration(needMinutes))"
        let base = "That fits \(need) before waking at \(Fmt.time(wake))."
        // Saving switches the edge on; say what that does to the evening plan
        // rather than letting its target turn into "lights out" unannounced.
        guard !store.link.enabled else { return base }
        return base + " Saving chains tomorrow morning to your evening plan, whose target becomes lights out."
    }

    // MARK: Derived values

    /// `nil` for an unnamed morning, whose copy reads "out the door".
    private var morningName: String? {
        let name = store.pair.morning.eventName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private var needMinutes: Int { Int((hours * 60).rounded()) }

    private var targetHHMM: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: target)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var wake: Date {
        store.wakeIsDerived
            ? target.addingTimeInterval(TimeInterval(-store.pair.morning.totalMinutes * 60))
            : target
    }

    private var deadline: Date { wake.addingTimeInterval(TimeInterval(-needMinutes * 60)) }

    // MARK: Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        target = Plan.at(store.pair.morning.target, on: Date())
        hours = Double(store.link.sleepNeed) / 60
        sleeper = store.link.sleeper
    }

    private func save() {
        store.saveSleep(morningTarget: targetHHMM, sleepNeed: needMinutes, sleeper: sleeper)
        dismiss()
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.bpMuted)
            .textCase(.uppercase)
    }
}

/// The in-app way to the sheet, in both skins' toolbars. Same router the
/// widgets' `backplan://sleep` goes through, so there is one sheet.
struct SleepSheetButton: View {
    @Environment(DeepLinkRouter.self) private var router

    var body: some View {
        Button {
            router.showSleep = true
        } label: {
            Image(systemName: "moon.zzz.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.bpPurpleElectric)
        }
        .accessibilityLabel("Wake-up and sleep")
    }
}
