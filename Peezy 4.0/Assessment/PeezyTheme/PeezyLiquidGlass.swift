//
//  PeezyLiquidGlass.swift
//  PeezyV1.0
//
//  Reusable "liquid glass" effect with a premium shader path on iOS 17+
//  and a safe fallback to peezyGlassBackground on earlier iOS.
//

import SwiftUI

// MARK: - Liquid Glass Modifier

struct PeezyLiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var intensity: CGFloat    // displacement intensity for the shader
    var speed: CGFloat        // animation speed
    var tintOpacity: Double   // subtle tint on top of the glass
    var highlightOpacity: Double // top highlight overlay

    @State private var time: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .background(
                    // Base background: a translucent material to integrate with system blur
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    // Inner stroke to define edges
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .overlay(
                    // Subtle brand tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PeezyTheme.Colors.brandYellow.opacity(tintOpacity))
                )
                .overlay(
                    // Top highlight for depth
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(highlightOpacity),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .modifier(LiquidRefractionLayer(cornerRadius: cornerRadius, intensity: intensity, speed: speed, time: time))
                .onAppear {
                    // Drive a lightweight animation for the shader time
                    withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                        time = 1.0
                    }
                }
        } else {
            // iOS 16 fallback: existing DIY glass
            content
                .peezyGlassBackground(cornerRadius: cornerRadius)
        }
    }

    // MARK: - Liquid Refraction Layer (iOS 17+)

    @available(iOS 17, *)
    private struct LiquidRefractionLayer: ViewModifier {
        var cornerRadius: CGFloat
        var intensity: CGFloat
        var speed: CGFloat
        var time: CGFloat

        func body(content: Content) -> some View {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .layerEffect(ShaderLibrary.liquidRefraction(intensity: Float(intensity),
                                                            speed: Float(speed),
                                                            t: Float(time)),
                             maxSampleOffset: .zero,
                             isEnabled: true)
        }
    }
}

// MARK: - Shader Library (iOS 17+)

@available(iOS 17, *)
enum ShaderLibrary {
    // A simple pseudo-liquid refraction shader using multi-octave noise to displace sampling.
    // This is designed to be subtle and performant.
    static func liquidRefraction(intensity: Float, speed: Float, t: Float) -> Shader {
        let function = ShaderFunction(library: .default, name: "liquid_refraction")
        return Shader(function: function, arguments: [
            .float(intensity),
            .float(speed),
            .float(t)
        ])
    }
}

// MARK: - View Extension

extension View {
    func peezyLiquidGlass(
        cornerRadius: CGFloat = PeezyTheme.Layout.cornerRadius,
        intensity: CGFloat = 0.75,
        speed: CGFloat = 0.25,
        tintOpacity: Double = 0.04,
        highlightOpacity: Double = 0.12
    ) -> some View {
        self.modifier(
            PeezyLiquidGlassModifier(
                cornerRadius: cornerRadius,
                intensity: intensity,
                speed: speed,
                tintOpacity: tintOpacity,
                highlightOpacity: highlightOpacity
            )
        )
    }
}

#if canImport(SwiftUI) && canImport(MetalKit)
import MetalKit
#endif

// The shader source is provided via a default library function name "liquid_refraction".
// Add a .metal shader under the same target named LiquidRefraction.metal with the function below:
//
// #include <metal_stdlib>
// using namespace metal;
//
// struct Params {
//     float intensity;
//     float speed;
//     float t;
// };
//
// // Simple 2D hash
// float hash(float2 p) {
//     return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
// }
//
// // 2D noise
// float noise(float2 p) {
//     float2 i = floor(p);
//     float2 f = fract(p);
//     float a = hash(i);
//     float b = hash(i + float2(1.0, 0.0));
//     float c = hash(i + float2(0.0, 1.0));
//     float d = hash(i + float2(1.0, 1.0));
//     float2 u = f * f * (3.0 - 2.0 * f);
//     return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
// }
//
// // Fractal Brownian Motion
// float fbm(float2 p) {
//     float v = 0.0;
//     float a = 0.5;
//     for (int i = 0; i < 4; i++) {
//         v += a * noise(p);
//         p *= 2.0;
//         a *= 0.5;
//     }
//     return v;
// }
//
// // Main layerEffect shader
// half4 liquid_refraction(float2 position, half4 color, half4 background, float2 size, device const Params& params) {
//     float2 uv = position / size;
//     float time = params.t * params.speed * 6.28318; // 2π
//
//     // Create a subtle flow field
//     float n1 = fbm(uv * 4.0 + float2(time * 0.2, time * 0.15));
//     float n2 = fbm(uv * 6.0 + float2(time * -0.1, time * 0.18));
//
//     // Displacement vector
//     float2 disp = float2(n1 - 0.5, n2 - 0.5) * params.intensity * 0.008;
//
//     // Sample the background with displacement
//     float2 refractedPos = position + disp * size;
//     half4 refracted = layer.sample(refractedPos);
//
//     // Mix the original with refracted to keep things subtle
//     half4 result = mix(color, refracted, 0.35);
//     return result;
// }
//
// IMPORTANT:
// - Place this LiquidRefraction.metal file in your target so the function name "liquid_refraction" is available.
// - If you prefer not to add a .metal file today, the effect will still look good from the material+tint+highlight,
//   but without the refraction displacement. To enable displacement, include the shader above.
//
