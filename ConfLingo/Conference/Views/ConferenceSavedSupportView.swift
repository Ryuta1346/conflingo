import SwiftUI

struct ConferenceSavedSupportView: View {
    let support: ConferenceSupportSnapshot
    let fontSize: Double
    @State private var reference: KnowledgeReference?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !support.answers.isEmpty { Text("資料へのAI質問 · 要確認").font(.title3.bold()) }
            ForEach(support.answers) { answer in
                Text(answer.text).font(.system(size: fontSize)).textSelection(.enabled)
                citations(answer.knowledgeReferences)
            }
            if !support.corrections.isEmpty { Text("採用した資料参照補正").font(.title3.bold()) }
            ForEach(support.corrections) { correction in
                Surface {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("元の原文").font(.caption)
                        Text(correction.original.sourceText).textSelection(.enabled)
                        Text("採用した原文").font(.caption)
                        Text(correction.sourceText).font(.system(size: fontSize)).textSelection(.enabled)
                        if let original = correction.original.translation { Text("元の訳文：\(original)").textSelection(.enabled) }
                        if let translated = correction.translation { Text(translated).font(.system(size: fontSize)).textSelection(.enabled) }
                        citations(correction.references)
                    }
                }
            }
            if !support.terms.isEmpty {
                DisclosureGroup("適用用語（\(support.terms.count)語）") {
                    ForEach(Array(support.terms.enumerated()), id: \.offset) { _, term in
                        Text("\(term.term)\(term.target.map { " = " + $0 } ?? "") · \(term.documentTitle) · \(term.line)行").font(.caption)
                    }
                }
            }
        }.sheet(item: $reference) { KnowledgeReferenceView(reference: $0, fontSize: fontSize) }
    }
    private func citations(_ references: [KnowledgeReference]) -> some View {
        ForEach(references) { item in
            Button("\(item.displayTitle) · \(item.provenance)") { reference = item }.font(.caption)
        }
    }
}
