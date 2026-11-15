import SGSimpleSettings
import UIKit

private func ayuPlane(_ rect: CGRect, foreground: UIColor, secondary: UIColor) {
    let shapes: [([(CGFloat, CGFloat)], UIColor)] = [
        ([(0.02, 0.65), (0.43, 0.02), (0.45, 0.02), (0.31, 0.65)], foreground),
        ([(0.36, 0.69), (0.46, 0.30), (0.48, 0.28), (0.48, 0.98)], foreground),
        ([(0.56, 0.02), (0.59, 0.02), (0.99, 0.65), (0.72, 0.65)], secondary),
        ([(0.54, 0.28), (0.57, 0.31), (0.68, 0.69), (0.54, 0.98)], secondary)
    ]
    for (points, color) in shapes {
        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            let value = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: value) } else { path.addLine(to: value) }
        }
        path.close()
        color.setFill()
        path.fill()
    }
}

public func ayuGramOwnerBadgeImage() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
        let seal = UIBezierPath()
        for index in 0 ..< 32 {
            let angle = CGFloat(index) * .pi / 16 - .pi / 2
            let radius: CGFloat = index % 2 == 0 ? 10.8 : 9.6
            let point = CGPoint(x: 11 + cos(angle) * radius, y: 11 + sin(angle) * radius)
            if index == 0 { seal.move(to: point) } else { seal.addLine(to: point) }
        }
        seal.close()
        UIColor(red: 0.56, green: 0.38, blue: 0.95, alpha: 1).setFill()
        seal.fill()
        ayuPlane(CGRect(x: 4.5, y: 4.2, width: 13, height: 13), foreground: .white, secondary: UIColor(red: 0.85, green: 0.77, blue: 1, alpha: 1))
    }
}

private func ayuBadgeColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
}

private struct AyuBadgeStyle {
    var colors: [UIColor]
    var foreground: UIColor
    var secondary: UIColor
    var text: UIColor
    var watermark: CGFloat
    var dots: [UIColor]
    var dotRadius: ClosedRange<CGFloat>
    var dotCount: Int
    var glow: UIColor?
}

private func ayuBadgeStyle(_ name: String) -> AyuBadgeStyle {
    switch name {
    case "SkyAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.25, 0.42, 0.97), ayuBadgeColor(0.36, 0.62, 1.0)], foreground: .white, secondary: ayuBadgeColor(0.80, 0.88, 1), text: .white, watermark: 0.12, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.22))
    case "NightAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.04, 0.05, 0.18), ayuBadgeColor(0.10, 0.12, 0.32)], foreground: ayuBadgeColor(0.64, 0.52, 1), secondary: ayuBadgeColor(1, 0.56, 0.82), text: .white, watermark: 0, dots: [ayuBadgeColor(1, 1, 1, 0.75), ayuBadgeColor(1, 0.60, 0.85, 0.8), ayuBadgeColor(0.65, 0.60, 1, 0.8)], dotRadius: 0.3 ... 0.7, dotCount: 34, glow: nil)
    case "TitaniumAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.03, 0.03, 0.04), ayuBadgeColor(0.20, 0.20, 0.22), ayuBadgeColor(0.07, 0.07, 0.08)], foreground: ayuBadgeColor(0.62, 0.62, 0.64), secondary: ayuBadgeColor(0.42, 0.42, 0.45), text: ayuBadgeColor(0.86, 0.86, 0.88), watermark: 0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.08))
    case "ProAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.44, 0.24, 0.98), ayuBadgeColor(0.70, 0.30, 0.62), ayuBadgeColor(0.96, 0.42, 0.20)], foreground: .white, secondary: ayuBadgeColor(1, 0.86, 0.76), text: .white, watermark: 0.12, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    case "DayAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(1, 0.91, 0.95), ayuBadgeColor(0.89, 0.88, 1)], foreground: ayuBadgeColor(0.60, 0.40, 0.98), secondary: ayuBadgeColor(1, 0.45, 0.62), text: ayuBadgeColor(0.45, 0.30, 0.92), watermark: 0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.5))
    case "DuckyAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.02, 0.02, 0.02), ayuBadgeColor(0.08, 0.05, 0.03)], foreground: ayuBadgeColor(1, 0.85, 0.22), secondary: ayuBadgeColor(1, 0.60, 0.10), text: .white, watermark: 0, dots: [ayuBadgeColor(0.62, 0.32, 0.10, 0.85), ayuBadgeColor(0.45, 0.22, 0.08, 0.85)], dotRadius: 0.5 ... 1.1, dotCount: 26, glow: nil)
    case "SparklingAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.08, 0.08, 0.40), ayuBadgeColor(0.20, 0.18, 0.72), ayuBadgeColor(0.08, 0.08, 0.40)], foreground: ayuBadgeColor(0.56, 0.58, 1), secondary: ayuBadgeColor(0.82, 0.82, 1), text: .white, watermark: 0, dots: [ayuBadgeColor(1, 1, 1, 0.85), ayuBadgeColor(0.75, 0.80, 1, 0.8)], dotRadius: 0.3 ... 0.8, dotCount: 30, glow: ayuBadgeColor(0.55, 0.55, 1, 0.35))
    default:
        let color: UIColor
        switch AyuGramIconSettings.selectedName ?? UIApplication.shared.alternateIconName {
        case "AyuRed": color = ayuBadgeColor(0.91, 0.15, 0.17)
        case "AyuPurple": color = ayuBadgeColor(0.50, 0.25, 0.96)
        default: color = ayuBadgeColor(0.19, 0.15, 0.28)
        }
        return AyuBadgeStyle(colors: [color, color], foreground: .white, secondary: ayuBadgeColor(0.83, 0.73, 1), text: .white, watermark: 0.2, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    }
}

public let ayuGramAppBadgeStyles: [(name: String, title: String)] = [
    ("Components/AppBadge", "Default"),
    ("SkyAppBadge", "Sky"),
    ("NightAppBadge", "Night"),
    ("TitaniumAppBadge", "Titanium"),
    ("ProAppBadge", "Pro"),
    ("DayAppBadge", "Day"),
    ("DuckyAppBadge", "Ducky"),
    ("SparklingAppBadge", "Sparkling")
]

/// Swiftgram's original badges, kept as images; their stored name has this prefix.
public let swiftgramAppBadgePrefix = "SG:"

/// Loads a bundled image by its asset name; set by the app window.
public var ayuGramBundleImageLoader: ((String) -> UIImage?)?

public let swiftgramAppBadgeStyles: [(name: String, title: String)] = [
    ("SG:Components/AppBadge", "Default"),
    ("SG:SkyAppBadge", "Sky"),
    ("SG:NightAppBadge", "Night"),
    ("SG:TitaniumAppBadge", "Titanium"),
    ("SG:ProAppBadge", "Pro"),
    ("SG:DayAppBadge", "Day"),
    ("SG:DuckyAppBadge", "Ducky"),
    ("SG:SparklingAppBadge", "Sparkling")
]

public let telegramAppBadgePrefix = "TG:"
public let ayuCustomTextBadgeId = "AYU:CUSTOM_TEXT"
public let ayuCustomImageBadgeId = "AYU:CUSTOM_IMAGE"

public let telegramAppBadgeStyles: [(name: String, title: String)] = [
    ("TG:Default", "Telegram"),
    ("TG:Blue", "Telegram Blue"),
    ("TG:Classic", "Classic"),
    ("TG:Dark", "Dark"),
    ("TG:Black", "Black"),
    ("TG:Gold", "Gold"),
    ("TG:Minimal", "Minimal")
]

public struct AyuCustomBadgeThemeOption: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let colors: [UIColor]
    public let textColor: UIColor
    public let accentColor: UIColor
}

public let ayuCustomBadgeThemes: [AyuCustomBadgeThemeOption] = [
    AyuCustomBadgeThemeOption(
        id: "telegram",
        title: "Telegram Blue",
        colors: [ayuBadgeColor(0.16, 0.56, 0.96), ayuBadgeColor(0.11, 0.70, 0.96)],
        textColor: .white,
        accentColor: ayuBadgeColor(0.84, 0.94, 1.0)
    ),
    AyuCustomBadgeThemeOption(
        id: "purple",
        title: "Ayu Purple",
        colors: [ayuBadgeColor(0.38, 0.24, 0.85), ayuBadgeColor(0.62, 0.34, 0.98)],
        textColor: .white,
        accentColor: ayuBadgeColor(0.88, 0.80, 1.0)
    ),
    AyuCustomBadgeThemeOption(
        id: "midnight",
        title: "Midnight",
        colors: [ayuBadgeColor(0.06, 0.08, 0.20), ayuBadgeColor(0.14, 0.17, 0.36)],
        textColor: .white,
        accentColor: ayuBadgeColor(0.56, 0.72, 1.0)
    ),
    AyuCustomBadgeThemeOption(
        id: "obsidian",
        title: "Obsidian",
        colors: [ayuBadgeColor(0.05, 0.05, 0.06), ayuBadgeColor(0.18, 0.18, 0.20)],
        textColor: ayuBadgeColor(0.95, 0.95, 0.97),
        accentColor: ayuBadgeColor(0.70, 0.70, 0.74)
    ),
    AyuCustomBadgeThemeOption(
        id: "crimson",
        title: "Crimson",
        colors: [ayuBadgeColor(0.75, 0.12, 0.24), ayuBadgeColor(0.95, 0.30, 0.24)],
        textColor: .white,
        accentColor: ayuBadgeColor(1.0, 0.84, 0.84)
    ),
    AyuCustomBadgeThemeOption(
        id: "emerald",
        title: "Emerald",
        colors: [ayuBadgeColor(0.06, 0.54, 0.38), ayuBadgeColor(0.14, 0.74, 0.52)],
        textColor: .white,
        accentColor: ayuBadgeColor(0.80, 1.0, 0.90)
    ),
    AyuCustomBadgeThemeOption(
        id: "gold",
        title: "Gold",
        colors: [ayuBadgeColor(0.72, 0.50, 0.08), ayuBadgeColor(0.94, 0.72, 0.20)],
        textColor: ayuBadgeColor(0.12, 0.08, 0.02),
        accentColor: ayuBadgeColor(0.30, 0.20, 0.04)
    ),
    AyuCustomBadgeThemeOption(
        id: "sunset",
        title: "Sunset",
        colors: [ayuBadgeColor(0.46, 0.22, 0.96), ayuBadgeColor(0.92, 0.38, 0.34)],
        textColor: .white,
        accentColor: ayuBadgeColor(1.0, 0.88, 0.82)
    )
]

private enum CustomBadgeDefaultsKey {
    static let text = "ayugram.customBadge.text"
    static let theme = "ayugram.customBadge.theme"
    static let showIcon = "ayugram.customBadge.showIcon"
}

public func ayuCustomBadgeSettings() -> (text: String, themeId: String, showIcon: Bool) {
    let defaults = UserDefaults.standard
    let rawText = defaults.string(forKey: CustomBadgeDefaultsKey.text)
    let text = rawText?.trimmingCharacters(in: .newlines) ?? "TELEGRAM"
    let themeId = defaults.string(forKey: CustomBadgeDefaultsKey.theme) ?? "telegram"
    let showIcon = defaults.object(forKey: CustomBadgeDefaultsKey.showIcon) as? Bool ?? true
    return (text, themeId, showIcon)
}

public func ayuSetCustomBadgeSettings(text: String, themeId: String, showIcon: Bool) {
    let defaults = UserDefaults.standard
    let cleaned = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
    defaults.set(cleaned, forKey: CustomBadgeDefaultsKey.text)
    defaults.set(themeId, forKey: CustomBadgeDefaultsKey.theme)
    defaults.set(showIcon, forKey: CustomBadgeDefaultsKey.showIcon)
}

public func ayuCustomBadgeImageURL() -> URL? {
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return appSupport.appendingPathComponent("AyuGramCustomBadge", isDirectory: true).appendingPathComponent("badge.png")
}

public func ayuHasCustomBadgeImage() -> Bool {
    guard let url = ayuCustomBadgeImageURL() else {
        return false
    }
    return FileManager.default.fileExists(atPath: url.path)
}

@discardableResult
public func ayuSaveCustomBadgeImage(_ sourceImage: UIImage) -> Bool {
    guard let url = ayuCustomBadgeImageURL() else {
        return false
    }
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let targetHeight: CGFloat = 23.0
    let aspect = sourceImage.size.height > 0 ? (sourceImage.size.width / sourceImage.size.height) : 4.0
    let targetWidth = max(23.0, min(140.0, round(targetHeight * aspect)))
    let targetSize = CGSize(width: targetWidth, height: targetHeight)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 3.0
    format.opaque = false
    let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
        let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: targetSize), cornerRadius: targetHeight / 2.0)
        capsule.addClip()
        sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let pngData = rendered.pngData() else {
        return false
    }
    do {
        try pngData.write(to: url, options: .atomic)
        return true
    } catch {
        return false
    }
}

public func ayuClearCustomBadgeImage() {
    guard let url = ayuCustomBadgeImageURL() else {
        return
    }
    try? FileManager.default.removeItem(at: url)
}

private func ayuTelegramBadgeStyle(_ name: String) -> AyuBadgeStyle {
    switch name {
    case "TG:Blue":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.14, 0.56, 0.96), ayuBadgeColor(0.08, 0.72, 0.96)], foreground: .white, secondary: ayuBadgeColor(0.84, 0.94, 1.0), text: .white, watermark: 0.10, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.18))
    case "TG:Classic":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.18, 0.64, 0.90), ayuBadgeColor(0.15, 0.56, 0.84)], foreground: .white, secondary: ayuBadgeColor(0.84, 0.95, 1.0), text: .white, watermark: 0.0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    case "TG:Dark":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.11, 0.14, 0.22), ayuBadgeColor(0.17, 0.22, 0.34)], foreground: ayuBadgeColor(0.24, 0.68, 1.0), secondary: ayuBadgeColor(0.62, 0.86, 1.0), text: .white, watermark: 0.0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    case "TG:Black":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.04, 0.04, 0.05), ayuBadgeColor(0.12, 0.12, 0.14)], foreground: .white, secondary: ayuBadgeColor(0.75, 0.75, 0.78), text: .white, watermark: 0.0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.06))
    case "TG:Gold":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.72, 0.50, 0.10), ayuBadgeColor(0.95, 0.74, 0.24)], foreground: ayuBadgeColor(0.15, 0.10, 0.02), secondary: ayuBadgeColor(0.32, 0.22, 0.05), text: ayuBadgeColor(0.14, 0.09, 0.02), watermark: 0.08, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.24))
    case "TG:Minimal":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.94, 0.96, 0.99), ayuBadgeColor(0.88, 0.92, 0.97)], foreground: ayuBadgeColor(0.14, 0.54, 0.94), secondary: ayuBadgeColor(0.40, 0.72, 0.98), text: ayuBadgeColor(0.10, 0.22, 0.38), watermark: 0.0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    default: // TG:Default
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.16, 0.54, 0.95), ayuBadgeColor(0.24, 0.66, 0.98)], foreground: .white, secondary: ayuBadgeColor(0.84, 0.94, 1.0), text: .white, watermark: 0.08, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    }
}

private func ayuRenderCapsuleBadge(
    label: String,
    style: AyuBadgeStyle,
    showIcon: Bool,
    scale: CGFloat,
    fixedWidth: CGFloat? = nil
) -> UIImage {
    let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.text]
    let nsText = label as NSString
    let textSize = nsText.size(withAttributes: attributes)

    let height: CGFloat = 23
    let computedWidth: CGFloat
    if let fixedWidth {
        computedWidth = fixedWidth
    } else if label.isEmpty && showIcon {
        computedWidth = 34
    } else if showIcon {
        computedWidth = max(76, min(168, ceil(28 + textSize.width + 10)))
    } else {
        computedWidth = max(56, min(168, ceil(textSize.width + 20)))
    }

    let base = CGSize(width: computedWidth, height: height)
    let format = UIGraphicsImageRendererFormat.preferred()
    if scale > 0 {
        format.scale = scale
    }
    return UIGraphicsImageRenderer(size: base, format: format).image { renderer in
        let context = renderer.cgContext
        let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: base), cornerRadius: base.height / 2)
        context.saveGState()
        capsule.addClip()
        let cgColors = style.colors.map { $0.cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: base.width, y: base.height), options: [])
        }
        if let glow = style.glow, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [glow.cgColor, glow.withAlphaComponent(0).cgColor] as CFArray, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: base.height * 0.6), options: [])
        }
        var seed: UInt32 = 0x41595547
        func next() -> CGFloat {
            seed = seed &* 1664525 &+ 1013904223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        for index in 0 ..< style.dotCount {
            let radius = style.dotRadius.lowerBound + (style.dotRadius.upperBound - style.dotRadius.lowerBound) * next()
            let point = CGPoint(x: next() * base.width, y: next() * base.height)
            style.dots[index % style.dots.count].setFill()
            UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        if style.watermark > 0 {
            ayuPlane(CGRect(x: -3, y: -10, width: base.width + 8, height: 45), foreground: UIColor.black.withAlphaComponent(style.watermark), secondary: UIColor.black.withAlphaComponent(style.watermark * 0.65))
        }
        context.restoreGState()

        if showIcon {
            let iconX: CGFloat = label.isEmpty ? (base.width - 17) / 2.0 : 7.0
            ayuPlane(CGRect(x: iconX, y: 3, width: 17, height: 17), foreground: style.foreground, secondary: style.secondary)
        }
        if !label.isEmpty {
            let textX: CGFloat = showIcon ? 28.0 : floor((base.width - textSize.width) / 2.0)
            let maxWidth = max(10.0, base.width - textX - 8.0)
            nsText.draw(
                in: CGRect(x: textX, y: (base.height - textSize.height) / 2.0, width: maxWidth, height: textSize.height),
                withAttributes: attributes
            )
        }
    }
}

public func ayuGramCustomBadgePreview(text: String, themeId: String, showIcon: Bool, scale: CGFloat) -> UIImage {
    let theme = ayuCustomBadgeThemes.first(where: { $0.id == themeId }) ?? ayuCustomBadgeThemes[0]
    let badgeStyle = AyuBadgeStyle(
        colors: theme.colors,
        foreground: theme.textColor,
        secondary: theme.accentColor,
        text: theme.textColor,
        watermark: 0.08,
        dots: [],
        dotRadius: 0 ... 0,
        dotCount: 0,
        glow: ayuBadgeColor(1, 1, 1, 0.14)
    )
    return ayuRenderCapsuleBadge(label: String(text.prefix(18)), style: badgeStyle, showIcon: showIcon, scale: scale)
}

public func ayuGramAppBadgeImage(style: String, scale: CGFloat) -> UIImage {
    if style == ayuCustomImageBadgeId,
       let url = ayuCustomBadgeImageURL(),
       let data = try? Data(contentsOf: url),
       let image = UIImage(data: data, scale: 3.0) {
        return image
    }
    if style == ayuCustomTextBadgeId {
        let custom = ayuCustomBadgeSettings()
        return ayuGramCustomBadgePreview(text: custom.text, themeId: custom.themeId, showIcon: custom.showIcon, scale: scale)
    }
    if style.hasPrefix(telegramAppBadgePrefix) {
        let tgStyle = ayuTelegramBadgeStyle(style)
        return ayuRenderCapsuleBadge(label: "TELEGRAM", style: tgStyle, showIcon: true, scale: scale, fixedWidth: 112)
    }
    if style.hasPrefix(swiftgramAppBadgePrefix), let image = ayuGramBundleImageLoader?(String(style.dropFirst(swiftgramAppBadgePrefix.count))) {
        return image
    }
    let resolvedStyle = ayuBadgeStyle(style)
    return ayuRenderCapsuleBadge(label: "AYUGRAM", style: resolvedStyle, showIcon: true, scale: scale, fixedWidth: 108)
}

func ayuGramAppBadgeImage() -> UIImage {
    return ayuGramAppBadgeImage(style: UserDefaults.standard.string(forKey: "customAppBadge") ?? "", scale: 0)
}

public func ayuGramSettingsIcon() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 29, height: 29)).image { _ in
        UIColor(red: 0.19, green: 0.15, blue: 0.28, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 29, height: 29), cornerRadius: 7).fill()
        ayuPlane(CGRect(x: 5, y: 5, width: 19, height: 19), foreground: .white, secondary: UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1))
    }
}

/// Sharp, larger variant of the settings icon for headers.
public func ayuGramLargeIcon(size: CGFloat) -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
        UIColor(red: 0.19, green: 0.15, blue: 0.28, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: size * 0.24).fill()
        let inset = size * 5.0 / 29.0
        ayuPlane(CGRect(x: inset, y: inset, width: size - inset * 2.0, height: size - inset * 2.0), foreground: .white, secondary: UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1))
    }
}

public func ayuGramMemberBadgeImage() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
        let outline = UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 18, height: 18), cornerRadius: 6)
        UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1).setStroke()
        outline.lineWidth = 1.2
        outline.stroke()
        ayuPlane(CGRect(x: 5, y: 4.5, width: 12, height: 13), foreground: .white, secondary: UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1))
    }
}
