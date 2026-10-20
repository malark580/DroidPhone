// EmulatorLaunchViewController.swift
// DroidPhone — Image download + QEMU launch flow

import UIKit

class EmulatorLaunchViewController: UIViewController {

    private let version: AndroidVersion

    // MARK: - UI Elements
    private let statusLabel    = UILabel()
    private let progressView   = UIProgressView(progressViewStyle: .default)
    private let actionButton   = UIButton(type: .system)
    private let infoCard       = UIView()

    private var downloadTask: URLSessionDownloadTask?

    init(version: AndroidVersion) {
        self.version = version
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = version.name
        view.backgroundColor = .systemBackground
        setupUI()
        checkImageAvailability()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Info card
        infoCard.backgroundColor = UIColor(named: "AccentColor")?.withAlphaComponent(0.1)
               ?? .systemGreen.withAlphaComponent(0.1)
        infoCard.layer.cornerRadius = 14
        infoCard.translatesAutoresizingMaskIntoConstraints = false

        let specs: [(String, String)] = [
            ("Android Version", version.name),
            ("Codename",        version.codename),
            ("API Level",       "API \(version.api)"),
            ("RAM",             "\(version.ramMB) MB"),
            ("Storage",         "\(version.diskGB) GB"),
            ("Architecture",    "x86_64 (QEMU TCG)"),
        ]
        let specStack = UIStackView(arrangedSubviews: specs.map { specRow($0.0, value: $0.1) })
        specStack.axis = .vertical
        specStack.spacing = 8
        specStack.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(specStack)

        // Status label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Progress view
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true

        // Action button
        actionButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        actionButton.backgroundColor = .systemGreen
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 14
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        [infoCard, specStack, statusLabel, progressView, actionButton].forEach { view.addSubview($0) }
        // Re-add since specStack is inside infoCard
        infoCard.addSubview(specStack)

        NSLayoutConstraint.activate([
            infoCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            infoCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            specStack.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 16),
            specStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            specStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),
            specStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            actionButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func specRow(_ title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = .secondaryLabel
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .boldSystemFont(ofSize: 14)
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: - Image Availability

    private var imagePath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(version.imageName)
    }

    private func checkImageAvailability() {
        if FileManager.default.fileExists(atPath: imagePath.path) {
            setReady()
        } else {
            setNeedsDownload()
        }
    }

    private func setReady() {
        statusLabel.text = "✅ Image ready — tap Launch to start Android"
        progressView.isHidden = true
        actionButton.setTitle("▶  Launch \(version.name)", for: .normal)
        actionButton.backgroundColor = .systemGreen
    }

    private func setNeedsDownload() {
        statusLabel.text = "⬇  Android image not found. Tap to download (~\(version.diskGB) GB)"
        actionButton.setTitle("Download Image", for: .normal)
        actionButton.backgroundColor = .systemBlue
    }

    // MARK: - Actions

    @objc private func actionTapped() {
        if FileManager.default.fileExists(atPath: imagePath.path) {
            launchEmulator()
        } else {
            downloadImage()
        }
    }

    // MARK: - Download

    private func downloadImage() {
        guard let url = URL(string: version.downloadURL) else { return }
        actionButton.isEnabled = false
        progressView.isHidden = false
        statusLabel.text = "⬇  Downloading \(version.name) image..."

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    // MARK: - Launch QEMU

    private func launchEmulator() {
        let emulatorVC = EmulatorViewController(version: version, imagePath: imagePath)
        emulatorVC.modalPresentationStyle = .fullScreen
        present(emulatorVC, animated: true)
    }
}

// MARK: - URLSessionDownloadDelegate

extension EmulatorLaunchViewController: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        progressView.setProgress(progress, animated: true)
        let mb = totalBytesWritten / 1_048_576
        let total = totalBytesExpectedToWrite / 1_048_576
        statusLabel.text = "⬇  \(mb) / \(total) MB"
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.moveItem(at: location, to: imagePath)
            setReady()
        } catch {
            statusLabel.text = "❌ Failed to save image: \(error.localizedDescription)"
            actionButton.isEnabled = true
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            statusLabel.text = "❌ Download failed: \(error.localizedDescription)"
            actionButton.isEnabled = true
            progressView.isHidden = true
        }
    }
}
