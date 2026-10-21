import Foundation

struct DirectPost: Codable {
    let url: String
    let date: String
    let text: String
    let quote: String
    let truncated: Bool
}
struct DirectSnapshot: Codable {
    let version: Int
    let pageURL: String
    let capturedAt: String
    let pageLoadedAt: String
    let status: String
    let posts: [DirectPost]
}
enum ForecastEngine {
    static func contains(_ expression: String,_ value: String) -> Bool { value.range(of:expression,options:[.regularExpression,.caseInsensitive]) != nil }
    static func campaignDay(_ post: Post) -> String? {
        let text=post.body.components(separatedBy:"Source text:").last ?? post.title
        guard let regex=try? NSRegularExpression(pattern:"(?i)day\\s*([0-9]+)\\s*/"),let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(match.range(at:1),in:text) else{return nil}
        return String(text[range])
    }
    static func resolved(_ post: Post, in posts:[Post]) -> Bool {
        guard post.isPrediction || post.isPlanned,let day=campaignDay(post) else{return false}
        return posts.contains { $0.isConfirmedCompletion && $0.date>post.date && campaignDay($0)==day }
    }
    static func classify(_ raw: DirectPost) -> Post? {
        guard let url=URL(string:raw.url),url.host=="x.com",raw.url.range(of:"^https://x[.]com/thsottiaux/status/[0-9]+$",options:.regularExpression) != nil,
              let date=DirectX.date(raw.date) else{return nil}
        let text=raw.text.lowercased()
        let mentionsReset=contains("\\breset(s)?\\b",text)
        let future=contains("\\b(will|going to|planning|plan to|expect|landing|coming|soon|within|by eod)\\b",text)
        let joke=contains("(we[’']?re|we are) (still )?(cooked|cooking)",text) && contains("day\\s*[0-9]+\\s*/",text)
        let button=mentionsReset && text.contains("button")
        var category="Codex Update",reason:String?,confidence:String?
        let denied=contains("no reset|not (?:going to |planning to |gonna )?reset|won[’']t reset|will not reset",text)
        let conditional=contains("(?:ship|improvement).{0,120}\\bor\\b.{0,60}\\breset\\b",text)
        if denied { category="Codex Update" }
        else if raw.truncated {
            if mentionsReset || joke {category="Reset Prediction";reason="原帖正文仍有折叠，当前信息不完整，只能作为待核实线索，不能认定有重置承诺或时间。";confidence="低"}
        } else if mentionsReset && conditional {
            category="Reset Prediction";confidence="低";reason="这是交付或重置的条件性承诺，尚未确认条件成立，不能当作确定的重置安排。"
        } else if mentionsReset && future {
            category="Reset Planned"
        } else if mentionsReset && contains("and reset|reset.{0,35}(done|complete|processed|propagated)|(?:have|has|just|we[’']ve|i[’']ve) reset|reset[.!]?(?: enjoy)?[.!]?$",text) {
            category="Reset Completed"
        } else if joke {
            category="Reset Prediction";confidence="低"
            reason="Day 活动上下文里使用 cooked/cooking 双关，可能暗示交付受阻后重置；但引用产品发布内容，也可能只是宣传玩笑。没有明确重置承诺，不能推出具体时间。"
        } else if button {
            category="Reset Prediction";confidence="低"
            reason="提到重置按钮，但可能是在玩梗；没有可核实的明确预告，不能据此推定将重置或具体时间。"
        } else if mentionsReset && contains("banked|reset card",text) {
            category="Banked Reset"
        }
        return Post(id:raw.url,title:raw.text,body:"Source text: "+raw.text+"\n\nSource: "+raw.url,category:category,date:date,url:url,source:"X Direct",predictionReason:reason,predictionConfidence:confidence,quotedText:raw.quote,bodyTruncated:raw.truncated)
    }
}
enum DirectX {
    static func date(_ value: String) -> Date? {
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return formatter.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
    static func load(root: URL,now: Date=Date()) -> (posts:[Post],status:String,healthy:Bool) {
        var posts:[String:Post]=[:],issues:[String]=[],good=0
        for (file,label) in [("x-direct-posts.json","主页"),("x-direct-replies.json","回复页")] {
            guard let data=try? Data(contentsOf:root.appendingPathComponent(file)),let snapshot=try? JSONDecoder().decode(DirectSnapshot.self,from:data) else{issues.append(label+"未连接");continue}
            guard snapshot.status=="ok",let captured=date(snapshot.capturedAt),let loaded=date(snapshot.pageLoadedAt),now.timeIntervalSince(captured)<180,now.timeIntervalSince(captured) > -120,now.timeIntervalSince(loaded)<240 else{
                issues.append(label+(snapshot.status=="needs_login" ? "需登录" : "不可用或已过期"));continue
            }
            good += 1
            for raw in snapshot.posts {if let post=ForecastEngine.classify(raw){posts[post.id]=post}}
        }
        return (posts.values.sorted{$0.date>$1.date},good==2 ? "X 直连正常（主页＋回复）" : "X 直连降级："+issues.joined(separator:"、"),good==2)
    }
}
