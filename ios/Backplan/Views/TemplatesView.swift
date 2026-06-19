import SwiftUI

struct TemplatesView: View {
    @Environment(PlanStore.self) private var store
    @State private var showingSave = false
    @State private var newName = ""
    @State private var pendingStarter: Starters.Starter?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Starters (prebuilt routines) ──
            VStack(alignment: .leading, spacing: 8) {
                Text("Starters — tap to load a routine")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.bpMuted)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Starters.plans) { starter in
                            starterChip(starter)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // ── Your templates ──
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    newName = store.plan.eventName
                    showingSave = true
                } label: {
                    Label("Save current as template", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.bpInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .neoPill(fill: .bpGold)
                }
                .buttonStyle(.plain)

                if !store.templates.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.templates) { template in
                                chip(template)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .alert("Save template", isPresented: $showingSave) {
            TextField("Template name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.saveTemplate(name: newName) }
        } message: {
            Text("Save the current target and steps as a reusable template.")
        }
        .confirmationDialog(
            "Replace your current steps?",
            isPresented: Binding(
                get: { pendingStarter != nil },
                set: { if !$0 { pendingStarter = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let starter = pendingStarter {
                Button("Load \(starter.name)", role: .destructive) {
                    store.loadStarter(starter)
                    pendingStarter = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingStarter = nil }
        } message: {
            Text("This swaps in the starter's steps. Your target time and event name stay.")
        }
    }

    private func starterChip(_ starter: Starters.Starter) -> some View {
        Button {
            if store.hasMeaningfulSteps {
                pendingStarter = starter
            } else {
                store.loadStarter(starter)
            }
        } label: {
            HStack(spacing: 6) {
                Text(starter.glyph)
                Text(starter.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.bpInk)
                Text("\(starter.stepCount) steps")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.bpMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .neoPill(fill: .bpGold.opacity(0.22))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ template: Template) -> some View {
        HStack(spacing: 6) {
            Button {
                store.loadTemplate(template)
            } label: {
                Text(template.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.bpInk)
            }
            .buttonStyle(.plain)

            Button {
                store.deleteTemplate(template)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.bpMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .neoPill(fill: .bpCard)
    }
}
