import Foundation
import Observation

@MainActor
@Observable
final class AudioInputUse {
    enum Owner: String {
        case conference = "Conference"
        case systemAudioProbe = "システム音声の確認"
        case dualTranscription = "2入力文字起こしの確認"
    }

    private(set) var owner: Owner?
    private var token: UUID?

    var busyMessage: String {
        "「\(owner?.rawValue ?? "別の画面")」が音声入力を使用中です。停止してから開始してください。"
    }

    func acquire(_ owner: Owner) -> UUID? {
        guard self.owner == nil else { return nil }
        let token = UUID()
        self.token = token
        self.owner = owner
        return token
    }

    func release(_ token: UUID?) {
        guard let token, self.token == token else { return }
        self.token = nil
        owner = nil
    }
}
