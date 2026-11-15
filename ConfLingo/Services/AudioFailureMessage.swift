import Foundation

enum AudioFailureMessage {
    static func transcription(_ error: any Error, origin: AudioOrigin?) -> UserMessage {
        let prefix = origin.map { "\($0.label)：" } ?? ""
        if error as? AudioSourceError == .permissionDenied {
            let guidance = origin == .systemAudio
                ? "システム設定 > プライバシーとセキュリティ > 画面収録とシステムオーディオ録音でConfLingoを許可してください。変更後はアプリの再起動が必要な場合があります。"
                : "システム設定 > プライバシーとセキュリティ > マイク で ConfLingo を許可してください。"
            return UserMessage(.failure, "\(prefix)音声入力へのアクセスが許可されていません。\(guidance)")
        }
        if error as? TranscriptEventHub.Failure == .overflow {
            return UserMessage(.failure, "\(prefix)字幕の処理が追いつかないため入力を停止します。最後の発話が欠けている可能性があります。")
        }
        return diagnostic(error, summary: "\(prefix)文字起こしを継続できません。入力設定を確認して、もう一度開始してください。確定済みの発話は保持しています。")
    }

    static func diagnostic(_ error: any Error, summary: String) -> UserMessage {
        let guidance: String?
        switch error {
        case let error as AudioSourceError: guidance = error.errorDescription
        case let error as AudioCaptureError: guidance = error.errorDescription
        case let error as SystemAudioCaptureError: guidance = error.errorDescription
        case let error as TranscriptionError: guidance = error.errorDescription
        case let error as VocabularyFailure: guidance = error.errorDescription
        default: guidance = nil
        }
        if let guidance { return UserMessage(.failure, summary + " " + guidance) }
        return UserMessage(.failure, summary, details: error.localizedDescription)
    }
}
