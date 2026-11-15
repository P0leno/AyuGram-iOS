import UIKit
import SGPlugins

@objc(Application) class Application: UIApplication {
    override init() {
        super.init()
        SGPluginEngine.registerWithBridge()
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
    }
}
