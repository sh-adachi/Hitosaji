import SwiftUI

struct PhotoAnalysisSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var token = ""
    @State private var error: String?
    @State private var hasSaved = false

    var body: some View {
        Form {
            Section {
                Text("写真の解析には、ひとさじ用の解析サーバーへの接続が必要です。管理者から案内された接続先とアクセストークンを入力してください。")
                    .font(.subheadline)
                TextField("https://example.com", text: $serverURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("解析サーバーURL").accessibilityIdentifier("photoServerURL")
                SecureField("アクセストークン", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("photoServerToken")
            } header: { Text("接続設定") } footer: {
                Text("URLはパスを付けずに入力してください。OpenAIのAPIキーは解析サーバーで管理し、この欄には入力しません。接続設定はこの端末のキーチェーンに保存します。")
            }
            Section {
                Text("解析ボタンを押したときだけ、選んだ写真と補足を解析サーバー経由でOpenAIへ送信します。食事の履歴や体重は送信しません。写真自体はアプリの記録に保存しません。")
                Text("写真から分からない材料や量があるため、結果は推定値です。記録前に内容を確認・修正してください。")
            } header: { Text("写真と解析結果について") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button("接続設定を保存", action: save).accessibilityIdentifier("savePhotoConfiguration")
                if hasSaved {
                    Button("接続設定を削除", role: .destructive) {
                        do {
                            try PhotoAnalysisConfiguration.remove()
                            serverURL = ""; token = ""; hasSaved = false; error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .navigationTitle("写真のAI解析").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let config = try? PhotoAnalysisConfiguration.load() {
                serverURL = config.serverURL; token = config.token; hasSaved = true
            }
        }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了", action: dismissNutritionKeyboard) } }
    }

    private func save() {
        dismissNutritionKeyboard()
        do {
            try PhotoAnalysisConfiguration(serverURL: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                           token: token.trimmingCharacters(in: .whitespacesAndNewlines)).save()
            dismiss()
        } catch PhotoServiceError.configuration {
            error = "接続先はパスなしのHTTPS URL、アクセストークンは管理者から受け取った32〜256文字の値を入力してください。"
        } catch { self.error = error.localizedDescription }
    }
}
