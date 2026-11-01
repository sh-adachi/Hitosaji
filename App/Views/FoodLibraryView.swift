import SwiftUI

struct FoodLibraryView: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var searchText = ""
    @State private var onlyCustom = false
    @State private var activeSheet: FoodLibrarySheet?
    @State private var foodToDelete: Food?
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("いつもの味を、\nあなたのリストに。")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(HTheme.ink)
                        Text("よく食べるものを保存して、毎日の記録を軽やかに。")
                            .font(.subheadline)
                            .foregroundStyle(HTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HCard {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(HTheme.muted)
                            TextField("食品・料理を検索", text: $searchText)
                                .submitLabel(.search)
                                .accessibilityIdentifier("libraryFoodSearch")
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

                    Picker("食品の種類", selection: $onlyCustom) {
                        Text("すべての食品").tag(false)
                        Text("マイ食品").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if visibleFoods.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HSectionTitle(title: onlyCustom ? "マイ食品" : "食品リスト", subtitle: "\(visibleFoods.count) 件・タップして食事を記録")
                            LazyVStack(spacing: 12) {
                                ForEach(visibleFoods) { food in
                                    foodRow(food)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("食品データについて")
                            .font(.caption.weight(.semibold))
                        Text("収録食品の栄養値は参考値です。商品や調理方法によって異なるため、記録時に栄養表示に合わせて編集できます。")
                            .font(.caption)
                    }
                    .foregroundStyle(HTheme.muted)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(HTheme.background)
            .navigationTitle("食品ライブラリ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .newFood
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("マイ食品を追加")
                    .accessibilityIdentifier("addCustomFood")
                    .disabled(store.isReadOnly)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了", action: dismissNutritionKeyboard)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .record(let food):
                    MealEntryView(date: Date(), period: currentMealPeriod, food: food)
                case .edit(let food):
                    FoodEditorView(food: food)
                case .newFood:
                    FoodEditorView()
                }
            }
            .confirmationDialog("マイ食品から削除しますか？", isPresented: Binding(
                get: { foodToDelete != nil },
                set: { if !$0 { foodToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("マイ食品を削除", role: .destructive) {
                    guard let food = foodToDelete else { return }
                    if !store.deleteFood(food.id) {
                        deletionError = store.errorMessage ?? "削除できませんでした。もう一度お試しください。"
                    }
                    foodToDelete = nil
                }
                Button("キャンセル", role: .cancel) { foodToDelete = nil }
            } message: {
                Text("これまでの食事記録はそのまま残ります。")
            }
            .alert("削除できませんでした", isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: {
                Text(deletionError ?? "")
            }
            .tint(HTheme.green)
        }
    }

    private var visibleFoods: [Food] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.foods.filter { food in
            (!onlyCustom || food.isCustom) && (query.isEmpty || food.name.localizedStandardContains(query) || food.serving.localizedStandardContains(query))
        }
    }

    private func foodRow(_ food: Food) -> some View {
        HCard {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    dismissNutritionKeyboard()
                    activeSheet = .record(food)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: food.isCustom ? "bookmark.fill" : "fork.knife")
                            .font(.title3)
                            .foregroundStyle(HTheme.green)
                            .frame(width: 44, height: 44)
                            .background(HTheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(food.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(HTheme.ink)
                            Text("\(food.serving) · \(HFormat.number(food.nutrition.energy)) kcal")
                                .font(.caption)
                                .foregroundStyle(HTheme.muted)
                            Text("P \(HFormat.number(food.nutrition.protein))  /  F \(HFormat.number(food.nutrition.fat))  /  C \(HFormat.number(food.nutrition.carbs)) g")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(HTheme.muted)
                            if food.isCustom {
                                Text("マイ食品")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(HTheme.green)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(food.name)、\(food.serving)、\(HFormat.number(food.nutrition.energy))キロカロリー。食事に記録")

                if food.isCustom {
                    Menu {
                        Button("食事に記録", systemImage: "plus.circle") {
                            activeSheet = .record(food)
                        }
                        Button("食品を編集", systemImage: "pencil") {
                            activeSheet = .edit(food)
                        }
                        .disabled(store.isReadOnly)
                        Button("マイ食品を削除", systemImage: "trash", role: .destructive) {
                            foodToDelete = food
                        }
                        .disabled(store.isReadOnly)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HTheme.muted)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(food.name)の操作")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HTheme.muted)
                        .padding(.top, 16)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var emptyState: some View {
        HCard {
            VStack(spacing: 14) {
                Image(systemName: onlyCustom && searchText.isEmpty ? "bookmark" : "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(HTheme.green)
                Text(onlyCustom && searchText.isEmpty ? "いつもの食品を登録しましょう" : "食品が見つかりませんでした")
                    .font(.headline)
                    .foregroundStyle(HTheme.ink)
                    .multilineTextAlignment(.center)
                Text(onlyCustom && searchText.isEmpty ? "お気に入りの商品や手作りの料理を\n栄養表示と一緒に保存できます。" : "別の名前で検索するか、\nマイ食品として新しく登録できます。")
                    .font(.subheadline)
                    .foregroundStyle(HTheme.muted)
                    .multilineTextAlignment(.center)
                Button("マイ食品を追加") { activeSheet = .newFood }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                    .disabled(store.isReadOnly)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var currentMealPeriod: MealPeriod {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<23: return .dinner
        default: return .snack
        }
    }
}

private enum FoodLibrarySheet: Identifiable {
    case record(Food)
    case edit(Food)
    case newFood

    var id: String {
        switch self {
        case .record(let food): return "record-\(food.id)"
        case .edit(let food): return "edit-\(food.id)"
        case .newFood: return "new"
        }
    }
}

private struct FoodEditorView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    private let originalFood: Food?
    @State private var name: String
    @State private var serving: String
    @State private var nutritionDraft: NutritionDraft
    @State private var validationMessage: String?

    init(food: Food? = nil) {
        originalFood = food
        _name = State(initialValue: food?.name ?? "")
        _serving = State(initialValue: food?.serving ?? "1 食")
        _nutritionDraft = State(initialValue: NutritionDraft(nutrition: food?.nutrition))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("よく食べる食品の栄養値を登録すると、次回から選ぶだけで記録できます。")
                        .font(.subheadline)
                        .foregroundStyle(HTheme.muted)
                    HCard {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("食品・料理名")
                                    .font(.caption)
                                    .foregroundStyle(HTheme.muted)
                                TextField("例：いつものヨーグルト", text: $name)
                                    .accessibilityIdentifier("mealName")
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("栄養値の基準量")
                                    .font(.caption)
                                    .foregroundStyle(HTheme.muted)
                                TextField("例：1 個、100 g、1 食", text: $serving)
                                    .accessibilityIdentifier("mealServing")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HSectionTitle(title: "基準量あたりの栄養")
                            Text("商品の栄養表示などを参考に入力してください。")
                                .font(.caption)
                                .foregroundStyle(HTheme.muted)
                        }
                        HCard {
                            NutritionInputFields(draft: $nutritionDraft)
                        }
                        Text("カロリー・PFCは必須（0も入力可能）です。食物繊維・食塩相当量は任意です。")
                            .font(.caption)
                            .foregroundStyle(HTheme.muted)
                    }
                    if originalFood != nil {
                        Text("変更は、これから記録する食事に反映されます。過去の食事記録は変わりません。")
                            .font(.caption)
                            .foregroundStyle(HTheme.muted)
                    }
                    if store.isReadOnly {
                        Text("現在は読み取り専用のため、食品を保存できません。")
                            .font(.subheadline)
                            .foregroundStyle(HTheme.muted)
                    }
                    Button(action: save) {
                        Text("マイ食品に保存")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .foregroundStyle(.white)
                            .background(HTheme.action, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isReadOnly)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(HTheme.background)
            .navigationTitle(originalFood == nil ? "マイ食品を追加" : "マイ食品を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(HTheme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(store.isReadOnly)
                        .accessibilityIdentifier("saveFood")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了", action: dismissNutritionKeyboard)
                }
            }
            .tint(HTheme.green)
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

    private func save() {
        dismissNutritionKeyboard()
        do {
            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedServing = serving.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedName.isEmpty else { throw NutritionInputError.message("食品・料理名を入力してください。") }
            guard !cleanedServing.isEmpty else { throw NutritionInputError.message("栄養値の基準量を入力してください。") }
            let nutrition = try nutritionDraft.parsed()
            let food = Food(id: originalFood?.id ?? UUID(), name: cleanedName, serving: cleanedServing, nutrition: nutrition, isCustom: true, source: "手入力")
            if store.saveFood(food) {
                dismiss()
            } else {
                validationMessage = store.errorMessage ?? "保存できませんでした。もう一度お試しください。"
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
