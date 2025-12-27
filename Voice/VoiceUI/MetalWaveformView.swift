// CosmoOS/Voice/VoiceUI/MetalWaveformView.swift
// Metal-accelerated waveform rendering for 120fps voice visualization
// Uses shared buffer pool for optimal GPU memory management

import SwiftUI
import MetalKit
import simd

// MARK: - Metal Waveform View (SwiftUI Wrapper)
struct MetalWaveformViewRepresentable: NSViewRepresentable {
    let levels: [Float]
    let barCount: Int
    let primaryColor: Color
    let secondaryColor: Color

    init(
        levels: [Float],
        barCount: Int = 12,
        primaryColor: Color = CosmoColors.cosmoAI,
        secondaryColor: Color = CosmoColors.lavender
    ) {
        self.levels = levels
        self.barCount = barCount
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }

    func makeNSView(context: Context) -> MetalWaveformNSView {
        let view = MetalWaveformNSView(barCount: barCount)
        view.setPrimaryColor(primaryColor)
        view.setSecondaryColor(secondaryColor)
        return view
    }

    func updateNSView(_ nsView: MetalWaveformNSView, context: Context) {
        nsView.updateLevels(levels)
    }
}

// MARK: - Metal Waveform NSView
class MetalWaveformNSView: NSView {
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?

    private var nsDisplayLink: CADisplayLink?
    private var currentLevels: [Float] = []
    private var targetLevels: [Float] = []
    private var barCount: Int

    // Buffer pooling for 120fps performance
    private var bufferPool: MetalBufferPool?
    private var frameBufferManager: FrameBufferManager?

    // Pre-allocated arrays to avoid per-frame allocations
    private var vertices: [SIMD2<Float>] = []
    private var colors: [SIMD4<Float>] = []

    // Colors (RGBA)
    private var primaryColor: SIMD4<Float> = SIMD4(0.72, 0.63, 0.85, 1.0)  // Lavender
    private var secondaryColor: SIMD4<Float> = SIMD4(0.66, 0.73, 0.91, 1.0)  // Sky blue

    // Animation (tuned for 120fps)
    private let interpolationSpeed: Float = 0.12  // Slightly slower for smoother 120fps
    private var lastFrameTime: CFTimeInterval = 0

    init(barCount: Int = 12) {
        self.barCount = barCount
        self.currentLevels = Array(repeating: 0.2, count: barCount)
        self.targetLevels = Array(repeating: 0.2, count: barCount)

        // Pre-allocate vertex arrays (6 vertices per bar for 2 triangles)
        self.vertices = Array(repeating: .zero, count: barCount * 6)
        self.colors = Array(repeating: .zero, count: barCount * 6)

        super.init(frame: .zero)
        setupMetal()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        self.barCount = 12
        super.init(coder: coder)
        setupMetal()
        setupDisplayLink()
    }

    @MainActor
    deinit {
        stopDisplayLink()
    }

    // MARK: - Setup
    private func setupMetal() {
        wantsLayer = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        self.device = device

        // Initialize buffer pool for 120fps performance
        bufferPool = MetalBufferPool(device: device)
        if let pool = bufferPool {
            frameBufferManager = FrameBufferManager(pool: pool)
        }

        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Enable triple buffering for smooth 120fps
        metalLayer.maximumDrawableCount = 3

        layer = metalLayer

        commandQueue = device.makeCommandQueue()

        // Create render pipeline
        createPipeline()
    }

    private func createPipeline() {
        // Use a simple vertex/fragment shader embedded as a string
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut vertexShader(
            uint vertexID [[vertex_id]],
            constant float2 *vertices [[buffer(0)]],
            constant float4 *colors [[buffer(1)]]
        ) {
            VertexOut out;
            out.position = float4(vertices[vertexID], 0.0, 1.0);
            out.color = colors[vertexID];
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            // Enable blending for smooth edges
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Failed to create Metal pipeline: \(error)")
        }
    }

    private func setupDisplayLink() {
        // Use modern NSView.displayLink API for macOS 26+
        let link = self.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.nsDisplayLink = link
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        render()
    }

    private func stopDisplayLink() {
        nsDisplayLink?.invalidate()
        nsDisplayLink = nil
    }

    // MARK: - Public API
    func updateLevels(_ levels: [Float]) {
        // Resample to barCount if needed
        if levels.isEmpty {
            targetLevels = (0..<barCount).map { i in
                Float(0.2 + 0.15 * sin(Double(i) * 0.6 + Date().timeIntervalSince1970 * 3))
            }
        } else {
            let step = max(1, levels.count / barCount)
            targetLevels = (0..<barCount).map { i in
                let index = min(i * step, levels.count - 1)
                return max(0.15, min(1.0, levels[index] * 1.5))
            }
        }
    }

    func setPrimaryColor(_ color: Color) {
        if let components = NSColor(color).cgColor.components, components.count >= 3 {
            primaryColor = SIMD4(
                Float(components[0]),
                Float(components[1]),
                Float(components[2]),
                components.count >= 4 ? Float(components[3]) : 1.0
            )
        }
    }

    func setSecondaryColor(_ color: Color) {
        if let components = NSColor(color).cgColor.components, components.count >= 3 {
            secondaryColor = SIMD4(
                Float(components[0]),
                Float(components[1]),
                Float(components[2]),
                components.count >= 4 ? Float(components[3]) : 1.0
            )
        }
    }

    // MARK: - Rendering
    private func render() {
        guard let pipelineState = pipelineState,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Interpolate current levels toward target levels (smooth animation)
        for i in 0..<barCount {
            currentLevels[i] += (targetLevels[i] - currentLevels[i]) * interpolationSpeed
        }

        // Update layer frame
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * (NSScreen.main?.backingScaleFactor ?? 2.0),
            height: bounds.height * (NSScreen.main?.backingScaleFactor ?? 2.0)
        )

        // Update pre-allocated vertex arrays (no allocations during render)
        let barWidth: Float = 0.06
        let spacing: Float = 0.02
        let totalWidth = Float(barCount) * barWidth + Float(barCount - 1) * spacing
        let startX = -totalWidth / 2

        for i in 0..<barCount {
            let level = currentLevels[i]
            let x = startX + Float(i) * (barWidth + spacing)
            let height = level * 0.8  // Scale to NDC
            let baseIndex = i * 6

            // Update quad vertices (two triangles) - no array creation
            // Bottom-left, Bottom-right, Top-left
            vertices[baseIndex] = SIMD2(x, -height / 2)
            vertices[baseIndex + 1] = SIMD2(x + barWidth, -height / 2)
            vertices[baseIndex + 2] = SIMD2(x, height / 2)

            // Top-left, Bottom-right, Top-right
            vertices[baseIndex + 3] = SIMD2(x, height / 2)
            vertices[baseIndex + 4] = SIMD2(x + barWidth, -height / 2)
            vertices[baseIndex + 5] = SIMD2(x + barWidth, height / 2)

            // Update colors for each vertex (2 triangles = 6 vertices)
            colors[baseIndex] = primaryColor      // Bottom-left
            colors[baseIndex + 1] = primaryColor  // Bottom-right
            colors[baseIndex + 2] = secondaryColor // Top-left
            colors[baseIndex + 3] = secondaryColor // Top-left
            colors[baseIndex + 4] = primaryColor  // Bottom-right
            colors[baseIndex + 5] = secondaryColor // Top-right
        }

        // Use pooled buffers for optimal performance
        let vertexBuffer: MTLBuffer?
        let colorBuffer: MTLBuffer?

        if let frameManager = frameBufferManager {
            vertexBuffer = frameManager.acquire(array: vertices)
            colorBuffer = frameManager.acquire(array: colors)
        } else {
            // Fallback to direct allocation
            vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<SIMD2<Float>>.stride,
                options: .storageModeShared
            )
            colorBuffer = device.makeBuffer(
                bytes: colors,
                length: colors.count * MemoryLayout<SIMD4<Float>>.stride,
                options: .storageModeShared
            )
        }

        guard let vBuffer = vertexBuffer, let cBuffer = colorBuffer else { return }

        // Render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(cBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()

        // Present with optimal timing for 120Hz
        drawable.present(afterMinimumDuration: 1.0 / 120.0)
        commandBuffer.commit()

        // Release pooled buffers
        frameBufferManager?.endFrame()
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
    }
}

// MARK: - Preview
// #Preview {
//     MetalWaveformViewRepresentable(
//         levels: (0..<60).map { _ in Float.random(in: 0.1...0.8) },
//         barCount: 12
//     )
//     .frame(width: 200, height: 40)
//     .background(Color.black)
// }
