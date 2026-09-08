/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import UIKit

class ProjectTableCell: UITableViewCell {
    static var reuseIdentifier: String = "NXProjectTableCell"
    private static let iconSide: CGFloat = 50
    private static let renderQueue = DispatchQueue(label: "org.emexlabs.nyxian.icon-render", qos: .userInitiated)
    private static let iconCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 8 * 1024 * 1024
        return c
    }()
    
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    private var titleCenterConstraint: NSLayoutConstraint!
    private var titleCenterConstraintBox: NSLayoutConstraint!
    private var subtitleBelowTitleConstraint: NSLayoutConstraint!
    private var iconConstraints: [NSLayoutConstraint] = []
    
    private var titleLeadingWithIcon: NSLayoutConstraint!
    private var titleLeadingWithoutIcon: NSLayoutConstraint!
    private var subtitleLeadingWithIcon: NSLayoutConstraint!
    private var subtitleLeadingWithoutIcon: NSLayoutConstraint!
    
    private var renderToken = UUID()
    private var pendingRawIcon: UIImage?
    private var pendingCacheKey: String?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setupViews()
        setupConstraints()
        observeScaleChanges()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        titleLabel.numberOfLines = 1
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .label
        
        subtitleLabel.numberOfLines = 1
        subtitleLabel.font = UIFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabel
        
        iconView.contentMode = .scaleAspectFit
        iconView.layer.minificationFilter = .trilinear
        
        if #unavailable(iOS 26.0) {
            iconView.clipsToBounds = true
            iconView.layer.cornerRadius = 10
            iconView.layer.cornerCurve = .continuous
            iconView.layer.borderWidth = 0.5
            iconView.layer.borderColor = UIColor.gray.cgColor
        }
        
        for v in [iconView, titleLabel, subtitleLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        
        separatorInset = .zero
        layoutMargins = .zero
        preservesSuperviewLayoutMargins = false
    }
    
    private func setupConstraints() {
        let side = Self.iconSide
        
        iconConstraints = [
            iconView.widthAnchor.constraint(equalToConstant: side),
            iconView.heightAnchor.constraint(equalToConstant: side),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ]
        
        titleLeadingWithIcon = titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16)
        titleLeadingWithoutIcon = titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        subtitleLeadingWithIcon = subtitleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16)
        subtitleLeadingWithoutIcon = subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        
        titleCenterConstraint = titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        titleCenterConstraintBox = titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10)
        subtitleBelowTitleConstraint = subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        
        NSLayoutConstraint.activate([
            titleCenterConstraint,
            subtitleBelowTitleConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
        
        NSLayoutConstraint.activate(iconConstraints)
        titleLeadingWithIcon.isActive = true
        subtitleLeadingWithIcon.isActive = true
    }
    
    private func observeScaleChanges() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitDisplayScale.self]) { (cell: ProjectTableCell, _) in
                cell.rerenderIconIfNeeded()
            }
        }
    }
    
    @available(iOS, deprecated: 17.0)
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if #unavailable(iOS 17.0) {
            if previous?.displayScale != traitCollection.displayScale {
                rerenderIconIfNeeded()
            }
        }
    }
    
    func configure(displayName: String,
                   bundleIdentifier: String?,
                   appIcon: UIImage?,
                   showArrow: Bool,
                   cacheKey: String? = nil) {
        titleLabel.text = displayName
        accessoryType = showArrow ? .disclosureIndicator : .none
        
        if let bundleIdentifier {
            subtitleLabel.text = bundleIdentifier
            subtitleLabel.isHidden = false
            subtitleBelowTitleConstraint.isActive = true
            titleCenterConstraint.isActive = false
            titleCenterConstraintBox.isActive = true
        } else {
            subtitleLabel.text = nil
            subtitleLabel.isHidden = true
            subtitleBelowTitleConstraint.isActive = false
            titleCenterConstraintBox.isActive = false
            titleCenterConstraint.isActive = true
        }
        
        var appIcon: UIImage? = appIcon
        if appIcon == nil {
            if #unavailable(iOS 26.0) {
                appIcon = UIImage(named: "DefaultIcon")
            }
        }
        
        //if let appIcon {
            iconView.isHidden = false
            NSLayoutConstraint.activate(iconConstraints)
            titleLeadingWithoutIcon.isActive = false
            titleLeadingWithIcon.isActive = true
            subtitleLeadingWithoutIcon.isActive = false
            subtitleLeadingWithIcon.isActive = true
            pendingRawIcon = appIcon
            pendingCacheKey = cacheKey ?? bundleIdentifier ?? displayName
            applyIcon(appIcon, key: pendingCacheKey!)
        /*} else {
            iconView.isHidden = true
            iconView.image = nil
            pendingRawIcon = nil
            pendingCacheKey = nil
            NSLayoutConstraint.deactivate(iconConstraints)
            titleLeadingWithIcon.isActive = false
            titleLeadingWithoutIcon.isActive = true
            subtitleLeadingWithIcon.isActive = false
            subtitleLeadingWithoutIcon.isActive = true
        }*/
    }
    
    private var currentScale: CGFloat {
        let s = traitCollection.displayScale
        return s > 0 ? s : 3.0
    }
    
    private func rerenderIconIfNeeded() {
        guard let raw = pendingRawIcon, let key = pendingCacheKey else { return }
        applyIcon(raw, key: key)
    }
    
    private func applyIcon(_ raw: UIImage?, key: String) {
        guard #available(iOS 26.0, *) else {
            renderToken = UUID()
            iconView.image = raw
            return
        }
        
        let scale = currentScale
        let side = Self.iconSide
        let cacheKey = "\(key)|\(side)@\(scale)" as NSString
        
        if let hit = Self.iconCache.object(forKey: cacheKey) {
            renderToken = UUID()
            iconView.image = hit
            return
        }
        
        let token = UUID()
        renderToken = token
        iconView.image = nil
        
        Self.renderQueue.async { [weak self] in
            var rendered: UIImage? = nil
            if let raw = raw {
                rendered = Gib26Icon(raw, CGSize(width: side, height: side), scale)
            } else {
                rendered = Gib26FallbackIcon(CGSize(width: side, height: side), scale)
            }
            rendered = rendered?.preparingForDisplay() ?? rendered
            
            DispatchQueue.main.async { [weak self] in
                if let rendered {
                    let px = side * scale
                    Self.iconCache.setObject(rendered, forKey: cacheKey, cost: Int(px * px * 4))
                }
                guard let self, self.renderToken == token else { return }
                self.iconView.image = rendered
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        renderToken = UUID()
        pendingRawIcon = nil
        pendingCacheKey = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        iconView.image = nil
        accessoryType = .none
        iconView.isHidden = false
        subtitleLabel.isHidden = false
    }
}
