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
                    .padding(.trailing, 20)
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
