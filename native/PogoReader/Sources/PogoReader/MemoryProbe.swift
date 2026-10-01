import Foundation
#if os(iOS)
import os
#endif

/// Memory figures for the extension. `phys_footprint` is the number iOS enforces the extension's
/// limit on (about 50 MB for a broadcast upload extension); `os_proc_available_memory()` is what
/// iOS says is left before that limit (iOS only).
public final class MemoryProbe {
    public private(set) var peakBytes: Int = 0
    /// The lowest `os_proc_available_memory()` seen (iOS only; nil elsewhere).
    public private(set) var lowestAvailableBytes: Int?

    public init() {}

    /// Current physical footprint in bytes (0 if the kernel call fails).
    public static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Bytes iOS says this process may still allocate; nil off iOS.
    public static func availableBytes() -> Int? {
        #if os(iOS)
        return Int(os_proc_available_memory())
        #else
        return nil
        #endif
    }

    /// Read the footprint now and fold it into the running peak (and the lowest available figure).
    @discardableResult
    public func sample() -> Int {
        let now = MemoryProbe.footprintBytes()
        if now > peakBytes { peakBytes = now }
        if let a = MemoryProbe.availableBytes(), lowestAvailableBytes == nil || a < lowestAvailableBytes! { lowestAvailableBytes = a }
        return now
    }

    public func resetPeak() { peakBytes = MemoryProbe.footprintBytes(); lowestAvailableBytes = nil }

    public static func megabytes(_ bytes: Int) -> Double { Double(bytes) / 1_048_576 }
}
