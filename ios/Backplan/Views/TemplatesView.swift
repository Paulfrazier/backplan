import SwiftUI

struct TemplatesView: View {
    @Environment(PlanStore.self) private var store
    @State private var showingSave = false
    @State private var newName = ""

    var body: some View {
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
        .alert("Save template", isPresented: $showingSave) {
            TextField("Template name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.saveTemplate(name: newName) }
        } message: {
            Text("Save the current target and steps as a reusable template.")
        }
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
