import SwiftUI

/// Keeps the same editor alive when focus or larger text moves it above the controls.
struct ComposerLayout: Layout {
    var expanded: Bool
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let sizes = measure(width: width, subviews: subviews)
        let controlsHeight = max(sizes.leading.height, sizes.trailing.height)
        let height = sizes.expanded ? sizes.field.height + spacing + controlsHeight : max(sizes.field.height, controlsHeight)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        let bottom = bounds.maxY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bottom), anchor: .bottomLeading,
                          proposal: ProposedViewSize(sizes.leading))
        subviews[1].place(at: CGPoint(x: sizes.expanded ? bounds.minX : bounds.minX + sizes.leading.width + spacing,
                                     y: sizes.expanded ? bounds.minY : bounds.midY),
                          anchor: sizes.expanded ? .topLeading : .leading, proposal: ProposedViewSize(sizes.field))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bottom), anchor: .bottomTrailing,
                          proposal: ProposedViewSize(sizes.trailing))
    }

    private func measure(width: CGFloat, subviews: Subviews) -> (leading: CGSize, field: CGSize, trailing: CGSize, expanded: Bool) {
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        let inlineWidth = width - leading.width - trailing.width - 2 * spacing
        let twoRows = expanded || inlineWidth < 140
        let fieldWidth = twoRows ? width : inlineWidth
        let field = subviews[1].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
        return (leading, field, trailing, twoRows)
    }
}
