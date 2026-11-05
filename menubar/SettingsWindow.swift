import Cocoa

// MARK: - 路径

private let homeDir = FileManager.default.homeDirectoryForCurrentUser
private let agentConfigPath = homeDir.appendingPathComponent(".config/poki-agent/config.json")
private let agentSecretsPath = homeDir.appendingPathComponent(".config/poki-agent/env.json")
private let imessageDirectory = homeDir.appendingPathComponent(".config/poki-agent/imessage")

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

    private var providers: [[String: Any]] = []
    private var models: [String] = []

    // 模型页
    private var providerPopUp: NSPopUpButton!
    private var modelPopUp: NSPopUpButton!
    private var authSegment: NSSegmentedControl!
    private var keyField: NSSecureTextField!
    private var modelStatus: NSTextField!
    private var loginButton: NSButton!

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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
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
        let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 576, height: 446))
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
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 552, height: 410))

        view.addSubview(label("供应商", x: 16, top: 20, width: 72, bold: true))
        providerPopUp = NSPopUpButton(frame: NSRect(x: 92, y: 18, width: 330, height: 26), pullsDown: false)
        providerPopUp.target = self
        providerPopUp.action = #selector(providerChanged)
        view.addSubview(providerPopUp)
        view.addSubview(button("刷新", x: 432, top: 17, width: 68, action: #selector(reloadProviders)))

        view.addSubview(label("模型", x: 16, top: 56, width: 72, bold: true))
        modelPopUp = NSPopUpButton(frame: NSRect(x: 92, y: 54, width: 330, height: 26), pullsDown: false)
        view.addSubview(modelPopUp)

        view.addSubview(label("认证", x: 16, top: 92, width: 72, bold: true))
        authSegment = NSSegmentedControl(labels: ["浏览器登录", "API Key"], trackingMode: .selectOne,
                                         target: self, action: #selector(authChanged))
        authSegment.frame = NSRect(x: 92, y: 90, width: 240, height: 26)
        authSegment.selectedSegment = 0
        view.addSubview(authSegment)

        view.addSubview(label("API Key", x: 16, top: 128, width: 72, bold: true))
        keyField = NSSecureTextField(frame: NSRect(x: 92, y: 126, width: 330, height: 26))
        keyField.placeholderString = "留空则不修改"
        view.addSubview(keyField)

        view.addSubview(note("密钥写入 ~/.config/poki-agent/env.json（权限 600，仅本机可读）。环境变量优先于这个文件。",
                             x: 92, top: 160, width: 400, height: 32))

        modelStatus = label("", x: 16, top: 200, width: 500)
        modelStatus.textColor = .secondaryLabelColor
        view.addSubview(modelStatus)

        loginButton = button("在终端登录…", x: 92, top: 228, width: 130, action: #selector(openLoginInTerminal))
        view.addSubview(loginButton)
        view.addSubview(button("打开配置目录", x: 232, top: 228, width: 130, action: #selector(openAgentConfigDir)))
        view.addSubview(button("保存", x: 372, top: 228, width: 90, action: #selector(saveModel), key: "\r"))

        view.addSubview(note("不选模型时，自动使用该供应商目录里的第一个对话模型。切换供应商后点「保存」才会生效。",
                             x: 16, top: 268, width: 510, height: 34))
        return view
    }

    private func buildIMessageTab() -> NSView {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 552, height: 410))

        view.addSubview(label("服务地址", x: 16, top: 20, width: 82, bold: true))
        urlField = NSTextField(frame: NSRect(x: 100, y: 18, width: 330, height: 26))
        urlField.placeholderString = "http://127.0.0.1:1234"
        view.addSubview(urlField)

        view.addSubview(label("服务器密码", x: 16, top: 56, width: 82, bold: true))
        passwordField = NSSecureTextField(frame: NSRect(x: 100, y: 54, width: 330, height: 26))
        passwordField.placeholderString = "BlueBubbles → Connection 里设置的那个"
        view.addSubview(passwordField)

        view.addSubview(label("允许发送者", x: 16, top: 92, width: 82, bold: true))
        senderField = NSTextField(frame: NSRect(x: 100, y: 90, width: 330, height: 26))
        senderField.placeholderString = "邮箱或手机号，只接受这一个"
        senderField.target = self
        senderField.action = #selector(senderEdited)
        view.addSubview(senderField)

        view.addSubview(label("直聊 GUID", x: 16, top: 128, width: 82, bold: true))
        guidField = NSTextField(frame: NSRect(x: 100, y: 126, width: 330, height: 26))
        guidField.placeholderString = "留空自动用 iMessage;-;<发送者>"
        view.addSubview(guidField)

        view.addSubview(label("目标设备", x: 16, top: 164, width: 82, bold: true))
        chatDevicePopUp = NSPopUpButton(frame: NSRect(x: 100, y: 162, width: 330, height: 26), pullsDown: false)
        view.addSubview(chatDevicePopUp)

        testButton = button("测试连接", x: 100, top: 200, width: 110, action: #selector(testConnection))
        view.addSubview(testButton)
        view.addSubview(button("保存", x: 340, top: 200, width: 90, action: #selector(saveIMessage), key: "\r"))

        imessageStatus = note("", x: 16, top: 238, width: 510, height: 40)
        imessageStatus.stringValue = ""
        view.addSubview(imessageStatus)

        view.addSubview(note("只写本地私有配置（600），不安装、不启动 BlueBubbles，也不发任何消息。启动入口在菜单栏「iMessage 通道」。",
                             x: 16, top: 286, width: 510, height: 34))
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

    // MARK: 模型页逻辑

    @objc func reloadProviders() {
        modelStatus.stringValue = "正在读取供应商…"
        runPoki(["providers", "--json"]) { [weak self] text, code in
            guard let self else { return }
            guard code == 0,
                  let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = object["providers"] as? [[String: Any]] else {
                self.modelStatus.stringValue = "读取供应商失败：\(text.prefix(120))"
                return
            }
            self.providers = list
            self.providerPopUp.removeAllItems()
            for entry in list {
                let id = entry["id"] as? String ?? ""
                let name = entry["name"] as? String ?? id
                let configured = entry["configured"] as? Bool ?? false
                self.providerPopUp.addItem(withTitle: "\(name) · \(id)\(configured ? " ✓" : "")")
                self.providerPopUp.lastItem?.representedObject = id
            }
            let current = object["current"] as? String ?? "openai"
            if let index = list.firstIndex(where: { ($0["id"] as? String) == current }) {
                self.providerPopUp.selectItem(at: index)
            }
            self.modelStatus.stringValue = "共 \(list.count) 个供应商"
            self.applySavedAuth()
            self.providerChanged()
            self.applySavedModel()
        }
    }

    private func applySavedAuth() {
        guard let saved = readJSON(agentConfigPath), let auth = saved["auth"] as? String else { return }
        authSegment.selectedSegment = auth == "api-key" ? 1 : 0
        keyField.isEnabled = authSegment.selectedSegment == 1
    }

    private func applySavedModel() {
        guard let saved = readJSON(agentConfigPath), let model = saved["model"] as? String,
              let provider = saved["provider"] as? String,
              let index = providers.firstIndex(where: { ($0["id"] as? String) == provider }) else { return }
        providerPopUp.selectItem(at: index)
        providerChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let target = self.models.firstIndex(of: model) else { return }
            self.modelPopUp.selectItem(at: target)
        }
    }

    @objc func providerChanged() {
        guard let provider = providerPopUp.selectedItem?.representedObject as? String else { return }
        let entry = providers.first(where: { ($0["id"] as? String) == provider })
        loginButton.isEnabled = entry?["oauth"] as? Bool ?? false
        if let envName = entry?["env"] as? String {
            keyField.placeholderString = "留空则不修改（变量 \(envName)）"
        } else {
            keyField.placeholderString = "该供应商没有已知的 key 变量"
        }
        modelStatus.stringValue = "正在读取 \(provider) 的模型…"
        modelPopUp.removeAllItems()
        models = []
        runPoki(["models", "--provider", provider, "--json"]) { [weak self] text, code in
            guard let self else { return }
            guard code == 0,
                  let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = object["models"] as? [String] else {
                self.modelStatus.stringValue = "读取模型失败：\(text.prefix(120))"
                return
            }
            self.models = list
            self.modelPopUp.removeAllItems()
            for id in list {
                self.modelPopUp.addItem(withTitle: id)
                self.modelPopUp.lastItem?.representedObject = id
            }
            self.modelStatus.stringValue = "\(provider)：\(list.count) 个可用模型"
        }
    }

    @objc func authChanged() {
        keyField.isEnabled = authSegment.selectedSegment == 1
    }

    @objc func saveModel() {
        guard let provider = providerPopUp.selectedItem?.representedObject as? String else {
            modelStatus.stringValue = "先选一个供应商"
            return
        }
        var config = readJSON(agentConfigPath) ?? [:]
        config["provider"] = provider
        if let model = modelPopUp.selectedItem?.representedObject as? String { config["model"] = model }
        config["auth"] = authSegment.selectedSegment == 0 ? "oauth" : "api-key"
        guard writeJSON(agentConfigPath, config) else {
            modelStatus.stringValue = "写入配置失败：\(agentConfigPath.path)"
            return
        }
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            let entry = providers.first(where: { ($0["id"] as? String) == provider })
            guard let envName = entry?["env"] as? String else {
                modelStatus.stringValue = "已保存供应商，但该供应商没有已知的 key 变量，密钥未保存"
                return
            }
            var secrets = readJSON(agentSecretsPath) ?? [:]
            secrets[envName] = key
            guard writeJSON(agentSecretsPath, secrets) else {
                modelStatus.stringValue = "写入密钥失败：\(agentSecretsPath.path)"
                return
            }
            keyField.stringValue = ""
            modelStatus.stringValue = "已保存 \(provider) · 密钥写入 \(envName)"
        } else {
            modelStatus.stringValue = "已保存 \(provider) · \(authSegment.selectedSegment == 0 ? "OAuth" : "API Key")"
        }
        NotificationCenter.default.post(name: Notification.Name("PokiSettingsChanged"), object: nil)
    }

    @objc func openAgentConfigDir() {
        let dir = agentConfigPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// OAuth 要在真终端里完成，这里写一个 .command 交给 Terminal，避免使用 Apple Events。
    @objc func openLoginInTerminal() {
        guard let provider = providerPopUp.selectedItem?.representedObject as? String else { return }
        let script = """
        #!/bin/sh
        export PATH="\(runtime.path):\(runtime.appendingPathComponent("tools").path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        "\(nodeBin.path)" "\(runtime.appendingPathComponent("agent/poki.mjs").path)" login --provider \(provider)
        echo
        echo "登录完成后可以关闭这个窗口，回到 Poki 设置点「刷新」。"
        """
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("poki-login-\(provider).command")
        do {
            try script.write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            NSWorkspace.shared.open(path)
            modelStatus.stringValue = "已打开终端，请在浏览器完成 \(provider) 登录"
        } catch {
            modelStatus.stringValue = "无法启动登录：\(error.localizedDescription)"
        }
    }

    // MARK: iMessage 逻辑

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
        reloadProviders()
        reloadIMessage()
    }

    /// 自检：不显示窗口，只验证控件都构建成功
    func selfCheck() -> Bool {
        window?.contentView?.layoutSubtreeIfNeeded()
        return providerPopUp != nil && modelPopUp != nil && authSegment != nil
            && urlField != nil && passwordField != nil && chatDevicePopUp != nil
    }
}
