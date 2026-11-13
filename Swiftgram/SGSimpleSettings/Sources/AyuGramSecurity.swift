import Foundation

/// Local-only provisioning checks (no network requests, no telemetry, no remote blocking).
public final class AyuGramSecurity {
    public static let shared = AyuGramSecurity()

    private init() {}

    static func provisioningPlist(_ data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex) else {
            return nil
        }
        let slice = data.subdata(in: start.lowerBound ..< end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)) as? [String: Any]
    }
}

public extension AyuGramSecurity {
    static let allowsCommunicationNotifications: Bool = {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path),
              let plist = AyuGramSecurity.provisioningPlist(data),
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            return true
        }
        return (entitlements["com.apple.developer.usernotifications.communication"] as? Bool) == true
    }()
}
