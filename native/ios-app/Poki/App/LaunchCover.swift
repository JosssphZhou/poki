import SwiftUI
import UIKit

/// The launch screen once more, as the app's first frame: the same ground and the same bear in the same place
/// as LaunchScreen.storyboard, so iOS's launch screen turns into the app with nothing moving. It then fades to
/// the page beneath it, so the blue does not jump to the home page's white or near-black. It waits for nothing.
/// With Reduce Motion it is not drawn at all. Touches go through it.
struct LaunchCover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gone = false

    var body: some View {
        if !gone && !reduceMotion {
            Fading { gone = true }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private struct Fading: UIViewRepresentable {
        var done: () -> Void
        func makeUIView(context: Context) -> LaunchCoverView { LaunchCoverView(done: done) }
        func updateUIView(_ view: LaunchCoverView, context: Context) {}
    }
}

/// The fade is a Core Animation one, which the system draws by itself from the moment the app's first frame goes
/// to the screen. A fade the app steps through frame by frame starts its clock when the page is built, and the
/// rest of a cold start can hold the app for longer than the whole fade: it measured as already two thirds over
/// when the first frame showed, and the blue then jumped to the page.
private final class LaunchCoverView: UIView, CAAnimationDelegate {
    /// The bear's side on the launch screen, as in LaunchScreen.storyboard.
    private static let bearSide: CGFloat = 136
    /// `-pokiSlow 20` stretches it, to catch a frame of it in a screenshot.
    private static let duration = 0.35 * HomeMotion.slow

    /// Holds both pictures and is what fades: SwiftUI owns this view's own opacity.
    private let pictures = UIView()
    private let ground = UIImageView(image: UIImage(named: "LaunchGround"))
    private let bear = UIImageView(image: UIImage(named: "ActivityBear-ready"))
    private let done: () -> Void
    private var started = false

    init(done: @escaping () -> Void) {
        self.done = done
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        ground.contentMode = .scaleToFill
        pictures.addSubview(ground)
        pictures.addSubview(bear)
        addSubview(pictures)
    }

    required init?(coder: NSCoder) { fatalError("LaunchCoverView is made in code") }

    override func layoutSubviews() {
        super.layoutSubviews()
        pictures.frame = bounds
        ground.frame = bounds
        bear.bounds = CGRect(x: 0, y: 0, width: Self.bearSide, height: Self.bearSide)
        bear.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !started else { return }
        started = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Self.duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.delegate = self
        pictures.layer.opacity = 0
        pictures.layer.add(fade, forKey: "fade")
    }

    func animationDidStop(_ animation: CAAnimation, finished: Bool) { done() }
}
