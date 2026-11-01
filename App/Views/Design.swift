import SwiftUI

enum HTheme {
    static let action = Color(light: 0x376551, dark: 0x376551)
    static let green = Color(light: 0x376551, dark: 0xA8C7AC)
    static let background = Color(light: 0xF7F7F0, dark: 0x171C18)
    static let ink = Color(light: 0x283B30, dark: 0xE4EDE0)
    static let orange = Color(light: 0xB8653D, dark: 0xEAAA84)
    static let muted = Color(light: 0x606F60, dark: 0x9FAF9F)
    static let card = Color(light: 0xFFFFFF, dark: 0x242D26)
    static let pale = Color(light: 0xEAF0E4, dark: 0x303F32)
    static let protein = Color(light: 0xB8754E, dark: 0xE5A376)
    static let fat = Color(light: 0xBB9839, dark: 0xDEC472)
    static let carbs = Color(light: 0x6B93A0, dark: 0x91C2D2)
}

extension Color {
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct HCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(HTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct HSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(HTheme.ink)
            Spacer()
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(HTheme.muted) }
        }
    }
}

enum HFormat {
    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    static func decimal(_ text: String) -> Double? {
        let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        guard let value = Double(normalized.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { return nil }
        return value
    }
    static func input(_ value: Double) -> String { value.rounded() == value && abs(value) < 1e15 ? String(format: "%.0f", value) : String(value) }
}

struct NutrientBar: View {
    let title: String
    let value: Double?
    let goal: Double
    let color: Color
    var unit = "g"
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                if let value {
                    Text(HFormat.number(value)).font(.subheadline.bold()).monospacedDigit()
                    Text("/ \(HFormat.number(goal)) \(unit)").font(.caption).foregroundStyle(HTheme.muted)
                } else {
                    Text("未入力あり").font(.caption).foregroundStyle(HTheme.muted)
                }
            }
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: geometry.size.width * min(max((goal > 0 ? (value ?? 0) / goal : 0), 0), 1))
                    }
            }.frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyNote: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 33, weight: .light)).foregroundStyle(HTheme.green)
                .frame(width: 76, height: 76).background(HTheme.pale, in: Circle())
            Text(title).font(.headline).foregroundStyle(HTheme.ink)
            Text(message).font(.subheadline).foregroundStyle(HTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

struct DecimalField: View {
    let title: String
    @Binding var text: String
    let unit: String
    let identifier: String
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 20)
            TextField("0", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(minWidth: 65, maxWidth: 120).accessibilityIdentifier(identifier)
            Text(unit).foregroundStyle(.secondary).font(.subheadline).frame(width: 38, alignment: .leading)
        }
    }
}
