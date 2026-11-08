import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var e: Engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if !e.authorized { accessCard }
                    hero
                    if e.running { jobCard }
                    else if !e.candidates.isEmpty { candidatesCard }
                    if !e.pendingDelete.isEmpty && !e.running { deleteCard }
                    tiles
                    chart
                    recent
                    Text("كل المعالجة على هاتفك — لا يُرفع أيّ ملف إلى الإنترنت.")
                        .font(Theme.font(12)).foregroundStyle(.tertiary).padding(.top, 8)
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { e.refresh() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ضاغط الفيديو").font(Theme.font(26, .bold))
                Text("فيديوهات أخفّ، بنفس الجودة والاسم والتاريخ").font(Theme.font(13.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if e.running { Pill(text: "يضغط الآن", dot: true) }
            else if !e.authorized { Pill(text: "يحتاج إذناً", fg: .orange, bg: .orange.opacity(0.14), dot: true) }
            else { Pill(text: "جاهز", dot: true) }
        }
        .padding(.top, 8).padding(.bottom, 6)
    }

    private var accessCard: some View {
        Card {
            Label("اسمح بالوصول إلى الصور", systemImage: "photo.on.rectangle").font(Theme.font(16, .semibold))
            Text("ليجد الفيديوهات الكبيرة ويحفظ نسخها المضغوطة. اختر «السماح بالوصول الكامل».")
                .font(Theme.font(13)).foregroundStyle(.secondary).padding(.vertical, 10)
            Button { Task { await e.requestAccess() } } label: {
                Text("السماح").font(Theme.font(15, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var hero: some View {
        let before = e.history.reduce(Int64(0)) { $0 + $1.before }
        let after = e.history.reduce(Int64(0)) { $0 + $1.after }
        let pct = before > 0 ? Double(before - after) / Double(before) : 0
        let p = Fmt.parts(e.savedTotal)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("المساحة التي وفّرتها").font(Theme.font(13.5, .medium)).foregroundStyle(.white.opacity(0.68))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(p.0).font(Theme.font(46, .bold)).contentTransition(.numericText())
                        Text(p.1).font(Theme.font(18, .semibold)).foregroundStyle(.white.opacity(0.68))
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    Text(e.history.isEmpty ? "ستظهر هنا النتيجة بعد أوّل فيديو" : "من \(e.history.count) فيديو مضغوط")
                        .font(Theme.font(13)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 9)
                    Circle().trim(from: 0, to: pct).stroke(Theme.bright, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90)).scaleEffect(x: -1)
                    VStack(spacing: 2) {
                        Text("\(Int(pct * 100))%").font(Theme.font(22, .bold))
                        Text("أصغر").font(Theme.font(11, .medium)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: 92, height: 92)
                .animation(.easeOut(duration: 0.9), value: pct)
            }
            if before > 0 {
                bar("الحجم الأصلي", before, 1, .white.opacity(0.35)).padding(.top, 20)
                bar("بعد الضغط", after, Double(after) / Double(before), Theme.bright).padding(.top, 12)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.165, blue: 0.125), Color(red: 0.04, green: 0.09, blue: 0.07)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func bar(_ label: String, _ v: Int64, _ f: Double, _ c: Color) -> some View {
        VStack(spacing: 6) {
            HStack { Text(label).font(Theme.font(12.5, .medium)).foregroundStyle(.white.opacity(0.68)); Spacer(); Text(Fmt.size(v)).font(Theme.font(12.5, .semibold)) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(c).frame(width: max(8, g.size.width * f))
                }
            }.frame(height: 8)
        }
    }

    private var candidatesCard: some View {
        let total = e.candidates.reduce(Int64(0)) { $0 + $1.size }
        return Card {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(e.candidates.count) فيديو أكبر من \(Store.shared.thresholdMb) MB").font(Theme.font(16, .semibold))
                    Text("حجمها الحالي \(Fmt.size(total))").font(Theme.font(12.5)).foregroundStyle(.secondary)
                }
            }
            Button { Task { await e.compressAll(interactive: true) } } label: {
                Text("ضغط الكل").font(Theme.font(15, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.top, 14)
            Text("أبقِ التطبيق مفتوحاً أثناء الضغط. في النهاية يطلب iOS تأكيد حذف الأصول مرّة واحدة.")
                .font(Theme.font(12)).foregroundStyle(.tertiary).padding(.top, 8)
        }
    }

    private var jobCard: some View {
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("يضغط الآن · \(e.doneInRun + 1) من \(e.totalInRun)").font(Theme.font(12.5, .medium)).foregroundStyle(.secondary)
                    Text("\u{2066}\(e.currentName)\u{2069}").font(Theme.font(15, .medium)).lineLimit(1)
                }
                Spacer()
                Text("\(Int(e.progress * 100))%").font(Theme.font(22, .bold)).foregroundStyle(Theme.accent)
            }
            ProgressView(value: e.progress).tint(Theme.accent).padding(.top, 14)
            HStack {
                Text("الحجم الأصلي \(Fmt.size(e.currentSize))" + (e.eta.map { " · متبقٍّ تقريباً \($0)" } ?? ""))
                    .font(Theme.font(12.5)).foregroundStyle(.secondary)
                Spacer()
                Button("إيقاف") { e.stop() }.font(Theme.font(13, .semibold))
            }.padding(.top, 10)
        }
    }

    private var deleteCard: some View {
        let free = e.pendingDelete.reduce(Int64(0)) { $0 + $1.before }
        return Card {
            Label("حرّر \(Fmt.size(free))", systemImage: "trash").font(Theme.font(16, .semibold))
            Text("\(e.pendingDelete.count) فيديو أصليّ ما زال موجوداً بجانب نسخته المضغوطة. احذفها بتأكيد واحد — تبقى 30 يوماً في «المحذوفة مؤخراً» للتراجع.")
                .font(Theme.font(13)).foregroundStyle(.secondary).padding(.vertical, 10)
            Button(role: .destructive) { Task { await e.deleteOriginals() } } label: {
                Text("حذف الأصول").font(Theme.font(15, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.bordered).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var tiles: some View {
        let now = Date()
        let week = e.history.filter { now.timeIntervalSince($0.date) < 7 * 86400 }.reduce(Int64(0)) { $0 + $1.saved }
        let month = e.history.filter { now.timeIntervalSince($0.date) < 30 * 86400 }.reduce(Int64(0)) { $0 + $1.saved }
        let avg = e.history.isEmpty ? 0 : e.history.map(\.pct).reduce(0, +) / e.history.count
        let best = e.history.max { $0.saved < $1.saved }
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile("هذا الأسبوع", week > 0 ? Fmt.size(week) : "—", "آخر 7 أيام")
                tile("هذا الشهر", month > 0 ? Fmt.size(month) : "—", "آخر 30 يوماً")
            }
            HStack(spacing: 12) {
                tile("متوسط التصغير", e.history.isEmpty ? "—" : "\u{2066}\(avg)%\u{2069}", "لكل فيديو")
                tile("أكبر توفير", best.map { Fmt.size($0.saved) } ?? "—", best.map { "\u{2066}\($0.name)\u{2069}" } ?? "لا يوجد بعد")
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ hint: String) -> some View {
        Card(padding: 16) {
            Text(label).font(Theme.font(12.5, .medium)).foregroundStyle(.secondary)
            Text(value).font(Theme.font(21, .bold)).padding(.top, 8).padding(.bottom, 3)
            Text(hint).font(Theme.font(11.5)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private struct Day: Identifiable { let id: Int; let date: Date; let mb: Double }

    private var chart: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Day] = (0..<14).map { i in
            let start = cal.date(byAdding: .day, value: -(13 - i), to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let s = e.history.filter { $0.date >= start && $0.date < end }.reduce(Int64(0)) { $0 + $1.saved }
            return Day(id: i, date: start, mb: Double(s) / 1_048_576)
        }
        let total = days.reduce(0) { $0 + $1.mb }
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("التوفير اليومي").font(Theme.font(16, .semibold))
                    Text("آخر 14 يوماً").font(Theme.font(12)).foregroundStyle(.tertiary)
                }
                Spacer()
                if total > 0 { Text(Fmt.size(Int64(total * 1_048_576))).font(Theme.font(15, .semibold)).foregroundStyle(Theme.accent) }
            }
            if total <= 0 {
                VStack(spacing: 8) {
                    Image(systemName: "video").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("لا يوجد توفير في هذه الفترة بعد").font(Theme.font(13.5, .medium)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 26)
            } else {
                Chart(days) { d in
                    BarMark(x: .value("اليوم", d.date, unit: .day), y: .value("MB", d.mb))
                        .foregroundStyle(d.id == 13 ? Theme.accent : Theme.accent.opacity(0.55))
                        .cornerRadius(4)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day(), centered: true) } }
                .chartYAxis(.hidden)
                .frame(height: 150).padding(.top, 14)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private var recent: some View {
        Card(padding: 6) {
            HStack {
                Text("آخر العمليات").font(Theme.font(16, .semibold))
                Spacer()
            }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            if e.history.isEmpty {
                Text("لم يُضغط أيّ فيديو بعد.").font(Theme.font(13.5)).foregroundStyle(.tertiary).padding(12)
            }
            ForEach(Array(e.history.prefix(4).enumerated()), id: \.element.id) { i, r in
                if i > 0 { Divider().padding(.leading, 84) }
                RecRow(r: r, withDay: true)
            }
        }
    }
}

struct RecRow: View {
    let r: Rec; let withDay: Bool
    var body: some View {
        HStack(spacing: 12) {
            Thumb(id: r.newId)
            VStack(alignment: .leading, spacing: 3) {
                Text("\u{2066}\(r.name)\u{2069}").font(Theme.font(14.5, .medium)).lineLimit(1)
                Text((withDay ? Fmt.day(r.date) + " · " : "") + Fmt.clock(r.date) + " · من \(Fmt.size(r.before)) إلى \(Fmt.size(r.after))")
                    .font(Theme.font(12)).foregroundStyle(.secondary).lineLimit(1)
                if !r.originalDeleted { Text("الأصل لم يُحذف بعد").font(Theme.font(11.5, .medium)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 8)
            Pill(text: "\u{2066}−\(r.pct)%\u{2069}")
        }
        .padding(12)
    }
}
