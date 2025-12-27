// CosmoOS/UI/Sanctuary/SanctuaryShaders.metal
// Sanctuary Metal Shaders - Apple-grade visual effects for the neural dashboard
// Phase 1 Foundation: Orb rendering, aurora background, particle systems, glow effects

#include <metal_stdlib>
using namespace metal;

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Common Structures
// ═══════════════════════════════════════════════════════════════════════════════

struct SanctuaryVertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct SanctuaryVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float2 worldPos;
};

// Uniforms for time-based animations
struct TimeUniforms {
    float time;
    float deltaTime;
};

// Uniforms for orb rendering
struct OrbUniforms {
    float4 primaryColor;
    float4 secondaryColor;
    float4 tertiaryColor;
    float4 glowColor;
    float2 center;
    float radius;
    float time;
    float breathingScale;
    float innerRotation;
    float outerRotation;
    float glowIntensity;
    float isActive;
};

// Uniforms for aurora background
struct AuroraUniforms {
    float2 resolution;
    float time;
    float4 colorA;
    float4 colorB;
    float4 colorC;
    float intensity;
    float speed;
};

// Uniforms for particle rendering
struct ParticleUniforms {
    float4 color;
    float size;
    float opacity;
    float time;
};

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Noise Functions (for procedural effects)
// ═══════════════════════════════════════════════════════════════════════════════

// Simple pseudo-random hash
float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// 2D noise function
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractal Brownian Motion (layered noise)
float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return value;
}

// Simplex-like noise for smoother gradients
float simplex(float2 p) {
    float2 s = float2(1.0 + 2.0 * 0.36602540378, 0.36602540378);
    float2 i = floor(p + (p.x + p.y) * s.y);
    float2 x0 = p - i + (i.x + i.y) * s.y;

    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 x1 = x0 - i1 + s.y;
    float2 x2 = x0 - 1.0 + 2.0 * s.y;

    float3 m = max(0.5 - float3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
    m = m * m;
    m = m * m;

    float n0 = dot(hash(i) * 2.0 - 1.0, x0);
    float n1 = dot(hash(i + i1) * 2.0 - 1.0, x1);
    float n2 = dot(hash(i + 1.0) * 2.0 - 1.0, x2);

    return 70.0 * dot(m, float3(n0, n1, n2));
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Aurora Background Shader
// ═══════════════════════════════════════════════════════════════════════════════

vertex SanctuaryVertexOut aurora_vertex(
    const device SanctuaryVertexIn* vertices [[buffer(0)]],
    constant float2& resolution [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    SanctuaryVertexOut out;

    float2 position = vertices[vid].position;

    // Convert to NDC
    out.position = float4(position, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    out.worldPos = position * resolution * 0.5;

    return out;
}

fragment float4 aurora_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant AuroraUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord;
    float t = uniforms.time * uniforms.speed;

    // Multiple layers of flowing noise
    float n1 = fbm(uv * 3.0 + float2(t * 0.1, t * 0.05), 4);
    float n2 = fbm(uv * 2.0 - float2(t * 0.08, t * 0.12), 3);
    float n3 = fbm(uv * 4.0 + float2(t * 0.06, -t * 0.04), 5);

    // Create aurora wave patterns
    float wave1 = sin(uv.y * 10.0 + t + n1 * 3.0) * 0.5 + 0.5;
    float wave2 = sin(uv.y * 8.0 - t * 0.7 + n2 * 2.0) * 0.5 + 0.5;
    float wave3 = sin(uv.y * 12.0 + t * 0.5 + n3 * 4.0) * 0.5 + 0.5;

    // Blend colors based on noise and waves
    float4 color1 = uniforms.colorA * wave1 * n1;
    float4 color2 = uniforms.colorB * wave2 * n2;
    float4 color3 = uniforms.colorC * wave3 * n3;

    // Combine with distance-based falloff from center
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);
    float falloff = 1.0 - smoothstep(0.3, 1.0, dist);

    float4 aurora = (color1 + color2 + color3) * uniforms.intensity * falloff;

    // Add subtle vignette
    float vignette = 1.0 - pow(dist * 1.2, 2.0);

    // Deep void base color
    float4 voidColor = float4(0.04, 0.04, 0.06, 1.0);

    return mix(voidColor, voidColor + aurora, vignette);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Orb Rendering Shader
// ═══════════════════════════════════════════════════════════════════════════════

vertex SanctuaryVertexOut orb_vertex(
    const device SanctuaryVertexIn* vertices [[buffer(0)]],
    constant OrbUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    SanctuaryVertexOut out;

    float2 position = vertices[vid].position;

    // Apply breathing scale
    float2 scaledPos = position * uniforms.breathingScale;

    out.position = float4(scaledPos, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    out.worldPos = scaledPos;

    return out;
}

fragment float4 orb_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant OrbUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord * 2.0 - 1.0; // Center UV at origin
    float dist = length(uv);

    // Discard pixels outside circle
    if (dist > 1.0) {
        discard_fragment();
    }

    // Create layered radial gradient
    float3 color = uniforms.primaryColor.rgb;

    // Inner highlight (top-left light source)
    float2 lightDir = normalize(float2(-0.5, -0.5));
    float highlight = max(0.0, dot(normalize(uv), lightDir));
    highlight = pow(highlight, 3.0) * 0.4;

    // Core glow (center brighter)
    float coreGlow = 1.0 - smoothstep(0.0, 0.5, dist);
    coreGlow = pow(coreGlow, 2.0);

    // Edge darkening
    float edgeDark = smoothstep(0.7, 1.0, dist);

    // Surface detail noise (animated)
    float surfaceNoise = fbm(uv * 3.0 + uniforms.time * 0.5, 3) * 0.15;

    // Animated ring patterns (inner rotation)
    float angle = atan2(uv.y, uv.x) + uniforms.innerRotation;
    float ring = sin(angle * 4.0 + uniforms.time * 2.0) * 0.1 + 0.9;

    // Combine all effects
    color = mix(uniforms.secondaryColor.rgb, color, coreGlow);
    color = mix(color, uniforms.tertiaryColor.rgb, edgeDark);
    color += highlight;
    color += surfaceNoise;
    color *= ring;

    // Active state glow
    if (uniforms.isActive > 0.5) {
        float pulse = sin(uniforms.time * 3.0) * 0.15 + 0.85;
        color *= pulse;
    }

    // Smooth edge anti-aliasing
    float alpha = 1.0 - smoothstep(0.95, 1.0, dist);

    return float4(color, alpha);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Orb Glow Ring Shader
// ═══════════════════════════════════════════════════════════════════════════════

fragment float4 orb_glow_ring_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant OrbUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    float dist = length(uv);

    // Ring parameters
    float ringWidth = 0.08;
    float ringRadius = 1.0;

    // Create ring mask
    float ringMask = smoothstep(ringRadius - ringWidth, ringRadius, dist) *
                     (1.0 - smoothstep(ringRadius, ringRadius + ringWidth, dist));

    // Angular gradient for color variation
    float angle = atan2(uv.y, uv.x) + uniforms.outerRotation;
    float t = (angle + M_PI_F) / (2.0 * M_PI_F);

    // Blend between glow colors
    float3 color = mix(
        uniforms.primaryColor.rgb,
        uniforms.secondaryColor.rgb,
        sin(t * M_PI_F * 2.0 + uniforms.time) * 0.5 + 0.5
    );

    // Pulsing intensity
    float pulse = sin(uniforms.time * 1.5) * 0.2 + 0.8;

    // Apply glow intensity and pulse
    float alpha = ringMask * uniforms.glowIntensity * pulse;

    return float4(color * pulse, alpha);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Connection Line Shader
// ═══════════════════════════════════════════════════════════════════════════════

struct ConnectionUniforms {
    float4 color1;
    float4 color2;
    float time;
    float glowIntensity;
    float flowSpeed;
};

fragment float4 connection_line_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant ConnectionUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord;

    // Gradient along the line
    float t = uv.x;

    // Flowing energy effect
    float flow = sin(t * 20.0 - uniforms.time * uniforms.flowSpeed) * 0.5 + 0.5;
    flow *= sin(t * 8.0 + uniforms.time * uniforms.flowSpeed * 0.5) * 0.3 + 0.7;

    // Color blend
    float3 color = mix(uniforms.color1.rgb, uniforms.color2.rgb, t);

    // Add flow brightness
    color += flow * 0.3;

    // Line thickness falloff from center
    float lineWidth = abs(uv.y - 0.5) * 2.0;
    float alpha = (1.0 - smoothstep(0.0, 1.0, lineWidth)) * uniforms.glowIntensity;

    // Add glow halo
    float glow = exp(-lineWidth * 3.0) * 0.5;
    alpha += glow * uniforms.glowIntensity;

    return float4(color, alpha);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - XP Particle Shader
// ═══════════════════════════════════════════════════════════════════════════════

struct ParticleVertexIn {
    float2 position [[attribute(0)]];
    float2 velocity [[attribute(1)]];
    float size [[attribute(2)]];
    float life [[attribute(3)]];
    float rotation [[attribute(4)]];
};

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float life;
    float rotation;
};

vertex ParticleVertexOut particle_vertex(
    const device ParticleVertexIn* particles [[buffer(0)]],
    constant float2& resolution [[buffer(1)]],
    constant float& time [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    ParticleVertexOut out;

    ParticleVertexIn p = particles[vid];

    // Convert to NDC
    float2 ndc = (p.position / resolution) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y

    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = p.size * (1.0 + p.life * 0.5); // Shrink as life decreases
    out.life = p.life;
    out.rotation = p.rotation;

    return out;
}

fragment float4 particle_fragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]],
    constant ParticleUniforms& uniforms [[buffer(0)]]
) {
    // Rotate point coordinates
    float c = cos(in.rotation);
    float s = sin(in.rotation);
    float2 uv = pointCoord - 0.5;
    uv = float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + 0.5;

    // Circular particle with soft edges
    float dist = length(uv - 0.5) * 2.0;
    float alpha = 1.0 - smoothstep(0.7, 1.0, dist);

    // Sparkle effect
    float sparkle = sin(in.rotation * 10.0 + uniforms.time * 20.0) * 0.3 + 0.7;

    // Apply life fade
    alpha *= in.life * uniforms.opacity;

    // Gold particle color with sparkle
    float3 color = uniforms.color.rgb * sparkle;

    return float4(color, alpha);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Glass Material Shader
// ═══════════════════════════════════════════════════════════════════════════════

struct GlassUniforms {
    float4 tintColor;
    float opacity;
    float blur;
    float borderOpacity;
    float cornerRadius;
    float2 size;
};

fragment float4 glass_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant GlassUniforms& uniforms [[buffer(0)]],
    texture2d<float> backgroundTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = in.texCoord;

    // Sample background with slight blur offset
    float4 bg = float4(0.0);
    float blurRadius = uniforms.blur * 0.01;

    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float2 offset = float2(x, y) * blurRadius;
            bg += backgroundTexture.sample(textureSampler, uv + offset);
        }
    }
    bg /= 25.0;

    // Apply tint
    float3 color = mix(bg.rgb, uniforms.tintColor.rgb, uniforms.tintColor.a);

    // Add glass highlight gradient (top-left to bottom-right)
    float highlight = 1.0 - (uv.x + uv.y) * 0.3;
    highlight = pow(highlight, 2.0) * 0.15;
    color += highlight;

    // Border glow
    float2 borderDist = min(uv, 1.0 - uv);
    float borderMask = 1.0 - smoothstep(0.0, 0.02, min(borderDist.x, borderDist.y));
    color += borderMask * uniforms.borderOpacity;

    return float4(color, uniforms.opacity);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - XP Progress Ring Shader
// ═══════════════════════════════════════════════════════════════════════════════

struct ProgressRingUniforms {
    float4 progressColor;
    float4 trackColor;
    float progress; // 0.0 to 1.0
    float ringWidth;
    float time;
    float isAnimating;
};

fragment float4 progress_ring_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant ProgressRingUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = in.texCoord * 2.0 - 1.0;
    float dist = length(uv);

    // Ring parameters
    float outerRadius = 1.0;
    float innerRadius = 1.0 - uniforms.ringWidth;

    // Create ring mask
    float ringMask = smoothstep(innerRadius - 0.02, innerRadius, dist) *
                     (1.0 - smoothstep(outerRadius, outerRadius + 0.02, dist));

    if (ringMask < 0.01) {
        discard_fragment();
    }

    // Calculate angle (start from top, go clockwise)
    float angle = atan2(uv.x, uv.y);
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);

    // Progress mask
    float progressMask = step(normalizedAngle, uniforms.progress);

    // Progress color
    float3 progressColor = uniforms.progressColor.rgb;

    // Add subtle shimmer when animating
    if (uniforms.isAnimating > 0.5) {
        float shimmer = sin(normalizedAngle * 30.0 - uniforms.time * 5.0) * 0.1 + 0.9;
        progressColor *= shimmer;
    }

    // Glow at progress end
    float endGlow = 0.0;
    if (uniforms.progress > 0.01) {
        float endAngle = uniforms.progress;
        float distToEnd = abs(normalizedAngle - endAngle);
        endGlow = exp(-distToEnd * 50.0) * 0.5;
    }

    // Combine track and progress
    float3 color = mix(uniforms.trackColor.rgb, progressColor, progressMask);
    color += endGlow * progressColor;

    // Round cap at progress end
    float capMask = 1.0;
    if (normalizedAngle > uniforms.progress - 0.01 && normalizedAngle < uniforms.progress + 0.01) {
        capMask = 1.0 - smoothstep(0.0, 0.02, abs(normalizedAngle - uniforms.progress));
    }

    return float4(color, ringMask * capMask);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Level Number Glow Shader
// ═══════════════════════════════════════════════════════════════════════════════

struct TextGlowUniforms {
    float4 glowColor;
    float intensity;
    float radius;
    float time;
};

fragment float4 text_glow_fragment(
    SanctuaryVertexOut in [[stage_in]],
    constant TextGlowUniforms& uniforms [[buffer(0)]],
    texture2d<float> textTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = in.texCoord;

    // Sample text alpha
    float textAlpha = textTexture.sample(textureSampler, uv).a;

    // Create glow by sampling around the text
    float glow = 0.0;
    float samples = 12.0;

    for (float i = 0.0; i < samples; i++) {
        float angle = i / samples * 2.0 * M_PI_F;
        float2 offset = float2(cos(angle), sin(angle)) * uniforms.radius;
        glow += textTexture.sample(textureSampler, uv + offset).a;
    }
    glow /= samples;

    // Pulsing glow
    float pulse = sin(uniforms.time * 2.0) * 0.2 + 0.8;

    // Combine text and glow
    float3 color = uniforms.glowColor.rgb * glow * uniforms.intensity * pulse;

    // Add solid text on top
    color = mix(color, float3(1.0), textAlpha);

    float alpha = max(glow * uniforms.intensity, textAlpha);

    return float4(color, alpha);
}
