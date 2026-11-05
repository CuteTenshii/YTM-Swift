//
//  VolumeNormalization.swift
//  YT Music
//

import Foundation

/// Tracks louder than the reference are turned down to it; quieter ones are left alone.
nonisolated enum VolumeNormalization {
    static func gain(loudnessDb: Double?) -> Double {
        guard let loudnessDb, loudnessDb > 0 else { return 1 }
        return pow(10, -loudnessDb / 20)
    }
}
