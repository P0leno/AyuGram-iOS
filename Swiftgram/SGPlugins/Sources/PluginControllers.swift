import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGStrings
import SGPluginBridge
import UndoUI

// MARK: - Plugin File Picker

private final class AyuPluginDocumentPicker: UIDocumentPickerViewController, UIDocumentPickerDelegate {
    var picked: ((URL) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let cb = self.picked
        self.picked = nil
        if let url = urls.first {
            cb?(url)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.picked = nil
    }
}

private enum PluginListSection: Int32 {
    case safeMode
    case install
    case installed
    case diagnostics
}

private enum PluginListEntry: ItemListNodeEntry {
    case safeModeToggle(Int, Bool, String)
    case safeModeInfo(Int, String)
    case installHeader(Int, String)
    case installFile(Int, String)
    case installURL(Int, String)
    case installedHeader(Int, String)
    case pluginRow(Int, AyuPluginRecord, String)
    case emptyPlugins(Int, String)
    case logsRow(Int, String, Int)

    var section: ItemListSectionId {
        switch self {
        case .safeModeToggle, .safeModeInfo:
            return PluginListSection.safeMode.rawValue
        case .installHeader, .installFile, .installURL:
            return PluginListSection.install.rawValue
        case .installedHeader, .pluginRow, .emptyPlugins:
            return PluginListSection.installed.rawValue
        case .logsRow:
            return PluginListSection.diagnostics.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .safeModeToggle: return 0
        case .safeModeInfo: return 1
        case .installHeader: return 10
        case .installFile: return 11
        case .installURL: return 12
        case .installedHeader: return 20
        case let .pluginRow(idx, _, _): return 100 + idx
        case .emptyPlugins: return 90
        case .logsRow: return 1000
        }
    }

    static func < (lhs: PluginListEntry, rhs: PluginListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PluginListArguments
        switch self {
        case let .safeModeToggle(_, value, title):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { args.toggleSafeMode($0) }
            )
        case let .safeModeInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .installHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .installFile(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args.installFile() }
            )
        case let .installURL(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args.installURL() }
            )
        case let .installedHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .pluginRow(_, record, statusLabel):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "\(record.name)  v\(record.version)",
                label: statusLabel,
                additionalDetailLabel: record.author,
                sectionId: self.section,
                style: .blocks,
                action: { args.openPlugin(record.id) }
            )
        case let .emptyPlugins(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .logsRow(_, title, count):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: count > 0 ? "\(count)" : "",
                sectionId: self.section,
                style: .blocks,
                action: { args.openLogs() }
            )
        }
    }
}

private final class PluginListArguments {
    let toggleSafeMode: (Bool) -> Void
    let installFile: () -> Void
    let installURL: () -> Void
    let openPlugin: (String) -> Void
    let openLogs: () -> Void

    init(
        toggleSafeMode: @escaping (Bool) -> Void,
        installFile: @escaping () -> Void,
        installURL: @escaping () -> Void,
        openPlugin: @escaping (String) -> Void,
        openLogs: @escaping () -> Void
    ) {
        self.toggleSafeMode = toggleSafeMode
        self.installFile = installFile
        self.installURL = installURL
        self.openPlugin = openPlugin
        self.openLogs = openLogs
    }
}

public func ayuPluginsController(context: AccountContext) -> ViewController {
    SGPluginEngine.shared.bindAccountContext(context)

    var pushController: ((ViewController) -> Void)?
    var presentAlert: ((UIAlertController) -> Void)?

    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(
            forName: SGPluginEngine.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    let arguments = PluginListArguments(
        toggleSafeMode: { enabled in
            SGPluginEngine.shared.isSafeModeEnabled = enabled
        },
        installFile: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let picker = AyuPluginDocumentPicker(forOpeningContentTypes: [.item, .data, .plainText], asCopy: true)
            picker.delegate = picker
            if presentationData.theme.overallDarkAppearance {
                picker.overrideUserInterfaceStyle = .dark
            }
            picker.picked = { url in
                SGPluginEngine.shared.installPlugin(fromFileURL: url, presentationContext: context)
            }
            context.sharedContext.mainWindow?.presentNative(picker)
        },
        installURL: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let alert = UIAlertController(
                title: "Ayu.Plugins.InstallFromURL".i18n(lang),
                message: "Ayu.Plugins.InstallURLHint".i18n(lang),
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.placeholder = "https://.../plugin.plugin"
                field.keyboardType = .URL
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: "Ayu.Plugins.InstallAction".i18n(lang), style: .default) { [weak alert] _ in
                guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let url = URL(string: text),
                      url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" else {
                    return
                }
                SGPluginEngine.shared.installPlugin(fromHTTPSURL: url, presentationContext: context)
            })
            presentAlert?(alert)
        },
        openPlugin: { pluginId in
            pushController?(ayuPluginDetailController(context: context, pluginId: pluginId))
        },
        openLogs: {
            pushController?(ayuPluginLogsController(context: context))
        }
    )

    let stateSignal = combineLatest(context.sharedContext.presentationData, changes)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let safeMode = SGPluginEngine.shared.isSafeModeEnabled
        let plugins = SGPluginEngine.shared.allPlugins()
        let logsCount = SGPluginEngine.shared.recentLogs().count

        var entries: [PluginListEntry] = [
            .safeModeToggle(0, safeMode, "Ayu.Plugins.SafeMode".i18n(lang)),
            .safeModeInfo(1, "Ayu.Plugins.SafeModeInfo".i18n(lang)),
            .installHeader(10, "Ayu.Plugins.InstallSection".i18n(lang)),
            .installFile(11, "Ayu.Plugins.InstallFromFile".i18n(lang)),
            .installURL(12, "Ayu.Plugins.InstallFromURL".i18n(lang)),
            .installedHeader(20, "Ayu.Plugins.InstalledSection".i18n(lang)),
        ]

        if plugins.isEmpty {
            entries.append(.emptyPlugins(90, "Ayu.Plugins.Empty".i18n(lang)))
        } else {
            for (index, record) in plugins.enumerated() {
                let status: String
                if record.incompatibleReason != nil {
                    status = "Ayu.Plugins.StatusIncompatible".i18n(lang)
                } else if record.lastError != nil {
                    status = "Ayu.Plugins.StatusError".i18n(lang)
                } else if safeMode && record.enabled {
                    status = "Ayu.Plugins.StatusSafeMode".i18n(lang)
                } else if record.enabled {
                    status = "Ayu.Plugins.StatusActive".i18n(lang)
                } else {
                    status = "Ayu.Plugins.StatusDisabled".i18n(lang)
                }
                entries.append(.pluginRow(index, record, status))
            }
        }

        entries.append(.logsRow(1000, "Ayu.Plugins.Logs".i18n(lang), logsCount))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Ayu.Plugins.Title".i18n(lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: stateSignal)
    pushController = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    presentAlert = { [weak controller] alert in
        controller?.present(alert, animated: true)
    }
    return controller
}

// MARK: - Plugin Detail & Native Settings Screen

private enum PluginDetailEntry: ItemListNodeEntry {
    case infoHeader(Int, String)
    case enableToggle(Int, Bool, String)
    case infoText(Int, String)
    case diagnosticText(Int, String)
    case settingHeader(Int, String)
    case settingSwitch(Int, AyuPluginSettingItemModel)
    case settingInput(Int, AyuPluginSettingItemModel)
    case settingSelector(Int, AyuPluginSettingItemModel)
    case settingSlider(Int, AyuPluginSettingItemModel)
    case settingAction(Int, AyuPluginSettingItemModel)
    case settingDivider(Int, String)
    case reloadAction(Int, String)
    case viewSourceAction(Int, String)
    case removeAction(Int, String)
    case menuAction(Int, AyuPluginMenuItem)

    var section: ItemListSectionId {
        switch self {
        case .infoHeader, .enableToggle, .infoText, .diagnosticText:
            return 0
        case .settingHeader, .settingSwitch, .settingInput, .settingSelector, .settingSlider, .settingAction, .settingDivider, .menuAction:
            return 1
        case .reloadAction, .viewSourceAction, .removeAction:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case let .infoHeader(id, _),
             let .enableToggle(id, _, _),
             let .infoText(id, _),
             let .diagnosticText(id, _),
             let .settingHeader(id, _),
             let .settingSwitch(id, _),
             let .settingInput(id, _),
             let .settingSelector(id, _),
             let .settingSlider(id, _),
             let .settingAction(id, _),
             let .settingDivider(id, _),
             let .reloadAction(id, _),
             let .viewSourceAction(id, _),
             let .removeAction(id, _),
             let .menuAction(id, _):
            return id
        }
    }

    static func < (lhs: PluginDetailEntry, rhs: PluginDetailEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PluginDetailArguments
        switch self {
        case let .infoHeader(_, text), let .settingHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enableToggle(_, value, title):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { args.toggleEnabled($0) }
            )
        case let .infoText(_, text), let .diagnosticText(_, text), let .settingDivider(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .settingSwitch(_, model):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: model.text,
                text: model.subtext.isEmpty ? nil : model.subtext,
                value: model.boolValue,
                sectionId: self.section,
                style: .blocks,
                updated: { args.updateSetting(model.key, $0) }
            )
        case let .settingInput(_, model):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(string: model.text + ": ", attributes: [.foregroundColor: presentationData.theme.list.itemPrimaryTextColor]),
                text: model.stringValue,
                placeholder: model.subtext,
                type: .regular(capitalization: false, autocorrection: false),
                clearType: .always,
                sectionId: self.section,
                textUpdated: { args.updateSetting(model.key, $0) },
                action: {},
                dismissKeyboardOnEnter: true
            )
        case let .settingSelector(_, model):
            let selectedTitle = (model.intValue >= 0 && model.intValue < model.items.count)
                ? model.items[model.intValue]
                : (model.items.first ?? "")
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: model.text,
                label: selectedTitle,
                sectionId: self.section,
                style: .blocks,
                action: { args.pickSelector(model) }
            )
        case let .settingSlider(_, model):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: model.text,
                label: String(format: "%.0f", model.doubleValue),
                additionalDetailLabel: model.subtext.isEmpty ? nil : model.subtext,
                sectionId: self.section,
                style: .blocks,
                action: { args.editSlider(model) }
            )
        case let .settingAction(_, model):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: model.text,
                kind: model.red ? .destructive : .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    if !model.actionId.isEmpty {
                        args.triggerAction(model.actionId)
                    }
                }
            )
        case let .reloadAction(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args.reload() }
            )
        case let .viewSourceAction(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args.viewSource() }
            )
        case let .removeAction(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args.remove() }
            )
        case let .menuAction(_, menuItem):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: menuItem.text,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args.triggerMenu(menuItem) }
            )
        }
    }
}

private final class PluginDetailArguments {
    let toggleEnabled: (Bool) -> Void
    let updateSetting: (String, Any) -> Void
    let pickSelector: (AyuPluginSettingItemModel) -> Void
    let editSlider: (AyuPluginSettingItemModel) -> Void
    let triggerAction: (String) -> Void
    let triggerMenu: (AyuPluginMenuItem) -> Void
    let reload: () -> Void
    let viewSource: () -> Void
    let remove: () -> Void

    init(
        toggleEnabled: @escaping (Bool) -> Void,
        updateSetting: @escaping (String, Any) -> Void,
        pickSelector: @escaping (AyuPluginSettingItemModel) -> Void,
        editSlider: @escaping (AyuPluginSettingItemModel) -> Void,
        triggerAction: @escaping (String) -> Void,
        triggerMenu: @escaping (AyuPluginMenuItem) -> Void,
        reload: @escaping () -> Void,
        viewSource: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        self.toggleEnabled = toggleEnabled
        self.updateSetting = updateSetting
        self.pickSelector = pickSelector
        self.editSlider = editSlider
        self.triggerAction = triggerAction
        self.triggerMenu = triggerMenu
        self.reload = reload
        self.viewSource = viewSource
        self.remove = remove
    }
}

public func ayuPluginDetailController(context: AccountContext, pluginId: String) -> ViewController {
    let schemaPromise = ValuePromise<[AyuPluginSettingItemModel]>([], ignoreRepeated: true)
    let refreshSchema: () -> Void = {
        SGPluginEngine.shared.fetchSettingsSchema(for: pluginId) { items in
            schemaPromise.set(items)
        }
    }
    refreshSchema()

    var presentAlert: ((UIAlertController) -> Void)?
    var popBack: (() -> Void)?
    var pushController: ((ViewController) -> Void)?

    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(
            forName: SGPluginEngine.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            refreshSchema()
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    let arguments = PluginDetailArguments(
        toggleEnabled: { value in
            SGPluginEngine.shared.setPluginEnabled(pluginId, enabled: value) { _ in
                refreshSchema()
            }
        },
        updateSetting: { key, value in
            SGPluginEngine.shared.updatePluginSetting(pluginId: pluginId, key: key, value: value)
        },
        pickSelector: { model in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = UIAlertController(title: model.text, message: model.subtext.isEmpty ? nil : model.subtext, preferredStyle: .actionSheet)
            for (index, option) in model.items.enumerated() {
                let title = index == model.intValue ? "✓ \(option)" : option
                sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                    SGPluginEngine.shared.updatePluginSetting(pluginId: pluginId, key: model.key, value: index)
                })
            }
            sheet.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            presentAlert?(sheet)
        },
        editSlider: { model in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = UIAlertController(
                title: model.text,
                message: String(format: "%.0f – %.0f", model.minValue, model.maxValue),
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.keyboardType = .decimalPad
                field.text = String(format: "%.0f", model.doubleValue)
            }
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_OK, style: .default) { [weak alert] _ in
                guard let raw = alert?.textFields?.first?.text, let val = Double(raw.replacingOccurrences(of: ",", with: ".")) else {
                    return
                }
                let clamped = min(model.maxValue, max(model.minValue, val))
                SGPluginEngine.shared.updatePluginSetting(pluginId: pluginId, key: model.key, value: clamped)
            })
            presentAlert?(alert)
        },
        triggerAction: { actionId in
            SGPluginEngine.shared.triggerSettingAction(pluginId: pluginId, actionId: actionId)
        },
        triggerMenu: { item in
            let accountId = context.account.peerId.toInt64()
            let menuCtx = AyuPluginMenuContext(
                account: accountId,
                peerId: accountId,
                messageId: 0,
                senderId: accountId,
                text: "",
                isOutgoing: true,
                date: Int32(Date().timeIntervalSince1970)
            )
            SGPluginEngine.shared.triggerMenuItem(pluginId: item.pluginId, itemId: item.itemId, context: menuCtx)
        },
        reload: {
            SGPluginEngine.shared.reloadPlugin(pluginId) { _ in
                refreshSchema()
            }
        },
        viewSource: {
            pushController?(ayuPluginSourceViewerController(context: context, pluginId: pluginId))
        },
        remove: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let alert = textAlertController(
                context: context,
                title: "Ayu.Plugins.Remove".i18n(lang),
                text: "Ayu.Plugins.RemoveConfirm".i18n(lang),
                actions: [
                    TextAlertAction(type: .destructiveAction, title: "Ayu.Plugins.Remove".i18n(lang), action: {
                        SGPluginEngine.shared.removePlugin(pluginId)
                        popBack?()
                    }),
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}),
                ]
            )
            context.sharedContext.mainWindow?.present(alert, on: .root)
        }
    )

    let stateSignal = combineLatest(context.sharedContext.presentationData, schemaPromise.get(), changes)
    |> map { presentationData, schema, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let record = SGPluginEngine.shared.plugin(id: pluginId)

        var entries: [PluginDetailEntry] = []
        let title = record?.name ?? pluginId
        if let record = record {
            entries.append(.enableToggle(1, record.enabled, "Ayu.Plugins.Enabled".i18n(lang)))
            var summary = "\(record.name) v\(record.version) — \(record.author)"
            if !record.descriptionText.isEmpty {
                summary += "\n\(record.descriptionText)"
            }
            entries.append(.infoText(2, summary))

            var diagParts: [String] = []
            if let incomp = record.incompatibleReason {
                diagParts.append("Incompatible (Android/JVM API):\n\(incomp)")
            }
            if let err = record.lastError {
                diagParts.append("Runtime Error:\n\(err)")
            }
            if !record.warnings.isEmpty {
                diagParts.append(record.warnings.joined(separator: "\n"))
            }
            if !diagParts.isEmpty {
                entries.append(.diagnosticText(3, diagParts.joined(separator: "\n\n")))
            }
        }

        if !schema.isEmpty {
            for (idx, item) in schema.enumerated() {
                let baseId = 100 + idx
                switch item.type {
                case "header":
                    entries.append(.settingHeader(baseId, item.text))
                case "switch":
                    entries.append(.settingSwitch(baseId, item))
                case "input":
                    entries.append(.settingInput(baseId, item))
                case "selector":
                    entries.append(.settingSelector(baseId, item))
                case "slider":
                    entries.append(.settingSlider(baseId, item))
                case "text":
                    entries.append(.settingAction(baseId, item))
                default:
                    entries.append(.settingDivider(baseId, item.text))
                }
            }
        }

        let pluginMenuActions = SGPluginEngine.shared.menuItems(for: "").filter { $0.pluginId == pluginId }
        if !pluginMenuActions.isEmpty {
            for (idx, item) in pluginMenuActions.enumerated() {
                entries.append(.menuAction(500 + idx, item))
            }
        }

        entries.append(.reloadAction(1000, "Ayu.Plugins.Reload".i18n(lang)))
        entries.append(.viewSourceAction(1001, "Ayu.Plugins.ViewSource".i18n(lang)))
        entries.append(.removeAction(1002, "Ayu.Plugins.Remove".i18n(lang)))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: stateSignal)
    presentAlert = { [weak controller] alert in
        if let popover = alert.popoverPresentationController, let view = controller?.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        controller?.present(alert, animated: true)
    }
    popBack = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    pushController = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}

// MARK: - Logs & Source Viewers

private final class PluginLogsArguments {
    let copyAll: () -> Void
    let shareAll: () -> Void
    let clearAll: () -> Void

    init(copyAll: @escaping () -> Void, shareAll: @escaping () -> Void, clearAll: @escaping () -> Void) {
        self.copyAll = copyAll
        self.shareAll = shareAll
        self.clearAll = clearAll
    }
}

private enum PluginLogsEntry: ItemListNodeEntry {
    case copyAllButton(Int, String)
    case shareButton(Int, String)
    case clearButton(Int, String)
    case logLine(Int, String)
    case emptyText(Int, String)

    var section: ItemListSectionId {
        switch self {
        case .copyAllButton, .shareButton, .clearButton: return 0
        case .logLine, .emptyText: return 1
        }
    }

    var stableId: Int {
        switch self {
        case .copyAllButton: return 0
        case .shareButton: return 1
        case .clearButton: return 2
        case let .logLine(id, _): return 10 + id
        case .emptyText: return 5
        }
    }

    static func < (lhs: PluginLogsEntry, rhs: PluginLogsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as? PluginLogsArguments
        switch self {
        case let .copyAllButton(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args?.copyAll() }
            )
        case let .shareButton(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args?.shareAll() }
            )
        case let .clearButton(_, title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: { args?.clearAll() }
            )
        case let .logLine(_, text), let .emptyText(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func ayuPresentCopiedToast(context: AccountContext, controller: ViewController?, text: String) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let toast = UndoOverlayController(
        presentationData: data,
        content: .copy(text: text),
        elevatedLayout: false,
        action: { _ in return false }
    )
    controller?.present(toast, in: .current)
}

public func ayuPluginLogsController(context: AccountContext) -> ViewController {
    var weakController: ViewController?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(
            forName: SGPluginEngine.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"

    let formattedLogsText: () -> String = {
        let logs = SGPluginEngine.shared.recentLogs()
        return logs.map { item in
            "[\(formatter.string(from: item.timestamp))] [\(item.level.uppercased())] [\(item.pluginId)] \(item.message)"
        }.joined(separator: "\n")
    }

    let copyAllAction: () -> Void = {
        let text = formattedLogsText()
        guard !text.isEmpty else {
            return
        }
        UIPasteboard.general.string = text
        let data = context.sharedContext.currentPresentationData.with { $0 }
        ayuPresentCopiedToast(context: context, controller: weakController, text: "Ayu.Plugins.LogsCopied".i18n(data.strings.baseLanguageCode))
    }

    let shareAllAction: () -> Void = {
        let text = formattedLogsText()
        guard !text.isEmpty, let controller = weakController else {
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ayugram-plugin-logs.txt")
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: tempURL)
            }
            if let view = controller.view {
                activity.popoverPresentationController?.sourceView = view
                activity.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: view.bounds.midX, y: view.bounds.midY), size: CGSize(width: 1.0, height: 1.0))
            }
            controller.present(activity, animated: true)
        } catch {
            UIPasteboard.general.string = text
            let data = context.sharedContext.currentPresentationData.with { $0 }
            ayuPresentCopiedToast(context: context, controller: controller, text: "Ayu.Plugins.LogsCopied".i18n(data.strings.baseLanguageCode))
        }
    }

    let clearAction: () -> Void = {
        SGPluginEngine.shared.clearLogs()
    }

    let arguments = PluginLogsArguments(copyAll: copyAllAction, shareAll: shareAllAction, clearAll: clearAction)

    let stateSignal = combineLatest(context.sharedContext.presentationData, changes)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let logs = SGPluginEngine.shared.recentLogs().reversed()
        var entries: [PluginLogsEntry] = []
        if !logs.isEmpty {
            entries.append(.copyAllButton(0, "Ayu.Plugins.CopyLogs".i18n(lang)))
            entries.append(.shareButton(1, "Ayu.Plugins.ShareLogs".i18n(lang)))
        }
        entries.append(.clearButton(2, "Ayu.Plugins.ClearLogs".i18n(lang)))
        if logs.isEmpty {
            entries.append(.emptyText(5, "Ayu.Plugins.LogsEmpty".i18n(lang)))
        } else {
            for (index, item) in logs.enumerated() {
                let line = "[\(formatter.string(from: item.timestamp))] [\(item.level.uppercased())] [\(item.pluginId)] \(item.message)"
                entries.append(.logLine(index, line))
            }
        }
        let rightButton: ItemListNavigationButton? = logs.isEmpty ? nil : ItemListNavigationButton(
            content: .text("Ayu.Plugins.CopyLogs".i18n(lang)),
            style: .regular,
            enabled: true,
            action: { copyAllAction() }
        )
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Ayu.Plugins.Logs".i18n(lang)),
            leftNavigationButton: nil,
            rightNavigationButton: rightButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: stateSignal)
    weakController = controller
    return controller
}

private func ayuPluginSourceViewerController(context: AccountContext, pluginId: String) -> ViewController {
    var weakController: ViewController?
    let sourceText = SGPluginEngine.shared.readPluginSource(pluginId)
    let stateSignal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var chunks: [String] = []
        var buffer = ""
        for line in lines {
            if buffer.count + line.count > 1200 {
                chunks.append(buffer)
                buffer = line
            } else {
                buffer = buffer.isEmpty ? line : (buffer + "\n" + line)
            }
        }
        if !buffer.isEmpty {
            chunks.append(buffer)
        }
        let entries: [PluginLogsEntry] = chunks.enumerated().map { idx, chunk in
            .logLine(idx, chunk)
        }
        let lang = presentationData.strings.baseLanguageCode
        let rightButton: ItemListNavigationButton? = sourceText.isEmpty ? nil : ItemListNavigationButton(
            content: .text("Ayu.Plugins.CopyLogs".i18n(lang)),
            style: .regular,
            enabled: true,
            action: {
                UIPasteboard.general.string = sourceText
                ayuPresentCopiedToast(context: context, controller: weakController, text: "Ayu.Plugins.LogsCopied".i18n(lang))
            }
        )
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("\(pluginId).plugin"),
            leftNavigationButton: nil,
            rightNavigationButton: rightButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        let noop: () -> Void = {}
        return (controllerState, (nodeState, noop))
    }
    let controller = ItemListController(context: context, state: stateSignal)
    weakController = controller
    return controller
}
