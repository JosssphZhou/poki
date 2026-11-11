import SwiftUI
import XCTest
@testable import Poki

@MainActor
final class ChatPresentationTests: XCTestCase {
    /// Synthetic data: exercise the same mix of prose, bold, table and total as an agent's report.
    private let report = """
    There are **2 delivered orders**.

    | Time | Shop | Item | Amount |
    | --- | --- | --- | ---: |
    | 18:29 | Example Restaurant with a long name | 1 × Meal | R$30.00 |
    | 13:13 | Example Café | 1 × Juice | R$20.00 |

    **Total: R$50.00**
    """

    func testAssistantReportParsesTableAndInlineFormatting() {
        let html = AssistantMarkdown(text: report).content.renderHTML()
        XCTAssertTrue(html.contains("<table>"), html)
        XCTAssertTrue(html.contains("<strong>2 delivered orders</strong>"), html)
        XCTAssertTrue(html.contains("<strong>Total: R$50.00</strong>"), html)
        XCTAssertEqual(html.components(separatedBy: "<tr>").count - 1, 3)
    }

    func testAssistantParsesHeadingsListsAndFencedCode() {
        let html = AssistantMarkdown(text: """
        ## Result

        1. First
        2. Second

        ```swift
        let total = 50
        ```
        """).content.renderHTML()
        XCTAssertTrue(html.contains("<h2>Result</h2>"), html)
        XCTAssertTrue(html.contains("<ol>"), html)
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"), html)
    }

    func testChineseReportKeepsBoldTextAndTable() {
        let html = AssistantMarkdown(text: """
        当前账号共有 **2 笔订单**，均已送达。

        | 商家 | 金额 |
        | --- | ---: |
        | 示例餐厅 | R$30.00 |
        | 示例咖啡店 | R$20.00 |

        **总花费：R$50.00（巴西雷亚尔）**
        """).content.renderHTML()
        XCTAssertTrue(html.contains("<strong>2 笔订单</strong>"), html)
        XCTAssertTrue(html.contains("<table>"), html)
        XCTAssertTrue(html.contains("<strong>总花费：R$50.00（巴西雷亚尔）</strong>"), html)
    }

    func testMessageWidthsExpandTogetherAndShortBubblesStayCompact() throws {
        let longText = String(repeating: "请查看当前页面并整理可见内容。", count: 12)
        for screenWidth: CGFloat in [320, 393, 768] {
            let available = screenWidth - 32
            let maximum = min(available, ChatLayout.maximumMessageWidth)
            let outgoing = MessageBubble(direction: .outgoing, text: longText, tail: true)
            let plan = PlanBubble(steps: [PlanStep(longText, state: .done)], tail: true)
            let userBounds = try paintedBounds(of: outgoing, width: available)
            let planBounds = try paintedBounds(of: plan, width: available)
            // Text can shrink to its longest wrapped line by up to one glyph. Both kinds
            // must reach the common limit rather than retain the old 280/320-point caps.
            XCTAssertGreaterThan(userBounds.width, maximum - 17)
            XCTAssertLessThanOrEqual(userBounds.width, maximum + 1)
            XCTAssertGreaterThan(planBounds.width, maximum - 16)
            XCTAssertLessThanOrEqual(planBounds.width, maximum + 1)
            XCTAssertEqual(userBounds.maxX, available, accuracy: 1)
            XCTAssertEqual(planBounds.minX, 0, accuracy: 1)

            let shortUser = try paintedBounds(of: MessageBubble(direction: .outgoing, text: "好的", tail: true), width: available)
            let shortPlan = try paintedBounds(of: PlanBubble(steps: [PlanStep("已完成", state: .done)], tail: true), width: available)
            XCTAssertLessThan(shortUser.width, 100)
            XCTAssertLessThan(shortPlan.width, 150)
            XCTAssertEqual(shortUser.maxX, available, accuracy: 1)
            XCTAssertEqual(shortPlan.minX, 0, accuracy: 1)

            let assistant = MessageBubble(direction: .incoming, text: longText, tail: true)
            let size = UIHostingController(rootView: assistant).sizeThatFits(in: CGSize(width: available, height: 10_000))
            XCTAssertEqual(size.width, available, accuracy: 1)
            let preview = VStack(alignment: .leading, spacing: 16) {
                outgoing
                MessageBubble(direction: .outgoing, text: "好的", tail: true)
                assistant
                plan.frame(maxWidth: .infinity, alignment: .leading)
                PlanBubble(steps: [PlanStep("已完成", state: .done)], tail: true)
            }.padding(16).frame(width: screenWidth).background(Color.white).environment(\.colorScheme, .light)
            let attachment = XCTAttachment(image: try XCTUnwrap(ImageRenderer(content: preview).uiImage))
            attachment.name = "unified-message-widths-\(Int(screenWidth))pt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func paintedBounds<V: View>(of content: V, width: CGFloat) throws -> CGRect {
        let renderer = ImageRenderer(content: content.frame(width: width, alignment: .leading)
            .background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var left = cg.width, right = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let i = (y * cg.width + x) * 4
                if min(pixels[i], pixels[i + 1], pixels[i + 2]) < 245 {
                    left = min(left, x)
                    right = max(right, x)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(right, left)
        return CGRect(x: CGFloat(left) / renderer.scale, y: 0,
            width: CGFloat(right - left + 1) / renderer.scale, height: CGFloat(cg.height) / renderer.scale)
    }

    func testWideTableStaysInsideNarrowChatBubble() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for width: CGFloat in [320, 393] {
            let bubble = MessageBubble(direction: .incoming, text: report, tail: true)
            let host = UIHostingController(rootView: bubble)
            let size = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
            XCTAssertLessThanOrEqual(size.width, width + 1)
            XCTAssertGreaterThan(size.height, 100)

            // A table uses layout preferences and a scrolling viewport. Give it a real window and
            // a display pass: ImageRenderer alone can leave those cells blank on its first pass.
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: CGSize(width: width, height: 800))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(250))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "assistant-table-\(Int(width))pt"
            attachment.lifetime = .keepAlways
            add(attachment)

            // The clipped columns must remain reachable, not merely fit the initial bubble.
            let table = try XCTUnwrap(scrollViews(in: host.view).first {
                $0.contentSize.width > $0.bounds.width + 1
            })
            table.setContentOffset(CGPoint(x: table.contentSize.width - table.bounds.width, y: 0), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let endImage = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let endAttachment = XCTAttachment(image: endImage)
            endAttachment.name = "assistant-table-\(Int(width))pt-last-columns"
            endAttachment.lifetime = .keepAlways
            add(endAttachment)
        }
    }

    func testPlanCursorInkIsCenteredWithChineseAndLatinCapitals() throws {
        for sample in ["国", "H"] {
            let content = PlanTypingLabel(text: sample, cursorVisible: true,
                font: .system(size: 15), color: .black)
                .padding(20).background(Color.white)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            let cg = try XCTUnwrap(renderer.uiImage?.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            var rowsByColumn: [Int: [Int]] = [:]
            for y in 0..<cg.height {
                for x in 0..<cg.width {
                    let offset = (y * cg.width + x) * 4
                    if pixels[offset] < 150 && pixels[offset + 1] < 150 && pixels[offset + 2] < 150 {
                        rowsByColumn[x, default: []].append(y)
                    }
                }
            }
            let columns = rowsByColumn.keys.sorted()
            let last = try XCTUnwrap(columns.last)
            var cursorStart = last
            while rowsByColumn[cursorStart - 1] != nil { cursorStart -= 1 }
            let cursorRows = columns.filter { $0 >= cursorStart }.flatMap { rowsByColumn[$0]! }
            let letterRows = columns.filter { $0 < cursorStart }.flatMap { rowsByColumn[$0]! }
            let cursorMid = Double(try XCTUnwrap(cursorRows.min()) + XCTUnwrap(cursorRows.max())) / 2
            let letterMid = Double(try XCTUnwrap(letterRows.min()) + XCTUnwrap(letterRows.max())) / 2
            XCTAssertEqual(cursorMid / renderer.scale, letterMid / renderer.scale, accuracy: 1,
                "cursor ink must be centred with \(sample), not merely share its baseline")
        }
    }

    func testPlanCursorWrapsWithTextWithoutBlinkLayoutChanges() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let text = "正在查看餐厅菜单与今日优惠活动"
        for width: CGFloat in [320, 393] {
            let visible = UIHostingController(rootView: PlanTypingLabel(text: text,
                cursorVisible: true, font: .system(size: 15), color: .primary))
            let hidden = UIHostingController(rootView: PlanTypingLabel(text: text,
                cursorVisible: false, font: .system(size: 15), color: .primary))
            let constraint = CGSize(width: 150, height: 1_000)
            let on = visible.sizeThatFits(in: constraint)
            let off = hidden.sizeThatFits(in: constraint)
            XCTAssertEqual(on.width, off.width, accuracy: 0.5)
            XCTAssertEqual(on.height, off.height, accuracy: 0.5)
            XCTAssertGreaterThan(on.height, 30, "exercise a wrapped final line")

            let root = VStack(alignment: .leading, spacing: 18) {
                PlanBubble(steps: [PlanStep("已打开活动页面", state: .done), PlanStep(text)], tail: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PlanTypingLabel(text: text, cursorVisible: true, font: .system(size: 15), color: .primary)
                    .frame(width: 150, alignment: .leading)
                PlanTypingLabel(text: "正在查看", cursorVisible: true, font: .system(size: 15), color: .primary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 24)
            let host = UIHostingController(rootView: root)
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .light
            window.frame = CGRect(x: 0, y: 0, width: width, height: 300)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .seconds(2))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "plan-cursor-\(Int(width))pt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    func testComposerCoversContentThroughBottomSafeArea() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let report = """
        已查看活动页面，以下是当前可见的内容。

        ## 一、当前看到的主要活动

        | 活动 | 说明 | 起送费 |
        | --- | --- | ---: |
        | 每日精选 Offers for you | 查看参与活动的商家与优惠菜品 | QAR 2 |
        | 聚餐精选 Gathering Picks | 适合多人分享的套餐 | QAR 4 |
        | 首单优惠 | 资格以结算页为准 | QAR 0 |

        ### 二、商家与菜品

        **示例餐厅** 提供汉堡、炸鸡与饮品套餐。

        1. 查看商家菜单和配送范围。
        2. 在结算前核对价格与优惠条件。

        以上金额为页面展示价格，未下单。
        """
        for style in [UIUserInterfaceStyle.light, .dark] {
            let root = ZStack {
                // Any gap below the composer would expose this red backing.
                Color.red.ignoresSafeArea()
                ScrollView {
                    MessageBubble(direction: .incoming, text: report, tail: true)
                        .padding(.horizontal, 16)
                }
                .background(Color(.systemBackground), ignoresSafeAreaEdges: [])
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatComposerSurface {
                    HStack {
                        Text("给 Poki 发消息").font(.system(size: 16)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue).font(.system(size: 28))
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            let host = UIHostingController(rootView: root)
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = style
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "chat-surface-\(style == .light ? "light" : "dark")"
            attachment.lifetime = .keepAlways
            add(attachment)

            let cg = try XCTUnwrap(image.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let sample = try XCTUnwrap(cg.cropping(to: CGRect(x: 20 * image.scale,
                y: (image.size.height - 8) * image.scale, width: 1, height: 1)))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            XCTAssertLessThan(abs(Int(pixel[0]) - Int(pixel[1])), 8, "bottom safe area must be neutral, not the red transcript backing")
            XCTAssertLessThan(abs(Int(pixel[1]) - Int(pixel[2])), 8)
            XCTAssertEqual(pixel[3], 255)
        }
    }
}
