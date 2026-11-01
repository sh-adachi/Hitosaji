import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var days = 7
    @State private var showWeight = false
    @State private var editedWeight: WeightEntry?
    @State private var deletedWeight: WeightEntry?

    private var summaries: [DailySummary] { NutritionAnalytics.dailySummaries(ending: Date(), days: days, entries: store.data.entries) }
    private var recorded: [DailySummary] { summaries.filter(\.isRecorded) }
    private var weights: [WeightEntry] { store.data.weights.sorted { $0.date > $1.date } }
    private var chartWeights: [WeightEntry] {
        guard let start = summaries.first?.date else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return weights.filter { $0.date >= start && $0.date < end }.reversed()
    }
    private var meanEnergy: Double { recorded.isEmpty ? 0 : recorded.reduce(0) { $0 + $1.nutrition.energy } / Double(recorded.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("SMALL STEPS, EVERY DAY").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2).foregroundStyle(HTheme.muted)
                        Text("積み重ねを、見える形に。").font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(HTheme.ink)
                    }
                    Picker("表示する期間", selection: $days) {
                        Text("7日間").tag(7)
                        Text("30日間").tag(30)
                    }.pickerStyle(.segmented)
                    HCard {
                        VStack(alignment: .leading, spacing: 21) {
                            HSectionTitle(title: "エネルギーの記録", subtitle: "直近\(days)日")
                            if recorded.isEmpty {
                                EmptyNote(symbol: "chart.bar.xaxis", title: "記録がグラフになります", message: "食事を記録すると、日ごとの\n摂取エネルギーを確認できます。")
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(HFormat.number(meanEnergy)).font(.system(size: 31, weight: .semibold, design: .rounded))
                                    Text("kcal / 記録日").font(.caption).foregroundStyle(HTheme.muted)
                                }
                                energyChart
                                HStack {
                                    Label("記録済み", systemImage: "circle.fill").foregroundStyle(HTheme.green)
                                    Spacer()
                                    Text("\(recorded.count)日 / \(days)日 記録")
                                }.font(.system(size: 10)).foregroundStyle(HTheme.muted)
                                Text("平均は記録がある日のみ。未記録の日は0 kcalとして計算しません。")
                                    .font(.caption2).foregroundStyle(HTheme.muted)
                            }
                        }.foregroundStyle(HTheme.ink)
                    }
                    HCard {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                HSectionTitle(title: "体重の推移")
                                Button { showWeight = true } label: { Label("記録", systemImage: "plus").font(.caption.bold()) }
                                    .accessibilityIdentifier("addWeight")
                            }
                            if chartWeights.isEmpty {
                                EmptyNote(symbol: "scalemass", title: "からだの変化も、少しずつ", message: "この期間の体重は未記録です。\n同じ日の記録は最新の値で更新します。")
                            } else {
                                if let latest = chartWeights.last {
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        Text(HFormat.number(latest.kilograms)).font(.system(size: 31, weight: .semibold, design: .rounded))
                                        Text("kg").font(.caption).foregroundStyle(HTheme.muted)
                                        Spacer()
                                        Text(latest.date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(HTheme.muted)
                                    }
                                }
                                Chart(chartWeights) { item in
                                    LineMark(x: .value("日付", item.date, unit: .day), y: .value("体重", item.kilograms))
                                        .foregroundStyle(HTheme.green).lineStyle(StrokeStyle(lineWidth: 2.5))
                                    PointMark(x: .value("日付", item.date, unit: .day), y: .value("体重", item.kilograms))
                                        .foregroundStyle(HTheme.green).symbolSize(35)
                                }
                                .chartYScale(domain: weightRange)
                                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                                .chartYAxis { AxisMarks(position: .leading) }
                                .frame(height: 160).accessibilityLabel("直近\(days)日間の体重グラフ")
                            }
                        }.foregroundStyle(HTheme.ink)
                    }
                    if !weights.isEmpty {
                        HSectionTitle(title: "体重の記録", subtitle: "タップで編集")
                        VStack(spacing: 0) {
                            ForEach(weights) { item in
                                HStack {
                                    Button { editedWeight = item } label: {
                                        HStack {
                                            Text(item.date.formatted(.dateTime.year().month().day())).font(.subheadline)
                                            Spacer()
                                            Text("\(HFormat.number(item.kilograms)) kg").font(.subheadline.bold()).monospacedDigit()
                                        }.foregroundStyle(HTheme.ink).padding(.vertical, 16).contentShape(Rectangle())
                                    }.accessibilityIdentifier("weight.\(item.id.uuidString)")
                                    Button { deletedWeight = item } label: { Image(systemName: "trash").font(.caption).foregroundStyle(HTheme.muted).frame(width: 40, height: 44) }
                                        .accessibilityLabel("\(item.date.formatted(.dateTime.month().day()))の体重を削除")
                                }.padding(.horizontal, 17)
                                if item.id != weights.last?.id { Divider().padding(.horizontal, 17) }
                            }
                        }.background(HTheme.card, in: RoundedRectangle(cornerRadius: 22))
                    }
                }.padding(22).padding(.bottom, 15)
            }.background(HTheme.background).navigationTitle("ふりかえり").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showWeight) { WeightEditorView() }
                .sheet(item: $editedWeight) { WeightEditorView(entry: $0) }
                .confirmationDialog("体重の記録を削除しますか？", isPresented: Binding(get: { deletedWeight != nil }, set: { if !$0 { deletedWeight = nil } }), titleVisibility: .visible) {
                    Button("削除", role: .destructive) { if let deletedWeight { _ = store.deleteWeight(deletedWeight.id) }; deletedWeight = nil }
                    Button("キャンセル", role: .cancel) { deletedWeight = nil }
                }
        }
    }

    private var energyChart: some View {
        Chart {
            ForEach(summaries) { item in
                if item.isRecorded {
                    BarMark(x: .value("日付", item.date, unit: .day), y: .value("エネルギー", item.nutrition.energy))
                        .foregroundStyle(HTheme.green.gradient).cornerRadius(4)
                }
            }
        }
        .chartXScale(domain: (summaries.first?.date ?? Date())...(Calendar.current.date(byAdding: .day, value: 1, to: summaries.last?.date ?? Date()) ?? Date()))
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 7)) { _ in AxisValueLabel(format: .dateTime.day()) } }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 180).accessibilityLabel("直近\(days)日間の記録済みエネルギー")
    }

    private var weightRange: ClosedRange<Double> {
        let values = chartWeights.map(\.kilograms)
        return max(0, (values.min() ?? 50) - 1)...((values.max() ?? 70) + 1)
    }
}

struct WeightEditorView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let entry: WeightEntry?
    @State private var date: Date
    @State private var kilograms: String
    @State private var message: String?

    init(entry: WeightEntry? = nil) {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? Date())
        _kilograms = State(initialValue: entry.map { HFormat.input($0.kilograms) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("記録日", selection: $date, in: ...Date(), displayedComponents: .date)
                    DecimalField(title: "体重", text: $kilograms, unit: "kg", identifier: "weightValue")
                } footer: { Text("同じ日に記録済みの体重がある場合は、今回の値で更新します。") }
                if let message { Section { Text(message).foregroundStyle(.red).font(.subheadline) } }
            }.navigationTitle(entry == nil ? "体重を記録" : "体重を編集").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }.fontWeight(.semibold).accessibilityIdentifier("saveWeight")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了", action: dismissNutritionKeyboard) }
                }
        }
    }

    private func save() {
        dismissNutritionKeyboard()
        guard let value = HFormat.decimal(kilograms), value > 0, value <= 500 else {
            message = "体重は0より大きく500以下の数値で入力してください。"; return
        }
        let record = WeightEntry(id: entry?.id ?? UUID(), date: date, kilograms: value)
        if store.saveWeight(record) { dismiss() }
        else { message = store.errorMessage }
    }
}
