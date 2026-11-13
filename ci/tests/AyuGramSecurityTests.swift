import Foundation

@main
struct SecurityTests {
    static func expect(_ value: @autoclosure () -> Bool, _ text: String) { precondition(value(), text) }

    static func main() {
        let profile = Data("garbage<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>TeamName</key><string>Personal</string><key>Entitlements</key><dict><key>com.apple.developer.usernotifications.communication</key><true/></dict></dict></plist>tail".utf8)
        let plist = AyuGramSecurity.provisioningPlist(profile)
        expect(plist?["TeamName"] as? String == "Personal", "The plist is cut out of the signed profile")
        let entitlements = plist?["Entitlements"] as? [String: Any]
        expect((entitlements?["com.apple.developer.usernotifications.communication"] as? Bool) == true, "Communication entitlement is parsed")
        expect(AyuGramSecurity.provisioningPlist(Data("no plist".utf8)) == nil, "A missing plist is nil")
        print("Local provisioning plist parsing verified")
    }
}
