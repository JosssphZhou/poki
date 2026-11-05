import Cocoa

// MARK: - 路径

private let homeDir = FileManager.default.homeDirectoryForCurrentUser
private let agentConfigPath = homeDir.appendingPathComponent(".config/poki-agent/config.json")
private let agentSecretsPath = homeDir.appendingPathComponent(".config/poki-agent/env.json")
private let imessageDirectory = homeDir.appendingPathComponent(".config/poki-agent/imessage")
private let customKeyName = "POKI_CUSTOM_API_KEY"

private func readJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return object
}

@discardableResult
private func writeJSON(_ url: URL, _ value: [String: Any], mode: Int = 0o600) -> Bool {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var payload = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        payload.append(0x0A)
        try payload.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return true
    } catch { return false }
}

/// 顶部为原点的容器，布局直接用「距顶部多少」计算。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let nodeBin: URL
    private let runtime: URL

    // 模型页
    private var providerField: NSTextField!
    private var baseUrlField: NSTextField!
    private var keyField: NSSecureTextField!
    private var modelCombo: NSComboBox!
    private var fetchButton: NSButton!
    private var modelStatus: NSTextField!

    // iMessage 页
    private var urlField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var senderField: NSTextField!
    private var guidField: NSTextField!
    private var chatDevicePopUp: NSPopUpButton!
    private var imessageStatus: NSTextField!
    private var testButton: NSButton!

    init(nodeBin: URL, runtime: URL) {
        self.nodeBin = nodeBin
        self.runtime = runtime
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Poki 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: 小工具

    private func label(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat, bold: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12)
        field.frame = NSRect(x: x, y: top + 3, width: width, height: 18)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func note(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat = 32) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.frame = NSRect(x: x, y: top, width: width, height: height)
        return field
    }

    private func button(_ title: String, x: CGFloat, top: CGFloat, width: CGFloat, action: Selector, key: String = "") -> NSButton {
        let item = NSButton(title: title, target: self, action: action)
        item.bezelStyle = .rounded
        item.frame = NSRect(x: x, y: top, width: width, height: 28)
        if !key.isEmpty { item.keyEquivalent = key }
        return item
    }

    // MARK: 构建

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 596, height: 456))
        tabs.autoresizingMask = [.width, .height]

        let modelTab = NSTabViewItem(identifier: "model")
        modelTab.label = "模型"
        modelTab.view = buildModelTab()
        tabs.addTabViewItem(modelTab)

        let chatTab = NSTabViewItem(identifier: "imessage")
        chatTab.label = "iMessage"
        chatTab.view = buildIMessageTab()
        tabs.addTabViewItem(chatTab)

        content.addSubview(tabs)
    }

    private func buildModelTab() -> NSView {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 572, height: 420))

        view.addSubview(label("供应商", x: 16, top: 20, width: 76, bold: true))
        providerField = NSTextField(frame: NSRect(x: 96, y: 18, width: 340, height: 26))
        providerField.placeholderString = "自定义名字，如 deepseek / my-relay"
        view.addSubview(providerField)

        view.addSubview(label("API 地址", x: 16, top: 56, width: 76, bold: true))
        baseUrlField = NSTextField(frame: NSRect(x: 96, y: 54, width: 430, height: 26))
        baseUrlField.placeholderString = "https://api.deepseek.com/v1"
        view.addSubview(baseUrlField)

        view.addSubview(label("API Key", x: 16, top: 92, width: 76, bold: true))
        keyField = NSSecureTextField(frame: NSRect(x: 96, y: 90, width: 430, height: 26))
        keyField.placeholderString = "sk-…"
        view.addSubview(keyField)

        view.addSubview(label("模型", x: 16, top: 128, width: 76, bold: true))
        modelCombo = NSComboBox(frame: NSRect(x: 96, y: 126, width: 340, height: 26))
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.numberOfVisibleItems = 12
        modelCombo.placeholderString = "点「获取模型」或直接输入模型名"
        view.addSubview(modelCombo)

        fetchButton = button("获取模型", x: 446, top: 125, width: 80, action: #selector(fetchModels))
        view.addSubview(fetchButton)

        view.addSubview(note("模型列表来自「API 地址」+ /models 接口。拉不到也可以直接手输模型名。",
                             x: 96, top: 160, width: 430, height: 32))

        modelStatus = label("", x: 16, top: 200, width: 520)
        modelStatus.textColor = .secondaryLabelColor
        view.addSubview(modelStatus)

        view.addSubview(button("保存", x: 96, top: 228, width: 96, action: #selector(saveModel), key: "\r"))
        view.addSubview(button("打开配置目录", x: 200, top: 228, width: 120, action: #selector(openAgentConfigDir)))

        view.addSubview(note("API Key 写入 ~/.config/poki-agent/env.json（权限 600，仅本机可读）。供应商与模型写进 models.json，pi 通过它识别自定义端点。",
                             x: 16, top: 268, width: 540, height: 34))
        return view
    }

    private func buildIMessageTab() -> NSView {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 572, height: 420))

        view.addSubview(label("服务地址", x: 16, top: 20, width: 82, bold: true))
        urlField = NSTextField(frame: NSRect(x: 100, y: 18, width: 340, height: 26))
        urlField.placeholderString = "http://127.0.0.1:1234"
        view.addSubview(urlField)

        view.addSubview(label("服务器密码", x: 16, top: 56, width: 82, bold: true))
        passwordField = NSSecureTextField(frame: NSRect(x: 100, y: 54, width: 340, height: 26))
        passwordField.placeholderString = "BlueBubbles → Connection 里设置的那个"
        view.addSubview(passwordField)

        view.addSubview(label("允许发送者", x: 16, top: 92, width: 82, bold: true))
        senderField = NSTextField(frame: NSRect(x: 100, y: 90, width: 340, height: 26))
        senderField.placeholderString = "邮箱或手机号，只接受这一个"
        senderField.target = self
        senderField.action = #selector(senderEdited)
        view.addSubview(senderField)

        view.addSubview(label("直聊 GUID", x: 16, top: 128, width: 82, bold: true))
        guidField = NSTextField(frame: NSRect(x: 100, y: 126, width: 340, height: 26))
        guidField.placeholderString = "留空自动用 iMessage;-;<发送者>"
        view.addSubview(guidField)

        view.addSubview(label("目标设备", x: 16, top: 164, width: 82, bold: true))
        chatDevicePopUp = NSPopUpButton(frame: NSRect(x: 100, y: 162, width: 340, height: 26), pullsDown: false)
        view.addSubview(chatDevicePopUp)

        testButton = button("测试连接", x: 100, top: 200, width: 110, action: #selector(testConnection))
        view.addSubview(testButton)
        view.addSubview(button("保存", x: 350, top: 200, width: 90, action: #selector(saveIMessage), key: "\r"))

        imessageStatus = note("", x: 16, top: 238, width: 520, height: 40)
        imessageStatus.stringValue = ""
        view.addSubview(imessageStatus)

        view.addSubview(note("只写本地私有配置（600），不安装、不启动 BlueBubbles，也不发任何消息。启动入口在菜单栏「iMessage 通道」。",
                             x: 16, top: 286, width: 520, height: 34))
        return view
    }

    // MARK: 子进程

    private func runPoki(_ arguments: [String], completion: @escaping (String, Int32) -> Void) {
        let process = Process()
        process.executableURL = nodeBin
        process.arguments = [runtime.appendingPathComponent("agent/poki.mjs").path] + arguments
        process.currentDirectoryURL = runtime
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(runtime.path):\(runtime.appendingPathComponent("tools").path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["IDEVICE_TOOLS"] = runtime.appendingPathComponent("tools/idevice-tools").path
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(text, process.terminationStatus) }
            } catch {
                DispatchQueue.main.async { completion(error.localizedDescription, 1) }
            }
        }
    }

    // MARK: 模型页

    /// 规范化用户填的 API 地址：至少是 http(s)，去掉尾部斜杠。
    private func normalizedBaseURL() -> String? {
        var text = baseUrlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            modelStatus.stringValue = "先填 API 地址，例如 https://api.deepseek.com/v1"
            return nil
        }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
            baseUrlField.stringValue = text
        }
        guard let parsed = URL(string: text), parsed.host != nil else {
            modelStatus.stringValue = "API 地址不是合法 URL。"
            return nil
        }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    @objc func fetchModels() {
        guard let base = normalizedBaseURL(), let url = URL(string: base + "/models") else { return }
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            modelStatus.stringValue = "先填 API Key，拉模型列表需要它。"
            return
        }
        fetchButton.isEnabled = false
        modelStatus.stringValue = "正在请求 \(base)/models …"
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetchButton.isEnabled = true
                if let error {
                    self.modelStatus.stringValue = "拉取失败：\(error.localizedDescription)。可以手动输入模型名。"
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    let preview = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(160) ?? ""
                    self.modelStatus.stringValue = "接口返回 HTTP \(http.statusCode)。\(preview)"
                    return
                }
                guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.modelStatus.stringValue = "响应不是 JSON，无法解析模型列表。可以手动输入模型名。"
                    return
                }
                var names: [String] = []
                if let list = object["data"] as? [[String: Any]] {
                    names = list.compactMap { $0["id"] as? String }
                } else if let list = object["models"] as? [[String: Any]] {
                    names = list.compactMap { ($0["name"] as? String) ?? ($0["id"] as? String) }
                }
                names = Array(Set(names)).sorted()
                guard !names.isEmpty else {
                    self.modelStatus.stringValue = "接口没返回可用模型。可以手动输入模型名。"
                    return
                }
                let current = self.modelCombo.stringValue
                self.modelCombo.removeAllItems()
                self.modelCombo.addItems(withObjectValues: names)
                self.modelCombo.stringValue = names.contains(current) ? current : names[0]
                self.modelStatus.stringValue = "拿到 \(names.count) 个模型，选一个再保存。"
            }
        }.resume()
    }

    @objc func saveModel() {
        let provider = providerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.isEmpty else { modelStatus.stringValue = "先填供应商名字。"; return }
        let lower = provider.lowercased().replacingOccurrences(of: " ", with: "-")
        guard lower.range(of: "^[a-z0-9][a-z0-9-]{0,48}$", options: .regularExpression) != nil else {
            modelStatus.stringValue = "供应商名只能用小写字母、数字和连字符。"
            return
        }
        guard let base = normalizedBaseURL() else { return }
        let model = modelCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { modelStatus.stringValue = "先选或填一个模型名。"; return }

        // 下拉里已有的模型都写进去，方便以后切换；当前选中的排在最前面。
        var pool = (modelCombo.objectValues as? [String]) ?? []
        pool.removeAll { $0 == model }
        pool.insert(model, at: 0)

        modelStatus.stringValue = "正在保存…"
        runPoki(["provider-set", "--id", lower, "--base-url", base,
                 "--models", pool.joined(separator: ","), "--model", model, "--json"]) { [weak self] text, code in
            guard let self else { return }
            guard code == 0 else {
                self.modelStatus.stringValue = "保存失败：\(text.prefix(200))"
                return
            }
            let key = self.keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                var secrets = readJSON(agentSecretsPath) ?? [:]
                secrets[customKeyName] = key
                guard writeJSON(agentSecretsPath, secrets) else {
                    self.modelStatus.stringValue = "供应商已保存，但写入密钥失败：\(agentSecretsPath.path)"
                    return
                }
                self.keyField.stringValue = ""
                self.keyField.placeholderString = "已保存（留空则不修改）"
            }
            self.providerField.stringValue = lower
            self.modelStatus.stringValue = "已保存 \(lower) · \(model)（\(pool.count) 个模型）"
            NotificationCenter.default.post(name: Notification.Name("PokiSettingsChanged"), object: nil)
        }
    }

    @objc func openAgentConfigDir() {
        let dir = agentConfigPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// 读回已保存的设置填进表单，密钥不回填。
    func reloadModelSettings() {
        let saved = readJSON(agentConfigPath) ?? [:]
        if let provider = saved["provider"] as? String { providerField.stringValue = provider }
        if let base = saved["baseUrl"] as? String { baseUrlField.stringValue = base }
        if let model = saved["model"] as? String { modelCombo.stringValue = model }
        if let secrets = readJSON(agentSecretsPath), secrets[customKeyName] != nil {
            keyField.placeholderString = "已保存（留空则不修改）"
        }
        modelStatus.stringValue = saved["baseUrl"] != nil
            ? "已配置：\(saved["provider"] as? String ?? "") · \(saved["model"] as? String ?? "")"
            : "还没配置，填好四项后保存。"
    }

    // MARK: iMessage

    @objc func senderEdited() {
        let sender = senderField.stringValue.trimmingCharacters(in: .whitespaces)
        if !sender.isEmpty { guidField.placeholderString = "iMessage;-;\(sender)" }
    }

    func reloadIMessage() {
        let connection = readJSON(imessageDirectory.appendingPathComponent("connection.json"))
        let config = readJSON(imessageDirectory.appendingPathComponent("imessage.json"))
        urlField.stringValue = connection?["url"] as? String ?? "http://127.0.0.1:1234"
        passwordField.stringValue = connection?["password"] as? String ?? ""
        senderField.stringValue = config?["sender"] as? String ?? ""
        guidField.stringValue = config?["chatGuid"] as? String ?? ""
        if let sender = config?["sender"] as? String, !sender.isEmpty {
            guidField.placeholderString = "iMessage;-;\(sender)"
        }
        imessageStatus.stringValue = connection == nil
            ? "尚未配置。填好下面几项后点「测试连接」，再「保存」。"
            : "已保存：\(connection?["url"] as? String ?? "")"
        loadDevices(preferred: config?["device"] as? String)
    }

    private func loadDevices(preferred: String?) {
        chatDevicePopUp.removeAllItems()
        runPoki(["status", "--json"]) { [weak self] text, _ in
            guard let self,
                  let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mcp = object["mcp"] as? [String: Any],
                  let devices = mcp["devices"] as? [[String: Any]] else { return }
            var selected = 0
            for (index, device) in devices.enumerated() {
                let name = device["name"] as? String ?? "设备"
                let id = device["id"] as? String ?? ""
                self.chatDevicePopUp.addItem(withTitle: "\(name) · \(id.prefix(8))")
                self.chatDevicePopUp.lastItem?.representedObject = id
                if preferred == id || preferred == name { selected = index }
            }
            if devices.isEmpty {
                self.chatDevicePopUp.addItem(withTitle: "没有检测到设备")
            } else {
                self.chatDevicePopUp.selectItem(at: selected)
            }
        }
    }

    @objc func testConnection() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        let text = raw.isEmpty ? "http://127.0.0.1:1234" : raw
        guard let parsed = URL(string: text), let host = parsed.host,
              ["127.0.0.1", "localhost", "::1"].contains(host), parsed.scheme == "http" else {
            imessageStatus.stringValue = "服务地址必须是本机 http 地址（127.0.0.1 / localhost）。"
            return
        }
        guard !passwordField.stringValue.isEmpty else {
            imessageStatus.stringValue = "先填 BlueBubbles 服务器密码。"
            return
        }
        var components = URLComponents(url: parsed.appendingPathComponent("api/v1/ping"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "password", value: passwordField.stringValue)]
        guard let target = components?.url else { return }
        imessageStatus.stringValue = "正在连接 \(host)…"
        testButton.isEnabled = false
        var request = URLRequest(url: target)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.testButton.isEnabled = true
                if let error {
                    self.imessageStatus.stringValue = "连不上：\(error.localizedDescription)。确认 BlueBubbles 正在运行、端口一致。"
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.imessageStatus.stringValue = "没有收到 HTTP 响应。"
                    return
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    self.imessageStatus.stringValue = "密码不对（HTTP \(http.statusCode)）。要和 BlueBubbles → Connection 里的密码一致。"
                } else if http.statusCode == 200 {
                    self.imessageStatus.stringValue = "连接正常 ✓ BlueBubbles 可达、密码有效。"
                } else {
                    self.imessageStatus.stringValue = "BlueBubbles 返回 HTTP \(http.statusCode)。"
                }
            }
        }.resume()
    }

    @objc func saveIMessage() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        let text = raw.isEmpty ? "http://127.0.0.1:1234" : raw
        guard let parsed = URL(string: text), let host = parsed.host,
              ["127.0.0.1", "localhost", "::1"].contains(host), parsed.scheme == "http" else {
            imessageStatus.stringValue = "服务地址必须是本机 http 地址。"
            return
        }
        let password = passwordField.stringValue
        guard !password.isEmpty else { imessageStatus.stringValue = "密码不能为空。"; return }
        let sender = senderField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !sender.isEmpty, !sender.contains(";") else {
            imessageStatus.stringValue = "发送者必须是单个地址，且不能含分号。"
            return
        }
        var guid = guidField.stringValue.trimmingCharacters(in: .whitespaces)
        if guid.isEmpty { guid = "iMessage;-;\(sender)" }
        guard ["iMessage;-;\(sender)", "any;-;\(sender)"].contains(guid) else {
            imessageStatus.stringValue = "GUID 只能是 iMessage;-;\(sender) 或 any;-;\(sender)。"
            return
        }
        guard let device = chatDevicePopUp.selectedItem?.representedObject as? String, !device.isEmpty else {
            imessageStatus.stringValue = "先选一个目标设备（需要 Poki 服务在运行，且手机已连接）。"
            return
        }
        try? FileManager.default.createDirectory(at: imessageDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: imessageDirectory.path)
        var base = parsed.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        let config: [String: Any] = ["sender": sender, "chatGuid": guid, "device": device, "auth": "oauth"]
        let connection: [String: Any] = ["url": base, "password": password]
        guard writeJSON(imessageDirectory.appendingPathComponent("imessage.json"), config),
              writeJSON(imessageDirectory.appendingPathComponent("connection.json"), connection) else {
            imessageStatus.stringValue = "写入配置失败。"
            return
        }
        imessageStatus.stringValue = "已保存。菜单栏「iMessage 通道」里可以启动。"
        NotificationCenter.default.post(name: Notification.Name("PokiSettingsChanged"), object: nil)
    }

    // MARK: 对外

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reloadModelSettings()
        reloadIMessage()
    }

    /// 自检：不显示窗口，只验证控件都构建成功
    func selfCheck() -> Bool {
        window?.contentView?.layoutSubtreeIfNeeded()
        return providerField != nil && baseUrlField != nil && keyField != nil && modelCombo != nil
            && urlField != nil && passwordField != nil && chatDevicePopUp != nil
    }
}
