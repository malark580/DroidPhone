// EmulatorViewController.swift
// DroidPhone — Metal-rendered QEMU framebuffer + touch input

import UIKit
import MetalKit

class EmulatorViewController: UIViewController {

    private let version: AndroidVersion
    private let imagePath: URL

    // QEMU bridge (wraps the C library)
    private var qemuBridge: QEMUBridge?

    // Metal rendering
    private var metalView: MTKView!
    private var renderer: FramebufferRenderer?

    // Toolbar
    private lazy var toolbar = EmulatorToolbar()

    // MARK: - Init

    init(version: AndroidVersion, imagePath: URL) {
        self.version = version
        self.imagePath = imagePath
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetalView()
        setupToolbar()
        startQEMU()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        qemuBridge?.stop()
    }

    // MARK: - Metal View

    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            showError("Metal not available on this device.")
            return
        }
        metalView = MTKView(frame: .zero, device: device)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 30
        view.addSubview(metalView)

        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -44),
        ])

        renderer = FramebufferRenderer(device: device)
        metalView.delegate = renderer
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.onHome    = { [weak self] in self?.qemuBridge?.sendKey(.home) }
        toolbar.onBack    = { [weak self] in self?.qemuBridge?.sendKey(.back) }
        toolbar.onRecent  = { [weak self] in self?.qemuBridge?.sendKey(.appSwitch) }
        toolbar.onPower   = { [weak self] in self?.qemuBridge?.sendKey(.power) }
        toolbar.onDismiss = { [weak self] in self?.dismiss(animated: true) }
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - QEMU Launch

    private func startQEMU() {
        let config = QEMUConfig(
            imagePath:  imagePath.path,
            ramMB:      version.ramMB,
            cpuCores:   ProcessInfo.processInfo.processorCount,
            androidAPI: version.api
        )
        qemuBridge = QEMUBridge(config: config)
        qemuBridge?.onFrameReady = { [weak self] pixelBuffer in
            self?.renderer?.update(pixelBuffer: pixelBuffer)
        }
        qemuBridge?.start()
    }

    // MARK: - Touch → QEMU USB Tablet

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        forwardTouches(touches, phase: .began)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        forwardTouches(touches, phase: .moved)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        forwardTouches(touches, phase: .ended)
    }

    private func forwardTouches(_ touches: Set<UITouch>, phase: UITouch.Phase) {
        guard let touch = touches.first, let mv = metalView else { return }
        let pt = touch.location(in: mv)
        let normalized = CGPoint(
            x: pt.x / mv.bounds.width,
            y: pt.y / mv.bounds.height
        )
        let buttons: UInt32 = (phase == .ended) ? 0 : 1
        qemuBridge?.sendPointerEvent(x: Float(normalized.x),
                                     y: Float(normalized.y),
                                     buttons: buttons)
    }

    // MARK: - Error

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - Status Bar

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
}
