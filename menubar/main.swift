import Cocoa

// MARK: - 路径

let appBundle = Bundle.main.bundleURL
let runtime = Bundle.main.resourceURL!.appendingPathComponent("poki")
let nodeBin = runtime.appendingPathComponent("node")
let daemonScript = runtime.appendingPathComponent("src/daemon.mjs")
let stdioScript = runtime.appendingPathComponent("src/stdio.mjs")
let ideviceTools = runtime.appendingPathComponent("tools/idevice-tools")

let home = FileManager.default.homeDirectoryForCurrentUser
let stateDir = home.appendingPathComponent("Library/Application Support/PokiMCP")
let endpoointFile = stateDir.appendingPathComponent("mcp.json")
let logDir = home.appendingPathComponent("Library/Logs/Poki")
let logFile = logDir.appendingPathComponent("daemon.log")
let imessageLog = logDir.appendingPathComponent("imessage.log")
let imessageDir = home.appendingPathComponent(".config/poki-agent/imessage")
let launchAgent = home.appendingPathComponent("Library/LaunchAgents/bot.poki.menubar.plist")
let agentLabel = "bot.poki.menubar"
let defaultPort = 47825

// MARK: - 服务

final class PokiService {
    enum Status: Equatable {
        case stopped
        case starting
        case running(port: Int, tools: Int)
        case failed(String)
    }

    private(set) var status: Status = .stopped { didSet { onChange?() } }
    var onChange: (() -> Void)?

    private var process: Process?
    private var logHandle: FileHandle?
    private var buffer = ""
    private var stoppingByUser = false
    private var restartCount = 0
    private var pendingRestart: DispatchWorkItem?

    private func log(_ text: String) {
        guard let handle = logHandle else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        if let data = "[\(stamp)] \(text)\n".data(using: .utf8) { handle.write(data) }
    }

    private func openLog() {
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        logHandle = try? FileHandle(forWritingTo: logFile)
        logHandle?.seekToEndOfFile()
    }

    /// 启动前清掉上一次遗留的 daemon：服务的生命周期必须与 App 一致。
    private func killStaleDaemon() {
        guard let data = try? Data(contentsOf: endpoointFile),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = entry["pid"] as? Int, pid > 0,
              pid != Int(ProcessInfo.processInfo.processIdentifier) else { return }
        guard kill(Int32(pid), 0) == 0 else {
            try? FileManager.default.removeItem(at: endpoointFile)
            return
        }
        kill(Int32(pid), SIGTERM)
        for _ in 0..<25 {
            if kill(Int32(pid), 0) != 0 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if kill(Int32(pid), 0) == 0 { kill(Int32(pid), SIGKILL) }
        try? FileManager.default.removeItem(at: endpoointFile)
        log("清理残留 daemon pid=\(pid)")
    }

    func start() {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: nodeBin.path) else {
            status = .failed("应用内置运行时缺失，请重新安装")
            return
        }
        pendingRestart?.cancel()
        pendingRestart = nil
        openLog()
        status = .starting
        stoppingByUser = false

        killStaleDaemon()

        let p = Process()
        p.executableURL = nodeBin
        p.arguments = [daemonScript.path, "--port", String(defaultPort)]
        p.currentDirectoryURL = runtime
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(runtime.path):\(runtime.appendingPathComponent("tools").path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["IDEVICE_TOOLS"] = ideviceTools.path
        env["POKI_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.consume(text)
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.handleExit(code: proc.terminationStatus) }
        }

        do {
            try p.run()
            process = p
            log("daemon 启动 pid=\(p.processIdentifier)")
        } catch {
            status = .failed("启动失败：\(error.localizedDescription)")
            log("启动失败 \(error)")
        }
    }

    private func consume(_ text: String) {
        buffer += text
        while let idx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx])
            buffer = String(buffer[buffer.index(after: idx)...])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            log(trimmed)
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["event"] as? String == "ready" {
                let port = obj["port"] as? Int ?? defaultPort
                let tools = obj["tools"] as? Int ?? 0
                DispatchQueue.main.async { [weak self] in
                    self?.restartCount = 0
                    self?.status = .running(port: port, tools: tools)
                }
            }
        }
        if buffer.count > 8192 { buffer = String(buffer.suffix(2048)) }
    }

    private func handleExit(code: Int32) {
        process = nil
        logHandle?.closeFile()
        logHandle = nil
        if stoppingByUser {
            status = .stopped
            return
        }
        status = .failed("服务异常退出（代码 \(code)），3 秒后重试")
        guard restartCount < 3 else {
            status = .failed("服务连续异常退出，已停止重试")
            return
        }
        restartCount += 1
        let item = DispatchWorkItem { [weak self] in self?.start() }
        pendingRestart = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    func stop() {
        pendingRestart?.cancel()
        pendingRestart = nil
        stoppingByUser = true
        guard let p = process else { status = .stopped; return }
        log("用户请求停止")
        p.terminate()
        let deadline = Date().addingTimeInterval(5)
        while p.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        process = nil
        status = .stopped
    }

    func restart() {
        stop()
        restartCount = 0
        start()
    }

    func shutdown() {
        pendingRestart?.cancel()
        stoppingByUser = true
        process?.terminate()
        let deadline = Date().addingTimeInterval(3)
        while let p = process, p.isRunning, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if let p = process, p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    var isRunning: Bool { process?.isRunning ?? false }
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = PokiService()
    var statusItem: NSStatusItem!
    var statusLine: NSMenuItem!
    var toggleItem: NSMenuItem!
    var restartItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var imessageStatusLine: NSMenuItem!
    var imessageToggleItem: NSMenuItem!
    var imessageCheckItem: NSMenuItem!
    var imessageProcess: Process?
    var imessageTrouble: String?
    var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeStatusImage(running: false)
            button.toolTip = "Poki"
        }
        buildMenu()

        service.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }

        syncLoginAgentPath()
        service.start()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.shutdown()
        imessageProcess?.terminate()
    }

    // MARK: 菜单

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLine = NSMenuItem(title: "正在启动…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "启动服务", action: #selector(toggleService), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        restartItem = NSMenuItem(title: "重启服务", action: #selector(restartService), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(.separator())

        let copy = NSMenuItem(title: "复制 MCP 配置", action: #selector(copyConfig), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)

        let openState = NSMenuItem(title: "打开状态目录", action: #selector(openStateDir), keyEquivalent: "")
        openState.target = self
        menu.addItem(openState)

        let openLog = NSMenuItem(title: "查看日志", action: #selector(openLogFile), keyEquivalent: "l")
        openLog.target = self
        menu.addItem(openLog)

        menu.addItem(.separator())

        let imessage = NSMenuItem(title: "iMessage 通道", action: nil, keyEquivalent: "")
        let imessageMenu = NSMenu()
        imessageStatusLine = NSMenuItem(title: "未配置", action: nil, keyEquivalent: "")
        imessageStatusLine.isEnabled = false
        imessageMenu.addItem(imessageStatusLine)
        imessageMenu.addItem(.separator())
        imessageToggleItem = NSMenuItem(title: "启动通道", action: #selector(toggleIMessage), keyEquivalent: "")
        imessageToggleItem.target = self
        imessageMenu.addItem(imessageToggleItem)
        imessageCheckItem = NSMenuItem(title: "检查连接", action: #selector(checkIMessage), keyEquivalent: "")
        imessageCheckItem.target = self
        imessageMenu.addItem(imessageCheckItem)
        imessageMenu.addItem(.separator())
        let imessageSetup = NSMenuItem(title: "配置 BlueBubbles…", action: #selector(copyIMessageSetup), keyEquivalent: "")
        imessageSetup.target = self
        imessageMenu.addItem(imessageSetup)
        let imessageOpen = NSMenuItem(title: "打开配置目录", action: #selector(openIMessageDir), keyEquivalent: "")
        imessageOpen.target = self
        imessageMenu.addItem(imessageOpen)
        let imessageLogItem = NSMenuItem(title: "查看通道日志", action: #selector(openIMessageLog), keyEquivalent: "")
        imessageLogItem.target = self
        imessageMenu.addItem(imessageLogItem)
        imessage.submenu = imessageMenu
        menu.addItem(imessage)

        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Poki", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func refresh() {
        let running: Bool
        switch service.status {
        case .running(let port, let tools):
            statusLine.title = tools > 0 ? "运行中 · 127.0.0.1:\(port) · \(tools) 个工具" : "运行中 · 127.0.0.1:\(port)"
            toggleItem.title = "停止服务"
            running = true
        case .starting:
            statusLine.title = "正在启动…"
            toggleItem.title = "停止服务"
            running = false
        case .stopped:
            statusLine.title = "已停止"
            toggleItem.title = "启动服务"
            running = false
        case .failed(let message):
            statusLine.title = message
            toggleItem.title = "启动服务"
            running = false
        }
        toggleItem.isEnabled = true
        restartItem.isEnabled = service.isRunning
        loginItem.state = FileManager.default.fileExists(atPath: launchAgent.path) ? .on : .off
        statusItem.button?.image = makeStatusImage(running: running)
        refreshIMessage()
    }

    func makeStatusImage(running: Bool) -> NSImage? {
        guard let base = Bundle.main.image(forResource: "menubar") else {
            let fallback = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Poki")
            fallback?.isTemplate = true
            return fallback
        }
        base.size = NSSize(width: 18, height: 18)
        base.isTemplate = false
        if running { return base }
        let dim = NSImage(size: NSSize(width: 18, height: 18))
        dim.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 0.35)
        dim.unlockFocus()
        dim.isTemplate = false
        return dim
    }

    // MARK: 动作

    @objc func toggleService() {
        if service.isRunning || service.status == .starting {
            service.stop()
        } else {
            service.start()
        }
        refresh()
    }

    @objc func restartService() {
        service.restart()
        refresh()
    }

    @objc func copyConfig() {
        let config: [String: Any] = [
            "mcpServers": [
                "poki-mcp": [
                    "command": nodeBin.path,
                    "args": [stdioScript.path]
                ]
            ]
        ]
        let text: String
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            text = str
        } else {
            text = "{\"mcpServers\":{\"poki-mcp\":{\"command\":\"\(nodeBin.path)\",\"args\":[\"\(stdioScript.path)\"]}}}"
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        flash("MCP 配置已复制到剪贴板")
    }

    @objc func openStateDir() {
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(stateDir)
    }

    @objc func openLogFile() {
        if !FileManager.default.fileExists(atPath: logFile.path) {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        NSWorkspace.shared.open(logFile)
    }

    // MARK: iMessage 通道

    var imessageConfigured: Bool {
        FileManager.default.fileExists(atPath: imessageDir.appendingPathComponent("connection.json").path)
    }

    func refreshIMessage() {
        guard imessageStatusLine != nil else { return }
        let running = imessageProcess?.isRunning ?? false
        if !imessageConfigured {
            imessageStatusLine.title = "未配置 · 用「配置 BlueBubbles…」取命令"
        } else if let trouble = imessageTrouble {
            imessageStatusLine.title = "已配置 · \(trouble)"
        } else if running {
            imessageStatusLine.title = "通道运行中"
        } else {
            imessageStatusLine.title = "已配置 · 通道未启动"
        }
        imessageToggleItem.title = running ? "停止通道" : "启动通道"
        imessageToggleItem.isEnabled = imessageConfigured
        imessageCheckItem.isEnabled = imessageConfigured
    }

    @objc func toggleIMessage() {
        if imessageProcess?.isRunning == true { stopIMessage() } else { startIMessage() }
        refreshIMessage()
    }

    func channelEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(runtime.path):\(runtime.appendingPathComponent("tools").path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["IDEVICE_TOOLS"] = ideviceTools.path
        env["POKI_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        return env
    }

    func startIMessage() {
        guard imessageConfigured else { return }
        imessageTrouble = nil
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: imessageLog.path) {
            FileManager.default.createFile(atPath: imessageLog.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: imessageLog) else { return }
        handle.seekToEndOfFile()

        let p = Process()
        p.executableURL = nodeBin
        p.arguments = [runtime.appendingPathComponent("agent/poki.mjs").path, "imessage"]
        p.currentDirectoryURL = runtime
        p.environment = channelEnvironment()
        p.standardOutput = handle
        p.standardError = handle
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.imessageProcess = nil
                if proc.terminationStatus != 0 {
                    self?.imessageTrouble = "退出码 \(proc.terminationStatus)，看通道日志"
                }
                self?.refreshIMessage()
            }
        }
        do {
            try p.run()
            imessageProcess = p
            flash("iMessage 通道已启动")
        } catch {
            imessageTrouble = "启动失败：\(error.localizedDescription)"
        }
        refreshIMessage()
    }

    func stopIMessage() {
        imessageProcess?.terminate()
        imessageProcess = nil
        flash("iMessage 通道已停止")
    }

    @objc func checkIMessage() {
        guard imessageConfigured else { return }
        imessageCheckItem.title = "检查中…"
        let p = Process()
        p.executableURL = nodeBin
        p.arguments = [runtime.appendingPathComponent("agent/poki.mjs").path, "imessage", "--check"]
        p.currentDirectoryURL = runtime
        p.environment = channelEnvironment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self] proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.imessageCheckItem.title = "检查连接"
                if proc.terminationStatus == 0 {
                    self.imessageTrouble = nil
                    self.flash("BlueBubbles 连接正常")
                } else {
                    self.imessageTrouble = text.isEmpty ? "检查失败" : String(text.prefix(70))
                    self.flash(self.imessageTrouble ?? "检查失败")
                }
                self.refreshIMessage()
            }
        }
        do { try p.run() }
        catch {
            imessageCheckItem.title = "检查连接"
            imessageTrouble = "无法执行检查"
            refreshIMessage()
        }
    }

    @objc func copyIMessageSetup() {
        let command = "poki imessage-setup"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(command, forType: .string)
        flash("已复制「\(command)」，粘到终端运行即配置")
    }

    @objc func openIMessageDir() {
        try? FileManager.default.createDirectory(at: imessageDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(imessageDir)
    }

    @objc func openIMessageLog() {
        if !FileManager.default.fileExists(atPath: imessageLog.path) {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: imessageLog.path, contents: nil)
        }
        NSWorkspace.shared.open(imessageLog)
    }

    @objc func toggleLogin() {
        if FileManager.default.fileExists(atPath: launchAgent.path) {
            try? FileManager.default.removeItem(at: launchAgent)
            flash("已关闭登录时启动")
        } else {
            writeLoginAgent()
            flash("已开启登录时启动")
        }
        refresh()
    }

    func writeLoginAgent() {
        try? FileManager.default.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(appBundle.path)</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        try? plist.write(to: launchAgent, atomically: true, encoding: .utf8)
    }

    /// 应用被移动后，登录项里的旧路径要跟着更新
    func syncLoginAgentPath() {
        guard FileManager.default.fileExists(atPath: launchAgent.path) else { return }
        if let text = try? String(contentsOf: launchAgent, encoding: .utf8),
           !text.contains(appBundle.path) {
            writeLoginAgent()
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(nodeBin: nodeBin, runtime: runtime)
        }
        settingsWindow?.show()
    }

    func flash(_ message: String) {
        let original = statusLine.title
        statusLine.title = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.statusLine.title = original
            self.refresh()
        }
    }
}

let app = NSApplication.shared

// 命令行自检：只构建设置窗口，不显示、不启动服务，用于打包后验证 UI 代码不崩。
if CommandLine.arguments.contains("--selftest") {
    app.setActivationPolicy(.accessory)
    let controller = SettingsWindowController(nodeBin: nodeBin, runtime: runtime)
    let ok = controller.selfCheck()
    print(ok ? "SELFTEST OK" : "SELFTEST FAILED")
    exit(ok ? 0 : 1)
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
