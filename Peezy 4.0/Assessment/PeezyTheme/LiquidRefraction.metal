#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Simple 2D hash for pseudo-random noise
float hash2d(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Value noise
float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash2d(i);
    float b = hash2d(i + float2(1.0, 0.0));
    float c = hash2d(i + float2(0.0, 1.0));
    float d = hash2d(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractal Brownian Motion – 4 octaves
float fbm4(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// SwiftUI layerEffect shader – subtle liquid-glass refraction
//
// position : pixel coordinate supplied by SwiftUI
// layer    : the rasterised layer to sample from
// intensity: displacement strength (0.75 is a good default)
// speed    : animation speed multiplier
// t        : normalised time 0→1, animated by the host view
[[stitchable]] half4 liquid_refraction(float2 position,
                                       SwiftUI::Layer layer,
                                       float intensity,
                                       float speed,
                                       float t) {
    // Derive a continuous time value (full rotation over one cycle)
    float time = t * speed * 6.28318; // 2*pi

    // Use position in a normalised-ish space for noise sampling.
    // Dividing by a constant keeps the pattern scale consistent
    // regardless of view size.
    float2 uv = position / 256.0;

    // Two noise layers scrolling in different directions
    float n1 = fbm4(uv * 4.0 + float2(time *  0.20, time *  0.15));
    float n2 = fbm4(uv * 6.0 + float2(time * -0.10, time *  0.18));

    // Displacement in pixels – kept small for a subtle wobble
    float2 disp = float2(n1 - 0.5, n2 - 0.5) * intensity * 2.0;

    // Sample the layer at the displaced position
    half4 refracted = layer.sample(position + disp);

    return refracted;
}
