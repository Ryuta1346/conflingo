import SwiftUI

struct WebReferencesView: View {
    let references: [WebReference]
    var body: some View {
        ForEach(references) { reference in
            if WebReference.validURL(reference.url) {
                VStack(alignment: .leading, spacing: 3) {
                    Link(reference.title.isEmpty ? reference.url.absoluteString : reference.title, destination: reference.url)
                    Text("\(reference.url.host ?? "") · 取得 \(reference.fetchedAt.formatted())")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AssistanceAnswerView: View {
    let answer: MeetingInsight
    let events: [TranscriptEvent]
    var research: ((String) -> Void)?
    @State private var reference: KnowledgeReference?
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(answer.kind.label) · 要確認").font(.caption).foregroundStyle(.secondary)
                ResearchAnswerText(answer: answer)
                ForEach(answer.evidenceIDs, id: \.self) { id in
                    if let event = events.first(where: { $0.id == id }) {
                        DisclosureGroup("発話 \(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)") {
                            Text(event.text).textSelection(.enabled)
                        }.font(.callout)
                    }
                }
                ForEach(answer.knowledgeReferences) { item in
                    Button("資料：\(item.displayTitle) · \(item.provenance)") { reference = item }.font(.caption)
                }
                WebReferencesView(references: answer.webReferences ?? [])
                if let research { Button("この提案をWebで調べる", systemImage: "globe") { research(answer.text) } }
            }
        }.sheet(item: $reference) { KnowledgeReferenceView(reference: $0, fontSize: 16) }
    }
}

struct WebResearchControls: View {
    @Bindable var research: WebResearchCoordinator
    let language: AnswerLanguage
    var enabled = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Webで調べる", systemImage: "globe") { research.open("") }.disabled(!enabled)
            ForEach(research.answers.reversed()) { answer in
                AssistanceAnswerView(answer: answer, events: research.store.finals,
                    research: enabled ? { research.open($0, evidenceIDs: answer.evidenceIDs) } : nil)
            }
        }
        .sheet(isPresented: $research.showsSheet, onDismiss: { research.cancel() }) {
            WebResearchView(research: research, language: language, enabled: enabled)
        }
    }
}

struct WebResearchView: View {
    @Bindable var research: WebResearchCoordinator
    let language: AnswerLanguage
    let enabled: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Webで調べる").font(.title2.bold())
                Spacer()
                Button("閉じる") { research.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("使用するLLM：\(research.settings.selected.destinationLabel)").font(.headline)
                    Text("設定済みLLMのWeb検索機能を使います。別の検索APIキーは不要です。モデル・契約によって利用できない場合があります。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("調べたいこと（2,000文字以内）", text: $research.draftQuery, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(3...6)
                    Text("質問、選択した発話または直近の確定発話（最大30件）、関連資料（最大5箇所）をLLMに送ります。LLMが検索語を決めるため、文脈が検索サービスに使われる可能性があります。音声は送りません。")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("回答に使う発話・資料を確認") {
                        ForEach(research.contextEvents.suffix(30)) { event in
                            Text("\(event.origin.label)：\(event.text)").font(.caption).textSelection(.enabled)
                        }
                        ForEach(research.knowledge.documents) { document in
                            Text(document.title).font(.caption)
                        }
                        Text("資料は質問と発話に関連する部分を選んで送ります。外部検索に使いたくない資料は外してから実行してください。")
                            .font(.caption)
                    }
                    Toggle("このセッションの発話・資料を使ったLLMのWeb調査を許可", isOn: Binding(
                        get: { research.permitted }, set: { research.setPermission($0) })).disabled(!research.supported)
                    HStack {
                        Text("調査 \(research.requestCount) / \(research.limit)回").font(.caption)
                        Stepper("上限", value: $research.limit, in: 1...200, step: 10).disabled(research.isBusy)
                    }
                    Text("1操作につきLLMへ1回要求し、60秒で打ち切ります。モデル内部の検索回数・追加料金はサービスに依存します。この上限は調査操作数で、検索回数や金額の上限ではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("LLMで調べる") {
                            let question = research.draftQuery
                            Task { await research.run(question: question, language: language) }
                        }.buttonStyle(.borderedProminent)
                            .disabled(!enabled || !research.canRun || !WebResearchCoordinator.validQuestion(research.draftQuery))
                        if research.isBusy { ProgressView().controlSize(.small); Button("調査を中断") { research.cancel() } }
                    }
                    Text(research.status).font(.callout).accessibilityLabel("Web調査状態：\(research.status)")
                    if research.state == .complete, let answer = research.answers.last {
                        AssistanceAnswerView(answer: answer, events: research.store.finals)
                    }
                }.padding(.trailing, 8)
            }
        }.padding(24).frame(minWidth: 480, idealWidth: 680, minHeight: 480, idealHeight: 720)
            .background(DesignTokens.canvas)
            .foregroundStyle(DesignTokens.text)
    }
}
