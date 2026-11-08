import AVFAudio
import CoreMedia
import Foundation
import ScreenCaptureKit

enum SystemAudioCaptureError: LocalizedError {
    case noDisplay, invalidPCM, conversionFailed, overflow

    var errorDescription: String? {
        switch self {
        case .noDisplay: "音声取得の基準となるディスプレイが見つかりません。"
        case .invalidPCM: "内部音声のデータを読み取れませんでした。入力を停止します。"
        case .conversionFailed: "内部音声を必要な形式へ変換できませんでした。"
        case .overflow: "内部音声の処理が追いつかないため入力を停止しました。"
        }
    }
}

/// Audio callbacks and the stream delegate can arrive on different queues.
/// The lock serializes conversion, termination, and all mutable state; frames own their PCM.
final class SystemAudioFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames: AudioFrameStream
    private let continuation: AudioFrameStream.Continuation
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var ended = false
    private var systemStopped = false
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    var wasStoppedBySystem: Bool { lock.withLock { systemStopped } }

    init(targetFormat: AVAudioFormat, capacity: Int = 256) {
        self.targetFormat = targetFormat
        let pair = AudioFrameStream.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        frames = pair.stream
        continuation = pair.continuation
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        receive(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock {
            systemStopped = true
            end(throwing: error)
        }
    }

    func receive(_ sample: CMSampleBuffer) {
        lock.withLock {
            guard !ended else { return }
            do {
                guard let pcm = try copyPCM(sample), let converted = try convert(pcm) else { return }
                try publish(converted)
            } catch {
                end(throwing: error)
            }
        }
    }

    func finish() {
        lock.withLock {
            guard !ended else { return }
            do {
                try flushConverter()
                end(throwing: nil)
            } catch {
                end(throwing: error)
            }
        }
    }

    private func publish(_ buffer: AVAudioPCMBuffer) throws {
        guard let frame = AudioFrame(copying: buffer) else { throw SystemAudioCaptureError.invalidPCM }
        switch continuation.yield(frame) {
        case .dropped: end(throwing: SystemAudioCaptureError.overflow)
        case .terminated: end(throwing: nil)
        case .enqueued: break
        @unknown default: end(throwing: SystemAudioCaptureError.overflow)
        }
    }

    private func flushConverter() throws {
        guard let converter else { return }
        while !ended {
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4_096) else {
                throw SystemAudioCaptureError.conversionFailed
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in
                status.pointee = .endOfStream
                return nil
            }
            guard status != .error, error == nil else { throw SystemAudioCaptureError.conversionFailed }
            if output.frameLength > 0 { try publish(output) }
            if status == .endOfStream || output.frameLength == 0 { return }
        }
    }

    private func end(throwing error: (any Error)?) {
        guard !ended else { return }
        ended = true
        converter = nil
        sourceFormat = nil
        continuation.finish(throwing: error)
    }

    private func copyPCM(_ sample: CMSampleBuffer) throws -> AVAudioPCMBuffer? {
        guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else {
            throw SystemAudioCaptureError.invalidPCM
        }
        let count = CMSampleBufferGetNumSamples(sample)
        if count == 0 { return nil }
        guard count > 0, count <= Int(Int32.max),
              let description = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
              CMFormatDescriptionGetMediaSubType(description) == kAudioFormatLinearPCM else {
            throw SystemAudioCaptureError.invalidPCM
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw SystemAudioCaptureError.invalidPCM
        }
        pcm.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList
        ) == noErr else { throw SystemAudioCaptureError.invalidPCM }
        return pcm
    }

    private func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        if sourceFormat != input.format {
            try flushConverter()
            guard !ended else { return nil }
            converter = nil
            sourceFormat = input.format
            if input.format == targetFormat { return input }
            guard let next = AVAudioConverter(from: input.format, to: targetFormat) else {
                throw SystemAudioCaptureError.conversionFailed
            }
            converter = next
        }
        if input.format == targetFormat { return input }
        guard let converter else { throw SystemAudioCaptureError.conversionFailed }
        let count = ceil(Double(input.frameLength) * targetFormat.sampleRate / input.format.sampleRate) + 16
        guard count > 0, count < Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(count)) else {
            throw SystemAudioCaptureError.conversionFailed
        }
        // AVAudioConverter invokes the input block synchronously within this locked conversion.
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let inputBuffer = input
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, error == nil else { throw SystemAudioCaptureError.conversionFailed }
        return output.frameLength > 0 ? output : nil
    }
}
