// HomeViewController.swift
// DroidPhone — Select Android version and launch emulation

import UIKit

struct AndroidVersion {
    let name: String
    let api: Int
    let codename: String
    let imageName: String   // filename of the disk image in app bundle / documents
    let downloadURL: String // fallback download URL
    let ramMB: Int
    let diskGB: Int
}

class HomeViewController: UIViewController {

    // MARK: - Android Version Catalogue

    static let versions: [AndroidVersion] = [
        AndroidVersion(name: "Android 4.4", api: 19, codename: "KitKat",
                       imageName: "android-x86-4.4-r5.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%204.4/android-x86-4.4-r5.iso/download",
                       ramMB: 512, diskGB: 4),
        AndroidVersion(name: "Android 5.1", api: 22, codename: "Lollipop",
                       imageName: "android-x86-5.1-r5.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%205.1/android-x86-5.1-r5.iso/download",
                       ramMB: 768, diskGB: 4),
        AndroidVersion(name: "Android 6.0", api: 23, codename: "Marshmallow",
                       imageName: "android-x86-6.0-r3.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%206.0/android-x86-6.0-r3.iso/download",
                       ramMB: 1024, diskGB: 6),
        AndroidVersion(name: "Android 7.1", api: 25, codename: "Nougat",
                       imageName: "android-x86-7.1-r5.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%207.1/android-x86-7.1-r5.iso/download",
                       ramMB: 1024, diskGB: 6),
        AndroidVersion(name: "Android 8.1", api: 27, codename: "Oreo",
                       imageName: "android-x86-8.1-r6.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%208.1/android-x86-8.1-r6.iso/download",
                       ramMB: 1536, diskGB: 8),
        AndroidVersion(name: "Android 9.0", api: 28, codename: "Pie",
                       imageName: "android-x86-9.0-r2.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%209.0/android-x86-9.0-r2.iso/download",
                       ramMB: 2048, diskGB: 8),
        AndroidVersion(name: "Android 10", api: 29, codename: "Q",
                       imageName: "android-x86-10.0-r5.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%2010.0/android-x86-10.0-r5.iso/download",
                       ramMB: 2048, diskGB: 8),
        AndroidVersion(name: "Android 11", api: 30, codename: "R",
                       imageName: "android-x86-11.0-r5.iso",
                       downloadURL: "https://sourceforge.net/projects/android-x86/files/Release%2011.0/android-x86-11.0-r5.iso/download",
                       ramMB: 3072, diskGB: 12),
    ]

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(VersionCell.self, forCellReuseIdentifier: VersionCell.reuseID)
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "🤖 DroidPhone"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource / Delegate

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Self.versions.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Choose Android Version"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VersionCell.reuseID, for: indexPath) as! VersionCell
        cell.configure(with: Self.versions[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 70 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let version = Self.versions[indexPath.row]
        let vc = EmulatorLaunchViewController(version: version)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - VersionCell

class VersionCell: UITableViewCell {
    static let reuseID = "VersionCell"

    private let versionLabel = UILabel()
    private let codenameLabel = UILabel()
    private let apiLabel = UILabel()
    private let androidIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let robotEmoji = UILabel()
        robotEmoji.text = "🤖"
        robotEmoji.font = .systemFont(ofSize: 32)
        robotEmoji.translatesAutoresizingMaskIntoConstraints = false

        versionLabel.font = .boldSystemFont(ofSize: 17)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        codenameLabel.font = .systemFont(ofSize: 13)
        codenameLabel.textColor = .secondaryLabel
        codenameLabel.translatesAutoresizingMaskIntoConstraints = false

        apiLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        apiLabel.textColor = .tertiaryLabel
        apiLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [versionLabel, codenameLabel, apiLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(robotEmoji)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            robotEmoji.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            robotEmoji.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            robotEmoji.widthAnchor.constraint(equalToConstant: 44),

            stack.leadingAnchor.constraint(equalTo: robotEmoji.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        accessoryType = .disclosureIndicator
    }

    func configure(with version: AndroidVersion) {
        versionLabel.text = version.name
        codenameLabel.text = version.codename
        apiLabel.text = "API \(version.api) · \(version.ramMB) MB RAM · \(version.diskGB) GB disk"
    }
}
