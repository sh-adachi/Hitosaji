import SwiftUI

private struct MealRoute: Identifiable {
    let id = UUID()
    let date: Date
    let period: MealPeriod
    var entry: MealEntry? = nil
}

struct TodayView: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var selectedDate = Date()
    @State private var route: MealRoute?
    @State private var showCalendar = false
    @State private var showNutrition = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var lastToday = Calendar.current.startOfDay(for: Date())

    private var entries: [MealEntry] { NutritionAnalytics.entries(on: selectedDate, in: store.data.entries) }
    private var total: Nutrition { NutritionAnalytics.total(entries) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var week: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 23) {
                    header
                    dateStrip
                    energyCard
                    macroCard
                    mealDiary
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "leaf").foregroundStyle(HTheme.green)
                        Text(entries.isEmpty ? "まずは、ひとさじ分の記録から。\n食べたものを、自分のペースで残しましょう。" : "記録した分だけ、今日の食事が見えてきます。\n量や栄養成分は、いつでも修正できます。")
                            .font(.caption).foregroundStyle(HTheme.muted).lineSpacing(4)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 5).padding(.bottom, 12)
                }.padding(.horizontal, 22).padding(.top, 8)
            }
            .background(HTheme.background)
            .navigationTitle("ひとさじ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "leaf.fill").foregroundStyle(HTheme.green).accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCalendar = true } label: { Image(systemName: "calendar") }
                        .accessibilityLabel("日付を選ぶ").accessibilityIdentifier("chooseDate")
                }
            }
            .sheet(item: $route) { item in
                MealEntryView(date: item.date, period: item.period, entry: item.entry)
            }
            .sheet(isPresented: $showCalendar) {
                NavigationStack {
                    DatePicker("表示する日", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("日付を選ぶ").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { showCalendar = false } } }
                }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNutrition) { nutritionDetail }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let today = Calendar.current.startOfDay(for: Date())
                if Calendar.current.isDate(selectedDate, inSameDayAs: lastToday) { selectedDate = today }
                lastToday = today
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("DAILY NOURISHMENT").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2.5).foregroundStyle(HTheme.muted)
                Text(isToday ? "きょうの、ひとさじ。" : selectedDate.formatted(.dateTime.month().day()) + "の記録")
                    .font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(HTheme.ink)
            }
            Spacer()
            VStack(spacing: 3) {
                Image(systemName: "book.closed").font(.system(size: 16))
                Text("\(NutritionAnalytics.recordedDays(in: store.data.entries))日記録").font(.system(size: 10, weight: .medium))
            }.foregroundStyle(HTheme.green).padding(12).background(HTheme.pale, in: RoundedRectangle(cornerRadius: 17))
                .accessibilityLabel("これまで\(NutritionAnalytics.recordedDays(in: store.data.entries))日記録")
        }
    }

    private var dateStrip: some View {
        VStack(spacing: 14) {
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left").font(.caption.bold()).frame(width: 30, height: 30) }
                    .accessibilityLabel("前の日").accessibilityIdentifier("previousDay")
                Spacer()
                Text(selectedDate.formatted(.dateTime.year().month().day().weekday())).font(.subheadline.weight(.medium)).foregroundStyle(HTheme.ink)
                Spacer()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right").font(.caption.bold()).frame(width: 30, height: 30) }
                    .accessibilityLabel("次の日").accessibilityIdentifier("nextDay")
            }
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                    let hasEntries = store.data.entries.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
                    Button { selectedDate = day } label: {
                        VStack(spacing: 8) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 11))
                            Text(day.formatted(.dateTime.day())).font(.system(.body, design: .rounded).weight(.semibold))
                            Circle().fill(selected ? .white.opacity(hasEntries ? 1 : 0) : HTheme.green.opacity(hasEntries ? 1 : 0)).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(selected ? Color.white : HTheme.muted)
                            .background(selected ? Color(light: 0x376551, dark: 0x376551) : Color.clear, in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(day.formatted(.dateTime.month().day().weekday()) + (hasEntries ? "、記録あり" : ""))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if !isToday {
                Button("今日へ戻る") { selectedDate = Date() }.font(.caption.bold()).accessibilityIdentifier("returnToday")
            }
        }
    }

    private var energyCard: some View {
        HStack(spacing: 17) {
            ZStack {
                Circle().stroke(HTheme.green.opacity(0.12), lineWidth: 10)
                Circle().trim(from: 0, to: min((store.data.goals.energy > 0 ? total.energy / store.data.goals.energy : 0), 1))
                    .stroke(HTheme.green, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 3) {
                    Image(systemName: "leaf.fill").font(.caption).foregroundStyle(HTheme.green).padding(.bottom, 2)
                    Text(HFormat.number(total.energy)).font(.system(size: 29, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)

                    Text("kcal").font(.system(size: 11)).foregroundStyle(HTheme.muted)
                }.padding(16)
            }.frame(width: 133, height: 133).accessibilityElement(children: .ignore)
                .accessibilityLabel("記録済みエネルギー")
                .accessibilityValue("\(HFormat.number(total.energy)) kcal").accessibilityIdentifier("energyTotal")
            VStack(alignment: .leading, spacing: 12) {
                Text("摂取エネルギー").font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("記録済みの合計").font(.caption).foregroundStyle(HTheme.muted)
                    Text("目標 \(HFormat.number(store.data.goals.energy)) kcal").font(.caption)
                }
                Text(energyMessage).font(.caption.weight(.medium)).foregroundStyle(HTheme.green)
                    .fixedSize(horizontal: false, vertical: true)
                if store.data.goals.isExample { Text("仮の目標・設定で変更").font(.system(size: 10)).foregroundStyle(HTheme.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(HTheme.ink).padding(21).frame(maxWidth: .infinity)
            .background(HTheme.pale, in: RoundedRectangle(cornerRadius: 27))
    }

    private var energyMessage: String {
        if entries.isEmpty { return "食事を記録して\n一日を見える形に。" }
        let delta = store.data.goals.energy - total.energy
        return delta >= 0 ? "目標まで \(HFormat.number(delta)) kcal" : "目標より \(HFormat.number(-delta)) kcal 多い"
    }

    private var macroCard: some View {
        HCard {
            VStack(spacing: 19) {
                HStack {
                    Text("栄養バランス").font(.subheadline.bold())
                    Spacer()
                    Button { showNutrition = true } label: { HStack(spacing: 3) { Text("詳しく"); Image(systemName: "arrow.up.right") }.font(.caption) }
                        .accessibilityIdentifier("nutritionDetail")
                }
                if dynamicTypeSize.isAccessibilitySize {
                    NutrientBar(title: "たんぱく質", value: total.protein, goal: store.data.goals.protein, color: HTheme.protein)
                    NutrientBar(title: "脂質", value: total.fat, goal: store.data.goals.fat, color: HTheme.fat)
                    NutrientBar(title: "炭水化物", value: total.carbs, goal: store.data.goals.carbs, color: HTheme.carbs)
                } else {
                HStack(alignment: .top, spacing: 15) {
                    macro("P", title: "たんぱく質", value: total.protein, goal: store.data.goals.protein, color: HTheme.protein)
                    macro("F", title: "脂質", value: total.fat, goal: store.data.goals.fat, color: HTheme.fat)
                    macro("C", title: "炭水化物", value: total.carbs, goal: store.data.goals.carbs, color: HTheme.carbs)
                }
                }
            }.foregroundStyle(HTheme.ink)
        }
    }

    private func macro(_ letter: String, title: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 4) {
                Text(letter).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(color)
                Text(title).font(.caption2).foregroundStyle(HTheme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(HFormat.number(value)).font(.system(size: 23, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                Text("g").font(.system(size: 10)).foregroundStyle(HTheme.muted)
            }
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.14)).overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geometry.size.width * min((goal > 0 ? value / goal : 0), 1))
                }
            }.frame(height: 5)
            Text("目標 \(HFormat.number(goal)) g").font(.caption2).foregroundStyle(HTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var mealDiary: some View {
        VStack(spacing: 14) {
            HStack {
                HSectionTitle(title: "食事の記録", subtitle: "\(entries.count)品")
                Button { route = MealRoute(date: selectedDate, period: defaultPeriod) } label: {
                    Image(systemName: "plus").font(.caption.bold()).frame(width: 31, height: 31).background(HTheme.pale, in: Circle())
                }.accessibilityLabel("食事を記録").accessibilityIdentifier("addMeal")
            }
            ForEach(MealPeriod.allCases) { period in
                let meals = entries.filter { $0.period == period }
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: period.symbol).font(.system(size: 19, weight: .light)).foregroundStyle(HTheme.green)
                            .frame(width: 42, height: 42).background(HTheme.pale, in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(period.label).font(.subheadline.bold()).foregroundStyle(HTheme.ink)
                            Text(meals.isEmpty ? "まだ記録がありません" : "\(meals.count)品 · \(HFormat.number(NutritionAnalytics.total(meals).energy)) kcal")
                                .font(.caption).foregroundStyle(HTheme.muted)
                        }
                        Spacer()
                        Button { route = MealRoute(date: selectedDate, period: period) } label: {
                            Image(systemName: "plus").font(.subheadline).frame(width: 40, height: 40)
                        }.accessibilityLabel("\(period.label)を記録").accessibilityIdentifier("add.\(period.rawValue)")
                    }.padding(15)
                    if !meals.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(meals) { entry in
                                Divider().padding(.leading, 17)
                                Button { route = MealRoute(date: selectedDate, period: period, entry: entry) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(entry.foodName).font(.subheadline).foregroundStyle(HTheme.ink)
                                            Text("\(entry.serving) × \(HFormat.input(entry.portions))").font(.caption).foregroundStyle(HTheme.muted)
                                        }
                                        Spacer()
                                        Text("\(HFormat.number(entry.total.energy))").font(.subheadline.monospacedDigit()).foregroundStyle(HTheme.ink)
                                        Text("kcal").font(.system(size: 10)).foregroundStyle(HTheme.muted)
                                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(HTheme.muted)
                                    }.padding(16).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("meal.\(entry.id.uuidString)")
                            }
                        }
                    }
                }.background(HTheme.card, in: RoundedRectangle(cornerRadius: 21))
            }
        }
    }

    private var nutritionDetail: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text(selectedDate.formatted(.dateTime.month().day()) + "の記録済み栄養素").font(.headline)
                    HCard {
                        VStack(spacing: 24) {
                            NutrientBar(title: "エネルギー", value: total.energy, goal: store.data.goals.energy, color: HTheme.green, unit: "kcal")
                            NutrientBar(title: "たんぱく質", value: total.protein, goal: store.data.goals.protein, color: HTheme.protein)
                            NutrientBar(title: "脂質", value: total.fat, goal: store.data.goals.fat, color: HTheme.fat)
                            NutrientBar(title: "炭水化物", value: total.carbs, goal: store.data.goals.carbs, color: HTheme.carbs)
                            NutrientBar(title: "食物繊維", value: total.fiber, goal: store.data.goals.fiber, color: HTheme.green)
                            NutrientBar(title: "食塩相当量", value: total.salt, goal: store.data.goals.salt, color: HTheme.muted)
                        }
                    }
                    Text("バーは設定した目標値に対する記録量です。栄養素の構成比や健康評価ではありません。食物繊維・食塩相当量が未入力の食品がある日は、その項目を「未入力あり」と表示します。")
                        .font(.caption).foregroundStyle(HTheme.muted).lineSpacing(5)
                    if store.data.goals.isExample { Text("現在の目標は入力例です。「設定」でご自身の目標に変更できます。").font(.caption).foregroundStyle(HTheme.orange) }
                }.padding(22)
            }.background(HTheme.background).navigationTitle("栄養の詳細").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showNutrition = false } } }
        }
    }

    private var defaultPeriod: MealPeriod {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<23: return .dinner
        default: return .snack
        }
    }
    private func shiftDay(_ delta: Int) {
        if let day = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) { selectedDate = day }
    }
}
