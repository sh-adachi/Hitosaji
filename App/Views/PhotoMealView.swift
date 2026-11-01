import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

@MainActor
struct PhotoMealView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let onSaved: () -> Void
    @State private var date: Date
    @State private var period: MealPeriod
    @State private var photoItem: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var preview: UIImage?
    @State private var hint = ""
    @State private var isPreparing = false
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var hasAnalyzed = false
    @State private var analysisNote = ""
    @State private var drafts: [PhotoMealDraft] = []
    @State private var expandedItems = Set<UUID>()
    @State private var errorMessage: String?
    @State private var alert: PhotoMealAlert?
    @State private var showsCamera = false
    @State private var showsSettings = false
    @State private var confirmsReanalysis = false
    @State private var isConfigured = PhotoAnalysisConfiguration.isConfigured
    @State private var configuredHost: String?
    @State private var operationID = UUID()
    @State private var workTask: Task<Void, Never>?
    @State private var cameraPermissionTask: Task<Void, Never>?

    init(date: Date, period: MealPeriod, onSaved: @escaping () -> Void) {
        _date = State(initialValue: date)
        _period = State(initialValue: period)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    photoSection
                    destinationSection
                    sendSection
                    if let errorMessage {
                        HCard {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(HTheme.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("photoError")
                        }
                    }
                    if isAnalyzing { loadingSection }
                    if hasAnalyzed && !isAnalyzing {
                        if drafts.isEmpty { emptyResult }
                        else { reviewSection }
                    }
                    if store.isReadOnly {
                        Text("現在は読み取り専用のため、写真の解析・記録の保存はできません。設定からデータを再読み込みしてください。")
                            .font(.subheadline)
                            .foregroundStyle(HTheme.muted)
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(HTheme.background)
            .navigationTitle("写真から食事を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        cancelWork()
                        dismiss()
                    }
                    .foregroundStyle(HTheme.muted)
                    .accessibilityIdentifier("photoCancel")
                }
                if !drafts.isEmpty && !isAnalyzing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", action: saveSelected)
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                            .accessibilityIdentifier("photoSave")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了", action: dismissNutritionKeyboard)
                }
            }
            .tint(HTheme.green)
            .onChange(of: photoItem) { _, item in
                if let item { loadPhoto(item) }
            }
            .onChange(of: hint) { _, value in
                if value.count > 500 { hint = String(value.prefix(500)) }
            }
            .onAppear(perform: refreshConfiguration)
            .onDisappear {
                cancelWork()
                cameraPermissionTask?.cancel()
            }
            .sheet(isPresented: $showsCamera) {
                MealCameraPicker { result in
                    showsCamera = false
                    switch result {
                    case .success(let image): prepareCameraImage(image)
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                } onCancel: {
                    showsCamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsSettings, onDismiss: refreshConfiguration) {
                NavigationStack {
                    PhotoAnalysisSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { showsSettings = false }
                            }
                        }
                }
            }
            .alert(alert?.title ?? "入力を確認してください", isPresented: Binding(
                get: { alert != nil },
                set: { if !$0 { alert = nil } }
            ), presenting: alert) { issue in
                if issue.canOpenSettings {
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Button("OK", role: .cancel) { alert = nil }
            } message: { issue in
                Text(issue.message)
            }
            .confirmationDialog("現在の解析結果と編集内容を置き換えますか？", isPresented: $confirmsReanalysis, titleVisibility: .visible) {
                Button("写真を送信して再解析", action: analyze)
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("食べたものを、写真から。")
                .font(.title2.weight(.semibold))
                .foregroundStyle(HTheme.ink)
            Text("AIが料理と栄養を推定します。結果を確認・修正してから記録しましょう。")
                .font(.subheadline)
                .foregroundStyle(HTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var photoSection: some View {
        VStack(spacing: 14) {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .background(HTheme.pale, in: RoundedRectangle(cornerRadius: 24))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .accessibilityLabel("選択した食事の写真")
                    .accessibilityIdentifier("photoPreview")
            } else {
                HCard {
                    VStack(spacing: 13) {
                        if isPreparing {
                            ProgressView().tint(HTheme.green)
                            Text("送信用の写真を準備しています")
                                .font(.subheadline)
                        } else {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(HTheme.green)
                            Text("料理全体が写った写真を選びましょう")
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.center)
                            Text("まだ写真は送信されません。")
                                .font(.caption)
                                .foregroundStyle(HTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(preview == nil ? "写真を選ぶ" : "写真を変更", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(HTheme.pale, in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityIdentifier("photoPick")
                Button(action: requestCamera) {
                    Label(preview == nil ? "撮影する" : "撮り直す", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(HTheme.pale, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photoCamera")
            }
            .foregroundStyle(HTheme.green)

            #if DEBUG
            if PhotoAnalysisConfiguration.isFixture {
                Button("テスト写真を使う", action: useFixturePhoto)
                    .font(.caption)
                    .accessibilityIdentifier("photoFixtureImage")
            }
            #endif
        }
    }

    private var destinationSection: some View {
        HCard {
            VStack(spacing: 16) {
                DatePicker("記録日", selection: $date, displayedComponents: .date)
                    .font(.subheadline)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                Divider()
                Picker("食事", selection: $period) {
                    ForEach(MealPeriod.allCases) { mealPeriod in
                        Text(mealPeriod.label).tag(mealPeriod)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("料理についての補足（任意）")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(hint.count) / 500")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(HTheme.muted)
                    }
                    TextField("例：ごはんは150g、サラダはドレッシングなし", text: $hint, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.subheadline)
                        .disabled(isAnalyzing)
                        .accessibilityIdentifier("photoHint")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("選んだ写真と補足を設定した解析サーバー経由でOpenAIへ送信します。写真はアプリ内の記録には保存しません。")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
                    .accessibilityIdentifier("photoDisclosure")
                if let configuredHost {
                    Text("接続先：\(configuredHost)")
                        .font(.caption2)
                        .foregroundStyle(HTheme.muted)
                }
                if !isConfigured {
                    Text("写真解析を使うには、解析サーバーへの接続設定が必要です。")
                        .font(.caption)
                        .foregroundStyle(HTheme.orange)
                }
                Button(isConfigured ? "接続設定を確認" : "接続を設定する") { showsSettings = true }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("photoConfigure")
                    .disabled(isAnalyzing)
            }

            Button {
                if drafts.isEmpty { analyze() }
                else { confirmsReanalysis = true }
            } label: {
                Label(hasAnalyzed ? "写真を送信して再解析" : "写真を送信して解析", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .foregroundStyle(.white)
                    .background(HTheme.action, in: RoundedRectangle(cornerRadius: 18))
                    .opacity(canAnalyze ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canAnalyze)
            .accessibilityIdentifier("photoAnalyze")
        }
    }

    private var loadingSection: some View {
        HCard {
            VStack(spacing: 12) {
                ProgressView().tint(HTheme.green)
                Text("写真から料理と栄養を推定しています")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("解析が終わっても、自動では記録されません。")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
                Button("解析を中止") {
                    cancelWork()
                    errorMessage = "解析を中止しました。同じ写真で再度解析できます。"
                }
                .font(.subheadline)
                .accessibilityIdentifier("photoStopAnalysis")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier("photoLoading")
    }

    private var emptyResult: some View {
        HCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("料理を確認できませんでした", systemImage: "photo.badge.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(HTheme.ink)
                if !analysisNote.isEmpty {
                    Text(analysisNote)
                        .font(.subheadline)
                        .foregroundStyle(HTheme.muted)
                }
                Text("食事が明るく大きく写る写真に変えるか、料理名や量を補足して再度解析してください。")
                    .font(.subheadline)
                    .foregroundStyle(HTheme.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoEmpty")
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HSectionTitle(title: "推定結果を確認", subtitle: "\(drafts.count) 品")
                Text("写真だけでは量や調味料は確定できません。内容と数値を確認し、違うものは除外してください。")
                    .font(.subheadline)
                    .foregroundStyle(HTheme.muted)
                if !analysisNote.isEmpty {
                    Text(analysisNote)
                        .font(.caption)
                        .foregroundStyle(HTheme.muted)
                }
            }
            ForEach($drafts) { $draft in
                PhotoMealResultCard(draft: $draft, isExpanded: Binding(
                    get: { expandedItems.contains(draft.id) },
                    set: { expanded in
                        if expanded { expandedItems.insert(draft.id) }
                        else { expandedItems.remove(draft.id) }
                    }
                ))
            }
            HCard {
                HStack(alignment: .firstTextBaseline) {
                    Text("記録する \(selectedCount) 品の合計")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(selectedEnergy.map(HFormat.number) ?? "—")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(HTheme.green)
                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(HTheme.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("photoTotal")
            }
            Button(action: saveSelected) {
                Text("選んだ \(selectedCount) 品を記録")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .foregroundStyle(.white)
                    .background(HTheme.action, in: RoundedRectangle(cornerRadius: 18))
                    .opacity(canSave ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityIdentifier("photoSaveBottom")
            Text("記録には「AI推定」と推定の理由を残します。写真自体は保存しません。")
                .font(.caption)
                .foregroundStyle(HTheme.muted)
        }
    }

    private var canAnalyze: Bool {
        jpeg != nil && isConfigured && !isPreparing && !isAnalyzing && !store.isReadOnly
    }

    private var selectedCount: Int { drafts.filter(\.isIncluded).count }

    private var canSave: Bool {
        selectedCount > 0 && !isSaving && !isPreparing && !isAnalyzing && !store.isReadOnly
    }

    private var selectedEnergy: Double? {
        var total = 0.0
        for draft in drafts where draft.isIncluded {
            guard let nutrition = try? draft.nutrition.parsed(), let multiplier = HFormat.decimal(draft.portions),
                  multiplier > 0, multiplier <= 100 else { return nil }
            total += nutrition.energy * multiplier
        }
        return total.isFinite ? total : nil
    }

    private func refreshConfiguration() {
        isConfigured = PhotoAnalysisConfiguration.isConfigured
        if let config = try? PhotoAnalysisConfiguration.load(), let endpoint = try? config.endpoint {
            configuredHost = endpoint.host
        } else {
            configuredHost = nil
        }
    }

    private func cancelWork() {
        operationID = UUID()
        workTask?.cancel()
        workTask = nil
        isPreparing = false
        isAnalyzing = false
    }

    private func beginPhotoPreparation() -> UUID {
        cancelWork()
        jpeg = nil
        preview = nil
        errorMessage = nil
        drafts = []
        expandedItems = []
        analysisNote = ""
        hasAnalyzed = false
        isPreparing = true
        return operationID
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        let id = beginPhotoPreparation()
        workTask = Task { @MainActor in
            do {
                guard let rawData = try await item.loadTransferable(type: Data.self) else { throw PhotoImageError.unreadable }
                try Task.checkCancellation()
                let processed = try await processPhotoData(rawData)
                try Task.checkCancellation()
                guard operationID == id else { return }
                try finishPhotoPreparation(processed)
                photoItem = nil
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                isPreparing = false
                workTask = nil
                photoItem = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareCameraImage(_ image: UIImage) {
        let id = beginPhotoPreparation()
        workTask = Task { @MainActor in
            do {
                let processing = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    guard let raw = image.jpegData(compressionQuality: 0.92) else { throw PhotoImageError.encoding }
                    return try PhotoImageProcessor.jpeg(from: raw)
                }
                let processed = try await withTaskCancellationHandler {
                    try await processing.value
                } onCancel: {
                    processing.cancel()
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                try finishPhotoPreparation(processed)
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                isPreparing = false
                workTask = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func processPhotoData(_ rawData: Data) async throws -> Data {
        let processing = Task.detached(priority: .userInitiated) { try PhotoImageProcessor.jpeg(from: rawData) }
        return try await withTaskCancellationHandler {
            try await processing.value
        } onCancel: {
            processing.cancel()
        }
    }

    private func finishPhotoPreparation(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw PhotoImageError.unreadable }
        jpeg = data
        preview = image
        isPreparing = false
        workTask = nil
    }

    private func analyze() {
        guard canAnalyze, let photo = jpeg else { return }
        dismissNutritionKeyboard()
        cancelWork()
        let id = operationID
        let submittedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        isAnalyzing = true
        errorMessage = nil
        drafts = []
        expandedItems = []
        hasAnalyzed = false
        analysisNote = ""
        workTask = Task { @MainActor in
            do {
                let result = try await PhotoAnalysisClient().analyze(jpeg: photo, hint: submittedHint)
                try Task.checkCancellation()
                guard operationID == id else { return }
                drafts = result.items.enumerated().map { PhotoMealDraft(index: $0.offset, item: $0.element) }
                analysisNote = result.note
                hasAnalyzed = true
                isAnalyzing = false
                workTask = nil
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                isAnalyzing = false
                workTask = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveSelected() {
        guard canSave else { return }
        dismissNutritionKeyboard()
        var records: [MealEntry] = []
        for draft in drafts where draft.isIncluded {
            do {
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let serving = draft.serving.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw NutritionInputError.message("食品・料理名を入力してください。") }
                guard !serving.isEmpty else { throw NutritionInputError.message("栄養値の基準量を入力してください。") }
                guard let multiplier = HFormat.decimal(draft.portions), multiplier > 0, multiplier <= 100 else {
                    throw NutritionInputError.message("食べた量には、0より大きく100以下の数値を入力してください。")
                }
                let nutrition = try draft.nutrition.parsed()
                var notes = ["AI推定（確認・編集後に記録）", "AIの確信度：\(draft.confidence.label)", "推定の理由：\(draft.reason)"]
                if !analysisNote.isEmpty { notes.append("解析メモ：\(analysisNote)") }
                records.append(MealEntry(id: draft.id, date: date, period: period, foodName: name, serving: serving,
                                         portions: multiplier, nutrition: nutrition, note: notes.joined(separator: "\n")))
            } catch {
                expandedItems.insert(draft.id)
                alert = .validation("\(draft.index + 1)品目：\(error.localizedDescription)")
                return
            }
        }
        isSaving = true
        let saved = store.saveEntries(records)
        isSaving = false
        if saved {
            dismiss()
            onSaved()
        } else {
            alert = .validation(store.errorMessage ?? "保存できませんでした。入力内容を確認して、もう一度お試しください。")
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            alert = .cameraUnavailable
            return
        }
        cancelWork()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showsCamera = true
        case .notDetermined:
            cameraPermissionTask?.cancel()
            cameraPermissionTask = Task { @MainActor in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                if granted { showsCamera = true }
                else { alert = .cameraDenied }
            }
        case .denied, .restricted:
            alert = .cameraDenied
        @unknown default:
            alert = .cameraUnavailable
        }
    }

    #if DEBUG
    private func useFixturePhoto() {
        guard PhotoAnalysisConfiguration.isFixture else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 320))
        let image = renderer.image { context in
            UIColor(red: 0.94, green: 0.95, blue: 0.90, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 110, y: 30, width: 260, height: 260))
            UIColor(red: 0.84, green: 0.64, blue: 0.40, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 190, y: 90, width: 140, height: 80))
            UIColor(red: 0.35, green: 0.55, blue: 0.35, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 140, y: 165, width: 90, height: 70))
        }
        prepareCameraImage(image)
    }
    #endif
}

private struct PhotoMealDraft: Identifiable {
    let id = UUID()
    let index: Int
    var isIncluded = true
    var name: String
    var serving: String
    var nutrition: NutritionDraft
    var portions = "1"
    let confidence: PhotoConfidence
    let reason: String

    init(index: Int, item: PhotoAnalysisItem) {
        self.index = index
        name = item.name
        serving = item.serving
        nutrition = NutritionDraft(nutrition: item.nutrition)
        confidence = item.confidence
        reason = item.reason
    }
}

private struct PhotoMealResultCard: View {
    @Binding var draft: PhotoMealDraft
    @Binding var isExpanded: Bool

    var body: some View {
        HCard {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $draft.isIncluded) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.name.isEmpty ? "料理名を入力" : draft.name)
                            .font(.headline)
                            .foregroundStyle(HTheme.ink)
                        Text(energyLabel)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(HTheme.green)
                    }
                }
                .accessibilityLabel("\(draft.index + 1)品目を記録する")
                .accessibilityIdentifier("photoInclude_\(draft.index)")

                VStack(alignment: .leading, spacing: 6) {
                    Text("AIの確信度：\(draft.confidence.label)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HTheme.orange)
                    Text(draft.reason)
                        .font(.caption)
                        .foregroundStyle(HTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    dismissNutritionKeyboard()
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text(isExpanded ? "編集欄を閉じる" : "内容・栄養値を確認して編集")
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photoEdit_\(draft.index)")

                if isExpanded {
                    editor
                }
                if !draft.isIncluded {
                    Text("この料理は記録しません。")
                        .font(.caption)
                        .foregroundStyle(HTheme.muted)
                }
            }
        }
    }

    private var energyLabel: String {
        guard let nutrition = try? draft.nutrition.parsed(), let multiplier = HFormat.decimal(draft.portions),
              multiplier > 0, multiplier <= 100, (nutrition.energy * multiplier).isFinite else { return "入力を確認してください" }
        return "推定 \(HFormat.number(nutrition.energy * multiplier)) kcal · \(draft.serving) × \(HFormat.input(multiplier))"
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("食品・料理名")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
                TextField("食品・料理名", text: $draft.name)
                    .accessibilityIdentifier("photoName_\(draft.index)")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("栄養値の基準量")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
                TextField("例：1皿・150g", text: $draft.serving)
                    .accessibilityIdentifier("photoServing_\(draft.index)")
            }
            Text("以下は写真に写った基準量あたりの推定値です。食べた量が同じなら1倍のまま記録できます。")
                .font(.caption)
                .foregroundStyle(HTheme.muted)
            PhotoNutritionFields(draft: $draft.nutrition, index: draft.index)
            HStack {
                Text("食べた量")
                    .font(.subheadline)
                Spacer()
                TextField("1", text: $draft.portions)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    .accessibilityIdentifier("photoPortions_\(draft.index)")
                Text("倍")
                    .font(.caption)
                    .foregroundStyle(HTheme.muted)
            }
            Text("食物繊維・食塩相当量の空欄は「不明」のまま保存します。数値を確かめられる場合のみ入力してください。")
                .font(.caption)
                .foregroundStyle(HTheme.muted)
        }
    }
}

private struct PhotoNutritionFields: View {
    @Binding var draft: NutritionDraft
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            row("カロリー", text: $draft.energy, unit: "kcal", name: "Energy")
            Divider()
            row("たんぱく質", text: $draft.protein, unit: "g", name: "Protein")
            Divider()
            row("脂質", text: $draft.fat, unit: "g", name: "Fat")
            Divider()
            row("炭水化物", text: $draft.carbs, unit: "g", name: "Carbs")
            Divider()
            row("食物繊維", text: $draft.fiber, unit: "g", name: "Fiber", optional: true)
            Divider()
            row("食塩相当量", text: $draft.salt, unit: "g", name: "Salt", optional: true)
        }
    }

    private func row(_ title: String, text: Binding<String>, unit: String, name: String, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline)
            if optional {
                Text("任意").font(.caption2).foregroundStyle(HTheme.muted)
            }
            Spacer(minLength: 6)
            TextField(optional ? "不明" : "必須", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(minWidth: 64, maxWidth: 96)
                .accessibilityLabel("\(index + 1)品目の\(title)")
                .accessibilityIdentifier("photo\(name)_\(index)")
            Text(unit)
                .font(.caption)
                .foregroundStyle(HTheme.muted)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 12)
    }
}

private enum PhotoMealAlert {
    case validation(String)
    case cameraDenied
    case cameraUnavailable

    var title: String {
        switch self {
        case .validation: return "内容を確認してください"
        case .cameraDenied: return "カメラの使用が許可されていません"
        case .cameraUnavailable: return "カメラを利用できません"
        }
    }

    var message: String {
        switch self {
        case .validation(let message): return message
        case .cameraDenied: return "端末の設定でカメラへのアクセスを許可してください。写真ライブラリから選ぶこともできます。"
        case .cameraUnavailable: return "この端末では撮影できません。写真ライブラリから食事の写真を選んでください。"
        }
    }

    var canOpenSettings: Bool {
        if case .cameraDenied = self { return true }
        return false
    }
}

private struct MealCameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Result<UIImage, Error>) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MealCameraPicker
        init(parent: MealCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onPhoto(.failure(PhotoImageError.unreadable))
                return
            }
            parent.onPhoto(.success(image))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}
