import Foundation
import Darwin

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    return info.resident_size
}

@main struct MemoryProbe {
    @MainActor static func main() {
        let store = SessionStore()
        for index in 0..<30_000 {
            let id = store.appendFinal("Synthetic sentence \(index).")!
            let unit = store.bufferSegment(id)!
            store.applyTranslation(id: unit.id, japanese: "合成字幕 \(index)")
        }
        let before = residentBytes()
        precondition(TranscriptPresentation.source(store).count == 30_000)
        precondition(TranscriptPresentation.translation(store).count == 30_000)
        let cached = residentBytes()
        weak var source = store.transcriptCache.source
        weak var translation = store.transcriptCache.translation
        for index in 0..<1_000 {
            store.updateVolatile("Partial \(index)")
            precondition(TranscriptPresentation.source(store).history === source)
            precondition(TranscriptPresentation.translation(store).history === translation)
        }
        let afterUpdates = residentBytes()
        store.reset()
        precondition(source == nil && translation == nil)
        print("rows,before_cache_bytes,after_cache_bytes,after_1000_updates_bytes,after_reset_bytes")
        print("30000,\(before),\(cached),\(afterUpdates),\(residentBytes())")
    }
}
