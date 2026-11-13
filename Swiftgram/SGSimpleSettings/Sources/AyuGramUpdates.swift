import Foundation

/// Static support metadata only. Remote update manifest checks are disabled.
public final class AyuGramUpdates {
    public static let shared = AyuGramUpdates()
    public static let channelURL = "https://t.me/ayugramiosupdates"
    public static let developerId: Int64 = 1272887902

    public init() {}

    public var currentBuild: Int {
        return Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "") ?? 0
    }
}
