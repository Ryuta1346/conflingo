import Foundation

enum SessionMode: String, CaseIterable {
    case transcription
    case translation

    var label: String {
        switch self {
        case .transcription: "文字起こし"
        case .translation: "リアルタイム翻訳"
        }
    }

    func translationTarget(source: String, target: String) -> String? {
        guard self == .translation, !target.isEmpty,
              Locale.Language(identifier: source).minimalIdentifier != Locale.Language(identifier: target).minimalIdentifier else { return nil }
        return target
    }
}
