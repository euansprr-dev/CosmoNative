// CosmoOS/Canvas/Shaders.metal
// Metal shaders for high-performance canvas rendering (60fps guaranteed)

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Structures
struct VertexIn {
    float2 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

// MARK: - Uniforms
struct Uniforms {
    float4x4 projectionMatrix;
    float2 canvasSize;
};

// MARK: - Vertex Shader
vertex VertexOut vertex_main(
    const device VertexIn* vertices [[buffer(0)]],
    const device float4* colors [[buffer(1)]],
    constant Uniforms& uniforms [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;

    // Get vertex position
    float2 position = vertices[vid].position;

    // Convert from canvas coordinates to NDC (Normalized Device Coordinates)
    // Canvas: (0,0) top-left, (width,height) bottom-right
    // NDC: (-1,-1) bottom-left, (1,1) top-right
    float x = (position.x / uniforms.canvasSize.x) * 2.0 - 1.0;
    float y = 1.0 - (position.y / uniforms.canvasSize.y) * 2.0;

    out.position = float4(x, y, 0.0, 1.0);
    out.color = colors[0];

    return out;
}

// MARK: - Fragment Shader
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Blur Shader (for glassmorphism effect)
kernel void blur_kernel(
    texture2d<half, access::read> inTexture [[texture(0)]],
    texture2d<half, access::write> outTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Gaussian blur for glassmorphism
    const int radius = 5;
    half4 color = half4(0.0);
    float total = 0.0;

    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            uint2 offset = uint2(int2(gid) + int2(x, y));

            // Gaussian weight
            float weight = exp(-(x*x + y*y) / (2.0 * radius * radius));

            color += inTexture.read(offset) * weight;
            total += weight;
        }
    }

    outTexture.write(color / total, gid);
}

// MARK: - Glow Shader (for selected blocks)
fragment float4 glow_fragment(
    VertexOut in [[stage_in]],
    constant float& time [[buffer(0)]]
) {
    float4 color = in.color;

    // Pulsing glow effect
    float pulse = sin(time * 2.0) * 0.3 + 0.7;
    color.rgb *= pulse;

    return color;
}

// MARK: - Gradient Shader (for block backgrounds)
fragment float4 gradient_fragment(
    VertexOut in [[stage_in]],
    constant float4& color1 [[buffer(0)]],
    constant float4& color2 [[buffer(1)]]
) {
    // Vertical gradient
    float t = in.position.y / 1080.0;  // Normalize to screen height
    return mix(color1, color2, t);
}
