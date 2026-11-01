import SwiftUI
import UIKit

struct MealEntryView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    private let originalEntry: MealEntry?
    @State private var selectedDate: Date
    @State private var selectedPeriod: MealPeriod
    @State private var isShowingEditor: Bool
    @State private var searchText = ""
    @State private var name: String
    @State private var serving: String
    @State private var portions: String
    @State private var nutritionDraft: NutritionDraft
    @State private var note: String
    @State private var saveAsFood = false
    @State private var validationMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsPhotoAnalysis = false

    init(date: Date, period: MealPeriod, entry: MealEntry? = nil, food: Food? = nil) {
        originalEntry = entry
        _selectedDate = State(initialValue: entry?.date ?? date)
        _selectedPeriod = State(initialValue: entry?.period ?? period)
        _isShowingEditor = State(initialValue: entry != nil || food != nil)
        _name = State(initialValue: entry?.foodName ?? food?.name ?? "")
        _serving = State(initialValue: entry?.serving ?? food?.serving ?? "1 食")
        _portions = State(initialValue: HFormat.input(entry?.portions ?? 1))
        _nutritionDraft = State(initialValue: NutritionDraft(nutrition: entry?.nutrition ?? food?.nutrition))
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isShowingEditor {
                        editor
                    } else {
                        foodPicker
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(HTheme.background)
            .navigationTitle(originalEntry == nil ? "食事を記録" : "食事の編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(HTheme.muted)
                }
                if isShowingEditor {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", action: save)
                            .fontWeight(.semibold)
                            .disabled(store.isReadOnly)
                            .accessibilityIdentifier("saveMeal")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了", action: dismissNutritionKeyboard)
                }
            }
            .tint(HTheme.green)
            .sheet(isPresented: $showsPhotoAnalysis) {
                PhotoMealView(date: selectedDate, period: selectedPeriod) {
                    showsPhotoAnalysis = false
                    dismiss()
                }
            }
            .confirmationDialog("この食事の記録を削除しますか？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("記録を削除", role: .destructive) {
                    guard let originalEntry else { return }
                    if store.deleteEntry(originalEntry.id) {
                        dismiss()
                    } else {
                        validationMessage = store.errorMessage ?? "削除できませんでした。もう一度お試しください。"
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .alert("入力を確認してください", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK", role: .cancel) { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }

    private var foodPicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日のひとさじを、記録。")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(HTheme.ink)
                Text("食品を選んで、食べた量を調整しましょう。")
                    .font(.subheadline)
                    .foregroundStyle(HTheme.muted)
            }

            HCard {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(HTheme.muted)
                    TextField("食品・料理を検索", text: $searchText)
                        .submitLabel(.search)
                        .accessibilityIdentifier("foodSearch")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(HTheme.muted)
                        }
                        .accessibilityLabel("検索文字を消去")
                    }
                }
            }

            Button { showsPhotoAnalysis = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("写真からAIで記録").font(.subheadline.weight(.semibold))
                        Text("料理と栄養を推定し、確認して記録").font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white).padding(18)
                .background(HTheme.action, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(store.isReadOnly)
            .accessibilityIdentifier("photoEntry")

            Button {
                name = ""
                serving = "1 食"
                portions = "1"
                nutritionDraft = NutritionDraft()
                saveAsFood = false
                isShowingEditor = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("栄養表示を見て入力")
                            .font(.subheadline.weight(.semibold))
                        Text("商品ラベルやレシピの数値を記録できます")
                            .font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(HTheme.green)
                .padding(18)
                .background(HTheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manualEntry")

            if !recentFoods.isEmpty {
                foodSection(title: "最近の記録から", foods: recentFoods)
            }

            if filteredFoods.isEmpty && recentFoods.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                    Text("食品が見つかりませんでした")
                        .font(.headline)
                    Text("別の名前で検索するか、栄養表示から入力できます。")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(HTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if !filteredFoods.isEmpty {
                foodSection(title: searchText.isEmpty ? "食品を選ぶ" : "検索結果", foods: filteredFoods)
            }

            Text("収録食品の栄養値は目安です。商品の栄養表示に合わせて編集できます。")
                .font(.caption)
                .foregroundStyle(HTheme.muted)
        }
    }

    private func foodSection(title: String, foods: [Food]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HSectionTitle(title: title)
            VStack(spacing: 1) {
                ForEach(foods) { food in
                    Button {
                        select(food)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: food.isCustom ? "bookmark.fill" : "fork.knife")
                                .font(.subheadline)
                                .foregroundStyle(HTheme.green)
                                .frame(width: 36, height: 36)
                                .background(HTheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(food.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(HTheme.ink)
                                Text(food.serving)
                                    .font(.caption)
                                    .foregroundStyle(HTheme.muted)
                            }
                            Spacer(minLength: 8)
                            Text("\(HFormat.number(food.nutrition.energy)) kcal")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(HTheme.muted)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(HTheme.muted)
                        }
                        .padding(16)
                        .background(HTheme.card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 24) {
            if originalEntry == nil {
                Button {
                    dismissNutritionKeyboard()
                    isShowingEditor = false
                } label: {
                    Label("食品を選び直す", systemImage: "chevron.left")
                        .font(.subheadline)
                }
            }

            HCard {
                VStack(spacing: 18) {
                    DatePicker("記録日", selection: $selectedDate, displayedComponents: .date)
                        .font(.subheadline)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    Divider()
                    Picker("食事", selection: $selectedPeriod) {
                        ForEach(MealPeriod.allCases) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HSectionTitle(title: "食べたもの")
                HCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("食品・料理名")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(HTheme.muted)
                            TextField("例：鮭のおにぎり", text: $name)
                                .font(.body)
                                .accessibilityIdentifier("mealName")
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("栄養値の基準量")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(HTheme.muted)
                            TextField("例：1 個、100 g、1 食", text: $serving)
                                .accessibilityIdentifier("mealServing")
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HSectionTitle(title: "基準量あたりの栄養")
                    Text("カロリー・PFCは必須です。0も入力できます。")
                        .font(.caption)
                        .foregroundStyle(HTheme.muted)
                }
                HCard {
                    NutritionInputFields(draft: $nutritionDraft)
                }
                Text("食物繊維・食塩相当量は、わかる場合のみ入力してください。未入力は「不明」として扱います。")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
            }

            VStack(alignment: .leading, spacing: 12) {
                HSectionTitle(title: "食べた量")
                HCard {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("基準量の何倍？")
                                    .font(.subheadline.weight(.medium))
                                Text("例：半分なら0.5、2個なら2")
                                    .font(.caption)
                                    .foregroundStyle(HTheme.muted)
                            }
                            Spacer()
                            TextField("1", text: $portions)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .frame(width: 64)
                                .accessibilityLabel("食べた量の倍率")
                                .accessibilityIdentifier("mealPortions")
                            Text("倍")
                                .foregroundStyle(HTheme.muted)
                        }
                        HStack(spacing: 8) {
                            ForEach([0.5, 1, 1.5, 2], id: \.self) { value in
                                Button {
                                    portions = HFormat.input(value)
                                } label: {
                                    Text("\(HFormat.number(value)) 倍")
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(HTheme.green.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Divider()
                        totalPreview
                    }
                }
            }

            HCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ひとことメモ（任意）")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HTheme.muted)
                    TextField("おいしかったこと、気づいたこと。", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("mealNote")
                    Divider()
                    Toggle("マイ食品にも保存", isOn: $saveAsFood)
                        .font(.subheadline)
                    Text("基準量あたりの栄養値を保存し、次回の入力をかんたんに。")
                        .font(.caption)
                        .foregroundStyle(HTheme.muted)
                }
            }

            if store.isReadOnly {
                Text("現在は読み取り専用のため、記録の保存・削除はできません。")
                    .font(.subheadline)
                    .foregroundStyle(HTheme.muted)
            }

            Button(action: save) {
                Text(originalEntry == nil ? "この内容で記録する" : "変更を保存する")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .foregroundStyle(.white)
                    .background(HTheme.action, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(store.isReadOnly)

            if originalEntry != nil {
                Button("この記録を削除", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .disabled(store.isReadOnly)
            }
        }
        .foregroundStyle(HTheme.ink)
    }

    private var totalPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("今回の記録")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(previewNutrition.map { HFormat.number($0.energy) } ?? "—")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(HTheme.green)
                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
            }
            HStack(spacing: 0) {
                previewNutrient("たんぱく質", value: previewNutrition?.protein)
                Spacer()
                previewNutrient("脂質", value: previewNutrition?.fat)
                Spacer()
                previewNutrient("炭水化物", value: previewNutrition?.carbs)
            }
        }
    }

    private func previewNutrient(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(HTheme.muted)
            Text(value.map { "\(HFormat.number($0)) g" } ?? "— g")
                .font(.subheadline.weight(.medium).monospacedDigit())
        }
    }

    private var previewNutrition: Nutrition? {
        guard let nutrition = try? nutritionDraft.parsed(),
              let multiplier = HFormat.decimal(portions), multiplier.isFinite, multiplier > 0 else { return nil }
        let result = nutrition.scaled(by: multiplier)
        guard result.energy.isFinite, result.protein.isFinite, result.fat.isFinite, result.carbs.isFinite else { return nil }
        return result
    }

    private var filteredFoods: [Food] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.foods }
        return store.foods.filter {
            $0.name.localizedStandardContains(query) || $0.serving.localizedStandardContains(query)
        }
    }

    private var recentFoods: [Food] {
        var seen = Set<String>()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.data.entries.sorted { $0.date > $1.date }.compactMap { entry -> Food? in
            let key = entry.foodName + "|" + entry.serving
            guard seen.insert(key).inserted else { return nil }
            guard query.isEmpty || entry.foodName.localizedStandardContains(query) || entry.serving.localizedStandardContains(query) else { return nil }
            return Food(id: entry.id, name: entry.foodName, serving: entry.serving, nutrition: entry.nutrition, isCustom: false, source: "最近の記録")
        }.prefix(query.isEmpty ? 4 : 20).map { $0 }
    }

    private func select(_ food: Food) {
        name = food.name
        serving = food.serving
        portions = "1"
        nutritionDraft = NutritionDraft(nutrition: food.nutrition)
        saveAsFood = false
        isShowingEditor = true
        dismissNutritionKeyboard()
    }

    private func save() {
        dismissNutritionKeyboard()
        do {
            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedServing = serving.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedName.isEmpty else { throw NutritionInputError.message("食品・料理名を入力してください。") }
            guard !cleanedServing.isEmpty else { throw NutritionInputError.message("栄養値の基準量を入力してください。") }
            guard let multiplier = HFormat.decimal(portions), multiplier.isFinite, multiplier > 0 else {
                throw NutritionInputError.message("食べた量には、0より大きい数値を入力してください。")
            }
            let nutrition = try nutritionDraft.parsed()
            let entry = MealEntry(
                id: originalEntry?.id ?? UUID(),
                date: selectedDate,
                period: selectedPeriod,
                foodName: cleanedName,
                serving: cleanedServing,
                portions: multiplier,
                nutrition: nutrition,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if store.saveEntry(entry, saveAsFood: saveAsFood) {
                dismiss()
            } else {
                validationMessage = store.errorMessage ?? "保存できませんでした。もう一度お試しください。"
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

/// Text values intentionally remain separate from numbers until the user saves.
/// An empty required value must never silently become zero.
struct NutritionDraft {
    var energy: String
    var protein: String
    var fat: String
    var carbs: String
    var fiber: String
    var salt: String

    init(nutrition: Nutrition? = nil) {
        energy = nutrition.map { HFormat.input($0.energy) } ?? ""
        protein = nutrition.map { HFormat.input($0.protein) } ?? ""
        fat = nutrition.map { HFormat.input($0.fat) } ?? ""
        carbs = nutrition.map { HFormat.input($0.carbs) } ?? ""
        fiber = nutrition?.fiber.map(HFormat.input) ?? ""
        salt = nutrition?.salt.map(HFormat.input) ?? ""
    }

    func parsed() throws -> Nutrition {
        Nutrition(
            energy: try required(energy, name: "カロリー"),
            protein: try required(protein, name: "たんぱく質"),
            fat: try required(fat, name: "脂質"),
            carbs: try required(carbs, name: "炭水化物"),
            fiber: try optional(fiber, name: "食物繊維"),
            salt: try optional(salt, name: "食塩相当量")
        )
    }

    private func required(_ text: String, name: String) throws -> Double {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NutritionInputError.message("\(name)を入力してください。含まれていない場合は0を入力できます。")
        }
        guard let value = HFormat.decimal(text), value.isFinite, value >= 0 else {
            throw NutritionInputError.message("\(name)には、0以上の数値を入力してください。")
        }
        return value
    }

    private func optional(_ text: String, name: String) throws -> Double? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return try required(text, name: name)
    }
}

enum NutritionInputError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}

struct NutritionInputFields: View {
    @Binding var draft: NutritionDraft

    var body: some View {
        VStack(spacing: 0) {
            row("カロリー", text: $draft.energy, unit: "kcal", identifier: "mealEnergy")
            Divider()
            row("たんぱく質", text: $draft.protein, unit: "g", identifier: "mealProtein")
            Divider()
            row("脂質", text: $draft.fat, unit: "g", identifier: "mealFat")
            Divider()
            row("炭水化物", text: $draft.carbs, unit: "g", identifier: "mealCarbs")
            Divider()
            row("食物繊維", text: $draft.fiber, unit: "g", identifier: "mealFiber", optional: true)
            Divider()
            row("食塩相当量", text: $draft.salt, unit: "g", identifier: "mealSalt", optional: true)
        }
    }

    private func row(_ name: String, text: Binding<String>, unit: String, identifier: String, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(HTheme.ink)
            if optional {
                Text("任意")
                    .font(.caption2)
                    .foregroundStyle(HTheme.muted)
            }
            Spacer(minLength: 6)
            TextField(optional ? "不明" : "必須", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(minWidth: 64, maxWidth: 96)
                .accessibilityLabel(name)
                .accessibilityIdentifier(identifier)
            Text(unit)
                .font(.caption)
                .foregroundStyle(HTheme.muted)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 13)
    }
}

func dismissNutritionKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
