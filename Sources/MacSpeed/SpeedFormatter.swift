import Foundation

// Turns a bytes-per-second value into a readable, fixed-width string so the
// menu bar text stays aligned and doesn't jitter as numbers change.
enum SpeedFormatter {

    // Decimal (1000-based) scaling, matching how network speeds are usually
    // quoted. Returns the number and unit separately so the caller can pad.
    static func parts(_ bytesPerSec: Double) -> (number: String, unit: String) {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSec, 0)
        var index = 0
        while value >= 1000 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let number: String
        if index == 0 {
            number = String(format: "%.0f", value)   // whole bytes
        } else {
            number = String(format: "%.2f", value)    // KB/s and up
        }
        return (number, units[index])
    }

    // Pads number to the right and unit to the left so columns line up in a
    // monospaced font.
    static func padded(_ bytesPerSec: Double) -> String {
        let p = parts(bytesPerSec)
        let number = p.number.leftPadded(to: 6)
        let unit = p.unit.rightPadded(to: 4)
        return number + " " + unit
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
    func rightPadded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
