//
//  MilkdropShaders.metal
//  YT Music
//
//  A MilkDrop-style feedback visualizer. The whole look comes from frame
//  feedback: each frame samples the *previous* frame through a warp (rotate +
//  zoom + per-pixel sine distortion), fades it slightly, and adds a fresh
//  audio-driven "injection" (a radial spectrum ring + a bass glow) on top. Over
//  many frames the injection smears into the flowing, liquid shapes MilkDrop is
//  known for. Audio (bass/mid/treble + the band levels) drives the warp and the
//  injection; the present pass tone-maps the HDR feedback buffer to the screen.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float time;
    float bass;
    float mid;
    float treb;
    float aspect;
    float decay;
    float bandCount;
    float level;
    // Preset parameters (interpolated between presets on the CPU side).
    float warpMode;    // 0 spiral · 1 spiral+swirl · 2 sine-flow · 3 pinch
    float injMode;     // 0 ring · 1 spiral arms · 2 wedges · 3 nested rings
    float symmetry;    // kaleidoscope fold count (0 = off)
    float rotSpeed;    // per-frame rotation (radians)
    float zoomBase;    // per-frame zoom offset
    float warpAmp;     // domain-warp amplitude
    float warpFreq;    // domain-warp frequency
    float swirl;       // rotation added proportional to radius (spiral)
    float4 colorA;
    float4 colorB;
    float4 colorC;
};

struct VSOut {
    float4 pos [[position]];
    float2 uv;
};

// A single oversized triangle covering the viewport — no vertex buffer needed.
vertex VSOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 corner[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VSOut out;
    out.pos = float4(corner[vid], 0, 1);
    out.uv = corner[vid] * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;   // 0 at top
    return out;
}

// Mirrors an angle (0…1) into `sym` kaleidoscope sectors.
static inline float foldAngle(float a, float sym) {
    if (sym < 0.5) return a;
    float x = fract(a * sym);
    return abs(x * 2.0 - 1.0);
}

// Warps + decays the previous frame and adds the audio injection.
fragment float4 milkdrop_feedback(VSOut in [[stage_in]],
                                  texture2d<float> prev [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant Uniforms& u [[buffer(0)]],
                                  constant float* bands [[buffer(1)]]) {
    float2 center = float2(0.5, 0.5);

    // --- warp the sampling coordinate for the feedback ---
    float2 p = in.uv - center;
    p.x *= u.aspect;
    float rad = length(p);

    if (u.warpMode > 2.5) {                          // pinch/bulge
        float pinch = sin(rad * 10.0 - u.time) * 0.012 * (0.5 + u.bass);
        p *= (1.0 - pinch);
    }

    float angle = u.rotSpeed + u.swirl * rad + u.treb * 0.06;
    float s = sin(angle), c = cos(angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);

    float zoom = 1.0 + u.zoomBase - u.bass * 0.055;   // bass "breathes" the zoom
    p *= zoom;

    float amp = u.warpAmp * (0.5 + u.mid * 1.8);
    if (u.warpMode > 1.5 && u.warpMode < 2.5) {      // sine flow
        p += amp * float2(sin(p.y * u.warpFreq + u.time * 1.3),
                          sin(p.x * u.warpFreq + u.time * 1.1));
    } else {
        p += amp * float2(sin(p.y * u.warpFreq + u.time * 1.3),
                          cos(p.x * u.warpFreq + u.time * 1.1));
    }

    p.x /= u.aspect;
    float3 prevColor = prev.sample(samp, center + p).rgb * u.decay;

    // --- fresh audio injection ---
    float2 q = in.uv - center;
    q.x *= u.aspect;
    float r = length(q);
    float a = atan2(q.y, q.x) / (2.0 * M_PI_F) + 0.5;   // 0…1 around the circle
    float af = foldAngle(a, u.symmetry);

    uint count = max(1u, uint(u.bandCount));
    uint bi = min(count - 1, uint(af * float(count)));
    float amp0 = bands[bi];

    float3 tint = mix(u.colorA.rgb, u.colorB.rgb, af);
    tint = mix(tint, u.colorC.rgb, amp0);

    float shape = 0.0;
    if (u.injMode < 0.5) {                              // radial ring
        float radius = 0.10 + amp0 * 0.42;
        shape = smoothstep(0.03, 0.0, abs(r - radius)) * (0.4 + amp0);
    } else if (u.injMode < 1.5) {                       // spiral arms
        float arms = 3.0 + floor(u.symmetry);
        float v = sin(af * arms * 6.2831 + r * 14.0 - u.time * 2.0) * 0.5 + 0.5;
        shape = pow(v, 3.0) * (0.4 + amp0) * smoothstep(0.8, 0.1, r);
    } else if (u.injMode < 2.5) {                       // wedges (bar spectrum)
        float edge = 0.08 + amp0 * 0.5;
        shape = smoothstep(edge, edge - 0.03, r) * step(0.06, r) * (0.4 + amp0);
    } else {                                            // nested rings
        float rings = fract(r * 6.0 - u.time * 0.5);
        shape = smoothstep(0.5, 0.0, abs(rings - 0.5)) * amp0;
    }

    float glow = smoothstep(0.32, 0.0, r) * u.bass;
    // Feedback settles at injection/(1-decay), so the per-frame injection must
    // stay small or the buffer saturates to white. This is the whole budget.
    float3 injection = (tint * shape + u.colorC.rgb * glow * 0.4)
                       * 0.07 * (1.0 + u.bass * 0.5);

    return float4(prevColor + injection, 1.0);
}

// Tone-maps the HDR feedback buffer down to the screen.
fragment float4 milkdrop_present(VSOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 sampler samp [[sampler(0)]]) {
    float3 color = src.sample(samp, in.uv).rgb;
    color = color / (color + 0.55);        // Reinhard-ish, tames highlights
    color = pow(color, float3(0.85));      // lift midtones
    return float4(color, 1.0);
}
