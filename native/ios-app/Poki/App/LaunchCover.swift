import SwiftUI

/// The launch screen once more, as the app's first frame: the same ground and the same bear in the same place
/// as LaunchScreen.storyboard, so iOS's launch screen turns into the app with nothing moving. It then fades to
/// the page beneath it, so the blue does not jump to the home page's white or near-black. It waits for nothing:
/// the fade starts with the first frame. With Reduce Motion it is taken away at once. Touches go through it.
struct LaunchCover: View {
    /// The bear's side on the launch screen, as in LaunchScreen.storyboard.
    static let bear: CGFloat = 136
    /// `-pokiSlow 20` stretches it, to catch a frame of it in a screenshot.
    static let fade = HomeMotion.paced(.easeOut(duration: 0.35))

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 1.0
    @State private var gone = false

    var body: some View {
        if !gone {
            ZStack {
                Image("LaunchGround").resizable()
                Image("ActivityBear-ready").resizable().frame(width: Self.bear, height: Self.bear)
            }
            .ignoresSafeArea()
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { gone = true; return }
                withAnimation(Self.fade) { opacity = 0 } completion: { gone = true }
            }
        }
    }
}
