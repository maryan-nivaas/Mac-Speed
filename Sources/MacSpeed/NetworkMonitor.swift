import Darwin
import Foundation

// Reads the kernel's per-interface 64-bit byte counters and turns successive
// readings into a download/upload rate. No packet inspection, no network
// access of its own — it only reads aggregate totals macOS already keeps.
final class NetworkMonitor {

    struct Sample {
        var inBytes: UInt64
        var outBytes: UInt64
        var time: Date
    }

    private var previous: Sample?

    struct Rate {
        var downBytesPerSec: Double
        var upBytesPerSec: Double
    }

    // Sum the in/out byte counters across all active, non-loopback interfaces.
    private func readCounters() -> (inBytes: UInt64, outBytes: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        let m2size = MemoryLayout<if_msghdr2>.stride

        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + 4 <= len {
                let msglen = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                let type = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
                if msglen == 0 { break }
                if Int32(type) == RTM_IFINFO2, offset + m2size <= len {
                    let m2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = m2.ifm_flags
                    let isUp = (flags & IFF_UP) != 0
                    let isLoopback = (flags & IFF_LOOPBACK) != 0
                    if isUp && !isLoopback {
                        totalIn += m2.ifm_data.ifi_ibytes
                        totalOut += m2.ifm_data.ifi_obytes
                    }
                }
                offset += msglen
            }
        }
        return (totalIn, totalOut)
    }

    // Returns the rate since the previous call, or nil on the very first call
    // (we need two readings to compute a delta).
    func tick() -> Rate? {
        guard let counters = readCounters() else { return nil }
        let now = Sample(inBytes: counters.inBytes, outBytes: counters.outBytes, time: Date())
        defer { previous = now }

        guard let prev = previous else { return nil }
        let elapsed = now.time.timeIntervalSince(prev.time)
        guard elapsed > 0 else { return nil }

        // Counters only ever increase; if they drop (interface removed/reset),
        // treat that direction's delta as zero rather than a huge number.
        let down = now.inBytes >= prev.inBytes ? Double(now.inBytes - prev.inBytes) : 0
        let up = now.outBytes >= prev.outBytes ? Double(now.outBytes - prev.outBytes) : 0

        return Rate(downBytesPerSec: down / elapsed, upBytesPerSec: up / elapsed)
    }

    func reset() { previous = nil }
}
