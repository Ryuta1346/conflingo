import SwiftUI

struct SessionModePicker: View {
    @Binding var selection: SessionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("開始モード", selection: $selection) {
                ForEach(SessionMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(selection == .transcription ? "音声を文字にします。翻訳は行いません。" : "原文をすぐに表示し、訳文は準備した欄に順次表示します。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
        }
    }
}
