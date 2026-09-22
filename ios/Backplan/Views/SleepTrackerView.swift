import SwiftUI

/// Track to sleep — the same night edge the bridge draws, anchored at now.
///
/// The pair pins both ends (a lights-out you chose, a morning you can't move)
/// and measures the gap. The tracker pins only the far end and lets the near one
/// ride the wall clock, because the question at 10pm in someone else's living
/// room isn't "when should bedtime start", it's *"if I stand up right now, what
/// do I get?"*. Same wake, same sleep need, same deadline; read forwards from
/// now instead of backwards from bedtime.
///
/// Mirrors the web `.track` section in index.html, wording included.
struct SleepTrackerView: View {
    @Environment(PlanStore.self) private var store

    @State private var editingOrigin = false
    @State private var isLoading = false
    @State private var error: TravelError?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            head
            // Render-once / tick-often, the same split index.html uses: only the
            // figure and the verdict move on the clock, so only they sit inside
            // a ticking context. Rebuilding the ride controls every second would
            // churn the sheet and loading state that live below them.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let track = store.sleepTrack(now: context.date) {
                    VStack(alignment: .leading, spacing: 14) {
                        figure(track)
                        rule
                        verdict(track)
                    }
                }
            }
            rule
            ride
            rule
            tail
        }
        .sheet(isPresented: $editingOrigin) {
            PlaceSearchView(
                title: "Where you are now",
                saved: store.places,
                anchor: store.searchAnchor
            ) { suggestion in
                store.track.ride.from = suggestion.ref
            }
        }
        // Changing mode, origin, or home should re-route; nothing else should.
        .task(id: rideKey) { await load(force: false) }
    }

    private var rule: some View {
        Rectangle().fill(.bpRule).frame(height: 1.5)
    }

    // MARK: Head

    private var head: some View {
        HStack(spacing: 10) {
            Text("Track to sleep")
                .font(.caption.weight(.bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(.bpPurple)
            Spacer(minLength: 0)
            Button {
                store.setTrackMode(false)
            } label: {
                Text("Exit")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .neoPill(fill: .bpCard)
                    .foregroundStyle(.bpMuted)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: The figure

    /// The number that moves. Monospaced digits so a digit rolling over doesn't
    /// shove the "of sleep" suffix sideways once a minute.
    private func figure(_ track: SleepTrack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("If you leave now")
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.bpMuted)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.sleep(track.sleepMinutes))
                    .font(.display(46))
                    .monospacedDigit()
                    .foregroundStyle(figureColor(track))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("of sleep")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.bpMuted)
            }
            Text(track.chainText(sleepNeed: store.link.sleepNeed))
                .font(.footnote)
                .foregroundStyle(.bpMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verdict(_ track: SleepTrack) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(track.pillText)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .neoPill(fill: pillFill(track), border: pillBorder(track))
                .foregroundStyle(pillInk(track))
                .fixedSize()
            Text(track.verdictText(sleepNeed: store.link.sleepNeed))
                .font(.subheadline)
                .foregroundStyle(.bpInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The ride home

    private var ride: some View {
        VStack(alignment: .leading, spacing: 10) {
            modePicker
            VStack(alignment: .leading, spacing: 10) {
                endpoint(label: "Leaving from",
                         value: store.track.ride.from?.label,
                         placeholder: "Where you are right now",
                         tappable: true)
                // The destination is the mode's premise, not a field —
                // "back-plan to home" is what makes this a sleep tracker and not
                // a second trip planner.
                endpoint(label: "Heading",
                         value: store.homeRef?.label,
                         placeholder: "No home place set",
                         tappable: false)
            }
            resultLine
            Text("Free-flow times, no traffic model — treat the trip home as a floor, not a promise.")
                .font(.caption)
                .foregroundStyle(.bpMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(TravelMode.allCases) { mode in
                Button {
                    store.track.ride.mode = mode
                } label: {
                    Label(mode.label, systemImage: mode.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .neoPill(fill: store.track.ride.mode == mode ? .bpPurpleElectric : .bpCard)
                        .foregroundStyle(store.track.ride.mode == mode ? Color.white : .bpInk)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func endpoint(label: String, value: String?, placeholder: String, tappable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.bpMuted)
            Button {
                if tappable { editingOrigin = true }
            } label: {
                HStack(spacing: 6) {
                    Text(value ?? placeholder)
                        .font(.subheadline)
                        .foregroundStyle(value == nil ? .bpMuted : .bpInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(!tappable && value != nil ? Color.bpLimeTint : Color.bpCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(!tappable && value != nil ? Color.bpLime : Color.bpRule,
                                      lineWidth: !tappable && value != nil ? 2 : 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!tappable)
        }
    }

    /// The ride's status line wears a travel step's words, because it is running
    /// the identical machinery — same RouteService, same cache, same caveat.
    @ViewBuilder
    private var resultLine: some View {
        HStack(spacing: 8) {
            if store.homeRef == nil {
                Text("Mark one of your saved places as home — that is what this mode plans to.")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoading {
                ProgressView().controlSize(.small)
                Text("Looking up route…").font(.caption).foregroundStyle(.bpMuted)
            } else if let error {
                Text(error.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bpCoral)
                refreshButton
            } else if let result = store.track.ride.result {
                Text("\(TravelFmt.distance(result.distanceM)) · \(Fmt.duration(result.minutes)) free-flow \(store.track.ride.mode.label.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
                refreshButton
            } else {
                Text("Say where you are and the trip home gets counted.")
                    .font(.caption)
                    .foregroundStyle(.bpMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await load(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(.bpMuted)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 7).strokeBorder(.bpRule, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Re-fetch travel time")
    }

    // MARK: Wake + sleep need

    /// The two ends of the figure above. The card that normally carries them is
    /// swapped out in this mode, so they come along — reading and writing the
    /// same `link.sleepNeed` and morning target the bridge does, never a copy.
    private var tail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Wake at")
                    DatePicker("", selection: wakeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(wakeIsDerived)
                        .opacity(wakeIsDerived ? 0.5 : 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Sleep needed")
                    HStack(spacing: 6) {
                        TextField("7.5", value: sleepHoursBinding, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Text("hours").font(.footnote).foregroundStyle(.bpMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(wakeNote)
                .font(.caption)
                .foregroundStyle(.bpMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Wake is editable only where it is genuinely a free variable. With a
    /// morning routine in place it is derived — the obligation minus the routine
    /// — and a field that silently moved the school bell would lie.
    private var wakeIsDerived: Bool { !store.pair.morning.steps.isEmpty }

    private var wakeBinding: Binding<Date> {
        Binding(
            // With an empty morning, wake *is* the morning target, so one getter
            // serves both states.
            get: { store.sleepTrack()?.wake ?? Date() },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.pair.morning.target = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }

    private var sleepHoursBinding: Binding<Double> {
        Binding(
            get: { Double(store.link.sleepNeed) / 60 },
            set: { hours in
                guard hours.isFinite, hours >= 0 else { return }
                store.link.sleepNeed = Int((hours * 60).rounded())
            }
        )
    }

    private var wakeNote: String {
        guard wakeIsDerived else {
            return "Tomorrow morning is empty, so waking is the whole of it. Exit and open the Tomorrow AM tab to back this up from a fixed obligation."
        }
        let track = store.sleepTrack()
        let name = store.pair.morning.eventName.trimmingCharacters(in: .whitespaces)
        let label = name.isEmpty ? "Out the door" : name
        let target = track.map { Fmt.time($0.morningTarget) } ?? "—"
        return "Derived — \(Fmt.duration(store.pair.morning.totalMinutes)) of tomorrow morning before \(label) at \(target). Exit to change it."
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.bpMuted)
            .textCase(.uppercase)
    }

    // MARK: Colours

    private func figureColor(_ track: SleepTrack) -> Color {
        switch track.verdict {
        case .onTrack: return .bpLimeInk
        case .tight: return .bpGoldInk
        case .short: return .bpCoral
        }
    }

    private func pillFill(_ track: SleepTrack) -> Color {
        switch track.verdict {
        case .onTrack: return .bpLimeTint
        case .tight: return .bpGoldTint
        case .short: return .bpCoralTint
        }
    }

    private func pillBorder(_ track: SleepTrack) -> Color {
        switch track.verdict {
        case .onTrack: return .bpLime
        case .tight: return .bpGold
        case .short: return .bpCoral
        }
    }

    private func pillInk(_ track: SleepTrack) -> Color {
        switch track.verdict {
        case .onTrack: return .bpLimeInk
        case .tight: return .bpGoldInk
        case .short: return .bpCoral
        }
    }

    // MARK: Actions

    private var rideKey: String {
        let from = store.track.ride.from.map { "\($0.lat),\($0.lng)" } ?? "-"
        let home = store.homeRef.map { "\($0.lat),\($0.lng)" } ?? "-"
        return "\(store.track.ride.mode.rawValue)|\(from)|\(home)"
    }

    private func load(force: Bool) async {
        guard store.track.ride.from != nil, store.homeRef != nil else {
            error = nil
            await store.refreshRide(force: false)   // clears a stale result
            return
        }
        isLoading = true
        error = await store.refreshRide(force: force)
        isLoading = false
    }
}
