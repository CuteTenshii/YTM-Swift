//
//  MilkdropVisualizerView.swift
//  YT Music
//
//  MilkDrop-style Metal feedback visualizer driven by the shared SpectrumAnalyzer.
//

import MetalKit
import QuartzCore
import SwiftUI

struct MilkdropVisualizerView: NSViewRepresentable {
    let analyzer: SpectrumAnalyzer?
    var colors: [PaletteColor]

    func makeCoordinator() -> MilkdropRenderer {
        MilkdropRenderer(analyzer: analyzer)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        context.coordinator.colors = colors
        context.coordinator.setup(view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.colors = colors
    }
}

final class MilkdropRenderer: NSObject, MTKViewDelegate {
    // Must match the bands the analyzer publishes; the shader indexes this many.
    private static let bandCount = 28

    private let analyzer: SpectrumAnalyzer?
    var colors: [PaletteColor] = []

    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var feedbackPipeline: MTLRenderPipelineState?
    private var presentPipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?

    private var front: MTLTexture?
    private var back: MTLTexture?

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var bass: Float = 0, mid: Float = 0, treb: Float = 0
    private var ready = false

    private let presets = MilkdropPreset.all
    private let cycleSeconds: Float = 20
    private let blendSeconds: Float = 5

    init(analyzer: SpectrumAnalyzer?) {
        self.analyzer = analyzer
    }

    // MARK: - Setup

    func setup(_ view: MTKView) {
        guard let device = view.device,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return }
        self.device = device
        self.queue = queue

        func pipeline(fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
            desc.fragmentFunction = library.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = format
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        feedbackPipeline = pipeline(fragment: "milkdrop_feedback", format: .rgba16Float)
        presentPipeline = pipeline(fragment: "milkdrop_present", format: view.colorPixelFormat)

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)

        startTime = CACurrentMediaTime()
        ready = feedbackPipeline != nil && presentPipeline != nil && sampler != nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        allocateTextures(width: Int(size.width), height: Int(size.height))
    }

    private func allocateTextures(width: Int, height: Int) {
        guard let device, width > 0, height > 0 else { front = nil; back = nil; return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private
        front = device.makeTexture(descriptor: desc)
        back = device.makeTexture(descriptor: desc)
        clear(front)
        clear(back)
    }

    /// A fresh texture's contents are undefined; the first frame would sample garbage.
    private func clear(_ texture: MTLTexture?) {
        guard let texture, let queue, let cb = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        cb.commit()
    }

    // MARK: - Frame

    func draw(in view: MTKView) {
        guard ready, let queue, let feedbackPipeline, let presentPipeline, let sampler,
              let front, let back, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }

        var bandValues = paddedBands()
        updateEnergies(bandValues)
        var uniforms = makeUniforms(aspect: Float(view.drawableSize.width /
                                                  max(1, view.drawableSize.height)))

        let fb = MTLRenderPassDescriptor()
        fb.colorAttachments[0].texture = front
        fb.colorAttachments[0].loadAction = .dontCare
        fb.colorAttachments[0].storeAction = .store
        if let enc = cb.makeRenderCommandEncoder(descriptor: fb) {
            enc.setRenderPipelineState(feedbackPipeline)
            enc.setFragmentTexture(back, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<MilkdropUniforms>.stride, index: 0)
            enc.setFragmentBytes(&bandValues, length: MemoryLayout<Float>.stride * bandValues.count, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        if let pass = view.currentRenderPassDescriptor,
           let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
            enc.setRenderPipelineState(presentPipeline)
            enc.setFragmentTexture(front, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        cb.present(drawable)
        cb.commit()

        self.front = back
        self.back = front
    }

    // MARK: - Audio → uniforms

    private func paddedBands() -> [Float] {
        let m = analyzer?.magnitudes() ?? []
        if m.count == Self.bandCount { return m }
        var out = [Float](repeating: 0, count: Self.bandCount)
        for i in 0..<min(m.count, Self.bandCount) { out[i] = m[i] }
        return out
    }

    private func updateEnergies(_ bands: [Float]) {
        func avg(_ range: Range<Int>) -> Float {
            let clamped = range.clamped(to: 0..<bands.count)
            guard !clamped.isEmpty else { return 0 }
            return bands[clamped].reduce(0, +) / Float(clamped.count)
        }
        let third = max(1, Self.bandCount / 3)
        func gained(_ v: Float) -> Float { min(1, v * 1.8) }
        bass = bass * 0.55 + gained(avg(0..<third)) * 0.45
        mid  = mid  * 0.6  + gained(avg(third..<(2 * third))) * 0.4
        treb = treb * 0.6  + gained(avg((2 * third)..<Self.bandCount)) * 0.4
    }

    private func makeUniforms(aspect: Float) -> MilkdropUniforms {
        let t = Float(CACurrentMediaTime() - startTime)
        let preset = currentPreset(at: t)
        return MilkdropUniforms(
            time: t,
            bass: bass, mid: mid, treb: treb,
            aspect: aspect.isFinite && aspect > 0 ? aspect : 1,
            decay: preset.decay,
            bandCount: Float(Self.bandCount),
            level: (bass + mid + treb) / 3,
            warpMode: preset.warpMode,
            injMode: preset.injMode,
            symmetry: preset.symmetry,
            rotSpeed: preset.rotSpeed,
            zoomBase: preset.zoomBase,
            warpAmp: preset.warpAmp,
            warpFreq: preset.warpFreq,
            swirl: preset.swirl,
            colorA: color(0, default: SIMD4(1.0, 0.30, 0.55, 1)),
            colorB: color(1, default: SIMD4(0.35, 0.55, 1.0, 1)),
            colorC: color(2, default: SIMD4(1.0, 0.85, 0.60, 1))
        )
    }

    private func currentPreset(at t: Float) -> MilkdropPreset {
        guard presets.count > 1 else { return presets.first ?? .default }
        let index = Int(t / cycleSeconds) % presets.count
        let next = (index + 1) % presets.count
        let local = t.truncatingRemainder(dividingBy: cycleSeconds)
        let raw = max(0, local - (cycleSeconds - blendSeconds)) / blendSeconds
        let blend = raw * raw * (3 - 2 * raw)
        return presets[index].blended(towards: presets[next], amount: blend)
    }

    private func color(_ index: Int, default fallback: SIMD4<Float>) -> SIMD4<Float> {
        guard index < colors.count else { return fallback }
        let c = colors[index]
        return SIMD4(Float(c.red), Float(c.green), Float(c.blue), 1)
    }
}

/// Layout must match `Uniforms` in MilkdropShaders.metal.
struct MilkdropUniforms {
    var time: Float
    var bass: Float
    var mid: Float
    var treb: Float
    var aspect: Float
    var decay: Float
    var bandCount: Float
    var level: Float
    var warpMode: Float
    var injMode: Float
    var symmetry: Float
    var rotSpeed: Float
    var zoomBase: Float
    var warpAmp: Float
    var warpFreq: Float
    var swirl: Float
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var colorC: SIMD4<Float>
}

struct MilkdropPreset {
    var warpMode: Float
    var injMode: Float
    var symmetry: Float
    var rotSpeed: Float
    var zoomBase: Float
    var warpAmp: Float
    var warpFreq: Float
    var swirl: Float
    var decay: Float

    func blended(towards other: MilkdropPreset, amount t: Float) -> MilkdropPreset {
        func lerp(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
        let past = t > 0.5
        return MilkdropPreset(
            warpMode: past ? other.warpMode : warpMode,
            injMode: past ? other.injMode : injMode,
            symmetry: past ? other.symmetry : symmetry,
            rotSpeed: lerp(rotSpeed, other.rotSpeed),
            zoomBase: lerp(zoomBase, other.zoomBase),
            warpAmp: lerp(warpAmp, other.warpAmp),
            warpFreq: lerp(warpFreq, other.warpFreq),
            swirl: lerp(swirl, other.swirl),
            decay: lerp(decay, other.decay)
        )
    }

    static let `default` = MilkdropPreset(
        warpMode: 0, injMode: 0, symmetry: 0, rotSpeed: 0.008,
        zoomBase: -0.008, warpAmp: 0.010, warpFreq: 7, swirl: 0, decay: 0.90)

    static let all: [MilkdropPreset] = [
        MilkdropPreset(warpMode: 1, injMode: 0, symmetry: 0, rotSpeed: 0.008,
                       zoomBase: -0.010, warpAmp: 0.010, warpFreq: 7, swirl: 0.5, decay: 0.905),
        MilkdropPreset(warpMode: 0, injMode: 2, symmetry: 6, rotSpeed: 0.006,
                       zoomBase: -0.006, warpAmp: 0.014, warpFreq: 9, swirl: 0, decay: 0.895),
        MilkdropPreset(warpMode: 2, injMode: 1, symmetry: 0, rotSpeed: 0.004,
                       zoomBase: -0.004, warpAmp: 0.024, warpFreq: 5, swirl: 0.2, decay: 0.915),
        MilkdropPreset(warpMode: 3, injMode: 3, symmetry: 0, rotSpeed: 0.010,
                       zoomBase: 0.005, warpAmp: 0.012, warpFreq: 6, swirl: 0, decay: 0.90),
        MilkdropPreset(warpMode: 1, injMode: 1, symmetry: 4, rotSpeed: -0.012,
                       zoomBase: -0.008, warpAmp: 0.012, warpFreq: 8, swirl: 0.6, decay: 0.90),
    ]
}
