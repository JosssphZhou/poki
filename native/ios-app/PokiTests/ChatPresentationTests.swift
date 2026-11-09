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

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}
