//
//  EqualizerTap.swift
//  YT Music
//
//  Installs an MTAudioProcessingTap that runs EqualizerProcessor over each item's audio.
//

import AVFoundation
import CoreMedia

/// Returns nil when there is no audio track or the tap can't be created.
@MainActor
func makeEqualizerAudioMix(for track: AVAssetTrack, processor: EqualizerProcessor) -> AVAudioMix? {
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        // Retained for the tap's lifetime; tapFinalize releases it.
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(processor).toOpaque()),
        `init`: tapInit,
        finalize: tapFinalize,
        prepare: tapPrepare,
        unprepare: nil,
        process: tapProcess
    )

    var tap: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks,
        kMTAudioProcessingTapCreationFlag_PostEffects, &tap
    )
    guard status == noErr, let tap else {
        // Balance the passRetained when tap creation fails.
        Unmanaged<EqualizerProcessor>.fromOpaque(callbacks.clientInfo!).release()
        return nil
    }

    let parameters = AVMutableAudioMixInputParameters(track: track)
    parameters.audioTapProcessor = tap
    let mix = AVMutableAudioMix()
    mix.inputParameters = [parameters]
    return mix
}

// MARK: - Tap callbacks (realtime audio thread)
//
// These must be plain C function pointers, so they're `nonisolated` to opt out
// of the module's default `@MainActor` isolation (an actor-isolated function
// can't be converted to `@convention(c)`).

private nonisolated func tapInit(tap: MTAudioProcessingTap,
                                 clientInfo: UnsafeMutableRawPointer?,
                                 tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    // C callbacks can't capture; carry the retained processor via tap storage.
    tapStorageOut.pointee = clientInfo
}

private nonisolated func tapFinalize(tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<EqualizerProcessor>.fromOpaque(storage).release()
}

private nonisolated func tapPrepare(tap: MTAudioProcessingTap,
                                    maxFrames: CMItemCount,
                                    processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    let processor = Unmanaged<EqualizerProcessor>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let asbd = processingFormat.pointee
    processor.prepare(sampleRate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame))
}

private nonisolated func tapProcess(tap: MTAudioProcessingTap,
                                    numberFrames: CMItemCount,
                                    flags: MTAudioProcessingTapFlags,
                                    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                                    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                                    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    guard status == noErr else { return }

    let processor = Unmanaged<EqualizerProcessor>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let frames = Int(numberFramesOut.pointee)
    guard frames > 0 else { return }

    let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    if buffers.count > 1 {
        for channel in 0..<buffers.count {
            guard let data = buffers[channel].mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            processor.processPlanar(samples, frames: frames, channel: channel)
        }
    } else if let buffer = buffers.first, let data = buffer.mData {
        // Interleaved: one buffer with mNumberChannels channels per frame.
        let channels = Int(buffer.mNumberChannels)
        let samples = data.assumingMemoryBound(to: Float.self)
        if channels <= 1 {
            processor.processPlanar(samples, frames: frames, channel: 0)
        } else {
            processor.processInterleaved(samples, frames: frames, channels: channels)
        }
    }
}
