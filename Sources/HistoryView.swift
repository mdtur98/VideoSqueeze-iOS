import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var e: Engine
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("السجلّ").font(Theme.font(26, .bold)).padding(.top, 8)
                    if !e.history.isEmpty {
                        Text("\(e.history.count) فيديو · وُفّر \(Fmt.size(e.savedTotal))").font(Theme.font(13.5)).foregroundStyle(.secondary).padding(.top, 5)
                    }
                    if e.history.isEmpty {
                        Card(padding: 28) {
                            VStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundStyle(Theme.accent)
                                Text("لا توجد عمليات بعد").font(Theme.font(17, .semibold))
                                Text("كل فيديو يُضغط سيظهر هنا مع حجمه قبل وبعد.").font(Theme.font(13.5)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity)
                        }.padding(.top, 18)
                    }
                    let groups = Dictionary(grouping: e.history) { Calendar.current.startOfDay(for: $0.date) }
                    ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                        let recs = groups[day]!
                        HStack {
                            Text(Fmt.day(day)).font(Theme.font(13, .medium)).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.size(recs.reduce(Int64(0)) { $0 + $1.saved })).font(Theme.font(13, .medium)).foregroundStyle(.secondary)
                        }.padding(.horizontal, 6).padding(.top, 18).padding(.bottom, 8)
                        Card(padding: 6) {
                            ForEach(Array(recs.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Divider().padding(.leading, 84) }
                                RecRow(r: r, withDay: false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}
