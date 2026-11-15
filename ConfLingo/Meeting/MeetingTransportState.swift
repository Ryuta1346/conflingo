import Accessibility
import Foundation
import Observation
import SwiftUI

enum MeetingTransportStatus {
    case ready, preparing, listening, paused, ended, stopping, stopFailed, interrupted

    var text: String {
        switch self {
        case .ready: "開始前"
        case .preparing: "準備中"
        case .listening: "取得中"
        case .paused: "一時停止"
        case .ended: "終了"
        case .stopping: "停止中"
        case .stopFailed: "停止未完了"
        case .interrupted: "停止・要確認"
        }
    }
    var symbol: String {
        switch self {
        case .ready: "circle"
        case .preparing, .stopping: "hourglass"
        case .listening: "waveform"
        case .paused: "pause.circle"
        case .ended: "stop.circle"
        case .stopFailed, .interrupted: "exclamationmark.triangle"
        }
    }
    var color: Color {
        switch self {
        case .listening: DesignTokens.positive
        case .stopFailed, .interrupted: DesignTokens.danger
        default: DesignTokens.secondary
        }
    }
}

extension MeetingWorkspace {
    var transportStatus: MeetingTransportStatus {
        if page == .review { return .ended }
        switch phase {
        case .preparing: return .preparing
        case .listening: return .listening
        case .stopping: return isBusy ? .stopping : .stopFailed
        case .idle:
            if isTransitioning { return .stopping }
            if isStarting { return .preparing }
            if controller.failure != nil { return .interrupted }
            return startedAt == nil ? .ready : .paused
        }
    }

    var displayedInputOrigins: [AudioOrigin] {
        [AudioOrigin.microphone, .systemAudio].filter {
            inputSelection.origins.contains($0) || controller.inputState($0) != .idle
        }
    }
}

/// Owned by the workspace, so opening another window never duplicates an announcement.
@MainActor
final class MeetingStatusAnnouncements {
    private let post: @MainActor (String) -> Void
    private var previous: MeetingTransportStatus?

    init(post: @escaping @MainActor (String) -> Void) { self.post = post }

    static func post(_ text: String) { AccessibilityNotification.Announcement(text).post() }

    func observe(_ meeting: MeetingWorkspace) {
        let status = withObservationTracking {
            meeting.transportStatus
        } onChange: { [weak self, weak meeting] in
            Task { @MainActor in
                guard let self, let meeting else { return }
                self.observe(meeting)
            }
        }
        if let previous, previous != status { post("会議：\(status.text)") }
        previous = status
    }
}
