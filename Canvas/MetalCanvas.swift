// CosmoOS/Canvas/MetalCanvas.swift
// Metal-accelerated canvas renderer - 120fps on ProMotion displays
// Uses buffer pooling for optimal GPU memory management

import SwiftUI
import Foundation
import Metal
import MetalKit
import simd

class MetalCanvasView: NSView {
    private var metalDevice: MTLDevice!
    private var metalLayer: CAMetalLayer!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState?
    private var nsDisplayLink: CADisplayLink?

    // Buffer pooling for 120fps performance
    private var bufferPool: MetalBufferPool!
    private var frameBufferManager: FrameBufferManager!

    // Pre-allocated buffers for common operations
    private var gridVertexBuffer: MTLBuffer?
    private var gridColorBuffer: MTLBuffer?
    private var lastGridSize: CGSize = .zero

    // Canvas state
    var blocks: [CanvasBlock] = []
    var gridEnabled = true
    var backgroundColor: NSColor = .black

    // Performance metrics
    private var frameCount: Int = 0
    private var lastMetricsTime: CFAbsoluteTime = 0
    private(set) var currentFPS: Double = 0

    // SwiftPM builds do not auto-compile .metal files into the default library.
    // We bundle Shaders.metal as a resource and compile it at runtime.
    private static var cachedShaderLibrary: MTLLibrary?
    private static var cachedShaderLibraryDeviceName: String?

    // Must match `Uniforms` in `Canvas/Shaders.metal` (padding for 16-byte alignment).
    private struct Uniforms {
        var projectionMatrix: simd_float4x4
        var canvasSize: SIMD2<Float>
        var _padding: SIMD2<Float> = .zero
    }

    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetal()
        if pipelineState != nil {
            setupDisplayLink()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Metal Setup
    private func setupMetal() {
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not supported on this device")
            return
        }

        metalDevice = device
        guard let queue = device.makeCommandQueue() else {
            print("Failed to create Metal command queue")
            return
        }
        commandQueue = queue

        // Initialize buffer pool for 120fps performance
        bufferPool = MetalBufferPool(device: device)
        frameBufferManager = FrameBufferManager(pool: bufferPool)
        bufferPool.setupMemoryPressureHandling()

        // Setup Metal layer with 120Hz support
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = bounds

        // Enable EDR (Extended Dynamic Range) for ProMotion displays
        metalLayer.wantsExtendedDynamicRangeContent = true

        // Set maximum drawable count for triple buffering (smooth 120fps)
        metalLayer.maximumDrawableCount = 3

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale

        // Only set drawable size if we have valid dimensions
        if bounds.size.width > 0 && bounds.size.height > 0 {
            metalLayer.drawableSize = CGSize(
                width: bounds.size.width * scale,
                height: bounds.size.height * scale
            )
        }

        layer = metalLayer
        wantsLayer = true

        // Create render pipeline
        let pipelineReady = setupRenderPipeline()
        if pipelineReady {
            print("Metal canvas initialized (120Hz ready)")
            print("   GPU: \(device.name)")
            print("   Buffer pool: enabled")
        }
    }

    @discardableResult
    private func setupRenderPipeline() -> Bool {
        guard let library = makeShaderLibrary() else {
            print("❌ Failed to create Metal shader library (Shaders.metal)")
            return false
        }

        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            print("❌ Missing required Metal functions vertex_main/fragment_main in Shaders.metal")
            return false
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable blending for transparency
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            return true
        } catch {
            print("❌ Failed to create pipeline state: \(error)")
            pipelineState = nil
            return false
        }
    }

    private func makeShaderLibrary() -> MTLLibrary? {
        if let cached = Self.cachedShaderLibrary,
           Self.cachedShaderLibraryDeviceName == metalDevice.name {
            return cached
        }

        // Inline shader source - always available regardless of build system (Xcode or SwiftPM)
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Uniforms {
            float4x4 projectionMatrix;
            float2 canvasSize;
            float2 _padding;
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut vertex_main(
            const device float2* vertices [[buffer(0)]],
            const device float4* colors [[buffer(1)]],
            constant Uniforms& uniforms [[buffer(2)]],
            uint vid [[vertex_id]]
        ) {
            VertexOut out;
            float2 pos = vertices[vid];
            float x = (pos.x / uniforms.canvasSize.x) * 2.0 - 1.0;
            float y = 1.0 - (pos.y / uniforms.canvasSize.y) * 2.0;
            out.position = float4(x, y, 0.0, 1.0);
            out.color = colors[0];
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """

        do {
            let options = MTLCompileOptions()
            options.mathMode = .fast
            let library = try metalDevice.makeLibrary(source: shaderSource, options: options)
            Self.cachedShaderLibrary = library
            Self.cachedShaderLibraryDeviceName = metalDevice.name
            print("✅ Metal shaders compiled successfully")
            return library
        } catch {
            print("❌ Failed to compile Metal shaders: \(error)")
            return nil
        }
    }

    // MARK: - Display Link (120fps on ProMotion)
    private func setupDisplayLink() {
        let link = self.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.nsDisplayLink = link
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        render()
    }

    // MARK: - Rendering
    func render() {
        guard let pipelineState else { return }

        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Track FPS
        updateFPSMetrics()

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0
        )

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Bind uniforms (buffer index 2) required by Shaders.metal
        var uniforms = Uniforms(
            projectionMatrix: matrix_identity_float4x4,
            canvasSize: SIMD2(Float(bounds.width), Float(bounds.height))
        )
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)

        // Render grid (if enabled)
        if gridEnabled {
            renderGrid(encoder: renderEncoder)
        }

        // Render blocks using pooled buffers
        for block in blocks {
            renderBlock(block, encoder: renderEncoder)
        }

        renderEncoder.endEncoding()

        // Present with optimal timing for 120Hz
        drawable.present(afterMinimumDuration: 1.0 / 120.0)
        commandBuffer.commit()

        // Release frame buffers back to pool
        frameBufferManager.endFrame()
    }

    private func updateFPSMetrics() {
        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastMetricsTime

        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastMetricsTime = now
        }
    }

    private func renderGrid(encoder: MTLRenderCommandEncoder) {
        // Grid rendering with Metal (60fps, no matter how many lines)
        let gridSpacing: Float = 50.0
        let lineColor: [Float] = [0.2, 0.2, 0.2, 0.3]  // Dark gray, semi-transparent

        // Vertical lines
        var x: Float = 0
        while x < Float(bounds.width) {
            let vertices: [Float] = [
                x, 0.0,
                x, Float(bounds.height)
            ]

            renderLine(vertices: vertices, color: lineColor, encoder: encoder)
            x += gridSpacing
        }

        // Horizontal lines
        var y: Float = 0
        while y < Float(bounds.height) {
            let vertices: [Float] = [
                0.0, y,
                Float(bounds.width), y
            ]

            renderLine(vertices: vertices, color: lineColor, encoder: encoder)
            y += gridSpacing
        }
    }

    private func renderBlock(_ block: CanvasBlock, encoder: MTLRenderCommandEncoder) {
        // Convert block to Metal vertices
        let x = Float(block.position.x)
        let y = Float(block.position.y)
        let w = Float(block.size.width) * Float(block.scale)
        let h = Float(block.size.height) * Float(block.scale)

        // Quad vertices (2 triangles)
        let vertices: [Float] = [
            x, y,           // Bottom-left
            x + w, y,       // Bottom-right
            x, y + h,       // Top-left
            x + w, y + h    // Top-right
        ]

        // Block color based on type
        let color = block.entityType.metalColor

        // Use pooled buffers instead of creating new ones every frame
        guard let vertexBuffer = frameBufferManager.acquire(array: vertices),
              let colorBuffer = frameBufferManager.acquire(array: color) else {
            return
        }

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func renderLine(vertices: [Float], color: [Float], encoder: MTLRenderCommandEncoder) {
        // Use pooled buffers for optimal performance
        guard let vertexBuffer = frameBufferManager.acquire(array: vertices),
              let colorBuffer = frameBufferManager.acquire(array: color) else {
            return
        }

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: 2)
    }

    // MARK: - Cleanup
    @MainActor
    deinit {
        nsDisplayLink?.invalidate()
        nsDisplayLink = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Guard against zero-size frames (causes Metal errors)
        guard newSize.width > 0, newSize.height > 0 else { return }
        guard metalLayer != nil else { return }

        metalLayer.frame = bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: newSize.width * scale,
            height: newSize.height * scale
        )
    }
}

// MARK: - Entity Type Color Mapping
extension EntityType {
    var metalColor: [Float] {
        switch self {
        case .idea:
            return [0.6, 0.4, 1.0, 1.0]  // Purple
        case .content:
            return [0.2, 0.7, 1.0, 1.0]  // Blue
        case .connection:
            return [1.0, 0.6, 0.2, 1.0]  // Orange
        case .research:
            return [0.2, 0.8, 0.5, 1.0]  // Green
        case .task:
            return [1.0, 0.3, 0.5, 1.0]  // Pink
        case .project:
            return [0.5, 0.5, 1.0, 1.0]  // Light purple
        case .calendar:
            return [0.3, 0.6, 1.0, 1.0]  // Sky blue
        case .note:
            return [0.2, 0.9, 0.9, 1.0]  // Cyan
        case .cosmoAI:
            return [0.55, 0.35, 0.95, 1.0]  // Violet (AI purple)
        case .cosmo:
            return [0.7, 0.3, 1.0, 1.0]  // Purple (Cosmo)
        case .journal:
            return [1.0, 0.8, 0.3, 1.0]  // Yellow
        case .swipeFile:
            return [1.0, 0.5, 0.4, 1.0]  // Coral
        case .thinkspace:
            return [0.55, 0.36, 0.96, 1.0]  // Thinkspace purple
        }
    }
}

/*
 MARK: - Metal Shaders

 These shaders should be in a separate .metal file (Shaders.metal):

 ```metal
 #include <metal_stdlib>
 using namespace metal;

 struct VertexIn {
     float2 position [[attribute(0)]];
 };

 struct VertexOut {
     float4 position [[position]];
     float4 color;
 };

 vertex VertexOut vertex_main(
     const device VertexIn* vertices [[buffer(0)]],
     const device float4* colors [[buffer(1)]],
     uint vid [[vertex_id]]
 ) {
     VertexOut out;

     // Convert to NDC (normalized device coordinates)
     float2 position = vertices[vid].position;
     out.position = float4(
         (position.x / 1920.0) * 2.0 - 1.0,  // Normalize to [-1, 1]
         1.0 - (position.y / 1080.0) * 2.0,
         0.0,
         1.0
     );

     out.color = colors[0];
     return out;
 }

 fragment float4 fragment_main(VertexOut in [[stage_in]]) {
     return in.color;
 }
 ```
 */
