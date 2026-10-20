// EmulatorToolbar.swift
// DroidPhone — Android soft navigation bar (Home, Back, Recents, Power)

import UIKit

class EmulatorToolbar: UIView {

    var onHome:    (() -> Void)?
    var onBack:    (() -> Void)?
    var onRecent:  (() -> Void)?
    var onPower:   (() -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.85)

        let buttons: [(String, Selector)] = [
            ("chevron.left",      #selector(backTapped)),
            ("house.fill",        #selector(homeTapped)),
            ("square.grid.2x2",   #selector(recentTapped)),
            ("power",             #selector(powerTapped)),
            ("xmark.circle.fill", #selector(dismissTapped)),
        ]

        let stack = UIStackView(arrangedSubviews: buttons.map { makeButton($0.0, action: $0.1) })
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeButton(_ systemName: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: systemName,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    @objc private func backTapped()    { onBack?() }
    @objc private func homeTapped()    { onHome?() }
    @objc private func recentTapped()  { onRecent?() }
    @objc private func powerTapped()   { onPower?() }
    @objc private func dismissTapped() { onDismiss?() }
}
