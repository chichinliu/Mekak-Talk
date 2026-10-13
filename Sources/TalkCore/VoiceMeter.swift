import Foundation

/// Maps the microphone level (0...1 on a 55 dB scale) to bar heights for the
/// recording capsule, so room noise stays flat and speech swings visibly.
public enum VoiceMeter {
    /// Levels below the noise floor read as silence; speech is expanded across the full height.
    public static func display(level: Double) -> Double {
        let gated = (min(1, max(0, level)) - 0.3) / 0.45
        return gated <= 0 ? 0 : pow(min(1, gated), 1.2)
    }

    /// A stable per-sample variation, so a steady voice still looks alive rather than a flat row.
    public static func jitter(sample: Int) -> Double {
        var hash = UInt64(truncatingIfNeeded: sample) &* 0x9E37_79B9_7F4A_7C15
        hash ^= hash >> 29
        return 0.62 + Double(hash % 1000) / 1000 * 0.5
    }
}
