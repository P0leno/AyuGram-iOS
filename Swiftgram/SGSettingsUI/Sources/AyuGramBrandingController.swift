import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGSimpleSettings
import SGStrings
import SGPluginBridge

private enum AyuBrandingSection: Int32 {
    case appName
    case badge
    case icons
    case ciExport
}

private enum AyuBrandingEntry: ItemListNodeEntry {
    case appNameHeader(Int, String)
    case bundleNameRow(Int, String, String)
    case customTitleRow(Int, String, String)
    case hideBrandingToggle(Int, String, Bool)
    case appNameFooter(Int, String)

    case badgeHeader(Int, String)
    case badgeSelectorRow(Int, String, String)

    case iconsHeader(Int, String)
    case iconRow(Int, String, String, Bool)
    case iconsFooter(Int, String)

    case ciHeader(Int, String)
    case prepareIconRow(Int, String)
    case resetRow(Int, String)
    case ciFooter(Int, String)

    var section: ItemListSectionId {
        switch self {
        case .appNameHeader, .bundleNameRow, .customTitleRow, .hideBrandingToggle, .appNameFooter:
            return AyuBrandingSection.appName.rawValue
        case .badgeHeader, .badgeSelectorRow:
            return AyuBrandingSection.badge.rawValue
        case .iconsHeader, .iconRow, .iconsFooter:
            return AyuBrandingSection.icons.rawValue
        case .ciHeader, .prepareIconRow, .resetRow, .ciFooter:
            return AyuBrandingSection.ciExport.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .appNameHeader(id, _),
             let .bundleNameRow(id, _, _),
             let .customTitleRow(id, _, _),
             let .hideBrandingToggle(id, _, _),
             let .appNameFooter(id, _),
             let .badgeHeader(id, _),
             let .badgeSelectorRow(id, _, _),
             let .iconsHeader(id, _),
             let .iconRow(id, _, _, _),
             let .iconsFooter(id, _),
             let .ciHeader(id, _),
             let .prepareIconRow(id, _),
             let .resetRow(id, _),
             let .ciFooter(id, _):
            return id
        }
    }

    static func <(lhs: AyuBrandingEntry, rhs: AyuBrandingEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! AyuBrandingArguments
        switch self {
        case let .appNameHeader(_, text),
             let .badgeHeader(_, text),
             let .iconsHeader(_, text),
             let .ciHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .bundleNameRow(_, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    args.copyBundleInfo()
                }
            )

        case let .customTitleRow(_, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    args.editCustomTitle()
                }
            )

        case let .hideBrandingToggle(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { enabled in
                    args.toggleHideBranding(enabled)
                }
            )

        case let .appNameFooter(_, text),
             let .iconsFooter(_, text),
             let .ciFooter(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .badgeSelectorRow(_, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: nil,
                title: title,
                label: label,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    args.openBadgeSelector()
                }
            )

        case let .iconRow(_, iconId, title, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                style: .left,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.selectIcon(iconId)
                }
            )

        case let .prepareIconRow(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.prepareCustomIconFile()
                }
            )

        case let .resetRow(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.resetBranding()
                }
            )
        }
    }
}

private final class AyuBrandingArguments {
    let editCustomTitle: () -> Void
    let toggleHideBranding: (Bool) -> Void
    let openBadgeSelector: () -> Void
    let selectIcon: (String) -> Void
    let prepareCustomIconFile: () -> Void
    let copyBundleInfo: () -> Void
    let resetBranding: () -> Void

    init(
        editCustomTitle: @escaping () -> Void,
        toggleHideBranding: @escaping (Bool) -> Void,
        openBadgeSelector: @escaping () -> Void,
        selectIcon: @escaping (String) -> Void,
        prepareCustomIconFile: @escaping () -> Void,
        copyBundleInfo: @escaping () -> Void,
        resetBranding: @escaping () -> Void
    ) {
        self.editCustomTitle = editCustomTitle
        self.toggleHideBranding = toggleHideBranding
        self.openBadgeSelector = openBadgeSelector
        self.selectIcon = selectIcon
        self.prepareCustomIconFile = prepareCustomIconFile
        self.copyBundleInfo = copyBundleInfo
        self.resetBranding = resetBranding
    }
}

private final class AyuCustomIconImagePickerBridge: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var onPick: ((UIImage) -> Void)?

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let cb = self.onPick
        self.onPick = nil
        let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        picker.dismiss(animated: true) {
            if let image {
                cb?(image)
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.onPick = nil
        picker.dismiss(animated: true)
    }
}

private func resizeSquarePNG(image: UIImage, dimension: CGFloat) -> Data? {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    format.opaque = true
    let size = CGSize(width: dimension, height: dimension)
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let rendered = renderer.image { _ in
        let aspect = max(size.width / max(image.size.width, 1.0), size.height / max(image.size.height, 1.0))
        let drawSize = CGSize(width: image.size.width * aspect, height: image.size.height * aspect)
        let origin = CGPoint(x: (size.width - drawSize.width) * 0.5, y: (size.height - drawSize.height) * 0.5)
        image.draw(in: CGRect(origin: origin, size: drawSize))
    }
    return rendered.pngData()
}

/// Controller for configuring in-app display title, white-label mode, Home Screen
/// alternate icons, custom badges, and exporting 1024x1024 icon PNG assets for CI builds.
public func ayuGramBrandingController(context: AccountContext) -> ViewController {
    let pickerBridge = AyuCustomIconImagePickerBridge()
    var weakController: ViewController?
    let refreshSignal = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshNonce = 0

    let triggerRefresh: () -> Void = {
        refreshNonce += 1
        refreshSignal.set(refreshNonce)
    }

    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer1 = NotificationCenter.default.addObserver(forName: AyuGramBrandingConfig.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        let observer2 = NotificationCenter.default.addObserver(forName: Notification.Name("AyuGram.AppIcon.didChange"), object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer1)
            NotificationCenter.default.removeObserver(observer2)
        }
    }

    let arguments = AyuBrandingArguments(
        editCustomTitle: {
            guard let controller = weakController else {
                return
            }
            let data = context.sharedContext.currentPresentationData.with { $0 }
            let locale = data.strings.baseLanguageCode
            let alert = UIAlertController(
                title: "Ayu.Branding.CustomTitle".i18n(locale),
                message: "Ayu.Branding.CustomTitlePrompt".i18n(locale),
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.text = AyuGramBrandingConfig.shared.customAppTitle ?? AyuGramBrandingConfig.shared.bundleDisplayName
                textField.placeholder = "AyuGram"
                textField.clearButtonMode = .whileEditing
            }
            alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: data.strings.Common_OK, style: .default) { _ in
                AyuGramBrandingConfig.shared.customAppTitle = alert.textFields?.first?.text
                triggerRefresh()
            })
            controller.present(alert, animated: true)
        },
        toggleHideBranding: { enabled in
            AyuGramBrandingConfig.shared.hideClientBranding = enabled
            triggerRefresh()
        },
        openBadgeSelector: {
            if let badgeController = AyuPluginBridge.shared.makeAppBadgeSettingsController(context: context) as? ViewController {
                (weakController?.navigationController as? NavigationController)?.pushViewController(badgeController)
            }
        },
        selectIcon: { iconId in
            let nameArg: String? = (iconId == AyuGramBrandingConfig.shared.defaultIconId) ? nil : iconId
            context.sharedContext.applicationBindings.requestSetAlternateIconName(nameArg) { success in
                DispatchQueue.main.async {
                    if !success, let controller = weakController {
                        let data = context.sharedContext.currentPresentationData.with { $0 }
                        let locale = data.strings.baseLanguageCode
                        controller.present(
                            textAlertController(
                                context: context,
                                title: nil,
                                text: "Ayu.IconChangeUnavailable".i18n(locale),
                                actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]
                            ),
                            in: .window(.root)
                        )
                    }
                    triggerRefresh()
                }
            }
        },
        prepareCustomIconFile: {
            guard let controller = weakController else {
                return
            }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true
            picker.delegate = pickerBridge
            pickerBridge.onPick = { image in
                guard let pngData = resizeSquarePNG(image: image, dimension: 1024.0) else {
                    return
                }
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("CustomAppIcon.png")
                try? pngData.write(to: fileURL, options: .atomic)
                let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                activity.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: fileURL)
                }
                if let view = controller.view {
                    activity.popoverPresentationController?.sourceView = view
                    activity.popoverPresentationController?.sourceRect = CGRect(
                        origin: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                        size: CGSize(width: 1.0, height: 1.0)
                    )
                }
                controller.present(activity, animated: true)
            }
            controller.present(picker, animated: true)
        },
        copyBundleInfo: {
            let branding = AyuGramBrandingConfig.shared
            UIPasteboard.general.string = branding.bundleDisplayName
        },
        resetBranding: {
            AyuGramBrandingConfig.shared.customAppTitle = nil
            AyuGramBrandingConfig.shared.hideClientBranding = false
            context.sharedContext.applicationBindings.requestSetAlternateIconName(nil) { _ in
                DispatchQueue.main.async {
                    triggerRefresh()
                }
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changes, refreshSignal.get())
    |> deliverOnMainQueue
    |> map { data, _, _ -> (ItemListControllerState, (ItemListNodeState, AyuBrandingArguments)) in
        let locale = data.strings.baseLanguageCode
        let config = AyuGramBrandingConfig.shared
        let selectedIcon = AyuGramIconSettings.selectedName ?? config.defaultIconId
        let badge = SGSimpleSettings.shared.customAppBadge
        let currentBadge = badge.isEmpty ? "Default" : badge

        var entries: [AyuBrandingEntry] = []
        entries.append(.appNameHeader(0, "Ayu.Branding.NameSection".i18n(locale)))
        entries.append(.bundleNameRow(1, "Ayu.Branding.BundleName".i18n(locale), config.bundleDisplayName))
        entries.append(.customTitleRow(2, "Ayu.Branding.CustomTitle".i18n(locale), config.effectiveAppTitle))
        entries.append(.hideBrandingToggle(3, "Ayu.Branding.HideClientBranding".i18n(locale), config.hideClientBranding))
        entries.append(.appNameFooter(4, "Ayu.Branding.NameFooter".i18n(locale)))

        entries.append(.badgeHeader(100, "Ayu.Branding.BadgeSection".i18n(locale)))
        entries.append(.badgeSelectorRow(101, "Ayu.Branding.AppBadge".i18n(locale), currentBadge))

        entries.append(.iconsHeader(200, "Ayu.Branding.IconsSection".i18n(locale)))
        var nextId = 201
        let builtinIcons = [
            "AyuClassic", "AyuPurple", "AyuRed",
            "BlueIcon", "BlackIcon", "SGDefault", "SGTitanium", "SGGlass"
        ]
        var renderedIds = Set<String>()
        for custom in config.customIcons {
            renderedIds.insert(custom.id)
            entries.append(.iconRow(nextId, custom.id, custom.title, selectedIcon == custom.id))
            nextId += 1
        }
        for builtin in builtinIcons where !renderedIds.contains(builtin) {
            entries.append(.iconRow(nextId, builtin, config.displayTitle(forIconName: builtin) ?? builtin, selectedIcon == builtin))
            nextId += 1
        }
        entries.append(.iconsFooter(599, "Ayu.Branding.IconsFooter".i18n(locale)))

        entries.append(.ciHeader(600, "Ayu.Branding.CustomAssetSection".i18n(locale)))
        entries.append(.prepareIconRow(601, "Ayu.Branding.ExportCustomIconPNG".i18n(locale)))
        entries.append(.resetRow(602, "Ayu.Branding.Reset".i18n(locale)))
        entries.append(.ciFooter(603, "Ayu.Branding.CustomAssetFooter".i18n(locale)))

        let state = ItemListControllerState(
            presentationData: ItemListPresentationData(data),
            title: .text("Ayu.Branding.Title".i18n(locale)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(data),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (state, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    weakController = controller
    return controller
}
