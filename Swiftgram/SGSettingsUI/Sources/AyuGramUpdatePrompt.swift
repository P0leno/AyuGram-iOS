import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import SGSimpleSettings

/// Opens a link inside Telegram when it can (t.me), otherwise in the browser.
func ayuGramOpenLink(context: AccountContext, url: String) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController
    context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: false, presentationData: data, navigationController: navigationController, dismissInput: {})
}

/// Opens the developer's profile; falls back to its t.me link if the profile is not cached yet.
func ayuGramOpenDeveloper(context: AccountContext) {
    let peerId = EnginePeer.Id(AyuGramUpdates.developerId)
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).startStandalone(next: { peer in
        if let peer, let profile = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            (context.sharedContext.mainWindow?.viewController as? NavigationController)?.pushViewController(profile)
        } else {
            ayuGramOpenLink(context: context, url: "https://t.me/@id\(AyuGramUpdates.developerId)")
        }
    })
}

/// Initializes optional local notification hooks once the main interface is ready.
/// Remote update manifest checks and remote security telemetry are disabled.
public func ayuGramPresentUpdateIfNeeded(context: AccountContext) {
    AyuGramPushRelay.renew(context: context)
    ayuGramBarkSetupHook = { context, present in
        ayuGramSetUpBark(context: context, present: present)
    }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge], completionHandler: { _, _ in })
}
