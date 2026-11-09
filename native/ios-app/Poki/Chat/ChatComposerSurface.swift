import SwiftUI

/// The full composer inset, including the home-indicator area, is opaque. Keeping only the field
/// opaque still lets the scrolling transcript show between the field and the bottom of the screen.
struct ChatComposerSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background {
                Color(.systemBackground).ignoresSafeArea(.container, edges: .bottom)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color(.separator).opacity(0.25)).frame(height: 0.5)
            }
    }
}
