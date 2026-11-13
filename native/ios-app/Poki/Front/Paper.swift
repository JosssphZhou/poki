import SwiftUI

/// The front's colours and type, taken from the prototype (`design/app-prototype/css/app.css`): warm paper,
/// near-black ink, one grey for second-level words, and hairlines. Flat: no cards, no shadows, and what you
/// can press is ink on paper. Poki's light (`PokiLight`) is the only colour.
enum Paper {
    static let page = dynamic(0xFAFAF9, 0x0C0C0D)
    static let ink = dynamic(0x111110, 0xF4F4F1)
    static let ink2 = dynamic(0x6F6F69, 0x8D8D87)
    /// The fill of quiet things: your message, the search field, a mark's circle.
    static let fill = dynamic(0xEFEFEC, 0x1C1C1E)
    static let line = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.14) : UIColor(white: 0, alpha: 0.13) })
    /// The message field and the suggestions: the bear's blue.
    static let field = dynamic(0xC4CEFB, 0x3A4270).opacity(0.8)
    static let chip = dynamic(0xDEE3FD, 0x2A3052).opacity(0.5)
    static let chipInk = dynamic(0x262D63, 0xD5DAFB)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { UIColor(Color(hex: $0.userInterfaceStyle == .dark ? dark : light)) })
    }

    /// A page's large words ("Good afternoon.", a first-run title): 28 semibold, set tight.
    static let title = Font.system(size: 28, weight: .semibold)
    static let titleTracking: CGFloat = -0.6
    static let row = Font.system(size: 17, weight: .medium)
    static let value = Font.system(size: 15)
    static let header = Font.system(size: 13, weight: .semibold)
    static let note = Font.system(size: 13)
}

/// What you press is ink: the page's one main button, a capsule in the words' own colour.
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Paper.page)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Paper.ink, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

/// A pill or a round button under the finger: it gives a little, and comes back when let go.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A switch in ink: the track takes the words' colour when on, in light and in dark.
struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Capsule().fill(configuration.isOn ? Paper.ink : Paper.ink2.opacity(0.35))
                .frame(width: 51, height: 31)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? Paper.page : .white).padding(2.5)
                }
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
        }
        .contentShape(.rect)
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// One flat row of a settings page: its name, a second line if it has one, a value, and a chevron when
/// it opens something. Rows are separated by hairlines (`PaperRows`).
struct PaperRow<Leading: View>: View {
    var title: String
    var detail: String?
    var value: String?
    var chevron = true
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).font(Paper.row).foregroundStyle(Paper.ink)
                if let detail { Text(verbatim: detail).font(Paper.note).foregroundStyle(Paper.ink2) }
            }
            Spacer(minLength: 8)
            if let value { Text(verbatim: value).font(Paper.value).foregroundStyle(Paper.ink2).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Paper.ink2.opacity(0.6)) }
        }
        .frame(minHeight: 54).contentShape(.rect)
    }
}

extension PaperRow where Leading == EmptyView {
    init(_ title: String, detail: String? = nil, value: String? = nil, chevron: Bool = true) {
        self.init(title: title, detail: detail, value: value, chevron: chevron, leading: { EmptyView() })
    }
}

/// A group of flat rows: a hairline above, between and below them.
struct PaperRows<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Paper.line).frame(height: 1)
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                    Rectangle().fill(Paper.line).frame(height: 1)
                }
            }
        }
    }
}

/// A small heading over a group of rows.
struct PaperHeader: View {
    var text: String
    var body: some View {
        Text(verbatim: text).font(Paper.header).foregroundStyle(Paper.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 22).padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The quiet words under a group of rows.
struct PaperFoot: View {
    var text: String
    var body: some View {
        Text(verbatim: text).font(Paper.note).foregroundStyle(Paper.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }
}

/// A flat settings page: its groups in one scrolling column, on paper.
struct PaperScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 0) { content }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.bottom, 28)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
    }
}

/// A mark in front of a row: done (ink, a tick), still to do (its number in a ring), or needs you (a ring
/// with an exclamation mark).
struct PaperMark: View {
    enum Kind: Equatable { case done, number(Int), warn, failed, yours }
    var kind: Kind
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            switch kind {
            case .done:
                Circle().fill(Paper.ink)
                Image(systemName: "checkmark").font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(Paper.page)
            case .number(let n):
                Circle().strokeBorder(Paper.ink2, lineWidth: 1.5)
                Text(verbatim: "\(n)").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Paper.ink2)
            case .warn:
                Circle().strokeBorder(Paper.ink, lineWidth: 1.5)
                Text(verbatim: "!").font(.system(size: size * 0.54, weight: .bold)).foregroundStyle(Paper.ink)
            case .failed:
                Circle().strokeBorder(Paper.ink2, lineWidth: 1.5)
                Image(systemName: "xmark").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Paper.ink2)
            case .yours:
                Circle().strokeBorder(Paper.ink2, lineWidth: 1.5)
                Image(systemName: "person.fill").font(.system(size: size * 0.42)).foregroundStyle(Paper.ink2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A `Section` of one of the app's own lists, drawn the front's way: flat rows on paper with hairlines
/// between them, the heading and the note in the page's small type. It takes what `Section` takes, so a
/// page keeps its rows, pickers and fields and only changes the word.
struct PaperSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content(); self.header = header(); self.footer = footer()
    }

    var body: some View {
        Section {
            content
                .font(Paper.row)
                .labelStyle(PaperLabelStyle())
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Paper.line)
                // Room above and below for a row of several lines; one line sits in the row's 54 points.
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } header: {
            header
                .font(Paper.header).foregroundStyle(Paper.ink2).textCase(nil)
                .listRowInsets(EdgeInsets(top: 22, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
        } footer: {
            footer
                .font(Paper.note).foregroundStyle(Paper.ink2)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.visible, edges: .top)
        .listSectionSeparator(.hidden, edges: .bottom)
        .listSectionSeparatorTint(Paper.line)
    }
}

extension PaperSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) { self.init(content: content, header: { EmptyView() }, footer: { EmptyView() }) }
}

extension PaperSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) { self.init(content: content, header: header, footer: { EmptyView() }) }
}

extension PaperSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) { self.init(content: content, header: { EmptyView() }, footer: footer) }
}

extension PaperSection where Header == Text, Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(content: content, header: { Text(title) }, footer: { EmptyView() }) }
}

/// A row's symbol and its words: the symbol in grey at one width, so the words of every row line up.
struct PaperLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon.foregroundStyle(Paper.ink2).frame(width: 22)
            configuration.title
        }
    }
}

/// A row's name and its value, as `PaperRow` sets them: the name in ink, the value smaller and grey.
struct PaperValueStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label.foregroundStyle(Paper.ink)
            Spacer(minLength: 8)
            configuration.content.font(Paper.value).foregroundStyle(Paper.ink2).multilineTextAlignment(.trailing)
        }
    }
}

extension View {
    /// A system list of `PaperSection`s: plain, on paper, with ink for what can be pressed.
    func paperList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Paper.page)
            .toolbarBackground(Paper.page, for: .navigationBar)
            .environment(\.defaultMinListRowHeight, 54)
            .labeledContentStyle(PaperValueStyle())
            .toggleStyle(InkToggleStyle())
            .tint(Paper.ink)
    }

    /// One of the app's own pages, pushed over the front: paper behind it and a plain bar on top.
    func paperPage() -> some View {
        scrollContentBackground(.hidden)
            .background(Paper.page)
            .toolbarBackground(Paper.page, for: .navigationBar)
            .toggleStyle(InkToggleStyle())
    }

    /// A tap on the page's empty space puts the keyboard away. Buttons and fields keep their own taps.
    func hidesKeyboardOnTap() -> some View {
        contentShape(.rect).onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
