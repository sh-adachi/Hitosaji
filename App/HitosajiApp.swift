import SwiftUI

@main
struct HitosajiApp: App {
    @StateObject private var store = NutritionStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(HTheme.green)
                .environment(\.locale, Locale(identifier: "ja_JP"))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: NutritionStore
    var body: some View {
        TabView {
            TodayView().tabItem { Label("きょう", systemImage: "leaf") }
            FoodLibraryView().tabItem { Label("食品", systemImage: "fork.knife") }
            TrendsView().tabItem { Label("ふりかえり", systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("設定", systemImage: "slider.horizontal.3") }
        }
        .alert("記録について", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("閉じる") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
