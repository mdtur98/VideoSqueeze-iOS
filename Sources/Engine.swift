import SwiftUI
import Photos
import BackgroundTasks

/// يدير الطابور: بحث ← ضغط ← حفظ ← (حذف الأصول بتأكيد واحد في الواجهة)
@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()
    nonisolated static let taskId = "com.squeeze.video.ios.compress"

    @Published var authorized = Library.authorized()
    @Published var candidates: [VideoItem] = []
    @Published var running = false
    @Published var currentName = ""
    @Published var currentSize: Int64 = 0
    @Published var progress: Double = 0
    @Published var doneInRun = 0
    @Published var totalInRun = 0
    @Published var history: [Rec] = Store.shared.history
    @Published var message: String?
    private let cancelFlag = Flag()
    private var cancel: Bool { get { cancelFlag.value } set { cancelFlag.value = newValue } }
    private var startedAt = Date()

    var pendingDelete: [Rec] { history.filter { !$0.originalDeleted } }
    var savedTotal: Int64 { history.reduce(0) { $0 + $1.saved } }
    var eta: String? {
        guard progress > 0.03 else { return nil }
        let el = Date().timeIntervalSince(startedAt)
        return Fmt.duration(el * (1 - progress) / progress)
    }

    func refresh() {
        authorized = Library.authorized()
        history = Store.shared.history
        guard authorized else { return }
        Task.detached(priority: .utility) {
            let c = Library.candidates()
            await MainActor.run { self.candidates = c }
        }
    }

    func requestAccess() async {
        authorized = await Library.requestAccess()
        refresh()
    }

    func stop() { cancel = true }

    /// يضغط كل المرشّحين؛ [deadline] للمهمّة الخلفية
    func compressAll(interactive: Bool, deadline: Date? = nil) async {
        guard !running, authorized else { return }
        let items = Library.candidates()
        guard !items.isEmpty else { refresh(); return }
        running = true; cancel = false; doneInRun = 0; totalInRun = items.count
        if interactive { UIApplication.shared.isIdleTimerDisabled = true }
        let st = Store.shared
        for item in items {
            if cancel { break }
            if let deadline, Date() > deadline { break }
            currentName = item.name; currentSize = item.size; progress = 0; startedAt = Date()
            do {
                let av = try await Library.avAsset(item.asset)
                let flag = cancelFlag
                let url = try await Compressor.compress(av, quality: st.quality, isCancelled: { flag.value }) { p in
                    Task { @MainActor in Engine.shared.progress = p }
                }
                let newSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                if newSize == 0 || Double(newSize) > Double(item.size) * 0.9 {
                    try? FileManager.default.removeItem(at: url)
                    st.skipped.insert(item.id)
                } else {
                    let newId = try await Library.save(url, like: item.asset, name: item.name)
                    st.add(Rec(date: Date(), name: item.name, before: item.size, after: newSize,
                               tookMs: Int64(Date().timeIntervalSince(startedAt) * 1000),
                               origId: item.id, newId: newId, originalDeleted: false))
                    history = st.history
                }
            } catch CompressError.cancelled {
                break
            } catch {
                st.skipped.insert(item.id)
                message = "تعذّر ضغط \(item.name): \(error.localizedDescription)"
            }
            doneInRun += 1
        }
        running = false; currentName = ""
        UIApplication.shared.isIdleTimerDisabled = false
        refresh()
        if interactive && !pendingDelete.isEmpty { await deleteOriginals() }
    }

    /// نافذة تأكيد واحدة من iOS لحذف كل الأصول المضغوطة
    func deleteOriginals() async {
        let pend = pendingDelete
        guard !pend.isEmpty else { return }
        do {
            try await Library.delete(pend.map(\.origId))
            let ids = Set(pend.map(\.origId))
            var h = Store.shared.history
            for i in h.indices where ids.contains(h[i].origId) { h[i].originalDeleted = true }
            Store.shared.history = h
            history = h
            message = "حُذفت الأصول — تبقى 30 يوماً في «المحذوفة مؤخراً». أفرغها لتتحرّر المساحة فوراً."
        } catch {
            message = "لم تُحذف الأصول بعد. يمكنك حذفها لاحقاً من الرئيسية."
        }
    }

    // ── المهمّة الخلفية: iOS يشغّلها متى شاء (غالباً ليلاً أثناء الشحن) ──
    nonisolated static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let t = task as? BGProcessingTask else { return }
            schedule()
            let work = Task { @MainActor in
                await Engine.shared.compressAll(interactive: false, deadline: Date().addingTimeInterval(25 * 60))
                t.setTaskCompleted(success: true)
            }
            t.expirationHandler = { Task { @MainActor in Engine.shared.stop() }; work.cancel() }
        }
    }

    nonisolated static func schedule() {
        guard Store.shared.background else { BGTaskScheduler.shared.cancelAllTaskRequests(); return }
        let r = BGProcessingTaskRequest(identifier: taskId)
        r.requiresExternalPower = true
        r.requiresNetworkConnectivity = false
        r.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

/// علم إلغاء آمن بين الخيوط
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}

enum Fmt {
    static func parts(_ b: Int64) -> (String, String) {
        let gb = Double(b) / 1_073_741_824, mb = Double(b) / 1_048_576
        if gb >= 100 { return (String(format: "%.0f", gb), "GB") }
        if gb >= 1 { return (trim(String(format: "%.2f", gb)), "GB") }
        if mb >= 10 { return (String(format: "%.0f", mb), "MB") }
        return (trim(String(format: "%.1f", mb)), "MB")
    }
    private static func trim(_ s: String) -> String {
        var t = s; while t.contains(".") && (t.hasSuffix("0") || t.hasSuffix(".")) { t.removeLast() }; return t
    }
    /// معزول بـ LRI حتى لا ينقلب داخل جملة عربية
    static func size(_ b: Int64) -> String { let p = parts(b); return "\u{2066}\(p.0) \(p.1)\u{2069}" }
    static func duration(_ s: TimeInterval) -> String {
        let s = Int(s)
        if s < 60 { return "\(s) ث" }
        if s < 3600 { return "\(s / 60) د \(s % 60) ث" }
        return "\(s / 3600) س \((s % 3600) / 60) د"
    }
    static let ar = Locale(identifier: "ar@numbers=latn")
    static func day(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d) { return "اليوم" }
        if c.isDateInYesterday(d) { return "أمس" }
        let f = DateFormatter(); f.locale = ar; f.dateFormat = c.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEEE d MMMM" : "d MMMM yyyy"
        return f.string(from: d)
    }
    static func clock(_ d: Date) -> String { let f = DateFormatter(); f.locale = ar; f.dateFormat = "h:mm a"; return f.string(from: d) }
}
