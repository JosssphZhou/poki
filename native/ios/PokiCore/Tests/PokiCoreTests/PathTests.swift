import XCTest
#if canImport(Vision) && canImport(ImageIO) && canImport(CoreText) && os(macOS)
import CoreGraphics
import CoreText
#endif
@testable import PokiCore

/// Paths: steps written ahead by the text of their targets, crossed in one call with no model, and
/// every case where a path must stop as a routine does.
final class PathTests: XCTestCase {
    /// Settings whose rows open the next page, with a prompt that can sit over any page: a tap goes to
    /// what is under the point, as on a phone.
    final class App: @unchecked Sendable {
        let wda: FakeWDA
        let page = LockedBox(0)
        let prompt = LockedBox<[Node]?>(nil)
        var pages: [[Node]]
        /// The label that opens the next page, per page.
        var opens: [String]
        let tapped = LockedBox<[String]>([])
        init(_ wda: FakeWDA, pages: [[Node]], opens: [String]) {
            self.wda = wda
            self.pages = pages
            self.opens = opens
            show()
            wda.set("POST /wda/tap") { [self] body in
                let x = body?["x"]?.double ?? -1, y = body?["y"]?.double ?? -1
                func hit(_ nodes: [Node]) -> Node? {
                    for n in nodes.reversed() {
                        if let inner = hit(n.children) { return inner }
                        if n.frame[0] <= x, x <= n.frame[0] + n.frame[2], n.frame[1] <= y, y <= n.frame[1] + n.frame[3], !["Alert", "Sheet"].contains(n.type) { return n }
                    }
                    return nil
                }
                if let over = self.prompt.value {
                    // The prompt takes every tap: one on its buttons closes it.
                    if let button = hit(over), button.type == "Button" { self.tapped.update { $0.append(button.label ?? "") }; self.prompt.value = nil }
                } else if let node = hit(self.pages[self.page.value]) {
                    self.tapped.update { $0.append(node.label ?? "") }
                    if self.page.value < self.opens.count, node.label == self.opens[self.page.value] { self.page.value += 1 }
                }
                self.show()
                return (200, ["value": .null])
            }
        }
        func show() { wda.tree(pages[page.value] + (prompt.value ?? []), app: "Settings") }
        func go(_ i: Int) { page.value = i; show() }
    }

    static let notifications = [Node("Alert", "Turn On Notifications?", [45, 300, 300, 180], [
        Node("StaticText", "Get alerts about updates", [60, 340, 270, 40]),
        Node("Button", "Not Now", [60, 420, 130, 44]),
        Node("Button", "Allow", [200, 420, 130, 44]),
    ])]


    func core(_ store: RoutineStore, configure: @escaping (inout CoreConfig) -> Void = { _ in }) -> (PokiCore, FakeWDA, App) {
        let wda = FakeWDA()
        let app = App(wda, pages: [RoutineTests.home, RoutineTests.general, RoutineTests.about], opens: ["General", "About"])
        let (core, _, _) = makeCore(wda) {
            $0.memory = store
            configure(&$0)
        }
        return (core, wda, app)
    }

    // MARK: A path

    func testAPathCrossesScreensInOneCallByTheTextOfItsTargets() async throws {
        let store = RoutineStore(url: nil)
        let (core, wda, app) = core(store)
        app.go(0)
        _ = await core.call("look", [:])
        let taps = wda.bodies("POST /wda/tap").count

        let result = await core.call("do", ["actions": [["path": ["goal": "read the iOS version", "steps": [["tap": "General"], ["tap": "about"]], "expect": ["iOS Version"]]]]])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("path: 2 steps"), result.text)
        XCTAssertTrue(result.text.contains("end check passed"), result.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, taps + 2)
        XCTAssertEqual(app.page.value, 2)

        // What the path did saves as a routine like steps sent by hand, with real targets.
        let saved = await core.call("routines", ["action": "save", "name": "version", "description": "read the iOS version"])
        XCTAssertFalse(saved.isError, saved.text)
        let routine = try XCTUnwrap(store.routine(named: "version"))
        XCTAssertEqual(routine.steps.map { $0.target?.type }, ["Button", "Button"])
        XCTAssertEqual(routine.steps.map { $0.target?.label }, ["General", "About"])
    }

    func testAPathStopsAtTheStepItCannotDoAndSaysWhatWasSent() async {
        let (core, _, app) = core(RoutineStore(url: nil)) { $0.actionCap = 1.2 }
        app.go(0)
        _ = await core.call("look", [:])

        let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "General"], ["tap": "Storage"]]]]]])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("path stopped at step 2 of 2: \"Storage\" is not on screen"), result.text)
        XCTAssertTrue(result.text.contains("steps 1 to 1 were sent"), result.text)
        XCTAssertEqual(app.page.value, 1)
    }

    // MARK: What a path allows

    func testAPathClosesWhatItSaysMayBeClosedWithNoModel() async {
        let (core, _, app) = core(RoutineStore(url: nil))
        app.go(1)
        app.prompt.value = Self.notifications
        app.show()
        _ = await core.call("look", [:])

        let result = await core.call("do", ["actions": [["path": ["goal": "read the iOS version", "steps": [["tap": "About"]], "dismiss": ["Later", "Not Now"], "read": ["iOS Version"]]]]])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(app.tapped.value, ["Not Now", "About"])
        XCTAssertTrue(result.text.contains("closed Button \"Not Now\" (allowed by the path)"), result.text)
        XCTAssertTrue(result.text.contains("read: iOS Version = 27.3"), result.text)
    }

    func testWhatAPathDidNotAllowIsNotClosed() async {
        let (core, _, app) = core(RoutineStore(url: nil)) { $0.actionCap = 1.2 }
        app.go(1)
        app.prompt.value = Self.notifications
        app.show()
        _ = await core.call("look", [:])

        let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "About"]], "dismiss": ["Later"]]]]])

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("behind an alert"), result.text)
        XCTAssertEqual(app.tapped.value, [])
    }

    func testAnOptionalStepIsLeftOutWhenItsTargetIsNotThere() async {
        let (core, _, app) = core(RoutineStore(url: nil))
        app.go(0)
        _ = await core.call("look", [:])
        let began = Date()

        let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "General"], ["tap": "Not Now", "optional": true], ["tap": "About"]]]]]])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(app.tapped.value, ["General", "About"])
        XCTAssertTrue(result.text.contains("1 optional step was left out"), result.text)
        XCTAssertLessThan(Date().timeIntervalSince(began), 6)
    }

    func testAnOptionalStepIsTakenWhenItsTargetIsThere() async {
        let (core, _, app) = core(RoutineStore(url: nil))
        app.go(1)
        app.prompt.value = Self.notifications
        app.show()
        _ = await core.call("look", [:])

        let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "Not Now", "optional": true], ["tap": "About"]]]]]])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(app.tapped.value, ["Not Now", "About"])
    }

    func testAStepsExpectIsReadFromTheScreenWithNoModel() async {
        let (core, _, app) = core(RoutineStore(url: nil))
        app.go(0)
        _ = await core.call("look", [:])

        let ok = await core.call("do", ["actions": [["path": ["steps": [["tap": "General", "expect": "Software Update"], ["tap": "About", "expect": ["iOS Version", "Model Name"]]]]]]])
        XCTAssertFalse(ok.isError, ok.text)
        XCTAssertEqual(app.page.value, 2)

        app.go(0)
        _ = await core.call("look", [:])
        let stopped = await core.call("do", ["actions": [["path": ["steps": [["tap": "General", "expect": "Storage"], ["tap": "About"]]]]]])
        XCTAssertTrue(stopped.isError)
        XCTAssertTrue(stopped.text.contains("stopped at step 1 of 2: the step was sent, but \"Storage\" did not appear after it"), stopped.text)
        XCTAssertEqual(app.page.value, 1)
    }

    func testAPathReadsAsItsGoalOrItsSteps() {
        let (core, _, _) = makeCore()
        XCTAssertEqual(core.computer.label(["path": ["goal": "check the version", "steps": [["tap": "General"]]]]), "Run “check the version”")
        XCTAssertEqual(core.computer.label(["path": ["steps": [["tap": "General"], ["tap": ["label": "About", "type": "Cell"]], ["swipe": "up"]]]]),
                       "Tap “General”, then tap “About”, then swipe up")
        XCTAssertEqual(core.computer.label(["path": [["long_press": "Photo"], ["tap": [200, 122]]]]), "Press and hold “Photo”, then tap at 200, 122")
    }

    func testAPathWithoutAGoalKeepsTypedTextOutOfActivityAndBusyReply() async {
        let (core, wda, _) = makeCore {
            $0.busyWait = 0
            $0.actionCap = 1.2
        }
        let busyReply = LockedBox<String?>(nil)
        wda.set("POST /wda/tap") { [weak core] _ in
            busyReply.value = await core?.call("look", [:]).text
            return (200, ["value": .null])
        }
        _ = await core.call("look", [:])

        let result = await core.call("do", ["actions": [["path": ["steps": [
            ["tap": "General"], ["type": "private search phrase", "into": "Search"],
        ]]]]])

        XCTAssertTrue(result.text.contains("stopped at step 2"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/keys").isEmpty)
        let started = await core.events.first { event in
            if case .toolStarted(let activity) = event { return activity.name == "do" }
            return false
        }
        guard case .toolStarted(let activity)? = started else { return XCTFail("No path activity") }
        XCTAssertEqual(activity.summary, "Tap “General”, then type text")
        XCTAssertEqual(busyReply.value?.split(separator: "\n").first.map(String.init),
                       "busy: another call is still running (do: Tap “General”, then type text); nothing was sent. Call again in a moment.")
    }

    func testASwipeInAPathTakesNoListNumber() async {
        for step: JSON in [["swipe": ["direction": "up", "in": 3]], ["swipe": "up", "in": 3]] {
            let wda = FakeWDA()
            wda.tree([Node("Button", "General", [16, 100, 358, 44])], app: "Settings")
            let (core, _, _) = makeCore(wda)
            _ = await core.call("look", [:])
            let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "General"], step]]]]])
            XCTAssertTrue(result.text.contains("not in: a number from an earlier read"), "\(step): \(result.text)")
            XCTAssertEqual(wda.bodies("POST /wda/tap").count, 0, "\(step): nothing was sent")
        }
    }

    func testADismissNamingAPaymentControlDoesNotPressIt() async {
        let wda = FakeWDA()
        wda.tree([Node("Button", "Pay", [16, 100, 358, 44])], app: "Shop")
        let (core, _, _) = makeCore(wda) { $0.actionCap = 1.5 }
        _ = await core.call("look", [:])

        let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "About"]], "dismiss": ["Pay"]]]]])

        XCTAssertTrue(result.text.contains("closing it needs the owner's approval"), result.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 0, "Pay was not pressed")
    }

    // MARK: Poki's own screen

    /// Poki in front once it is launched, showing its approval settings.
    func pokiOnLaunch(_ wda: FakeWDA) {
        wda.set("POST /wda/apps/activate") { [wda] body in
            if body?["bundleId"]?.string == "nz.zheha.poki" {
                wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "nz.zheha.poki", "name": "Poki"]]) }
                wda.tree([Node("Button", "Never Ask", [16, 100, 358, 44])], app: "Poki")
            }
            return (200, ["value": .null])
        }
    }

    func testAPathSendsNoInputIntoPoki() async {
        let cases: [(steps: [JSON], dismiss: [JSON], rules: Bool, fromPoki: Bool)] = [
            ([["launch": "com.example.other"], ["launch": "nz.zheha.poki"], ["tap": "Never Ask"]], [], true, false),
            ([["launch": "nz.zheha.poki"], ["tap": [200, 122]]], [], false, false),
            ([["launch": "nz.zheha.poki"], ["tap": "Continue"]], ["Never Ask"], true, false),
            // A launch that did not open its app leaves Poki in front.
            ([["launch": ["bundle": "com.example.gone"]], ["tap": [200, 122]]], [], false, true),
        ]
        for c in cases {
            let wda = FakeWDA()
            wda.tree([Node("Button", "General", [16, 100, 358, 44])], app: "Settings")
            pokiOnLaunch(wda)
            if c.fromPoki {
                wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "nz.zheha.poki", "name": "Poki"]]) }
                wda.tree([Node("Button", "Never Ask", [16, 100, 358, 44])], app: "Poki")
            }
            let (core, _, _) = makeCore(wda) { $0.sensitive.enabled = c.rules; $0.actionCap = 1.5 }
            _ = await core.call("look", [:])

            let result = await core.call("do", ["actions": [["path": ["steps": .array(c.steps), "dismiss": .array(c.dismiss)]]]])

            XCTAssertTrue(result.text.contains("Poki takes no taps or typing inside the Poki app"), "\(c.steps): \(result.text)")
            XCTAssertEqual(wda.bodies("POST /wda/tap").count, 0, "\(c.steps): nothing was tapped in Poki")
        }
    }

    // MARK: Optional extras with a decision model

    func testAPathRefusesNumbersFromAnEarlierRead() async {
        let (core, wda, app) = core(RoutineStore(url: nil))
        app.go(0)
        _ = await core.call("look", [:])
        let taps = wda.bodies("POST /wda/tap").count
        let result = await core.call("do", ["actions": [["path": ["steps": [["tap": "General"], ["tap": 3]]]]]])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("a target in a path is the element's text"), result.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, taps, "nothing was sent")
    }

    // MARK: Bounded continuous steps (calculator, duplicate contacts, search scroll, failure handback)

    func testCalculatorMultiDigitPathHandlesRealDeviceKeysAndReducesReads() async {
        let wda = FakeWDA()
        let display = LockedBox("12")
        let tapped = LockedBox<[String]>([])
        let keypad: [(String, [Double])] = [
            ("C", [16, 360, 82, 82]), ("%", [112, 360, 82, 82]), ("÷", [208, 360, 82, 82]), ("×", [304, 360, 82, 82]),
            ("7", [16, 456, 82, 82]), ("8", [112, 456, 82, 82]), ("9", [208, 456, 82, 82]), ("−", [304, 456, 82, 82]),
            ("4", [16, 552, 82, 82]), ("5", [112, 552, 82, 82]), ("6", [208, 552, 82, 82]), ("+", [304, 552, 82, 82]),
            ("1", [16, 648, 82, 82]), ("2", [112, 648, 82, 82]), ("3", [208, 648, 82, 82]), ("=", [304, 648, 82, 82]),
            ("0", [112, 744, 82, 82]), (".", [208, 744, 82, 82]),
        ]
        #if canImport(Vision) && canImport(ImageIO) && canImport(CoreText) && os(macOS)
        @Sendable func displayPNG(_ text: String) -> Data {
            PictureSketchTests.png { context in
                let glyph = NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 56, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
                ])
                context.textPosition = CGPoint(x: 90, y: 545)
                CTLineDraw(CTLineCreateWithAttributedString(glyph), context)
            }
        }
        wda.set("GET /screenshot") { _ in (200, ["value": .string(displayPNG(display.value).base64EncodedString())]) }
        #endif
        @Sendable func calculatorTree(labeledDisplay: Bool) -> JSON {
            let clearLabel = display.value == "0" ? "AC" : "C"
            var children: [JSON] = [
                ["type": "XCUIElementTypeButton", "label": "History", "rect": ["x": 16, "y": 68, "width": 44, "height": 44], "children": []],
                ["type": labeledDisplay ? "XCUIElementTypeStaticText" : "XCUIElementTypeOther",
                 "name": labeledDisplay ? "display" : .null,
                 "label": labeledDisplay ? .string(display.value) : .null,
                 "rect": ["x": 16, "y": 256, "width": 370, "height": 90], "children": []],
            ]
            for (rawLabel, rect) in keypad {
                let label = rawLabel == "C" ? clearLabel : rawLabel
                children.append([
                    "type": "XCUIElementTypeKey", "label": .string(label),
                    "rect": ["x": .number(rect[0]), "y": .number(rect[1]), "width": .number(rect[2]), "height": .number(rect[3])],
                    "children": [],
                ])
            }
            return ["type": "XCUIElementTypeApplication", "label": "Calculator",
                    "rect": ["x": 0, "y": 0, "width": 402, "height": 874], "children": .array(children)]
        }
        let labeledDisplay = LockedBox(false)
        wda.set("GET /wda/screen") { _ in (200, ["value": ["screenSize": ["width": 402, "height": 874]]]) }
        wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "com.apple.calculator", "name": "Calculator"]]) }
        wda.set("GET /source") { _ in (200, ["value": calculatorTree(labeledDisplay: labeledDisplay.value)]) }
        wda.set("POST /wda/tap") { body in
            let x = body?["x"]?.double ?? -1, y = body?["y"]?.double ?? -1
            if let hit = keypad.first(where: { x >= $0.1[0] && x <= $0.1[0] + $0.1[2] && y >= $0.1[1] && y <= $0.1[1] + $0.1[3] }) {
                let actual = hit.0 == "C" ? (display.value == "0" ? "AC" : "C") : hit.0
                tapped.update { $0.append(actual) }
                if actual == "C" || actual == "AC" { display.value = "0" }
                else { display.update { $0 = $0 == "0" ? actual : $0 + actual } }
            }
            return (200, ["value": .null])
        }

        let (core, _, _) = makeCore(wda)
        _ = await core.call("look", [:])
        let readsBefore = wda.sent.filter { $0 == "GET /source" }.count

        let result = await core.call("do", ["actions": [["path": [
            "goal": "enter 778",
            "steps": [
                ["choose": [["tap": "C"], ["tap": "AC"]], "optional": true],
                ["tap": "7"], ["tap": "7"], ["tap": "8"],
            ],
            "read": ["display"],
        ]]]])

        let readsDuring = wda.sent.filter { $0 == "GET /source" }.count - readsBefore
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(tapped.value, ["C", "7", "7", "8"])
        XCTAssertEqual(display.value, "778")
        #if canImport(Vision) && canImport(ImageIO) && canImport(CoreText) && os(macOS)
        XCTAssertTrue(result.text.contains("read: display = 778"), result.text)
        #endif
        XCTAssertLessThanOrEqual(readsDuring, 3, "bounded keypad path must avoid per-digit tree reads: \(readsDuring)")

        // Also verify when display is labeled with the same digit ("7") as Key "7": repeated digit picks Key "7".
        labeledDisplay.value = true
        display.value = "7"
        tapped.value = []
        _ = await core.call("look", [:])
        let repeatDigit = await core.call("do", ["actions": [["path": [
            "steps": [["tap": "7"], ["tap": "9"]],
            "read": ["display"],
        ]]]])
        XCTAssertFalse(repeatDigit.isError, repeatDigit.text)
        XCTAssertEqual(tapped.value, ["7", "9"])
        XCTAssertTrue(repeatDigit.text.contains("read: display = 779"), repeatDigit.text)
    }

    func testContactsDuplicateNameDisambiguatesByRowContextAndStopsWhenAmbiguous() async {
        let wda = FakeWDA()
        let selectedContact = LockedBox<String?>(nil)
        let duplicateSameOrg = LockedBox(false)
        @Sendable func contactsNodes() -> [Node] {
            if let org = selectedContact.value {
                let phone = org == "Acme Corp" ? "+1 415-555-0101" : "+1 415-555-0202"
                return [
                    Node("NavigationBar", "Alex Chen", [0, 50, 390, 44]),
                    Node("StaticText", org, [16, 110, 358, 24]),
                    Node("Cell", nil, [0, 160, 390, 64], [
                        Node("StaticText", "mobile", [16, 166, 120, 20], value: "mobile"),
                        Node("StaticText", phone, [16, 190, 300, 28], value: phone),
                    ]),
                ]
            }
            let secondOrg = duplicateSameOrg.value ? "Acme Corp" : "Beta Studio"
            return [
                Node("NavigationBar", "Contacts", [0, 50, 390, 44]),
                Node("Table", nil, [0, 94, 390, 700], [
                    Node("Cell", "Alex Chen", [0, 100, 390, 64], [
                        Node("StaticText", "Alex Chen", [16, 106, 200, 24]),
                        Node("StaticText", "Acme Corp", [16, 132, 200, 20]),
                    ]),
                    Node("Cell", "Alex Chen", [0, 164, 390, 64], [
                        Node("StaticText", "Alex Chen", [16, 170, 200, 24]),
                        Node("StaticText", secondOrg, [16, 196, 200, 20]),
                    ]),
                ]),
            ]
        }
        wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "com.apple.MobileAddressBook", "name": "Contacts"]]) }
        wda.set("GET /source") { _ in
            func json(_ n: Node) -> JSON {
                ["type": .string("XCUIElementType\(n.type)"),
                 "name": n.label.map(JSON.string) ?? .null,
                 "label": n.label.map(JSON.string) ?? .null,
                 "value": n.value.map(JSON.string) ?? .null,
                 "rect": ["x": .number(n.frame[0]), "y": .number(n.frame[1]), "width": .number(n.frame[2]), "height": .number(n.frame[3])],
                 "children": .array(n.children.map(json))]
            }
            return (200, ["value": ["type": "XCUIElementTypeApplication", "label": "Contacts",
                                    "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
                                    "children": .array(contactsNodes().map(json))]])
        }
        wda.set("POST /wda/tap") { body in
            let y = body?["y"]?.double ?? -1
            if selectedContact.value == nil {
                if y >= 100 && y < 164 { selectedContact.value = "Acme Corp" }
                else if y >= 164 && y < 228 { selectedContact.value = duplicateSameOrg.value ? "Acme Corp" : "Beta Studio" }
            }
            return (200, ["value": .null])
        }

        let (core, _, _) = makeCore(wda) { $0.actionCap = 1.2 }
        _ = await core.call("look", [:])
        let readsBefore = wda.sent.filter { $0 == "GET /source" }.count

        let picked = await core.call("do", ["actions": [["path": [
            "goal": "open Alex Chen at Beta Studio and read mobile",
            "steps": [
                ["choose": [
                    ["when": "Beta Studio", "tap": ["label": "Alex Chen", "with": "Beta Studio"]],
                    ["when": "Search", "steps": [["type": "Alex Chen", "into": "Search"], ["tap": ["label": "Alex Chen", "with": "Beta Studio"]]]],
                ]],
            ],
            "read": ["mobile"],
        ]]]])

        let readsDuring = wda.sent.filter { $0 == "GET /source" }.count - readsBefore
        XCTAssertFalse(picked.isError, picked.text)
        XCTAssertEqual(selectedContact.value, "Beta Studio")
        XCTAssertTrue(picked.text.contains("read: mobile = +1 415-555-0202"), picked.text)
        XCTAssertLessThanOrEqual(readsDuring, 3, "bounded choose + read should reuse fresh trees: \(readsDuring)")

        // Ambiguous duplicate rows: both match "Alex Chen" with "Acme Corp" -> must stop without tapping either.
        selectedContact.value = nil
        duplicateSameOrg.value = true
        _ = await core.call("look", [:])
        let tapsBefore = wda.bodies("POST /wda/tap").count
        let ambiguous = await core.call("do", ["actions": [["path": [
            "steps": [["choose": [["tap": ["label": "Alex Chen", "with": "Acme Corp"]]]]],
            "read": ["mobile"],
        ]]]])

        XCTAssertTrue(ambiguous.isError, ambiguous.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, tapsBefore, "must not guess among ambiguous duplicate contacts")
        XCTAssertNil(selectedContact.value)
    }

    func testSearchResultsScrollPathOpensTargetAndStopsImmediatelyWhenNotFound() async {
        let wda = FakeWDA()
        let query = LockedBox("")
        let scrolled = LockedBox(false)
        let opened = LockedBox<String?>(nil)
        let scrollCalls = LockedBox(0)
        @Sendable func nodes() -> [Node] {
            if let page = opened.value {
                return [
                    Node("NavigationBar", page, [0, 50, 390, 44]),
                    Node("StaticText", "Status", [16, 120, 358, 44], value: "Ready"),
                ]
            }
            var items: [Node] = [
                Node("SearchField", "Search", [16, 60, 358, 36], value: query.value),
            ]
            if query.value.lowercased().contains("lang") {
                if !scrolled.value {
                    items.append(Node("Table", nil, [0, 110, 390, 700], [
                        Node("Cell", "Preferred Languages", [0, 120, 390, 60], [
                            Node("StaticText", "Preferred Languages", [16, 126, 300, 24]),
                            Node("StaticText", "Apps", [16, 152, 200, 20]),
                        ]),
                        Node("Cell", "Keyboard Languages", [0, 180, 390, 60]),
                    ]))
                } else {
                    items.append(Node("Table", nil, [0, 110, 390, 700], [
                        Node("Cell", "Language & Region", [0, 200, 390, 60], [
                            Node("StaticText", "Language & Region", [16, 206, 300, 24]),
                            Node("StaticText", "General", [16, 232, 200, 20]),
                        ]),
                    ]))
                }
            }
            return items
        }
        wda.set("GET /source") { _ in
            func json(_ n: Node) -> JSON {
                ["type": .string("XCUIElementType\(n.type)"),
                 "name": n.label.map(JSON.string) ?? .null,
                 "label": n.label.map(JSON.string) ?? .null,
                 "value": n.value.map(JSON.string) ?? .null,
                 "rect": ["x": .number(n.frame[0]), "y": .number(n.frame[1]), "width": .number(n.frame[2]), "height": .number(n.frame[3])],
                 "children": .array(n.children.map(json))]
            }
            return (200, ["value": ["type": "XCUIElementTypeApplication", "label": "Settings",
                                    "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
                                    "children": .array(nodes().map(json))]])
        }
        wda.set("POST /wda/keys") { body in
            let text = (body?["value"]?.array ?? []).compactMap(\.string).joined()
            query.update { $0 += text }
            return (200, ["value": .null])
        }
        wda.set("POST /wda/pressAndDragWithVelocity") { _ in
            scrollCalls.update { $0 += 1 }
            scrolled.value = true
            return (200, ["value": .null])
        }
        wda.set("POST /wda/tap") { body in
            let y = body?["y"]?.double ?? -1
            if scrolled.value && y >= 200 && y <= 260 { opened.value = "Language & Region" }
            return (200, ["value": .null])
        }

        let (core, _, _) = makeCore(wda) { $0.toolDeadline = 12; $0.actionCap = 3 }
        _ = await core.call("look", [:])
        let found = await core.call("do", ["actions": [["path": [
            "goal": "search Lang, scroll to Language & Region, and read Status",
            "steps": [
                ["type": "Lang", "into": "Search"],
                ["scroll_to": ["text": "Language & Region", "with": "General"]],
                ["tap": ["contains": "Language & Region", "with": "General"]],
            ],
            "read": ["Status"],
        ]]]])

        XCTAssertFalse(found.isError, found.text)
        XCTAssertEqual(opened.value, "Language & Region")
        XCTAssertTrue(found.text.contains("read: Status = Ready"), found.text)
        XCTAssertEqual(scrollCalls.value, 1)

        // Not-found scroll inside path: must stop at scroll_to and never run downstream tap.
        opened.value = nil
        let tapsBefore = wda.bodies("POST /wda/tap").count
        let missing = await core.call("do", ["actions": [["path": [
            "steps": [
                ["scroll_to": ["text": "Nonexistent Result", "max_swipes": 3]],
                ["tap": "Nonexistent Result"],
            ],
        ]]]])

        XCTAssertTrue(missing.isError, missing.text)
        XCTAssertTrue(missing.text.contains("stopped at step 1"), missing.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, tapsBefore, "downstream tap must not run after scroll_to fails")
    }

    func testMissingRequiredReadFieldReturnsFreshScreenWithoutRepeatingSideEffects() async {
        let wda = FakeWDA()
        let opened = LockedBox(false)
        wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "com.apple.MobileAddressBook", "name": "Contacts"]]) }
        wda.set("GET /source") { _ in
            let nodes: [Node] = opened.value ? [
                Node("NavigationBar", "Alex Chen", [0, 50, 390, 44]),
                Node("StaticText", "Acme Corp", [16, 110, 358, 24]),
                Node("Cell", nil, [0, 160, 390, 64], [
                    Node("StaticText", "mobile", [16, 166, 120, 20]),
                    Node("Button", "+1 415-555-0101", [16, 190, 300, 28]),
                ]),
            ] : [
                Node("NavigationBar", "Contacts", [0, 50, 390, 44]),
                Node("Cell", "Alex Chen", [0, 100, 390, 64], [
                    Node("StaticText", "Alex Chen", [16, 106, 200, 24]),
                    Node("StaticText", "Acme Corp", [16, 132, 200, 20]),
                ]),
            ]
            func json(_ n: Node) -> JSON {
                ["type": .string("XCUIElementType\(n.type)"),
                 "name": n.label.map(JSON.string) ?? .null,
                 "label": n.label.map(JSON.string) ?? .null,
                 "value": n.value.map(JSON.string) ?? .null,
                 "rect": ["x": .number(n.frame[0]), "y": .number(n.frame[1]), "width": .number(n.frame[2]), "height": .number(n.frame[3])],
                 "children": .array(n.children.map(json))]
            }
            return (200, ["value": ["type": "XCUIElementTypeApplication", "label": "Contacts",
                                    "rect": ["x": 0, "y": 0, "width": 390, "height": 844],
                                    "children": .array(nodes.map(json))]])
        }
        wda.set("POST /wda/tap") { _ in
            opened.value = true
            return (200, ["value": .null])
        }

        let (core, _, _) = makeCore(wda)
        _ = await core.call("look", [:])
        let tapsBefore = wda.bodies("POST /wda/tap").count

        let result = await core.call("do", ["actions": [["path": [
            "goal": "open Alex Chen and read mobile and Email",
            "steps": [["tap": ["label": "Alex Chen", "with": "Acme Corp"]]],
            "read": ["mobile", "Email"],
            "wait_ms": 400,
        ]]]])

        XCTAssertEqual(wda.bodies("POST /wda/tap").count, tapsBefore + 1, "side-effecting tap must run exactly once")
        XCTAssertTrue(result.text.contains("read: mobile = +1 415-555-0101"), result.text)
        XCTAssertTrue(result.text.contains("missing fields: \"Email\""), result.text)
        XCTAssertTrue(result.text.contains("do not repeat"), result.text)
        XCTAssertTrue(result.text.contains("+1 415-555-0101"), "fresh detail screen returned: \(result.text)")
        XCTAssertNotNil(result.jpeg, "fresh screenshot returned to model")
    }

    func testBoundedChooseRejectsNestingAndEnforcesApprovalAndPokiGuards() async {
        let wda = FakeWDA()
        wda.tree([Node("Button", "Pay", [16, 100, 358, 44])], app: "Shop")
        let (core, _, _) = makeCore(wda) { $0.actionCap = 1.2 }
        _ = await core.call("look", [:])

        // Nested choose must be refused before any input is sent.
        let nested = await core.call("do", ["actions": [["path": ["steps": [
            ["choose": [["when": "Pay", "steps": [["choose": [["tap": "Pay"]]]]]]],
        ]]]]])
        XCTAssertTrue(nested.isError, nested.text)
        XCTAssertTrue(nested.text.contains("nothing was sent"), nested.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 0)

        // Too many branches (> 6) must be refused before any input is sent.
        let tooMany = await core.call("do", ["actions": [["path": ["steps": [
            ["choose": .array((1...7).map { ["tap": .string("B\($0)")] })],
        ]]]]])
        XCTAssertTrue(tooMany.isError, tooMany.text)
        XCTAssertTrue(tooMany.text.contains("at most 6 branches"), tooMany.text)

        // Sensitive action inside choose branch must still require owner approval.
        let sensitiveBranch = await core.call("do", ["actions": [["path": ["steps": [
            ["choose": [["when": "Pay", "tap": "Pay"]]],
        ]]]]])
        XCTAssertTrue(sensitiveBranch.isError, sensitiveBranch.text)
        XCTAssertTrue(sensitiveBranch.text.contains("needs the owner's approval"), sensitiveBranch.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 0)

        // Poki guard inside choose branch must still block input in Poki.
        pokiOnLaunch(wda)
        let intoPoki = await core.call("do", ["actions": [["path": ["steps": [
            ["choose": [["when": "Pay", "steps": [["launch": "nz.zheha.poki"], ["tap": "Never Ask"]]]]],
        ]]]]])
        XCTAssertTrue(intoPoki.isError, intoPoki.text)
        XCTAssertTrue(intoPoki.text.contains("Poki takes no taps or typing inside the Poki app"), intoPoki.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 0)
    }

    func testPromptAndDoToolDescriptionDoNotGrowPastBaseline() {
        let doDescription = PokiCore.tools.first { $0["name"]?.string == "do" }?["description"]?.string ?? ""
        XCTAssertLessThanOrEqual(PokiCore.instructions.count, 1835)
        XCTAssertLessThanOrEqual(doDescription.count, 7666)
    }
}
