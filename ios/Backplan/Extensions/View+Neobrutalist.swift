import SwiftUI

/// Hard-offset shadow card (neobrutalist) — the SwiftUI `.shadow` modifier always
/// blurs, so we fake the crisp offset with a solid ink rectangle behind the fill.
struct NeoCard: ViewModifier {
    var fill: Color = .bpCard
    var border: Color = .bpInk
    var radius: CGFloat = 14
    var offset: CGFloat = 4
    var lineWidth: CGFloat = 2
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(border)
                        .offset(x: offset, y: offset)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(border, lineWidth: lineWidth)
                }
            )
    }
}

extension View {
    func neoCard(
        fill: Color = .bpCard,
        border: Color = .bpInk,
        radius: CGFloat = 14,
        offset: CGFloat = 4,
        lineWidth: CGFloat = 2,
        padding: CGFloat = 18
    ) -> some View {
        modifier(NeoCard(fill: fill, border: border, radius: radius, offset: offset, lineWidth: lineWidth, padding: padding))
    }
}

/// A neobrutalist pill/button surface (no internal padding control beyond caller's).
struct NeoPill: ViewModifier {
    var fill: Color
    var border: Color = .bpInk
    var offset: CGFloat = 2
    var lineWidth: CGFloat = 1.5

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Capsule().fill(border).offset(x: offset, y: offset)
                    Capsule().fill(fill)
                    Capsule().strokeBorder(border, lineWidth: lineWidth)
                }
            )
    }
}

extension View {
    func neoPill(fill: Color, border: Color = .bpInk, offset: CGFloat = 2, lineWidth: CGFloat = 1.5) -> some View {
        modifier(NeoPill(fill: fill, border: border, offset: offset, lineWidth: lineWidth))
    }
}
