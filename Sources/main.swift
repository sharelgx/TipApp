import Cocoa
import SwiftUI
import UserNotifications
import ServiceManagement

struct Post: Codable, Identifiable {
    var id: String
    var title: String
    var body: String
    var category: String
    var date: Date
    var url: URL
    var relevant: Bool {
        let text = (title + " " + category).lowercased()
        return text.contains("reset") || text.contains("credit") || text.contains("额度") || text.contains("重置")
    }
    var isConfirmedCompletion: Bool {
        let c = category.lowercased()
        return c.contains("completed") && !c.contains("planned")
    }
    var notificationBody: String {
        let c = category.lowercased()
        if c.contains("planned") {
            return "Tibo 预告将重置 Codex 额度，目前尚未确认完成。请点击查看原帖中的时间安排。"
        }
        if isConfirmedCompletion {
            return "Tibo 已宣布 Codex 额度重置完成。请查看你的账户确认是否到账，点击可查看原帖。"
        }
        if c.contains("bank") || title.lowercased().contains("bank") {
            return "Tibo 发布了重置卡相关消息。是否已发放及如何使用，请点击查看原帖；这不代表额度已自动重置。"
        }
        return "Tibo 发布了额度或重置相关消息，当前未归类为计划或完成。请点击查看原帖核实。"
    }
    var kind: String {
        let c = category.lowercased()
        if c.contains("planned") { return "计划重置" }
        if c.contains("completed") { return "已宣布完成" }
        if c.contains("bank") || title.lowercased().contains("bank") { return "重置卡消息" }
        return relevant ? "重置相关" : "Codex 动态"
    }
}

final class FeedParser: NSObject, XMLParserDelegate {
    var posts: [Post] = []
    var fields: [String:String] = [:]
    var element = ""
    var inside = false
    static func parse(_ data: Data) throws -> [Post] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.posts.isEmpty else { throw NSError(domain: "Feed", code: 1, userInfo: [NSLocalizedDescriptionKey:"消息源为空或格式已变化"]) }
        return delegate.posts.sorted { $0.date > $1.date }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        element = name
        if name == "item" { inside = true; fields = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inside { fields[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8), inside { fields[element, default: ""] += s }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "item" else { return }
        inside = false
        let body = fields["description", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try! NSRegularExpression(pattern: "https://x\\.com/thsottiaux/status/[0-9]+")
        guard let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let r = Range(match.range, in: body), let url = URL(string: String(body[r])) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: fields["pubDate", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        posts.append(Post(id: url.absoluteString, title: fields["title", default: ""], body: body, category: fields["category", default:""], date:date, url:url))
    }
}

struct ReminderView: View {
    let post: Post
    let count: Int
    let dismiss: () -> Void
    private var isTest: Bool { post.id.hasPrefix("test-") }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                if let url = Bundle.main.url(forResource:"tibo-avatar",withExtension:"jpg"), let avatar = NSImage(contentsOf:url) {
                    Image(nsImage:avatar).resizable().scaledToFill().frame(width:44,height:44).clipShape(Circle())
                }
                VStack(alignment:.leading,spacing:4) {
                    Text((isTest ? "【测试】" : "") + "Tibo · " + post.kind).font(.title3.weight(.semibold))
                    Text(isTest ? "模拟提醒 · 并非新的重置消息" : "Codex 额度消息").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(post.notificationBody).font(.system(size:14)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            HStack {
                Text(count > 1 ? "还有 \(count - 1) 条待查看" : "文字提醒会保留到你关闭").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(count > 1 ? "下一条" : "关闭提醒",action:dismiss).keyboardShortcut(.cancelAction)
                Button("查看原帖") { NSWorkspace.shared.open(post.url) }
            }
        }.padding(24).frame(width:440,alignment:.leading).preferredColorScheme(.light)
    }
}

@MainActor final class ReminderPresenter: NSObject, NSWindowDelegate {
    private var pending: [Post] = []
    private var panel: NSPanel?
    var isVisible: Bool { panel?.isVisible ?? false }
    func show(_ post: Post) {
        guard !pending.contains(where: { $0.id == post.id }) else { return }
        pending.append(post)
        render()
    }
    private func render() {
        guard let post = pending.first else { panel?.orderOut(nil); return }
        if panel == nil {
            let window = NSPanel(contentRect:NSRect(x:0,y:0,width:440,height:230),styleMask:[.titled,.closable,.nonactivatingPanel],backing:.buffered,defer:false)
            window.title = "Tibo 文字提醒"
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            window.delegate = self
            panel = window
        }
        guard let panel else { return }
        panel.contentViewController = NSHostingController(rootView:ReminderView(post:post,count:pending.count,dismiss:{ [weak self] in self?.dismiss() }))
        if !panel.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x:frame.maxX-panel.frame.width-24,y:frame.maxY-panel.frame.height-24))
            }
        }
        panel.orderFrontRegardless()
    }
    private func dismiss() {
        if !pending.isEmpty { pending.removeFirst() }
        render()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}

@MainActor final class Monitor: ObservableObject {
    @Published var posts: [Post] = []
    @Published var message = "等待首次检查"
    @Published var checked: Date?
    @Published var busy = false
    @Published var paused = false
    @Published var permission = "尚未检查"
    @Published var login = false
    @Published var loginMessage = ""
    @Published var voiceEnabled = UserDefaults.standard.object(forKey:"voiceEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(voiceEnabled,forKey:"voiceEnabled")
            if !voiceEnabled, let process = voiceProcess, process.isRunning { process.terminate() }
        }
    }
    @Published var audioMessage = ""
    private let reminders = ReminderPresenter()
    private var voiceProcess: Process?
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private var seen: Set<String>
    private var initialized: Bool
    private let cache: URL
    init() {
        seen = Set(UserDefaults.standard.stringArray(forKey:"seen") ?? [])
        initialized = UserDefaults.standard.bool(forKey:"initialized")
        cache = FileManager.default.urls(for: .applicationSupportDirectory, in:.userDomainMask)[0].appendingPathComponent("TiboWatch/posts.json")
        if let data = try? Data(contentsOf:cache), let stored = try? JSONDecoder().decode([Post].self, from:data) { posts = stored }
        login = SMAppService.mainApp.status == .enabled
    }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval:60, repeats:true) { [weak self] _ in Task { @MainActor in await self?.check() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification, object:nil, queue:.main) { [weak self] _ in Task { @MainActor in await self?.check() } }
        Task { await refreshPermission(); await check() }
    }
    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = settings.authorizationStatus == .authorized ? "已允许" : settings.authorizationStatus == .denied ? "未允许，请在系统设置中开启" : "尚未允许"
    }
    func allow() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]); await refreshPermission() }
        catch { permission = error.localizedDescription }
    }
    func notify(_ post: Post) async throws {
        let content = UNMutableNotificationContent()
        let isTest = post.id.hasPrefix("test-")
        content.title = (isTest ? "【测试】" : "") + "Tibo · \(post.kind)"
        content.body = (isTest ? "这是一条模拟通知，并非新的重置消息。\n" : "") + post.notificationBody
        let spoken = post.isConfirmedCompletion && voiceEnabled
        content.sound = spoken ? nil : .default
        content.userInfo = ["url":post.url.absoluteString]
        let center = UNUserNotificationCenter.current()
        try await center.add(UNNotificationRequest(identifier:post.id,content:content,trigger:nil))
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { reminders.show(post) }
        if spoken, settings.authorizationStatus == .authorized, settings.soundSetting == .enabled {
            // Use the media output path tested on this Mac. Coalesce simultaneous
            // completion announcements so the same phrase cannot overlap itself.
            if let process = voiceProcess, process.isRunning { return }
            guard let url = Bundle.main.url(forResource:"reset-confirmed",withExtension:"caf") else {
                audioMessage = "中文播报文件缺失"
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/afplay")
            process.arguments = [url.path]
            do {
                try process.run()
                voiceProcess = process
                audioMessage = ""
            } catch { audioMessage = "中文播报失败：\(error.localizedDescription)" }
        }
    }
    func test() async {
        await allow()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let identifier = "test-\(UUID())"
        var report: [String:Any] = [
            "time": ISO8601DateFormatter().string(from:Date()),
            "authorizationStatus": settings.authorizationStatus.rawValue,
            "alertSetting": settings.alertSetting.rawValue,
            "soundSetting": settings.soundSetting.rawValue,
            "notificationCenterSetting": settings.notificationCenterSetting.rawValue,
            "alertStyle": settings.alertStyle.rawValue,
            "identifier": identifier
        ]
        do {
            try await notify(Post(id:identifier, title:"这是一条 Tibo Watch 测试通知，点击可打开 Tibo 主页。",body:"",category:"Reset Completed",date:Date(),url:URL(string:"https://x.com/thsottiaux")!))
            report["submitted"] = true
            report["textWindowVisible"] = reminders.isVisible
            report["voiceEnabled"] = voiceEnabled
            let playback = voiceProcess
            report["playbackStarted"] = playback?.isRunning ?? false
            report["playbackError"] = audioMessage
            try? await Task.sleep(nanoseconds:5_000_000_000)
            if let playback, !playback.isRunning { report["playbackExitStatus"] = playback.terminationStatus }
            let delivered = await center.deliveredNotifications()
            report["delivered"] = delivered.contains { $0.request.identifier == identifier }
            message = "测试通知已提交，请查看屏幕右上角或通知中心"
        } catch {
            report["submitted"] = false
            report["error"] = error.localizedDescription
            message = "通知失败：\(error.localizedDescription)"
        }
        try? FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true)
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:cache.deletingLastPathComponent().appendingPathComponent("notification-test.json"),options:.atomic)
        }
    }
    func check() async {
        guard !busy, !paused else { return }
        busy = true
        defer { busy = false }
        do {
            var request = URLRequest(url:URL(string:"https://tibo.modelyard.dev/feed.xml")!, cachePolicy:.reloadIgnoringLocalCacheData, timeoutInterval:25)
            request.setValue("TiboWatch/1.0 (macOS personal RSS reader)", forHTTPHeaderField:"User-Agent")
            let (data,response) = try await URLSession.shared.data(for:request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NSError(domain:"HTTP",code:1,userInfo:[NSLocalizedDescriptionKey:"消息源暂时不可用"]) }
            let fresh = try FeedParser.parse(data)
            posts = fresh
            var notificationFailed = false
            if initialized {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                for post in fresh.reversed() where !seen.contains(post.id) {
                    if post.relevant {
                        guard settings.authorizationStatus == .authorized else { notificationFailed = true; continue }
                        do { try await notify(post) } catch { notificationFailed = true; continue }
                    }
                    seen.insert(post.id)
                }
            } else {
                // Baseline prevents historical posts from producing an alert storm.
                seen.formUnion(fresh.map(\.id))
                initialized = true
                defaults.set(true,forKey:"initialized")
            }
            defaults.set(Array(seen),forKey:"seen")
            try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(fresh).write(to:cache, options:.atomic)
            checked = Date()
            message = notificationFailed ? "有新消息待通知，请检查通知权限" : "检查成功 · 每 60 秒检查"
        } catch { message = "检查失败：\(error.localizedDescription)" }
        await refreshPermission()
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            login = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许" : ""
        } catch { loginMessage = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
    }
}

struct Panel: View {
    @ObservedObject var model: Monitor
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                VStack(alignment:.leading,spacing:3) {
                    Text("Tibo Watch").font(.title2.weight(.semibold))
                    Link("@thsottiaux · Codex", destination:URL(string:"https://x.com/thsottiaux")!).font(.subheadline)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            VStack(alignment:.leading,spacing:5) {
                Label(model.paused ? "监控已暂停" : model.message, systemImage:model.paused ? "pause.circle" : "arrow.clockwise.circle")
                if let checked = model.checked { Text("最近检查 \(checked.formatted(date:.omitted,time:.standard))").font(.caption).foregroundStyle(.secondary) }
                Text("通知：\(model.permission)").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack { Text("重置与重置卡").font(.headline); Spacer(); Button("检查") { Task { await model.check() } }.disabled(model.busy || model.paused) }
            if model.posts.isEmpty {
                Text("正在连接公开消息源。首次读取只建立基线，之后的新消息才会提醒。").foregroundStyle(.secondary).padding(.vertical,12)
            } else {
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:16) {
                        ForEach(model.posts.filter(\.relevant).prefix(30)) { post in
                            VStack(alignment:.leading,spacing:5) {
                                HStack { Text(post.kind).font(.caption.weight(.semibold)); Spacer(); Text(post.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                                Link(post.title,destination:post.url).font(.system(size:13,weight:.medium)).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
                                if let text = post.body.components(separatedBy:"Source text: ").last, post.body.contains("Source text:") {
                                    Text(text.components(separatedBy:"\n\nSource:")[0]).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                                }
                            }
                        }
                    }.padding(.trailing,5)
                }.frame(height:250)
            }
            Divider()
            VStack(alignment:.leading,spacing:4) {
                Text("来源：ModelYard 公开 RSS（第三方）").font(.caption)
                if let latest = model.posts.first {
                    Text("源内最新：\(latest.date.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                    if Date().timeIntervalSince(latest.date) > 86400 {
                        Text("超过 24 小时无新条目，可能无新帖，也可能来源滞后。请核对 X。").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("包含计划与完成消息；不代表你的账户额度已到账。休眠期间停止检查，唤醒后补查。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("测试通知") { Task { await model.test() } }
                Button(model.paused ? "继续" : "暂停") { model.paused.toggle(); if !model.paused { Task { await model.check() } } }
                Spacer()
                Menu {
                    Toggle("中文播报（使用媒体音量）",isOn:$model.voiceEnabled)
                    Toggle("登录时启动",isOn:Binding(get:{model.login},set:{model.setLogin($0)}))
                    Button("系统通知设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                    Link("查看消息源",destination:URL(string:"https://tibo.modelyard.dev/")!)
                    Button("退出 Tibo Watch") { NSApp.terminate(nil) }
                } label: { Image(systemName:"gearshape") }.menuStyle(.borderlessButton).frame(width:28)
            }
            if !model.audioMessage.isEmpty { Text(model.audioMessage).font(.caption).foregroundStyle(.red) }
            if !model.loginMessage.isEmpty { Text(model.loginMessage).font(.caption).foregroundStyle(.secondary) }
        }.padding(20).frame(width:390).preferredColorScheme(.light)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    let model = Monitor()
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource:"tibo-avatar",withExtension:"jpg"), let avatar = NSImage(contentsOf:url) {
            let icon = NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
                NSBezierPath(ovalIn:rect).addClip()
                avatar.draw(in:rect)
                return true
            }
            icon.isTemplate = false
            item.button?.image = icon
        } else {
            item.button?.image = NSImage(systemSymbolName:"bell.badge", accessibilityDescription:"Tibo 重置提醒")
        }
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.toolTip = "Tibo Watch · 重置与重置卡提醒"
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:Panel(model:model))
        model.start()
        Task {
            if CommandLine.arguments.contains("--test-notification") { await model.test() }
            else { await model.allow() }
        }
        toggle()
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button { popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY); NSApp.activate(ignoringOtherApps:true) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner,.sound,.list] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["url"] as? String, let url = URL(string:raw), url.host == "x.com", url.path.hasPrefix("/thsottiaux") else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}

if CommandLine.arguments.contains("--check-notification-copy") {
    for category in ["Reset Planned", "Reset Completed", "Banked Reset", "Reset Discussion", "Reset Planned Completed"] {
        let post = Post(id:"check",title:category == "Banked Reset" ? "banked" : "update",body:"",category:category,date:Date(),url:URL(string:"https://x.com/thsottiaux")!)
        if category.contains("Planned") { precondition(!post.isConfirmedCompletion && post.notificationBody.contains("尚未确认完成")) }
        if category == "Reset Completed" { precondition(post.isConfirmedCompletion && post.notificationBody.contains("确认是否到账")) }
        print("\(post.kind)：\(post.notificationBody)")
    }
} else if CommandLine.arguments.contains("--check-feed") {
    let data = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments.last!))
    let posts = try FeedParser.parse(data)
    precondition(posts.count > 0)
    precondition(posts.allSatisfy { $0.url.host == "x.com" && $0.url.path.hasPrefix("/thsottiaux/status/") })
    print("Parsed \(posts.count) posts; \(posts.filter(\.relevant).count) reset events; latest \(posts[0].date)")
} else {
    MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    }
}
