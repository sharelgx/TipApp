import Foundation

// Chromium Native Messaging: this executable only receives public post snapshots
// from the extension ID allowed by the browser's native-host registration.
struct IncomingPost: Codable { let url: String; let date: String; let text: String; let quote: String; let truncated: Bool }
struct Snapshot: Codable { let version: Int; let pageURL: String; let capturedAt: String; let pageLoadedAt: String; let status: String; let posts: [IncomingPost]; let changed: Bool? }
func readExact(_ count: Int) -> Data? {
    var result=Data()
    while result.count<count {
        let data=FileHandle.standardInput.readData(ofLength:count-result.count)
        if data.isEmpty{return nil};result.append(data)
    }
    return result
}
func send(_ object: [String:Any]) {
    guard let data=try? JSONSerialization.data(withJSONObject:object),data.count<1_000_000 else{return}
    var size=UInt32(data.count).littleEndian
    withUnsafeBytes(of:&size){FileHandle.standardOutput.write(Data($0))}
    FileHandle.standardOutput.write(data)
}
let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
while let header=readExact(4) {
    let size=header.enumerated().reduce(0){$0 | (Int($1.element)<<($1.offset*8))}
    guard size>0,size<=2_000_000,let data=readExact(size) else{break}
    do {
        let snapshot=try JSONDecoder().decode(Snapshot.self,from:data)
        guard snapshot.version==1,let page=URL(string:snapshot.pageURL),page.scheme=="https",page.host=="x.com",
              ["/thsottiaux","/thsottiaux/with_replies"].contains(page.path),page.query==nil,
              ["ok","unavailable","needs_login"].contains(snapshot.status),snapshot.posts.count<=100,
              let captured=formatter.date(from:snapshot.capturedAt),abs(captured.timeIntervalSinceNow)<120,
              let loaded=formatter.date(from:snapshot.pageLoadedAt),loaded<=captured else{throw NSError(domain:"Bridge",code:1)}
        for post in snapshot.posts {
            guard let url=URL(string:post.url),url.scheme=="https",url.host=="x.com",url.query==nil,
                  post.url.range(of:"^https://x[.]com/thsottiaux/status/[0-9]+$",options:.regularExpression) != nil,
                  formatter.date(from:post.date) != nil,post.text.utf8.count<=48000,post.quote.utf8.count<=48000 else{throw NSError(domain:"Bridge",code:2)}
        }
        let root=ProcessInfo.processInfo.environment["TIBO_BRIDGE_TEST_ROOT"].map { URL(fileURLWithPath:$0) } ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TiboWatch")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let target=root.appendingPathComponent(page.path.hasSuffix("with_replies") ? "x-direct-replies.json":"x-direct-posts.json")
        try data.write(to:target,options:.atomic)
        if snapshot.changed==true { DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.tibowatch.x.changed"),object:nil,userInfo:nil,deliverImmediately:true) }
        send(["ok":true,"captured":snapshot.posts.count])
    }catch{send(["ok":false,"error":"Invalid public-post snapshot"])}
}
