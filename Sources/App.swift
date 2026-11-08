import SwiftUI
import Photos

@main
struct SqueezeApp: App {
    @Environment(\.scenePhase) private var phase
    init() { Engine.registerBackground() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(Engine.shared)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .tint(Theme.accent)
        }
        .onChange(of: phase) { p in
            if p == .background { Engine.schedule() }
            if p == .active { Engine.shared.refresh() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var e: Engine
    var body: some View {
        TabView {
            HomeView().tabItem { Label("الرئيسية", systemImage: "house.fill") }
            HistoryView().tabItem { Label("السجلّ", systemImage: "clock.arrow.circlepath") }
            SettingsView().tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
        }
        .alert(e.message ?? "", isPresented: Binding(get: { e.message != nil }, set: { if !$0 { e.message = nil } })) {
            Button("حسناً", role: .cancel) {}
        }
    }
}

// ── نظام التصميم ──
enum Theme {
    static let accent = Color(red: 0.055, green: 0.624, blue: 0.431)
    static let bright = Color(red: 0.204, green: 0.827, blue: 0.600)
    static func font(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let name: String
        switch w {
        case .bold, .heavy, .black: name = "IBMPlexSansArabic-Bold"
        case .semibold: name = "IBMPlexSansArabic-SemiBold"
        case .medium: name = "IBMPlexSansArabic-Medium"
        default: name = "IBMPlexSansArabic-Regular"
        }
        return .custom(name, size: size)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct Pill: View {
    let text: String; var fg: Color = Theme.accent; var bg: Color = Theme.accent.opacity(0.12); var dot = false
    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(fg).frame(width: 7, height: 7) }
            Text(text).font(Theme.font(12, .medium)).foregroundStyle(fg)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(bg, in: Capsule())
    }
}

struct Thumb: View {
    let id: String; var size: CGFloat = 60
    @State private var img: UIImage?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill))
            if let img { Image(uiImage: img).resizable().scaledToFill() }
            else { Image(systemName: "video.fill").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            let d = Library.duration(id)
            if img != nil && d > 0 {
                Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60))
                    .font(Theme.font(10, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: id) { img = await Library.thumbnail(id, size: size) }
    }
}
