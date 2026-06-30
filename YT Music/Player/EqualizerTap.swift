//
//  EqualizerTap.swift
//  YT Music
//
//  Bridges the (pure) EqualizerProcessor into AVPlayer playback via an
//  MTAudioProcessingTap. AVPlayer has no built-in EQ, so we install an audio
//  tap on the item's audio track: the tap's `process` callback fires on a
//  realtime audio thread with the decoded PCM, which we filter in place before
//  it reaches the output.
//
//  The C-style callbacks can't capture Swift context, so the processor is passed
//  through the tap's storage as a retained pointer (released in `finalize`).
//

import AVFoundation
import CoreMedia

/// Builds an `AVAudioMix` that runs `processor` over the item's first audio
/// track. Returns nil if no audio track is available or the tap can't be
/// created (in which case playback proceeds un-equalized).
@MainActor
func makeEqualizerAudioMix(for track: AVAssetTrack, processor: EqualizerProcessor) -> AVAudioMix? {
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        // Retain the processor for the tap's lifetime; tapFinalize releases it.
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
        // Balance the passRetained above if tap creation failed.
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
    // Carry the retained processor pointer over into the tap's storage.
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
        // Planar / non-interleaved: one buffer per channel.
        for channel in 0..<buffers.count {
            guard let data = buffers[channel].mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            processor.processPlanar(samples, frames: frames, channel: channel)
        }
    } else if let buffer = buffers.first, let data = buffer.mData {
        // Interleaved: a single buffer with mNumberChannels channels per frame.
        let channels = Int(buffer.mNumberChannels)
        let samples = data.assumingMemoryBound(to: Float.self)
        if channels <= 1 {
            processor.processPlanar(samples, frames: frames, channel: 0)
        } else {
            processor.processInterleaved(samples, frames: frames, channels: channels)
        }
    }
}
