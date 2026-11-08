import AVFAudio
import CoreMedia
import ScreenCaptureKit
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct SystemAudioPCMTests {
    @Test func capturedSamplesAreOwnedAndOrdered() async throws {
        let format = try makeFormat()
        let output = SystemAudioFrameOutput(targetFormat: format)
        let original = try makeBuffer([0.25, -0.5], format: format)
        let sample = try makeSample(original)
        output.receive(sample)
        original.floatChannelData?[0][0] = 1
        output.receive(try makeSample(makeBuffer([0.75], format: format)))
        output.finish()
        var values: [[Float]] = []
        for try await frame in output.frames { values.append(samples(frame.buffer)) }
        #expect(values == [[0.25, -0.5], [0.75]])
    }

    @Test func resamplesStereoToAnalyzerFormat() async throws {
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_800))
        input.frameLength = 4_800
        for channel in 0..<2 {
            let data = try #require(input.floatChannelData?[channel])
            for index in 0..<4_800 { data[index] = 0.25 }
        }
        let target = try makeFormat()
        let output = SystemAudioFrameOutput(targetFormat: target)
        output.receive(try makeSample(input))
        output.finish()
        var frames = 0
        var peak: Float = 0
        for try await frame in output.frames {
            #expect(frame.buffer.format == target)
            frames += Int(frame.buffer.frameLength)
            peak = max(peak, samples(frame.buffer).map(abs).max() ?? 0)
        }
        #expect(frames > 1_000 && frames <= 1_600)
        #expect(peak > 0.1 && peak < 0.5)
    }

    @Test func overflowFailsInsteadOfSilentlyDroppingAudio() async throws {
        let format = try makeFormat()
        let output = SystemAudioFrameOutput(targetFormat: format, capacity: 1)
        let sample = try makeSample(makeBuffer([0.5], format: format))
        output.receive(sample)
        output.receive(sample)
        await #expect(throws: SystemAudioCaptureError.overflow) {
            for try await _ in output.frames {}
        }
    }

    @Test func normalStopFlushesResamplerTail() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let input = try makeBuffer(Array(repeating: Float(0.25), count: 4_800), format: format)
        let output = SystemAudioFrameOutput(targetFormat: try makeFormat())
        output.receive(try makeSample(input))
        output.finish()
        var count = 0
        for try await frame in output.frames { count += Int(frame.buffer.frameLength) }
        #expect(count == 1_600)
    }

    @Test func formatChangeFlushesPreviousFormatBeforeNewSamples() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let target = try makeFormat()
        let output = SystemAudioFrameOutput(targetFormat: target)
        output.receive(try makeSample(makeBuffer(Array(repeating: Float(0.25), count: 4_800), format: format)))
        output.receive(try makeSample(makeBuffer([0.75], format: target)))
        output.finish()
        var values: [Float] = []
        for try await frame in output.frames { values += samples(frame.buffer) }
        #expect(values.count == 1_601)
        #expect(values.last == 0.75)
    }

    @Test func emptyAudioIsIgnoredWithoutEndingTheStream() async throws {
        let format = try makeFormat()
        let input = try makeBuffer([0], format: format)
        input.frameLength = 0
        let output = SystemAudioFrameOutput(targetFormat: format)
        output.receive(try makeSample(input))
        output.receive(try makeSample(makeBuffer([0.5], format: format)))
        output.finish()
        var values: [Float] = []
        for try await frame in output.frames { values += samples(frame.buffer) }
        #expect(values == [0.5])
    }

    @Test func invalidSampleFailsAndLateSamplesAreIgnored() async throws {
        let format = try makeFormat()
        let output = SystemAudioFrameOutput(targetFormat: format)
        let sample = try makeSample(makeBuffer([0.5], format: format))
        CMSampleBufferInvalidate(sample)
        output.receive(sample)
        output.receive(try makeSample(makeBuffer([1], format: format)))
        await #expect(throws: SystemAudioCaptureError.invalidPCM) {
            for try await _ in output.frames { Issue.record("Invalid sample was accepted") }
        }
    }

    @Test func silentAudioIsValidAndStopRejectsLateFrames() async throws {
        let format = try makeFormat()
        let output = SystemAudioFrameOutput(targetFormat: format)
        output.receive(try makeSample(makeBuffer([0, 0], format: format)))
        output.finish()
        output.receive(try makeSample(makeBuffer([1], format: format)))
        var values: [Float] = []
        for try await frame in output.frames { values += samples(frame.buffer) }
        #expect(values == [0, 0])
    }

    @Test @MainActor func backendConfiguresOnlyInternalAudioAndRetainsFailedStopForRetry() async throws {
        let driver = StubScreenStream()
        let capture = ScreenCaptureAudioCapture { config, _ in
            #expect(config.capturesAudio)
            #expect(config.excludesCurrentProcessAudio)
            #expect(!config.captureMicrophone)
            return driver
        }
        _ = try await capture.start(targetFormat: makeFormat())
        #expect(driver.starts == 1)
        driver.failStop = true
        await #expect(throws: StubSystemCapture.Failure.stop) { try await capture.stop() }
        driver.failStop = false
        try await capture.stop()
        try await capture.stop()
        #expect(driver.stops == 2)
    }

    @Test @MainActor func failedOSStartCanBeRetriedWhenOSAlreadyStopped() async throws {
        let driver = StubScreenStream()
        driver.failStart = true
        driver.alreadyStopped = true
        let capture = ScreenCaptureAudioCapture { _, _ in driver }
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        await #expect(throws: StubSystemCapture.Failure.start) { try await source.start(targetFormat: makeFormat()) }
        #expect(source.state == .idle)
        driver.failStart = false
        driver.alreadyStopped = false
        _ = try await source.start(targetFormat: makeFormat())
        try await source.stop()
        #expect(driver.starts == 2)
    }

    @Test @MainActor func factoryFailureReleasesOutputAndAllowsRetry() async throws {
        let driver = StubScreenStream()
        driver.unavailable = true
        let capture = ScreenCaptureAudioCapture { _, _ in
            if driver.unavailable { throw SystemAudioCaptureError.noDisplay }
            return driver
        }
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        await #expect(throws: SystemAudioCaptureError.noDisplay) { try await source.start(targetFormat: makeFormat()) }
        #expect(source.state == .idle)
        driver.unavailable = false
        _ = try await source.start(targetFormat: makeFormat())
        try await source.stop()
        #expect(driver.starts == 1)
    }
}

@MainActor
final class StubScreenStream: ScreenAudioStreaming {
    var starts = 0
    var stops = 0
    var failStop = false
    var unavailable = false
    var failStart = false
    var alreadyStopped = false
    func startCapture() async throws {
        starts += 1
        if failStart { throw StubSystemCapture.Failure.start }
    }
    func stopCapture() async throws {
        stops += 1
        if alreadyStopped { throw SCStreamError(.attemptToStopStreamState) }
        if failStop { throw StubSystemCapture.Failure.stop }
    }
}

func makeSample(_ buffer: AVAudioPCMBuffer) throws -> CMSampleBuffer {
    var description: CMAudioFormatDescription?
    var asbd = buffer.format.streamDescription.pointee
    let status = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description
    )
    #expect(status == noErr)
    let format = try #require(description)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
        presentationTimeStamp: .zero, decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    #expect(CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
        sampleCount: Int(buffer.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
    ) == noErr)
    let result = try #require(sample)
    if buffer.frameLength > 0 {
        #expect(CMSampleBufferSetDataBufferFromAudioBufferList(
            result, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: buffer.audioBufferList
        ) == noErr)
    }
    #expect(CMSampleBufferSetDataReady(result) == noErr)
    return result
}
