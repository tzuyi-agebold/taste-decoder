import Foundation

/// A stable content hash for a synced row: if it changes, the row needs uploading.
/// FNV-1a (64-bit) over the fields — stable across launches and platforms, unlike `Hasher`.
enum SyncFingerprint {
    static func hash(_ fields: [String?]) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for (index, field) in fields.enumerated() {
            // A separator plus a nil marker keeps ["a", nil] distinct from [nil, "a"] and ["a", ""].
            let token = (index == 0 ? "" : "\u{1F}") + (field.map { "=" + $0 } ?? "\u{0}")
            for byte in token.utf8 {
                value ^= UInt64(byte)
                value = value &* 0x0000_0100_0000_01b3
            }
        }
        return String(value, radix: 16)
    }

    /// Dates rounded to milliseconds so a value that went through the server compares equal.
    static func field(_ date: Date?) -> String? {
        date.map { String(Int64((($0.timeIntervalSince1970) * 1000).rounded())) }
    }

    static func field(_ int: Int) -> String { String(int) }
}
