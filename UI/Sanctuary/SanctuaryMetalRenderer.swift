// CosmoOS/UI/Sanctuary/SanctuaryMetalRenderer.swift
// Metal Rendering Pipeline for Sanctuary UI - 120fps ProMotion optimized
// Phase 1 Foundation: Connects shaders to SwiftUI views

import SwiftUI
import MetalKit
import simd

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Shader Uniform Structures (Must match SanctuaryShaders.metal)
// ═══════════════════════════════════════════════════════════════════════════════

struct SanctuaryTimeUniforms {
    var time: Float
    var deltaTime: Float
}

struct SanctuaryOrbUniforms {
    var primaryColor: SIMD4<Float>
    var secondaryColor: SIMD4<Float>
    var tertiaryColor: SIMD4<Float>
    var glowColor: SIMD4<Float>
    var center: SIMD2<Float>
    var radius: Float
    var time: Float
    var breathingScale: Float
    var innerRotation: Float
    var outerRotation: Float
    var glowIntensity: Float
    var isActive: Float
}

struct SanctuaryAuroraUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var colorC: SIMD4<Float>
    var intensity: Float
    var speed: Float
}

struct SanctuaryParticleUniforms {
    var color: SIMD4<Float>
    var size: Float
    var opacity: Float
    var time: Float
}

struct SanctuaryConnectionUniforms {
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var time: Float
    var glowIntensity: Float
    var flowSpeed: Float
}

struct SanctuaryGlassUniforms {
    var tintColor: SIMD4<Float>
    var opacity: Float
    var blur: Float
    var borderOpacity: Float
    var cornerRadius: Float
    var size: SIMD2<Float>
}

struct SanctuaryProgressRingUniforms {
    var progressColor: SIMD4<Float>
    var trackColor: SIMD4<Float>
    var progress: Float
    var ringWidth: Float
    var time: Float
    var isAnimating: Float
}

struct SanctuaryTextGlowUniforms {
    var glowColor: SIMD4<Float>
    var intensity: Float
    var radius: Float
    var time: Float
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Particle Data Structure
// ═══════════════════════════════════════════════════════════════════════════════

struct SanctuaryParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var size: Float
    var life: Float
    var rotation: Float

    static func random(in rect: CGRect, life: Float = 1.0) -> SanctuaryParticle {
        SanctuaryParticle(
            position: SIMD2(
                Float.random(in: Float(rect.minX)...Float(rect.maxX)),
                Float.random(in: Float(rect.minY)...Float(rect.maxY))
            ),
            velocity: SIMD2(
                Float.random(in: -50...50),
                Float.random(in: -100 ... -20)
            ),
            size: Float.random(in: 4...12),
            life: life,
            rotation: Float.random(in: 0...(2 * .pi))
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Sanctuary Metal Renderer
// ═══════════════════════════════════════════════════════════════════════════════

/// Central Metal rendering engine for Sanctuary UI
/// Manages device, command queues, pipelines, and buffer pooling for 120fps rendering
final class SanctuaryMetalRenderer {

    // MARK: - Singleton
    static let shared: SanctuaryMetalRenderer? = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal not available on this device")
            return nil
        }
        return SanctuaryMetalRenderer(device: device)
    }()

    // MARK: - Metal Core
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let bufferPool: MetalBufferPool

    // MARK: - Shader Library
    private var shaderLibrary: MTLLibrary?

    // MARK: - Render Pipelines
    private(set) var auroraPipeline: MTLRenderPipelineState?
    private(set) var orbPipeline: MTLRenderPipelineState?
    private(set) var orbGlowPipeline: MTLRenderPipelineState?
    private(set) var connectionPipeline: MTLRenderPipelineState?
    private(set) var particlePipeline: MTLRenderPipelineState?
    private(set) var glassPipeline: MTLRenderPipelineState?
    private(set) var progressRingPipeline: MTLRenderPipelineState?
    private(set) var textGlowPipeline: MTLRenderPipelineState?

    // MARK: - Pre-allocated Vertex Buffers
    private var quadVertexBuffer: MTLBuffer?

    // MARK: - Timing
    private var startTime: CFTimeInterval
    var currentTime: Float {
        Float(CFAbsoluteTimeGetCurrent() - startTime)
    }

    // MARK: - Initialization

    private init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.bufferPool = MetalBufferPool(device: device)
        self.startTime = CFAbsoluteTimeGetCurrent()

        setupShaderLibrary()
        setupRenderPipelines()
        setupVertexBuffers()

        print("✅ SanctuaryMetalRenderer initialized")
        print("   GPU: \(device.name)")
        print("   Max Threads/Group: \(device.maxThreadsPerThreadgroup)")
    }

    // MARK: - Shader Library Setup

    private func setupShaderLibrary() {
        // Inline shader source for SwiftPM compatibility
        // This matches SanctuaryShaders.metal but compiled at runtime
        let shaderSource = loadShaderSource()

        do {
            let options = MTLCompileOptions()
            options.mathMode = .fast
            options.languageVersion = .version3_1

            shaderLibrary = try device.makeLibrary(source: shaderSource, options: options)
            print("✅ Sanctuary shaders compiled successfully")
        } catch {
            print("❌ Failed to compile Sanctuary shaders: \(error)")
        }
    }

    private func loadShaderSource() -> String {
        // Comprehensive shader source matching SanctuaryShaders.metal
        return """
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

        struct AuroraUniforms {
            float2 resolution;
            float time;
            float4 colorA;
            float4 colorB;
            float4 colorC;
            float intensity;
            float speed;
        };

        struct ParticleUniforms {
            float4 color;
            float size;
            float opacity;
            float time;
        };

        struct ConnectionUniforms {
            float4 color1;
            float4 color2;
            float time;
            float glowIntensity;
            float flowSpeed;
        };

        struct ProgressRingUniforms {
            float4 progressColor;
            float4 trackColor;
            float progress;
            float ringWidth;
            float time;
            float isAnimating;
        };

        // ═══════════════════════════════════════════════════════════════════════════════
        // MARK: - Noise Functions
        // ═══════════════════════════════════════════════════════════════════════════════

        float hash(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

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

        // ═══════════════════════════════════════════════════════════════════════════════
        // MARK: - Simple Vertex Shader (shared)
        // ═══════════════════════════════════════════════════════════════════════════════

        vertex SanctuaryVertexOut sanctuary_vertex(
            uint vid [[vertex_id]],
            constant float2* vertices [[buffer(0)]]
        ) {
            SanctuaryVertexOut out;

            // Fullscreen quad positions
            float2 positions[4] = {
                float2(-1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0,  1.0)
            };

            float2 texCoords[4] = {
                float2(0.0, 1.0),
                float2(1.0, 1.0),
                float2(0.0, 0.0),
                float2(1.0, 0.0)
            };

            out.position = float4(positions[vid], 0.0, 1.0);
            out.texCoord = texCoords[vid];
            out.worldPos = positions[vid];

            return out;
        }

        // ═══════════════════════════════════════════════════════════════════════════════
        // MARK: - Aurora Background Shader
        // ═══════════════════════════════════════════════════════════════════════════════

        fragment float4 aurora_fragment(
            SanctuaryVertexOut in [[stage_in]],
            constant AuroraUniforms& uniforms [[buffer(0)]]
        ) {
            float2 uv = in.texCoord;
            float t = uniforms.time * uniforms.speed;

            // PERFORMANCE FIX: Reduced FBM octaves from 4+3+5=12 to 2+2=4 (77% reduction)
            // Aurora is already blurred and flowing - fewer octaves imperceptible
            float n1 = fbm(uv * 3.0 + float2(t * 0.1, t * 0.05), 2);
            float n2 = fbm(uv * 2.0 - float2(t * 0.08, t * 0.12), 2);

            // Create aurora wave patterns (simplified - blend n1 and n2)
            float wave1 = sin(uv.y * 10.0 + t + n1 * 3.0) * 0.5 + 0.5;
            float wave2 = sin(uv.y * 8.0 - t * 0.7 + n2 * 2.0) * 0.5 + 0.5;
            float wave3 = sin(uv.y * 12.0 + t * 0.5 + (n1 + n2) * 2.0) * 0.5 + 0.5;

            // Blend colors based on noise and waves
            float4 color1 = uniforms.colorA * wave1 * n1;
            float4 color2 = uniforms.colorB * wave2 * n2;
            float4 color3 = uniforms.colorC * wave3 * ((n1 + n2) * 0.5);

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

        fragment float4 orb_fragment(
            SanctuaryVertexOut in [[stage_in]],
            constant OrbUniforms& uniforms [[buffer(0)]]
        ) {
            float2 uv = in.texCoord * 2.0 - 1.0;
            float dist = length(uv);

            if (dist > 1.0) {
                discard_fragment();
            }

            float3 color = uniforms.primaryColor.rgb;

            // Inner highlight
            float2 lightDir = normalize(float2(-0.5, -0.5));
            float highlight = max(0.0, dot(normalize(uv), lightDir));
            highlight = pow(highlight, 3.0) * 0.4;

            // Core glow
            float coreGlow = 1.0 - smoothstep(0.0, 0.5, dist);
            coreGlow = pow(coreGlow, 2.0);

            // Edge darkening
            float edgeDark = smoothstep(0.7, 1.0, dist);

            // Surface detail noise
            float surfaceNoise = fbm(uv * 3.0 + uniforms.time * 0.5, 3) * 0.15;

            // Animated ring patterns
            float angle = atan2(uv.y, uv.x) + uniforms.innerRotation;
            float ring = sin(angle * 4.0 + uniforms.time * 2.0) * 0.1 + 0.9;

            // Combine effects
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

            float ringWidth = 0.08;
            float ringRadius = 1.0;

            float ringMask = smoothstep(ringRadius - ringWidth, ringRadius, dist) *
                             (1.0 - smoothstep(ringRadius, ringRadius + ringWidth, dist));

            float angle = atan2(uv.y, uv.x) + uniforms.outerRotation;
            float t = (angle + M_PI_F) / (2.0 * M_PI_F);

            float3 color = mix(
                uniforms.primaryColor.rgb,
                uniforms.secondaryColor.rgb,
                sin(t * M_PI_F * 2.0 + uniforms.time) * 0.5 + 0.5
            );

            float pulse = sin(uniforms.time * 1.5) * 0.2 + 0.8;
            float alpha = ringMask * uniforms.glowIntensity * pulse;

            return float4(color * pulse, alpha);
        }

        // ═══════════════════════════════════════════════════════════════════════════════
        // MARK: - Connection Line Shader
        // ═══════════════════════════════════════════════════════════════════════════════

        fragment float4 connection_line_fragment(
            SanctuaryVertexOut in [[stage_in]],
            constant ConnectionUniforms& uniforms [[buffer(0)]]
        ) {
            float2 uv = in.texCoord;
            float t = uv.x;

            float flow = sin(t * 20.0 - uniforms.time * uniforms.flowSpeed) * 0.5 + 0.5;
            flow *= sin(t * 8.0 + uniforms.time * uniforms.flowSpeed * 0.5) * 0.3 + 0.7;

            float3 color = mix(uniforms.color1.rgb, uniforms.color2.rgb, t);
            color += flow * 0.3;

            float lineWidth = abs(uv.y - 0.5) * 2.0;
            float alpha = (1.0 - smoothstep(0.0, 1.0, lineWidth)) * uniforms.glowIntensity;

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
            uint vid [[vertex_id]],
            constant ParticleVertexIn* particles [[buffer(0)]],
            constant float2& resolution [[buffer(1)]]
        ) {
            ParticleVertexOut out;

            ParticleVertexIn p = particles[vid];

            float2 ndc = (p.position / resolution) * 2.0 - 1.0;
            ndc.y = -ndc.y;

            out.position = float4(ndc, 0.0, 1.0);
            out.pointSize = p.size * (1.0 + p.life * 0.5);
            out.life = p.life;
            out.rotation = p.rotation;

            return out;
        }

        fragment float4 particle_fragment(
            ParticleVertexOut in [[stage_in]],
            float2 pointCoord [[point_coord]],
            constant ParticleUniforms& uniforms [[buffer(0)]]
        ) {
            float c = cos(in.rotation);
            float s = sin(in.rotation);
            float2 uv = pointCoord - 0.5;
            uv = float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + 0.5;

            float dist = length(uv - 0.5) * 2.0;
            float alpha = 1.0 - smoothstep(0.7, 1.0, dist);

            float sparkle = sin(in.rotation * 10.0 + uniforms.time * 20.0) * 0.3 + 0.7;

            alpha *= in.life * uniforms.opacity;

            float3 color = uniforms.color.rgb * sparkle;

            return float4(color, alpha);
        }

        // ═══════════════════════════════════════════════════════════════════════════════
        // MARK: - XP Progress Ring Shader
        // ═══════════════════════════════════════════════════════════════════════════════

        fragment float4 progress_ring_fragment(
            SanctuaryVertexOut in [[stage_in]],
            constant ProgressRingUniforms& uniforms [[buffer(0)]]
        ) {
            float2 uv = in.texCoord * 2.0 - 1.0;
            float dist = length(uv);

            float outerRadius = 1.0;
            float innerRadius = 1.0 - uniforms.ringWidth;

            float ringMask = smoothstep(innerRadius - 0.02, innerRadius, dist) *
                             (1.0 - smoothstep(outerRadius, outerRadius + 0.02, dist));

            // PERFORMANCE FIX: Use step() instead of discard_fragment()
            // discard breaks early-z optimization and prevents GPU from culling early
            // Return transparent color instead for pixels outside ring
            float visibility = step(0.01, ringMask);

            float angle = atan2(uv.x, uv.y);
            float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);

            float progressMask = step(normalizedAngle, uniforms.progress);

            float3 progressColor = uniforms.progressColor.rgb;

            if (uniforms.isAnimating > 0.5) {
                float shimmer = sin(normalizedAngle * 30.0 - uniforms.time * 5.0) * 0.1 + 0.9;
                progressColor *= shimmer;
            }

            float endGlow = 0.0;
            if (uniforms.progress > 0.01) {
                float distToEnd = abs(normalizedAngle - uniforms.progress);
                endGlow = exp(-distToEnd * 50.0) * 0.5;
            }

            float3 color = mix(uniforms.trackColor.rgb, progressColor, progressMask);
            color += endGlow * progressColor;

            // PERFORMANCE FIX: Use visibility mask instead of discard
            return float4(color, ringMask * visibility);
        }
        """
    }

    // MARK: - Render Pipeline Setup

    private func setupRenderPipelines() {
        guard let library = shaderLibrary else {
            print("❌ No shader library available")
            return
        }

        // Aurora Pipeline
        auroraPipeline = createPipeline(
            library: library,
            vertexFunction: "sanctuary_vertex",
            fragmentFunction: "aurora_fragment",
            label: "Aurora"
        )

        // Orb Pipeline
        orbPipeline = createPipeline(
            library: library,
            vertexFunction: "sanctuary_vertex",
            fragmentFunction: "orb_fragment",
            label: "Orb"
        )

        // Orb Glow Ring Pipeline
        orbGlowPipeline = createPipeline(
            library: library,
            vertexFunction: "sanctuary_vertex",
            fragmentFunction: "orb_glow_ring_fragment",
            label: "OrbGlow"
        )

        // Connection Line Pipeline
        connectionPipeline = createPipeline(
            library: library,
            vertexFunction: "sanctuary_vertex",
            fragmentFunction: "connection_line_fragment",
            label: "Connection"
        )

        // Particle Pipeline
        particlePipeline = createPipeline(
            library: library,
            vertexFunction: "particle_vertex",
            fragmentFunction: "particle_fragment",
            label: "Particle"
        )

        // Progress Ring Pipeline
        progressRingPipeline = createPipeline(
            library: library,
            vertexFunction: "sanctuary_vertex",
            fragmentFunction: "progress_ring_fragment",
            label: "ProgressRing"
        )

        print("✅ Sanctuary render pipelines created")
    }

    private func createPipeline(
        library: MTLLibrary,
        vertexFunction: String,
        fragmentFunction: String,
        label: String
    ) -> MTLRenderPipelineState? {
        guard let vertexFn = library.makeFunction(name: vertexFunction),
              let fragmentFn = library.makeFunction(name: fragmentFunction) else {
            print("❌ Missing functions: \(vertexFunction)/\(fragmentFunction)")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Sanctuary.\(label)"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable blending for transparency
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("❌ Failed to create \(label) pipeline: \(error)")
            return nil
        }
    }

    // MARK: - Vertex Buffer Setup

    private func setupVertexBuffers() {
        // Fullscreen quad vertices (NDC)
        let quadVertices: [SIMD2<Float>] = [
            SIMD2(-1.0, -1.0),
            SIMD2( 1.0, -1.0),
            SIMD2(-1.0,  1.0),
            SIMD2( 1.0,  1.0)
        ]

        quadVertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - Buffer Acquisition

    func acquireBuffer<T>(array: [T]) -> MTLBuffer? {
        return bufferPool.acquire(array: array)
    }

    func acquireBuffer(length: Int) -> MTLBuffer? {
        return bufferPool.acquire(length: length)
    }

    func releaseBuffer(_ buffer: MTLBuffer) {
        bufferPool.release(buffer)
    }

    // MARK: - Frame Buffer Manager

    func createFrameBufferManager() -> FrameBufferManager {
        return FrameBufferManager(pool: bufferPool)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Aurora Background Metal View
// ═══════════════════════════════════════════════════════════════════════════════

/// Metal-rendered aurora background for Sanctuary
struct SanctuaryAuroraMetalView: NSViewRepresentable {
    var colorA: Color = SanctuaryColors.Dimensions.cognitive
    var colorB: Color = SanctuaryColors.Dimensions.creative
    var colorC: Color = SanctuaryColors.Dimensions.physiological
    var intensity: CGFloat = 0.3
    var speed: CGFloat = 0.5

    func makeNSView(context: Context) -> SanctuaryAuroraNSView {
        let view = SanctuaryAuroraNSView()
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: SanctuaryAuroraNSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ view: SanctuaryAuroraNSView) {
        view.colorA = colorA.simd4
        view.colorB = colorB.simd4
        view.colorC = colorC.simd4
        view.intensity = Float(intensity)
        view.speed = Float(speed)
    }
}

class SanctuaryAuroraNSView: NSView {
    private var metalLayer: CAMetalLayer!
    private var nsDisplayLink: CADisplayLink?
    private var renderer: SanctuaryMetalRenderer?
    private var frameBufferManager: FrameBufferManager?

    var colorA: SIMD4<Float> = SIMD4(0.39, 0.4, 0.94, 1.0)
    var colorB: SIMD4<Float> = SIMD4(0.96, 0.62, 0.04, 1.0)
    var colorC: SIMD4<Float> = SIMD4(0.06, 0.73, 0.51, 1.0)
    var intensity: Float = 0.3
    var speed: Float = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    deinit {
        stopDisplayLink()
    }

    private func setupMetal() {
        guard let renderer = SanctuaryMetalRenderer.shared else {
            print("❌ SanctuaryMetalRenderer not available")
            return
        }

        self.renderer = renderer
        self.frameBufferManager = renderer.createFrameBufferManager()

        wantsLayer = true

        metalLayer = CAMetalLayer()
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        layer = metalLayer
    }

    private var lastRenderTime: CFTimeInterval = 0
    private let targetFrameRate: Double = 30.0  // PERFORMANCE: Limit to 30fps for aurora (it's subtle)
    private let renderQueue = DispatchQueue(label: "sanctuary.aurora.render", qos: .userInteractive)

    private func setupDisplayLink() {
        let link = self.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.nsDisplayLink = link
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        // PERFORMANCE FIX: Render on dedicated queue, not main queue
        renderQueue.async {
            self.renderIfNeeded()
        }
    }

    private func stopDisplayLink() {
        nsDisplayLink?.invalidate()
        nsDisplayLink = nil
    }

    private func renderIfNeeded() {
        // Frame rate limiter - skip frame if too soon
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = 1.0 / targetFrameRate
        guard now - lastRenderTime >= minInterval else { return }
        lastRenderTime = now
        render()
    }

    private func render() {
        guard let renderer = renderer,
              let pipeline = renderer.auroraPipeline,
              bounds.width > 0 && bounds.height > 0,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            return
        }

        // Update layer size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        // Create render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)

        // Set uniforms
        var uniforms = SanctuaryAuroraUniforms(
            resolution: SIMD2(Float(bounds.width), Float(bounds.height)),
            time: renderer.currentTime,
            colorA: colorA,
            colorB: colorB,
            colorC: colorC,
            intensity: intensity,
            speed: speed
        )

        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SanctuaryAuroraUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()

        drawable.present(afterMinimumDuration: 1.0 / 120.0)
        commandBuffer.commit()

        frameBufferManager?.endFrame()
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Hero Orb Metal View
// ═══════════════════════════════════════════════════════════════════════════════

/// Metal-rendered Hero Orb with layered effects
struct SanctuaryHeroOrbMetalView: NSViewRepresentable {
    var level: Int = 1
    var xpProgress: CGFloat = 0.5
    var isActive: Bool = false
    var breathingScale: CGFloat = 1.0

    func makeNSView(context: Context) -> SanctuaryHeroOrbNSView {
        let view = SanctuaryHeroOrbNSView()
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: SanctuaryHeroOrbNSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ view: SanctuaryHeroOrbNSView) {
        view.level = level
        view.xpProgress = Float(xpProgress)
        view.isActive = isActive
        view.breathingScale = Float(breathingScale)
    }
}

class SanctuaryHeroOrbNSView: NSView {
    private var metalLayer: CAMetalLayer!
    private var nsDisplayLink: CADisplayLink?
    private var renderer: SanctuaryMetalRenderer?
    private var frameBufferManager: FrameBufferManager?

    var level: Int = 1 {
        didSet {
            if level != oldValue {
                updateCachedColors()
            }
        }
    }
    var xpProgress: Float = 0.5
    var isActive: Bool = false
    var breathingScale: Float = 1.0

    // PERFORMANCE FIX: Cache level-based colors instead of computing every frame
    private var cachedPrimaryColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    private var cachedSecondaryColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    private var cachedTertiaryColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    private var cachedGlowColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
        setupDisplayLink()
        updateCachedColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    deinit {
        stopDisplayLink()
    }

    private func updateCachedColors() {
        let orbColors = SanctuaryColors.HeroOrb.forLevel(level)
        cachedPrimaryColor = orbColors.primary.simd4
        cachedSecondaryColor = orbColors.secondary.simd4
        cachedTertiaryColor = orbColors.tertiary.simd4
        cachedGlowColor = orbColors.glow.simd4
    }

    private var lastRenderTime: CFTimeInterval = 0
    private let targetFrameRate: Double = 30.0  // PERFORMANCE FIX: Reduced from 60fps - breathing is subtle enough at 30fps
    private let renderQueue = DispatchQueue(label: "sanctuary.orb.render", qos: .userInteractive)

    private func setupMetal() {
        guard let renderer = SanctuaryMetalRenderer.shared else { return }

        self.renderer = renderer
        self.frameBufferManager = renderer.createFrameBufferManager()

        wantsLayer = true

        metalLayer = CAMetalLayer()
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        layer = metalLayer
    }

    private func setupDisplayLink() {
        let link = self.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.nsDisplayLink = link
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        // PERFORMANCE FIX: Render on dedicated queue, not main queue
        renderQueue.async {
            self.renderIfNeeded()
        }
    }

    private func stopDisplayLink() {
        nsDisplayLink?.invalidate()
        nsDisplayLink = nil
    }

    private func renderIfNeeded() {
        // Frame rate limiter
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = 1.0 / targetFrameRate
        guard now - lastRenderTime >= minInterval else { return }
        lastRenderTime = now
        render()
    }

    private func render() {
        guard let renderer = renderer,
              let orbPipeline = renderer.orbPipeline,
              bounds.width > 0 && bounds.height > 0,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            return
        }

        // Update layer size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        // Create render pass with transparent background
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let time = renderer.currentTime

        // PERFORMANCE FIX: Use cached colors instead of computing every frame
        // Render orb
        encoder.setRenderPipelineState(orbPipeline)

        var orbUniforms = SanctuaryOrbUniforms(
            primaryColor: cachedPrimaryColor,
            secondaryColor: cachedSecondaryColor,
            tertiaryColor: cachedTertiaryColor,
            glowColor: cachedGlowColor,
            center: SIMD2(Float(bounds.width / 2), Float(bounds.height / 2)),
            radius: Float(min(bounds.width, bounds.height) / 2),
            time: time,
            breathingScale: breathingScale,
            innerRotation: time * 0.5,
            outerRotation: time * -0.3,
            glowIntensity: isActive ? 1.2 : 0.8,
            isActive: isActive ? 1.0 : 0.0
        )

        encoder.setFragmentBytes(&orbUniforms, length: MemoryLayout<SanctuaryOrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Render glow ring
        if let glowPipeline = renderer.orbGlowPipeline {
            encoder.setRenderPipelineState(glowPipeline)
            encoder.setFragmentBytes(&orbUniforms, length: MemoryLayout<SanctuaryOrbUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()

        drawable.present(afterMinimumDuration: 1.0 / 120.0)
        commandBuffer.commit()

        frameBufferManager?.endFrame()
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - XP Progress Ring Metal View
// ═══════════════════════════════════════════════════════════════════════════════

/// Metal-rendered XP progress ring
struct SanctuaryProgressRingMetalView: NSViewRepresentable {
    var progress: CGFloat
    var progressColor: Color = SanctuaryColors.XP.primary
    var trackColor: Color = SanctuaryColors.XP.track
    var ringWidth: CGFloat = 0.15
    var isAnimating: Bool = true

    func makeNSView(context: Context) -> SanctuaryProgressRingNSView {
        let view = SanctuaryProgressRingNSView()
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: SanctuaryProgressRingNSView, context: Context) {
        updateView(nsView)
    }

    private func updateView(_ view: SanctuaryProgressRingNSView) {
        view.progress = Float(progress)
        view.progressColor = progressColor.simd4
        view.trackColor = trackColor.simd4
        view.ringWidth = Float(ringWidth)
        view.isAnimating = isAnimating
    }
}

class SanctuaryProgressRingNSView: NSView {
    private var metalLayer: CAMetalLayer!
    private var nsDisplayLink: CADisplayLink?
    private var renderer: SanctuaryMetalRenderer?

    var progress: Float = 0.5
    var progressColor: SIMD4<Float> = SIMD4(1.0, 0.84, 0.0, 1.0)
    var trackColor: SIMD4<Float> = SIMD4(0.2, 0.2, 0.2, 0.5)
    var ringWidth: Float = 0.15
    var isAnimating: Bool = true

    private var lastRenderTime: CFTimeInterval = 0
    private let targetFrameRate: Double = 30.0  // Progress ring only needs 30fps
    private let renderQueue = DispatchQueue(label: "sanctuary.ring.render", qos: .userInteractive)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    deinit {
        stopDisplayLink()
    }

    private func setupMetal() {
        guard let renderer = SanctuaryMetalRenderer.shared else { return }

        self.renderer = renderer

        wantsLayer = true

        metalLayer = CAMetalLayer()
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        layer = metalLayer
    }

    private func setupDisplayLink() {
        let link = self.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.nsDisplayLink = link
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        // PERFORMANCE FIX: Render on dedicated queue, not main queue
        renderQueue.async {
            self.renderIfNeeded()
        }
    }

    private func stopDisplayLink() {
        nsDisplayLink?.invalidate()
        nsDisplayLink = nil
    }

    private func renderIfNeeded() {
        // Frame rate limiter
        let now = CFAbsoluteTimeGetCurrent()
        let minInterval = 1.0 / targetFrameRate
        guard now - lastRenderTime >= minInterval else { return }
        lastRenderTime = now
        render()
    }

    private func render() {
        guard let renderer = renderer,
              let pipeline = renderer.progressRingPipeline,
              bounds.width > 0 && bounds.height > 0,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            return
        }

        // Update layer size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        // Create render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)

        var uniforms = SanctuaryProgressRingUniforms(
            progressColor: progressColor,
            trackColor: trackColor,
            progress: progress,
            ringWidth: ringWidth,
            time: renderer.currentTime,
            isAnimating: isAnimating ? 1.0 : 0.0
        )

        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SanctuaryProgressRingUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()

        drawable.present(afterMinimumDuration: 1.0 / 120.0)
        commandBuffer.commit()
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Color Extensions for Metal
// ═══════════════════════════════════════════════════════════════════════════════

extension Color {
    /// Convert SwiftUI Color to SIMD4<Float> for Metal shaders
    var simd4: SIMD4<Float> {
        guard let components = NSColor(self).cgColor.components else {
            return SIMD4(1, 1, 1, 1)
        }

        switch components.count {
        case 1:
            // Grayscale
            return SIMD4(Float(components[0]), Float(components[0]), Float(components[0]), 1.0)
        case 2:
            // Grayscale + Alpha
            return SIMD4(Float(components[0]), Float(components[0]), Float(components[0]), Float(components[1]))
        case 3:
            // RGB
            return SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), 1.0)
        case 4:
            // RGBA
            return SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), Float(components[3]))
        default:
            return SIMD4(1, 1, 1, 1)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - SwiftUI View Modifiers
// ═══════════════════════════════════════════════════════════════════════════════

extension View {
    /// Apply Sanctuary aurora background
    func sanctuaryAuroraBackground(
        colorA: Color = SanctuaryColors.Dimensions.cognitive,
        colorB: Color = SanctuaryColors.Dimensions.creative,
        colorC: Color = SanctuaryColors.Dimensions.physiological,
        intensity: CGFloat = 0.3,
        speed: CGFloat = 0.5
    ) -> some View {
        self.background(
            SanctuaryAuroraMetalView(
                colorA: colorA,
                colorB: colorB,
                colorC: colorC,
                intensity: intensity,
                speed: speed
            )
        )
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
struct SanctuaryMetalRenderer_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            SanctuaryAuroraMetalView()

            VStack(spacing: 40) {
                SanctuaryHeroOrbMetalView(
                    level: 7,
                    xpProgress: 0.65,
                    isActive: true,
                    breathingScale: 1.0
                )
                .frame(width: 200, height: 200)

                SanctuaryProgressRingMetalView(
                    progress: 0.65,
                    ringWidth: 0.12
                )
                .frame(width: 100, height: 100)
            }
        }
        .frame(width: 800, height: 600)
    }
}
#endif
