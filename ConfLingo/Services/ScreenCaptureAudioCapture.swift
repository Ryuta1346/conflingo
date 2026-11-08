import AVFAudio
import Foundation
import ScreenCaptureKit

@MainActor
protocol ScreenAudioStreaming: AnyObject {
    func startCapture() async throws
    func stopCapture() async throws
}

@MainActor
private final class ScreenAudioStream: ScreenAudioStreaming {
    private let stream: SCStream

    init(_ stream: SCStream) { self.stream = stream }
    func startCapture() async throws { try await stream.startCapture() }
    func stopCapture() async throws { try await stream.stopCapture() }
}

@MainActor
final class ScreenCaptureAudioCapture: SystemAudioCapturing {
    typealias StreamFactory = @MainActor (SCStreamConfiguration, SystemAudioFrameOutput) async throws -> any ScreenAudioStreaming
    private let makeStream: StreamFactory
    private var stream: (any ScreenAudioStreaming)?
    private var output: SystemAudioFrameOutput?
    private var started = false

    init(makeStream: @escaping StreamFactory = ScreenCaptureAudioCapture.makeSystemStream) {
        self.makeStream = makeStream
    }

    func start(targetFormat: AVAudioFormat) async throws -> AudioFrameStream {
        guard output == nil else { throw AudioSourceError.alreadyRunning }
        let output = SystemAudioFrameOutput(targetFormat: targetFormat)
        self.output = output
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // No screen output is attached. Keep unused video configuration inexpensive.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        do {
            let stream = try await makeStream(configuration, output)
            self.stream = stream
            try await stream.startCapture()
            started = true
            return output.frames
        } catch {
            output.finish()
            // SystemAudioSource owns cleanup, including a partially started stream.
            throw error
        }
    }

    func stop() async throws {
        output?.finish()
        if let stream, output?.wasStoppedBySystem != true {
            do {
                try await stream.stopCapture()
            } catch {
                // A failed start may leave no running OS stream to stop.
                guard !started, (error as? SCStreamError)?.code == .attemptToStopStreamState else { throw error }
            }
        }
        stream = nil
        output = nil
        started = false
    }

    private static func makeSystemStream(
        configuration: SCStreamConfiguration, output: SystemAudioFrameOutput
    ) async throws -> any ScreenAudioStreaming {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw SystemAudioCaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.gavrri.conflingo.system-audio"))
        return ScreenAudioStream(stream)
    }
}
