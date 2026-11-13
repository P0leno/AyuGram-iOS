import Foundation

@main
struct UpdateMetadataTests {
    static func expect(_ value: @autoclosure () -> Bool, _ text: String) { precondition(value(), text) }

    static func main() {
        expect(AyuGramUpdates.channelURL.hasPrefix("https://"), "Support URL is https")
        expect(AyuGramUpdates.shared.currentBuild >= 0, "Local build reader succeeds")
        print("Offline update metadata verified")
    }
}
