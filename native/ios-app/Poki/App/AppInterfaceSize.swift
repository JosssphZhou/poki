import SwiftUI
import UIKit

/// One native content-size category for this window, including UIKit presentations and editors.
/// Removing the override restores iOS's current per-app preference immediately.
enum AppInterfaceSize {
    static let defaultsKey = "appInterfaceSize"
    static let system = "system"
    static let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    static func category(for preference: String) -> UIContentSizeCategory? {
        categories.first { $0.rawValue == preference }
    }

    static func apply(_ preference: String, to window: UIWindow) {
        if let category = category(for: preference) {
            if !window.traitOverrides.contains(UITraitPreferredContentSizeCategory.self)
                || window.traitCollection.preferredContentSizeCategory != category {
                window.traitOverrides.preferredContentSizeCategory = category
            }
        } else if window.traitOverrides.contains(UITraitPreferredContentSizeCategory.self) {
            window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
        }
    }

    /// The navigation bars use Poki's custom fonts, which must resolve against this window's traits.
    static func updateNavigationFonts(in window: UIWindow) {
        let traits = window.traitCollection
        let systemLarge = UIFont.preferredFont(forTextStyle: .largeTitle, compatibleWith: traits)
        let bold = systemLarge.fontDescriptor.withSymbolicTraits(.traitBold) ?? systemLarge.fontDescriptor
        let large = Prominent.uiFont(.largeTitle, .bold, compatibleWith: traits) ?? UIFont(descriptor: bold, size: systemLarge.pointSize)
        let inline = Prominent.uiFont(.headline, .semibold, compatibleWith: traits) ?? UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
        func apply(_ bar: UINavigationBar) {
            var largeAttributes = bar.largeTitleTextAttributes ?? [:]
            var inlineAttributes = bar.titleTextAttributes ?? [:]
            largeAttributes[.font] = large
            inlineAttributes[.font] = inline
            bar.largeTitleTextAttributes = largeAttributes
            bar.titleTextAttributes = inlineAttributes
        }
        apply(UINavigationBar.appearance())
        func visit(_ controller: UIViewController) {
            if let navigation = controller as? UINavigationController { apply(navigation.navigationBar) }
            controller.children.forEach(visit)
            if let presented = controller.presentedViewController { visit(presented) }
        }
        if let root = window.rootViewController { visit(root) }
    }

}

struct InterfaceSizeSettingsView: View {
    @AppStorage(AppInterfaceSize.defaultsKey) private var preference = AppInterfaceSize.system
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pendingIndex: Int?
    @State private var dragging = false

    private var followsSystem: Bool { AppInterfaceSize.category(for: preference) == nil }
    private var index: Int {
        let category = AppInterfaceSize.category(for: preference) ?? UIContentSizeCategory(typeSize)
        return AppInterfaceSize.categories.firstIndex(of: category) ?? 3
    }

    var body: some View {
        GeometryReader { geometry in
            List {
                Section {
                    controls
                }
                Section {
                    InterfaceSizePreview()
                        .dynamicTypeSize(previewSize)
                        // Leave enough room for the real chat components at accessibility sizes.
                        .frame(height: max(520, geometry.size.height * 0.72))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    SettingsHeader("Preview")
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Interface Size")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewSize: DynamicTypeSize {
        guard let pendingIndex else { return typeSize }
        return DynamicTypeSize(AppInterfaceSize.categories[pendingIndex]) ?? typeSize
    }

    @ViewBuilder private var controls: some View {
        Toggle("Follow System", isOn: Binding(
            get: { followsSystem },
            set: { preference = $0 ? AppInterfaceSize.system : UIContentSizeCategory(typeSize).rawValue }
        ))
        .accessibilityIdentifier("interfaceSize.followSystem")
        if !followsSystem {
            Slider(value: Binding(
                get: { Double(pendingIndex ?? index) },
                set: { value in
                    let step = Int(value.rounded())
                    if dragging {
                        pendingIndex = step
                    } else {
                        preference = AppInterfaceSize.categories[step].rawValue
                    }
                }
            ), in: 0...Double(AppInterfaceSize.categories.count - 1), step: 1) {
                Text("Interface Size")
            } minimumValueLabel: {
                endpoint("Interface Size Minimum", size: 14)
            } maximumValueLabel: {
                endpoint("Interface Size Maximum", size: 18)
            } onEditingChanged: { editing in
                dragging = editing
                if !editing, let pendingIndex {
                    preference = AppInterfaceSize.categories[pendingIndex].rawValue
                    self.pendingIndex = nil
                }
            }
            .sensoryFeedback(.selection, trigger: pendingIndex ?? index)
            .tint(Color(.secondaryLabel))
            .accessibilityValue(Text("Size \((pendingIndex ?? index) + 1) of \(AppInterfaceSize.categories.count)"))
            .accessibilityIdentifier("interfaceSize.slider")
        }
    }

    private func endpoint(_ label: LocalizedStringKey, size: CGFloat) -> some View {
        Text(label)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 28)
            .dynamicTypeSize(.large)
            .accessibilityHidden(true)
    }

}

/// Sample data rendered by the production chat components so their appearance stays in sync.
private struct InterfaceSizePreview: View {
    private let started = Date(timeIntervalSince1970: 0)

    var body: some View {
        VStack(spacing: 0) {
            ChatTopBar(status: PokiStatus(.ready), home: false, busy: false,
                       openThreads: {}, newConversation: {}, openDetails: {})
                .overlayPreferenceValue(PicturePlaceKey.self) { anchors in
                    GeometryReader { proxy in
                        PokiFlight(status: PokiStatus(.ready), home: false, writing: false,
                                   places: anchors.mapValues { proxy[$0] }, pokes: 0, tap: {})
                    }
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Poki"))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MessageBubble(direction: .outgoing, text: String(localized: "Help me plan tomorrow."), tail: true)
                    MessageBubble(direction: .incoming, text: String(localized: "Start with your most important task in the morning. Leave time for lunch and a short walk.\n\nI can also help you set a reminder."), tail: true)
                    TaskCard(title: String(localized: "Reminder created"),
                             steps: [PlanStep(String(localized: "Tomorrow at 9:00 AM"), state: .done)],
                             state: .done, app: AppIconStore.name("com.apple.reminders") ?? "Reminders", started: started,
                             ended: started.addingTimeInterval(2), plannedTotal: 1)
                    MessageBubble(direction: .outgoing, text: String(localized: "Show me the full plan."), tail: true)
                    MessageBubble(direction: .incoming, text: String(localized: "Your plan is ready. You can review it here and make changes whenever you like."), tail: true)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            ComposerInputView(input: .constant(""), focused: .constant(false), running: false,
                              send: { _, _ in }, stop: {}, openVoice: {})
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Message Poki"))
                .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
        }
        .background { HomeBackdrop(home: false, working: false, frozen: true) }
        .clipShape(.rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
        .accessibilityIdentifier("interfaceSize.preview")
    }
}
