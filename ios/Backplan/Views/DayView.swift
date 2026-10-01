import SwiftUI
import UniformTypeIdentifiers

/// The Day tab: pin the times that can't move, drop everything else in, see
/// when to leave. Port of the web Day view.
struct DayView: View {
    @Environment(PlanStore.self) private var store
    @AppStorage("backplan.mode") private var mode = "plan"
    @State private var editMode: EditMode = .inactive
    @State private var expanded: Set<UUID> = DayView.debugExpanded
    @State private var scrollTarget: UUID?
    @State private var pendingEdit: UUID?

    var body: some View {
        // 30s is plenty: the hero's countdown is minute-granular.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let result = store.dayResult(now: ctx.date)
            content(result, now: ctx.date)
                .task(id: result.needed.map(\.key)) { await store.fetchDayLegs(result.needed) }
        }
    }

    private func content(_ result: DayResult, now: Date) -> some View {
        @Bindable var store = store
        let status = DayStatus.make(result, now: now)
        return NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        DayHeroView(status: status).plainDayRow()
                    }
                    Section {
                        blockRows(result, now: now, store: $store)
                        footer(result)
                    } header: {
                        header(store: $store)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
                .scrollContentBackground(.hidden)
                .background(.bpPaper)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        ArmBar(source: .day)
                        DayTrayView { id in scrollTarget = id }
                    }
                }
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    scrollTarget = nil
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your day")
                        .font(.display(22))
                        .foregroundStyle(.bpPurple)
                }
            }
        }
        .tint(.bpPurpleElectric)
        .confirmationDialog(
            "Open this plan in the Plan tab?",
            isPresented: Binding(get: { pendingEdit != nil }, set: { if !$0 { pendingEdit = nil } }),
            titleVisibility: .visible
        ) {
            Button("Open plan", role: .destructive) {
                if let id = pendingEdit { openPlan(id) }
                pendingEdit = nil
            }
            Button("Cancel", role: .cancel) { pendingEdit = nil }
        } message: {
            Text("It replaces the plan you have open there.")
        }
    }

    @ViewBuilder
    private func blockRows(_ result: DayResult, now: Date, store: Bindable<PlanStore>) -> some View {
        let s = store.wrappedValue
        ForEach(store.day.blocks) { $block in
            // Resolve by id: a row can outlive its index for a frame mid-delete.
            if let item = result.items.first(where: { $0.id == block.id }) {
                DayBlockRow(
                    block: $block,
                    item: item,
                    gap: result.gap(before: item.index),
                    nextAnchorName: result.gap(before: item.index).map { g in
                        let n = s.day.blocks.indices.contains(g.q) ? s.day.blocks[g.q].name : ""
                        return n.trimmingCharacters(in: .whitespaces).isEmpty ? "the next fixed time" : n
                    },
                    places: s.places,
                    linked: block.link.map { id in s.templates.contains { $0.id == id } } ?? false,
                    now: now,
                    expanded: Binding(
                        get: { expanded.contains(block.id) },
                        set: { if $0 { expanded.insert(block.id) } else { expanded.remove(block.id) } }
                    ),
                    onEditPlan: { requestEdit(block.link) }
                )
                .id(block.id)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 16))
            }
        }
        .onMove { s.day.blocks.move(fromOffsets: $0, toOffset: $1) }
        .onDelete { s.day.blocks.remove(atOffsets: $0) }
        // Drops from the tray: a long-press on a chip lifts it, and the List
        // opens a gap wherever it's held.
        .onInsert(of: [.plainText]) { index, providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let payload = obj as? String, let item = TrayItem(payload: payload) else { return }
                    Task { @MainActor in
                        if let id = s.addBlock(item, at: index), item == .flex || item == .anchor {
                            scrollTarget = id
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func footer(_ result: DayResult) -> some View {
        let s = store
        if result.items.isEmpty {
            Text("Nothing planned yet. Long-press a block in the tray and drag it up, or tap one to add it.")
                .font(.subheadline)
                .foregroundStyle(.bpMuted)
                .plainDayRow()
        } else if !s.day.blocks.contains(where: { $0.placeID != nil || ($0.steps?.contains { $0.travel?.to != nil } ?? false) }) {
            Text(s.places.isEmpty
                 ? "Tip: save home and a few spots under Plan → Places, then give blocks a place — travel time between them fills itself in."
                 : "Tip: give a block a place and the travel time from the previous place (or home) fills itself in.")
                .font(.footnote)
                .foregroundStyle(.bpMuted)
                .plainDayRow()
        }
    }

    private func header(store: Bindable<PlanStore>) -> some View {
        HStack(spacing: 10) {
            Picker("Which day", selection: store.day.date) {
                ForEach(TargetDay.allCases) { d in Text(d.label).tag(d) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            Spacer()
            if store.wrappedValue.day.blocks.count > 1 {
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
        }
        .padding(.vertical, 4)
    }

    private func requestEdit(_ templateID: UUID?) {
        guard let templateID else { return }
        if store.editingWouldReplace(templateID) {
            pendingEdit = templateID
        } else {
            openPlan(templateID)
        }
    }

    private func openPlan(_ templateID: UUID) {
        store.editLinkedPlan(templateID)
        mode = "plan"
    }

    private static var debugExpanded: Set<UUID> {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-BPExpand") {
            return Set(PlanStore.debugDayBlockIDs())
        }
        #endif
        return []
    }
}

// MARK: - Hero

struct DayHeroView: View {
    let status: DayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    label(status.label)
                    Text(status.time)
                        .font(.display(40))
                        .foregroundStyle(status.late ? .bpCoral : .bpLimeInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(status.meta)
                        .font(.footnote)
                        .foregroundStyle(.bpMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    label("Next fixed")
                    Text(status.nextFixedTime)
                        .font(.display(26))
                        .foregroundStyle(.bpPurple)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(status.nextFixedName)
                        .font(.footnote)
                        .foregroundStyle(.bpMuted)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                .frame(maxWidth: 130, alignment: .trailing)
            }
            if let warning = status.warning {
                Text(warning)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x9A2A16))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.bpCoralTint))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.bpCoral, lineWidth: 2))
            }
        }
        .neoCard()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.bpMuted)
            .textCase(.uppercase)
    }
}

extension View {
    func plainDayRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 20))
    }
}
