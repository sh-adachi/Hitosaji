import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var editGoals = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "leaf.fill").font(.system(size: 31, weight: .light)).foregroundStyle(HTheme.green)
                            .frame(width: 65, height: 65).background(HTheme.pale, in: RoundedRectangle(cornerRadius: 19))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ひとさじ").font(.title3.bold()).foregroundStyle(HTheme.ink)
                            Text("食べるを、心地よく。").font(.subheadline).foregroundStyle(HTheme.muted)
                        }
                    }.padding(.vertical, 10)
                }
                Section {
                    Button { editGoals = true } label: {
                        HStack {
                            Label("栄養の目標", systemImage: "scope").foregroundStyle(HTheme.ink)
                            Spacer()
                            Text("\(HFormat.number(store.data.goals.energy)) kcal").font(.subheadline).foregroundStyle(HTheme.muted)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(HTheme.muted)
                        }
                    }.accessibilityIdentifier("editGoals")
                    if store.data.goals.isExample {
                        Label("いまの目標は入力例です", systemImage: "info.circle").font(.subheadline).foregroundStyle(HTheme.orange)
                    }
                } header: { Text("自分に合わせる") } footer: {
                    Text("目標値はご自身で設定する比較用の数値です。年齢や体格からの自動算出は行いません。変更すると、過去の日付にも現在の目標を表示します。")
                }
                Section {
                    NavigationLink {
                        PhotoAnalysisSettingsView()
                    } label: {
                        Label("写真のAI解析", systemImage: "camera.viewfinder")
                    }.accessibilityIdentifier("photoSettings")
                } header: { Text("食事の入力") }
                Section {
                    LabeledContent("食事の記録", value: "\(store.data.entries.count)品")
                    LabeledContent("体重の記録", value: "\(store.data.weights.count)件")
                    LabeledContent("マイ食品", value: "\(store.data.customFoods.count)品")
                    LabeledContent("保存先", value: "この端末内")
                    if store.isReadOnly {
                        Text("データの読み込みに失敗しています。既存の記録を保護するため、保存を停止しています。")
                            .font(.caption).foregroundStyle(.red)
                        Button("データを再読み込み") { store.reload() }.accessibilityIdentifier("reloadData")
                    }
                } header: { Text("データ") } footer: {
                    Text("アカウント登録は不要です。クラウド同期には対応していません。アプリを削除すると、端末内の記録も削除されます。")
                }
                Section {
                    NavigationLink("使い方と栄養データについて") { aboutView }
                    LabeledContent("バージョン", value: "1.0")
                } header: { Text("このアプリについて") }
            }.scrollContentBackground(.hidden).background(HTheme.background)
                .navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editGoals) { GoalsEditorView(goals: store.data.goals) }
        }
    }

    private var aboutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                help("1. 食べたものを記録", "「きょう」で日付と朝食・昼食・夕食・間食を選びます。食品を検索するか、栄養成分表示を見ながら手入力してください。")
                help("2. 食べた量を合わせる", "栄養成分は表示した基準量あたりの値です。食べた量を0.5倍、1.5倍などに変更すると、記録量が自動で計算されます。")
                help("3. 自分のペースでふりかえる", "カロリーとPFC（たんぱく質・脂質・炭水化物）を日別に確認できます。「ふりかえり」では7日・30日の記録と体重の推移が見られます。")
                help("食品の栄養成分について", "内蔵食品は一般的な食品の参考値です。商品、材料、調理方法で変わるため、実際の商品表示に合わせて修正してください。食物繊維と食塩相当量が分からない場合は空欄にできます。空欄は0として扱いません。")
                help("マイ食品", "よく食べる食品は「食品」から登録できます。食品の値を編集しても、すでに保存した食事の記録は変わりません。")
                help("写真から記録", "食事の追加画面で「写真からAIで記録」を選びます。写真を選択または撮影し、送信して解析した後に、料理名・量・栄養値を確認して保存できます。解析サーバーの接続設定が必要です。結果は推定値で、写真から分からない材料や調味料があります。")
                help("対応範囲", "食事の検索・手入力・写真解析、栄養の集計、体重記録に対応しています。バーコード検索、専門家によるアドバイスは含まれていません。")
            }.padding(24)
        }.background(HTheme.background).navigationTitle("使い方").navigationBarTitleDisplayMode(.inline)
    }
    private func help(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline).foregroundStyle(HTheme.ink)
            Text(body).font(.subheadline).foregroundStyle(HTheme.muted).lineSpacing(6)
        }
    }
}

struct GoalsEditorView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var energy: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String
    @State private var fiber: String
    @State private var salt: String
    @State private var error: String?

    init(goals: NutritionGoals) {
        _energy = State(initialValue: HFormat.input(goals.energy))
        _protein = State(initialValue: HFormat.input(goals.protein))
        _fat = State(initialValue: HFormat.input(goals.fat))
        _carbs = State(initialValue: HFormat.input(goals.carbs))
        _fiber = State(initialValue: HFormat.input(goals.fiber))
        _salt = State(initialValue: HFormat.input(goals.salt))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DecimalField(title: "エネルギー", text: $energy, unit: "kcal", identifier: "goalEnergy")
                    DecimalField(title: "たんぱく質", text: $protein, unit: "g", identifier: "goalProtein")
                    DecimalField(title: "脂質", text: $fat, unit: "g", identifier: "goalFat")
                    DecimalField(title: "炭水化物", text: $carbs, unit: "g", identifier: "goalCarbs")
                    DecimalField(title: "食物繊維", text: $fiber, unit: "g", identifier: "goalFiber")
                    DecimalField(title: "食塩相当量", text: $salt, unit: "g", identifier: "goalSalt")
                } header: { Text("1日あたりの目標") } footer: {
                    Text("すべての項目に0より大きい値を入力してください。表示のための個人設定で、食事内容の良否を判定する数値ではありません。")
                }
                if let error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
            }.navigationTitle("栄養の目標").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold).accessibilityIdentifier("saveGoals") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了", action: dismissNutritionKeyboard) }
                }
        }
    }
    private func save() {
        dismissNutritionKeyboard()
        let parsed = [energy, protein, fat, carbs, fiber, salt].compactMap(HFormat.decimal)
        guard parsed.count == 6, parsed.allSatisfy({ $0 > 0 }) else {
            error = "すべての目標を0より大きい数値で入力してください。"; return
        }
        let goals = NutritionGoals(energy: parsed[0], protein: parsed[1], fat: parsed[2], carbs: parsed[3], fiber: parsed[4], salt: parsed[5], isExample: false)
        if store.saveGoals(goals) { dismiss() } else { error = store.errorMessage }
    }
}
