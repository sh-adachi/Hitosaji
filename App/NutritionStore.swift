import SwiftUI

@MainActor
final class NutritionStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var errorMessage: String?
    @Published private(set) var isReadOnly = false
    private let repository: NutritionRepository

    init() {
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("--uitesting")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(testing ? "Hitosaji-UITests" : "Hitosaji", isDirectory: true)
        if testing && args.contains("--reset-data") { try? FileManager.default.removeItem(at: directory) }
        repository = NutritionRepository(directory: directory)
        reload()
        if testing && args.contains("--sample-data") && data.entries.isEmpty && !isReadOnly {
            _ = commit(DemoData.make())
        }
    }

    var foods: [Food] { data.customFoods + FoodCatalog.foods }

    func reload() {
        do {
            data = try repository.load()
            isReadOnly = false
            errorMessage = nil
        } catch {
            isReadOnly = true
            errorMessage = "記録を読み込めませんでした。元のデータを保護するため保存を停止しています。設定から再読み込みできます。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func commit(_ updated: AppData) -> Bool {
        guard !isReadOnly else {
            errorMessage = "記録を読み込めていないため保存できません。設定から再読み込みしてください。"
            return false
        }
        do {
            try repository.save(updated)
            data = updated
            return true
        } catch {
            errorMessage = "保存できませんでした。入力内容を確認してください。\n\(error.localizedDescription)"
            return false
        }
    }

    func saveEntry(_ entry: MealEntry, saveAsFood: Bool = false) -> Bool {
        var updated = data
        if let index = updated.entries.firstIndex(where: { $0.id == entry.id }) { updated.entries[index] = entry }
        else { updated.entries.append(entry) }
        if saveAsFood {
            updated.customFoods.append(Food(name: entry.foodName, serving: entry.serving, nutrition: entry.nutrition, isCustom: true, source: "自分で登録した食品"))
        }
        return commit(updated)
    }

    func deleteEntry(_ id: UUID) -> Bool {
        var updated = data
        updated.entries.removeAll { $0.id == id }
        return commit(updated)
    }

    /// Photo review saves every selected dish in one atomic repository transaction.
    func saveEntries(_ entries: [MealEntry]) -> Bool {
        guard !entries.isEmpty, entries.count <= 12 else {
            errorMessage = "記録する料理を1〜12品選んでください。"
            return false
        }
        var updated = data
        updated.entries.append(contentsOf: entries)
        return commit(updated)
    }

    func saveFood(_ food: Food) -> Bool {
        var updated = data
        if let index = updated.customFoods.firstIndex(where: { $0.id == food.id }) { updated.customFoods[index] = food }
        else { updated.customFoods.append(food) }
        return commit(updated)
    }

    func deleteFood(_ id: UUID) -> Bool {
        var updated = data
        updated.customFoods.removeAll { $0.id == id }
        return commit(updated)
    }

    func saveWeight(_ entry: WeightEntry) -> Bool {
        var updated = data
        // A daily weigh-in replaces that day's earlier value.
        updated.weights.removeAll { $0.id == entry.id || Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
        updated.weights.append(entry)
        return commit(updated)
    }

    func deleteWeight(_ id: UUID) -> Bool {
        var updated = data
        updated.weights.removeAll { $0.id == id }
        return commit(updated)
    }

    func saveGoals(_ goals: NutritionGoals) -> Bool {
        var updated = data
        updated.goals = goals
        return commit(updated)
    }
}
