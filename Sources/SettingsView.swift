import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var e: Engine
    @State private var threshold = Store.shared.thresholdMb
    @State private var quality = Store.shared.quality
    @State private var bg = Store.shared.background

    private let qDesc = ["أقرب ما يكون إلى الأصل. توفير أقلّ.",
                         "بلا فرق تراه العين، وتوفير كبير. الخيار الأفضل لمعظم الناس.",
                         "مناسب للأرشفة والمشاركة. أكبر توفير مع فرق طفيف في التفاصيل الدقيقة."]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("الحدّ الأدنى", selection: $threshold) {
                        ForEach([50, 100, 200, 500], id: \.self) { Text("\($0) MB").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: threshold) { Store.shared.thresholdMb = $0; e.refresh() }
                } header: { Text("اضغط الفيديوهات الأكبر من").font(Theme.font(13)) }

                Section {
                    Picker("الجودة", selection: $quality) {
                        Text("الأعلى").tag(0); Text("موصى به").tag(1); Text("أصغر حجماً").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: quality) { Store.shared.quality = $0 }
                    Text(qDesc[quality]).font(Theme.font(13)).foregroundStyle(.secondary)
                    Text("الدقّة دائماً FHD (1080p) بترميز HEVC، وبنفس عدد الإطارات.").font(Theme.font(12.5)).foregroundStyle(.tertiary)
                } header: { Text("الجودة").font(Theme.font(13)) }

                Section {
                    Toggle(isOn: $bg) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("الضغط في الخلفية").font(Theme.font(15, .medium))
                            Text("أثناء الشحن، في الوقت الذي يختاره iOS (غالباً ليلاً)").font(Theme.font(12.5)).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: bg) { Store.shared.background = $0; Engine.schedule() }
                } header: { Text("التشغيل").font(Theme.font(13)) } footer: {
                    Text("iOS لا يسمح بالعمل الدائم في الخلفية. ما يُضغط ليلاً يُحفظ، وتحذف الأصول بلمسة واحدة عند فتح التطبيق.").font(Theme.font(12))
                }

                Section {
                    Button("إعادة محاولة الفيديوهات المتخطّاة") { Store.shared.skipped = []; e.refresh() }.font(Theme.font(15))
                    Button("فتح إعدادات الكاميرا") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }.font(Theme.font(15))
                } header: { Text("أدوات").font(Theme.font(13)) } footer: {
                    Text("نصيحة: الإعدادات ← الكاميرا ← تسجيل الفيديو ← 1080p، و«التنسيقات» ← عالي الكفاءة؛ فتُصوَّر الفيديوهات الجديدة صغيرة من البداية.\n\nتُتخطّى الفيديوهات المعدّلة والتصوير البطيء والسينمائي لأنّ تأثيراتها تضيع عند إنشاء ملف جديد.")
                        .font(Theme.font(12))
                }
            }
            .navigationTitle("الإعدادات")
        }
    }
}
