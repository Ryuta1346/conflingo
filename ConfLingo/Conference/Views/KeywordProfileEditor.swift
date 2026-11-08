import SwiftUI

struct KeywordProfileEditor: View {
    @Bindable var profiles: KeywordProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var renameText = ""
    @State private var renaming = false
    @State private var deleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("専門用語辞書").font(.title2.weight(.semibold))
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("使用する辞書", selection: Binding(
                get: { profiles.selectedID }, set: { profiles.select($0) }
            )) {
                ForEach(profiles.profiles) { Text($0.name).tag($0.id) }
            }
            HStack {
                Button("新規作成", systemImage: "plus") { profiles.addProfile(name: "新しい辞書") }
                Button("複製", systemImage: "doc.on.doc") { profiles.duplicate(profiles.selectedID) }
                Button("名前を変更", systemImage: "pencil") {
                    renameText = profiles.selectedProfile.name
                    renaming = true
                }
                Spacer()
                Button("削除", systemImage: "trash", role: .destructive) { deleting = true }
                    .disabled(profiles.profiles.count <= 1)
            }
            Text("専門用語・固定訳語").font(.headline)
            TextEditor(text: Binding(
                get: { profiles.selectedProfile.keywords },
                set: { profiles.updateSelectedKeywords($0) }
            ))
            .font(.body)
            .padding(8)
            .frame(minHeight: 150, maxHeight: 240)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.border))
            .accessibilityLabel("専門用語・固定訳語")
            Text("カンマ・読点・改行で区切ります。例：evals=評価。訳語を省略すると原文表記を保持します。変更は自動保存され、次回の開始から適用されます。")
                .font(.callout).foregroundStyle(DesignTokens.secondary)
        }
        .padding(28)
        .frame(width: 580)
        .background(DesignTokens.canvas)
        .alert("辞書の名前を変更", isPresented: $renaming) {
            TextField("名前", text: $renameText)
            Button("キャンセル", role: .cancel) {}
            Button("変更") { profiles.rename(profiles.selectedID, to: renameText) }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("「\(profiles.selectedProfile.name)」を削除しますか？", isPresented: $deleting) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { profiles.delete(profiles.selectedID) }
        } message: {
            Text("この辞書の用語を削除します。他の辞書や現在の字幕は残ります。")
        }
    }
}
