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
    var source: String? = nil
    var relevant: Bool {
        let text = (title + " " + category).lowercased()
        return text.contains("reset") || text.contains("credit") || text.contains("额度") || text.contains("重置")
    }
    var announcementTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"zh_CN")
        formatter.timeZone = TimeZone(identifier:"Asia/Shanghai")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from:date)
    }
    var isPlanned: Bool { category.lowercased().contains("planned") }
    var announcementSoundName: String? {
        if isPlanned { return "reset-planned" }
        return isConfirmedCompletion ? "reset-confirmed" : nil
    }
    var estimatedResetDate: Date? {
        let source = body.components(separatedBy:"Source text:").last?.components(separatedBy:"\n\nSource:").first ?? ""
        let pattern = "(?i)\\bwithin\\s+(?:the\\s+next\\s+)?([0-9]{1,2})\\s+hours?\\b"
        let regex = try! NSRegularExpression(pattern:pattern)
        if let match = regex.firstMatch(in:source,range:NSRange(source.startIndex...,in:source)),
           let r = Range(match.range(at:1),in:source), let hours = Int(source[r]), hours > 0, hours <= 48 {
            return date.addingTimeInterval(Double(hours)*3600)
        }
        return nil
    }
    var timeSpeechKeys: [String] {
        guard let expected = estimatedResetDate else { return ["intro","unknown","end"] }
        var calendar = Calendar(identifier:.gregorian)
        calendar.timeZone = TimeZone(identifier:"Asia/Shanghai")!
        let c = calendar.dateComponents([.month,.day,.hour,.minute],from:expected)
        return ["intro","beijing",String(c.month!),"month",String(c.day!),"day",String(c.hour!),"hour",String(c.minute!),"minute","before","end"]
    }
    var expectedTimeText: String {
        let source = body.components(separatedBy:"Source text:").last?.components(separatedBy:"\n\nSource:").first ?? ""
        if let expected = estimatedResetDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier:"zh_CN")
            formatter.timeZone = TimeZone(identifier:"Asia/Shanghai")
            formatter.dateFormat = "M月d日 HH:mm"
            return "原帖预计在北京时间 \(formatter.string(from:expected)) 前重置；这是预估窗口。"
        }
        let lower = source.lowercased()
        if lower.contains("eod") || lower.contains("end of day") {
            let zone = lower.contains("pst") ? "（原帖时区标为 PST）" : "（原帖未明确时区）"
            return "原帖预计在发布当天结束前重置\(zone)，未给出精确时刻。"
        }
        return "原帖未给出可精确换算的预计时刻，请点击查看时间安排。"
    }
    var isConfirmedCompletion: Bool {
        let c = category.lowercased()
        return c.contains("completed") && !c.contains("planned")
    }
    var notificationBody: String {
        let c = category.lowercased()
        if c.contains("planned") {
            return "Tibo 预告将重置 Codex 额度，目前尚未确认完成。\n" + expectedTimeText
        }
        if isConfirmedCompletion {
            return "Tibo 已宣布 Codex 额度重置完成。请查看你的账户确认是否到账，点击可查看原帖。\n公告发布时间（北京时间）："+announcementTime
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

enum BackupParser {
    static func matches(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern:pattern,options:[.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap {
            guard let range = Range($0.range(at:1),in:text) else { return nil }
            return String(text[range])
        }
    }
    static func plain(_ text: String) -> String {
        var value = text.replacingOccurrences(of:"<[^>]+>",with:" ",options:.regularExpression)
        for (entity,replacement) in [("&amp;","&"),("&#39;","'"),("&apos;","'"),("&quot;","\""),("&lt;","<"),("&gt;",">"),("&nbsp;"," ")] {
            value = value.replacingOccurrences(of:entity,with:replacement)
        }
        return value.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func parse(_ data: Data) throws -> [Post] {
        guard let html = String(data:data,encoding:.utf8) else { throw NSError(domain:"BackupFeed",code:1) }
        var posts: [Post] = []
        for article in matches("(<article[^>]*class=\"cx-post\"[^>]*>.*?</article>)",html) {
            guard let tag = matches("(<article[^>]*>)",article).first,
                  let type = matches("data-type=\"([^\"]+)\"",tag).first,
                  ["regular","both","banked"].contains(type),
                  let rawDate = matches("<time[^>]*datetime=\"([^\"]+)\"",article).first,
                  let quote = matches("<blockquote[^>]*>(.*?)</blockquote>",article).first,
                  let rawURL = matches("cite=\"(https://x[.]com/thsottiaux/status/[0-9]+)\"",article).first,
                  let url = URL(string:rawURL) else { continue }
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            guard let date = formatter.date(from:rawDate) ?? ISO8601DateFormatter().date(from:rawDate) else { continue }
            let planned = tag.contains("data-status=\"announced\"")
            let category = planned ? "Reset Planned" : type == "banked" ? "Banked Reset" : "Reset Completed"
            posts.append(Post(id:rawURL,title:planned ? "Tibo 发布重置预告" : type == "banked" ? "Tibo 发布重置卡消息" : "Tibo 宣布重置完成",body:"Source text: "+plain(quote)+"\n\nSource: "+rawURL,category:category,date:date,url:url,source:"OpenTheRank"))
        }
        guard !posts.isEmpty else { throw NSError(domain:"BackupFeed",code:2,userInfo:[NSLocalizedDescriptionKey:"备用来源结构变化或无有效公告"]) }
        return posts.sorted { $0.date > $1.date }
    }
}

struct TimeSpeechBank: Decodable {
    let sampleRate: Int
    let clips: [String:Data]
    static func render(_ post: Post) throws -> URL {
        guard let url = Bundle.main.url(forResource:"timebank",withExtension:"json") else {
            throw NSError(domain:"Speech",code:1,userInfo:[NSLocalizedDescriptionKey:"预计时间语音库缺失"])
        }
        let bank = try JSONDecoder().decode(TimeSpeechBank.self,from:Data(contentsOf:url))
        guard bank.sampleRate == 44100 else { throw NSError(domain:"Speech",code:2) }
        var pcm = Data()
        for key in post.timeSpeechKeys {
            guard let clip = bank.clips[key], !clip.isEmpty, clip.count % 2 == 0 else {
                throw NSError(domain:"Speech",code:3,userInfo:[NSLocalizedDescriptionKey:"时间语音片段缺失："+key])
            }
            pcm.append(clip)
            pcm.append(Data(repeating:0,count:["intro","before","unknown"].contains(key) ? 17640 : 1764))
        }
        guard pcm.count < 8_820_000 else { throw NSError(domain:"Speech",code:4) }
        var wave = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of:&little) { wave.append(contentsOf:$0) } }
        number(UInt32(36+pcm.count)); wave.append(Data("WAVEfmt ".utf8))
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(bank.sampleRate)); number(UInt32(bank.sampleRate*2)); number(UInt16(2)); number(UInt16(16))
        wave.append(Data("data".utf8)); number(UInt32(pcm.count)); wave.append(pcm)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("tibo-plan-"+UUID().uuidString+".wav")
        try wave.write(to:target,options:.atomic)
        return target
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
    private var voiceAssetName: String?
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
        let spoken = post.announcementSoundName != nil && voiceEnabled
        content.sound = spoken ? nil : .default
        content.userInfo = ["url":post.url.absoluteString]
        let center = UNUserNotificationCenter.current()
        try await center.add(UNNotificationRequest(identifier:post.id,content:content,trigger:nil))
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { reminders.show(post) }
        if spoken, settings.authorizationStatus == .authorized, settings.soundSetting == .enabled {
            // Use the media output path tested on this Mac. Coalesce simultaneous
            // completion announcements so the same phrase cannot overlap itself.
            let soundKey = post.isPlanned ? post.id : post.announcementSoundName
            if let process = voiceProcess, process.isRunning {
                if voiceAssetName == soundKey { return }
                process.terminate()
            }
            guard let name = post.announcementSoundName, let url = Bundle.main.url(forResource:name,withExtension:"caf") else {
                audioMessage = "中文播报文件缺失"
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/afplay")
            do {
                let playbackURL = post.isPlanned ? try TimeSpeechBank.render(post) : url
                process.arguments = [playbackURL.path]
                if post.isPlanned {
                    process.terminationHandler = { _ in try? FileManager.default.removeItem(at:playbackURL) }
                }
                do { try process.run() }
                catch { if post.isPlanned { try? FileManager.default.removeItem(at:playbackURL) }; throw error }
                voiceProcess = process
                voiceAssetName = soundKey
                audioMessage = ""
            } catch { audioMessage = "中文播报失败：\(error.localizedDescription)" }
        }
    }
    func test(planned: Bool = false) async {
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
            "kind": planned ? "planned" : "completed",
            "identifier": identifier
        ]
        do {
            try await notify(Post(id:identifier, title:"这是一条 Tibo Watch 测试通知，点击可打开 Tibo 主页。",body:planned ? "Source text: Landing within the next 2 hours" : "",category:planned ? "Reset Planned" : "Reset Completed",date:Date(),url:URL(string:"https://x.com/thsottiaux")!))
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
            async let primaryResult = fetchSource("https://tibo.modelyard.dev/feed.xml",parser:FeedParser.parse)
            async let backupResult = fetchSource("https://opentherank.com/codex-reset/",parser:BackupParser.parse)
            let (primary,backup) = await (primaryResult,backupResult)
            var merged: [String:Post] = [:]
            var warnings: [String] = []
            switch primary {
            case .success(let items): for var post in items { post.source = "ModelYard"; merged[post.id] = post }
            case .failure: warnings.append("主源失败")
            }
            var supplementary = 0
            switch backup {
            case .success(let items):
                for post in items where merged[post.id] == nil { merged[post.id] = post; supplementary += 1 }
            case .failure: warnings.append("备用源失败")
            }
            guard !merged.isEmpty else { throw NSError(domain:"Sources",code:1,userInfo:[NSLocalizedDescriptionKey:"两个消息源均不可用"]) }
            let fresh = merged.values.sorted { $0.date > $1.date }
            posts = fresh
            var notificationFailed = false
            if initialized {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                for post in fresh.reversed() where !seen.contains(post.id) {
                    // Backfill recent missing announcements, without alerting years of
                    // history when the secondary source is first enabled.
                    if post.source == "OpenTheRank", post.date.timeIntervalSinceNow < -48*3600 {
                        seen.insert(post.id); continue
                    }
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
            message = notificationFailed ? "有新消息待通知，请检查通知权限" : warnings.isEmpty ? "双源检查成功 · 每 60 秒检查" : warnings.joined(separator:"、")+" · 当前为单源检查"
            let audit: [String:Any] = ["checkedAt":ISO8601DateFormatter().string(from:Date()),"warnings":warnings,"supplementaryPosts":supplementary,"posts":fresh.count]
            try JSONSerialization.data(withJSONObject:audit,options:.prettyPrinted).write(to:cache.deletingLastPathComponent().appendingPathComponent("source-check.json"),options:.atomic)
        } catch { message = "检查失败：\(error.localizedDescription)" }
        await refreshPermission()
    }
    private func fetchSource(_ address: String, parser: (Data) throws -> [Post]) async -> Result<[Post],Error> {
        do {
            let request = URLRequest(url:URL(string:address)!,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:25)
            let (data,response) = try await URLSession.shared.data(for:request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain:"HTTP",code:1) }
            return .success(try parser(data))
        } catch { return .failure(error) }
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
                                Text("来源："+(post.source ?? "ModelYard")).font(.caption2).foregroundStyle(.secondary)
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
                Text("来源：ModelYard＋OpenTheRank（第三方交叉检查）").font(.caption)
                if let latest = model.posts.first {
                    Text("源内最新：\(latest.date.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
                    if Date().timeIntervalSince(latest.date) > 86400 {
                        Text("超过 24 小时无新条目，可能无新帖，也可能来源滞后。请核对 X。").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("包含计划与完成消息；不代表你的账户额度已到账。休眠期间停止检查，唤醒后补查。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Menu("测试提醒") {
                    Button("预计重置（计划）") { Task { await model.test(planned:true) } }
                    Button("已宣布完成") { Task { await model.test() } }
                }.fixedSize()
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
            if CommandLine.arguments.contains("--test-planned-notification") { await model.test(planned:true) }
            else if CommandLine.arguments.contains("--test-notification") { await model.test() }
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
        if category.contains("Planned") { precondition(!post.isConfirmedCompletion && post.notificationBody.contains("尚未确认完成") && post.announcementSoundName == "reset-planned") }
        if category == "Reset Completed" { precondition(post.isConfirmedCompletion && post.notificationBody.contains("确认是否到账")) }
        print("\(post.kind)：\(post.notificationBody)")
    }
    let referenceDate = Date(timeIntervalSince1970:0)
    let relative = Post(id:"check",title:"plan",body:"Source text: Landing within the next 2 hours",category:"Reset Planned",date:referenceDate,url:URL(string:"https://x.com/thsottiaux")!)
    precondition(relative.expectedTimeText.contains("1月1日 10:00"))
    precondition(relative.timeSpeechKeys == ["intro","beijing","1","month","1","day","10","hour","0","minute","before","end"])
    let eod = Post(id:"check",title:"plan",body:"Source text: Landing sometime today by EOD PST",category:"Reset Planned",date:referenceDate,url:relative.url)
    precondition(eod.expectedTimeText.contains("PST") && !eod.expectedTimeText.contains("北京时间"))
    precondition(eod.timeSpeechKeys == ["intro","unknown","end"])
    print("预计时间转换与模糊时区边界检查通过")
} else if CommandLine.arguments.contains("--check-time-speech") {
    let date = ISO8601DateFormatter().date(from:"2026-10-19T21:45:00Z")!
    let post = Post(id:"check",title:"plan",body:"Source text: Landing within the next 2 hours",category:"Reset Planned",date:date,url:URL(string:"https://x.com/thsottiaux")!)
    precondition(post.expectedTimeText.contains("10月20日 07:45"))
    let file = try TimeSpeechBank.render(post)
    try Data(contentsOf:file).write(to:URL(fileURLWithPath:CommandLine.arguments.last!),options:.atomic)
    try FileManager.default.removeItem(at:file)
    print(post.expectedTimeText)
    print("同一时间结果的语音片段："+post.timeSpeechKeys.joined(separator:","))
} else if CommandLine.arguments.contains("--check-backup") {
    let posts = try BackupParser.parse(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments.last!)))
    precondition(posts.contains { $0.id == "https://x.com/thsottiaux/status/2112432076767289678" && $0.isConfirmedCompletion })
    precondition(posts.contains { $0.isPlanned && !$0.isConfirmedCompletion })
    print("备用源解析通过，\(posts.count) 条，最新：\(posts[0].date)；计划/完成区分通过")
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
