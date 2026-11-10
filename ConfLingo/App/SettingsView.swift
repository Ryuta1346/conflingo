import SwiftUI

struct SettingsView: View {
    @Binding var fontSize: Double
    @Binding var alwaysOnTop: Bool
    @Binding var appearance: String
    @Binding var answerLanguage: AnswerLanguage
    let credentials: GeminiCredentials
    let editDictionary: () -> Void
    let prepare: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "設定", subtitle: "入力と表示を、使いやすく。", eyebrow: "ConfLingo")
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("音声と言語").font(.headline)
                        LabeledContent("認識言語・翻訳先") {
                            Button("字幕の準備へ", action: prepare)
                        }
                        Divider()
                        LabeledContent("専門用語辞書") {
                            Button("辞書を管理", action: editDictionary)
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("表示と操作").font(.headline)
                        Picker("配色", selection: $appearance) {
                            Text("システムに合わせる").tag("system")
                            Text("ライト").tag("light")
                            Text("ダーク").tag("dark")
                        }
                        .frame(maxWidth: 360)
                        Divider()
                        Stepper("字幕の文字サイズ：\(Int(fontSize)) pt", value: $fontSize, in: 10...48, step: 2)
                        Toggle("ウィンドウを最前面に表示", isOn: $alwaysOnTop)
                        Divider()
                        LabeledContent("Conferenceの開始 / 停止", value: "⌘ R")
                        LabeledContent("文字を拡大 / 縮小", value: "⌘ ＋ / −")
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("AI会話支援").font(.headline)
                        Picker("AIの回答言語", selection: $answerLanguage) {
                            ForEach(AnswerLanguage.allCases, id: \.self) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        Text("質問や発話の言語に関係なく適用します。変更は次の回答から反映されます。")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                        Divider()
                        GeminiKeySettingsView(credentials: credentials)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("データの扱い").font(.headline)
                        Text("Conferenceの字幕はMarkdownで書き出せます。Meetingの発話も終了後にMarkdownで書き出せます。アプリ内の保存一覧は未対応で、発話はアプリ終了まで保持します。どちらも自動保存せず、音声ファイルは保存しません。")
                            .foregroundStyle(DesignTokens.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
    }
}
