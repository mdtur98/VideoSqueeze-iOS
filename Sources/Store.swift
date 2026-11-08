import Foundation

/// الإعدادات + السجلّ (مصدر الإحصائيات)
struct Rec: Codable, Identifiable, Hashable {
    var id: String { newId }
    let date: Date
    let name: String
    let before: Int64
    let after: Int64
    let tookMs: Int64
    let origId: String
    let newId: String
    var originalDeleted: Bool
    var saved: Int64 { before - after }
    var pct: Int { before > 0 ? Int(saved * 100 / before) : 0 }
}

final class Store {
    static let shared = Store()
    private let d = UserDefaults.standard

    var thresholdMb: Int { get { d.object(forKey: "threshold") as? Int ?? 100 } set { d.set(newValue, forKey: "threshold") } }
    var quality: Int { get { d.object(forKey: "quality") as? Int ?? 1 } set { d.set(newValue, forKey: "quality") } }
    var background: Bool { get { d.object(forKey: "bg") as? Bool ?? true } set { d.set(newValue, forKey: "bg") } }

    /// معرّفات الفيديوهات الناتجة (لا تُضغط مرّة أخرى) والمتخطّاة
    var done: Set<String> { get { Set(d.stringArray(forKey: "done") ?? []) } set { d.set(Array(newValue), forKey: "done") } }
    var skipped: Set<String> { get { Set(d.stringArray(forKey: "skipped") ?? []) } set { d.set(Array(newValue), forKey: "skipped") } }

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
    var history: [Rec] {
        get { (try? JSONDecoder().decode([Rec].self, from: Data(contentsOf: url))) ?? [] }
        set { try? JSONEncoder().encode(newValue).write(to: url, options: .atomic) }
    }
    func add(_ r: Rec) { var h = history; h.insert(r, at: 0); history = h; done.insert(r.newId) }
}
