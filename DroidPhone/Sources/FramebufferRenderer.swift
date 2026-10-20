// FramebufferRenderer.swift
// DroidPhone — Metal renderer for QEMU framebuffer output

import MetalKit
import CoreVideo

class FramebufferRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var currentPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()

    // Vertex buffer for a fullscreen quad
    private var vertexBuffer: MTLBuffer?

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        setupPipeline()
        setupTextureCache()
        setupVertexBuffer()
    }

    // MARK: - Setup

    private func setupPipeline() {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vid [[vertex_id]],
                                      constant float4 *vertices [[buffer(0)]]) {
            VertexOut out;
            float2 pos = vertices[vid].xy;
            float2 uv  = vertices[vid].zw;
            out.position = float4(pos, 0.0, 1.0);
            out.texCoord = uv;
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]],
                                       sampler smp [[sampler(0)]]) {
            return tex.sample(smp, in.texCoord);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vertFn  = library.makeFunction(name: "vertexShader"),
              let fragFn  = library.makeFunction(name: "fragmentShader") else {
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertFn
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func setupTextureCache() {
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    private func setupVertexBuffer() {
        // Fullscreen quad: pos (NDC), texcoord
        let vertices: [Float] = [
            -1,  1,   0, 0,   // top-left
             1,  1,   1, 0,   // top-right
            -1, -1,   0, 1,   // bottom-left
             1, -1,   1, 1,   // bottom-right
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: .storageModeShared)
    }

    // MARK: - Update

    func update(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        currentPixelBuffer = pixelBuffer
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let pb = currentPixelBuffer
        lock.unlock()

        guard let pb,
              let cache = textureCache,
              let pipeline = pipelineState,
              let vbuf = vertexBuffer,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store

        // Create Metal texture from CVPixelBuffer
        let width  = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pb,
                                                  nil, .bgra8Unorm,
                                                  width, height, 0, &cvTexture)
        guard let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else {
            encoder.endEncoding()
            cmdBuf.present(drawable)
            cmdBuf.commit()
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vbuf, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)

        // Default sampler (linear filtering)
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        if let sampler = device.makeSamplerState(descriptor: samplerDesc) {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
