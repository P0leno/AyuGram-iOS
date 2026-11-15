import Foundation

public struct AyuCustomIconDescriptor: Codable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

private struct AyuBrandingManifestPayload: Codable {
    var display_name: String?
    var badge_title: String?
    var hide_client_branding: Bool?
    var default_icon: String?
    var icons: [AyuCustomIconDescriptor]?
}

/// Manages bundled branding metadata from `branding.json` / `Info.plist` together
/// with device-local in-app customization overrides (name, badge, white-label mode).
public final class AyuGramBrandingConfig {
    public static let shared = AyuGramBrandingConfig()
    public static let didChange = Notification.Name("AyuGram.Branding.didChange")

    private enum DefaultsKey {
        static let customAppTitle = "ayugram.branding.customAppTitle"
        static let hideClientBranding = "ayugram.branding.hideClientBranding"
    }

    private let manifest: AyuBrandingManifestPayload

    private init() {
        if let url = Bundle.main.url(forResource: "branding", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AyuBrandingManifestPayload.self, from: data) {
            self.manifest = decoded
        } else {
            self.manifest = AyuBrandingManifestPayload()
        }
    }

    /// The Home Screen display name compiled into Info.plist.
    public var bundleDisplayName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        if let manifestName = self.manifest.display_name, !manifestName.isEmpty {
            return manifestName
        }
        return "AyuGram"
    }

    /// Optional device-local override for the in-app header title shown inside AyuGram Settings.
    public var customAppTitle: String? {
        get {
            let value = UserDefaults.standard.string(forKey: DefaultsKey.customAppTitle)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == true ? nil : value
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: DefaultsKey.customAppTitle)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.customAppTitle)
            }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    /// When enabled, client-specific subtitle/version branding hints are minimized in settings.
    public var hideClientBranding: Bool {
        get {
            if UserDefaults.standard.object(forKey: DefaultsKey.hideClientBranding) == nil {
                return self.manifest.hide_client_branding ?? false
            }
            return UserDefaults.standard.bool(forKey: DefaultsKey.hideClientBranding)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.hideClientBranding)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    /// Effective title displayed inside the AyuGram Settings hero card and branding screens.
    public var effectiveAppTitle: String {
        if let custom = self.customAppTitle {
            return custom
        }
        if self.hideClientBranding {
            return self.bundleDisplayName == "AyuGram" ? "Telegram" : self.bundleDisplayName
        }
        return self.bundleDisplayName
    }

    public var defaultIconId: String {
        if let value = self.manifest.default_icon, !value.isEmpty {
            return value
        }
        return "AyuClassic"
    }

    /// Custom icons explicitly listed in `branding.json` plus any extra `CFBundleAlternateIcons` entries.
    public var customIcons: [AyuCustomIconDescriptor] {
        var result: [AyuCustomIconDescriptor] = []
        var seen = Set<String>()

        for icon in self.manifest.icons ?? [] {
            if seen.insert(icon.id).inserted {
                result.append(icon)
            }
        }

        if let iconsDict = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let alternates = iconsDict["CFBundleAlternateIcons"] as? [String: Any] {
            for key in alternates.keys.sorted() {
                if seen.insert(key).inserted {
                    result.append(AyuCustomIconDescriptor(id: key, title: key))
                }
            }
        }
        return result
    }

    /// Human-readable icon title for custom icons from `branding.json`.
    public func displayTitle(forIconName iconName: String) -> String? {
        if let match = (self.manifest.icons ?? []).first(where: { $0.id == iconName }) {
            return match.title
        }
        return nil
    }
}
