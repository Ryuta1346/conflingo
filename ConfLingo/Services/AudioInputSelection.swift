import Foundation
import SwiftUI

enum AudioInputSelection: String, CaseIterable, Identifiable, Sendable {
    case microphone, systemAudio, both
    var id: Self { self }
    var label: String {
        switch self {
        case .microphone: "マイク・外部入力"
        case .systemAudio: "Macの内部音声"
        case .both: "マイク・外部入力 ＋ 内部音声"
        }
    }
    var origins: Set<AudioOrigin> {
        switch self {
        case .microphone: [.microphone]
        case .systemAudio: [.systemAudio]
        case .both: [.microphone, .systemAudio]
        }
    }
}

struct AudioInputPicker: View {
    @Binding var selection: AudioInputSelection
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("音声入力", selection: $selection) {
                ForEach(AudioInputSelection.allCases) { Text($0.label).tag($0) }
            }
            Text("マイク・外部入力はMacのシステム設定で選択した入力機器を使います。内部音声はこのアプリを除くMac全体の再生音です。")
                .font(.caption).foregroundStyle(.secondary)
            if selection == .both {
                Text("スピーカーの音がマイクにも入る場合は、ヘッドフォンを使うと重複を抑えられます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
