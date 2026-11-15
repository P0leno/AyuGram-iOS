import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import UndoUI
import SGStrings
import SGPluginBridge
import CPluginPython

public struct AyuPluginRecord: Codable, Equatable {
    public var id: String
    public var fileName: String
    public var name: String
    public var author: String
    public var version: String
    public var descriptionText: String
    public var enabled: Bool
    public var incompatibleReason: String?
    public var lastError: String?
    public var warnings: [String]
    public var installedAt: TimeInterval

    public init(
        id: String,
        fileName: String,
        name: String,
        author: String,
        version: String,
        descriptionText: String,
        enabled: Bool,
        incompatibleReason: String? = nil,
        lastError: String? = nil,
        warnings: [String] = [],
        installedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.fileName = fileName
        self.name = name
        self.author = author
        self.version = version
        self.descriptionText = descriptionText
        self.enabled = enabled
        self.incompatibleReason = incompatibleReason
        self.lastError = lastError
        self.warnings = warnings
        self.installedAt = installedAt
    }
}

public struct AyuPluginSettingItemModel: Equatable {
    public var type: String
    public var key: String
    public var text: String
    public var subtext: String
    public var boolValue: Bool
    public var stringValue: String
    public var intValue: Int
    public var doubleValue: Double
    public var minValue: Double
    public var maxValue: Double
    public var stepValue: Double
    public var items: [String]
    public var accent: Bool
    public var red: Bool
    public var actionId: String
}

public struct AyuPluginLogEntry: Equatable {
    public var timestamp: Date
    public var level: String
    public var pluginId: String
    public var message: String
}

public final class SGPluginEngine: NSObject, AyuPluginHost, AyuPythonNativeDelegate {
    public static let shared = SGPluginEngine()
    public static let stateDidChangeNotification = Notification.Name("AyuPluginEngineStateDidChange")

    private static let safeModeDefaultsKey = "ayu_plugins_safe_mode_v1"

    private let stateLock = NSLock()
    private let pythonQueue = DispatchQueue(label: "io.ayugram.plugins.python", qos: .userInitiated)
    private let runtime = AyuPythonRuntime.shared()

    private weak var activeContext: AccountContext?
    private var records: [AyuPluginRecord] = []
    private var loadedIds: Set<String> = []
    private var logs: [AyuPluginLogEntry] = []
    private var started = false

    public static func registerWithBridge() {
        AyuPluginBridge.shared.registerHost(SGPluginEngine.shared)
    }

    private override init() {
        super.init()
        self.runtime.delegate = self
        self.ensureDirectories()
        self.loadManifest()
    }

    // MARK: - Paths & Manifest

    private var rootDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("AyuGramPlugins", isDirectory: true)
    }

    private var scriptsDirectory: URL {
        return self.rootDirectory.appendingPathComponent("scripts", isDirectory: true)
    }

    private var settingsDirectory: URL {
        return self.rootDirectory.appendingPathComponent("settings", isDirectory: true)
    }

    private var modulesDirectory: URL {
        return self.rootDirectory.appendingPathComponent("modules", isDirectory: true)
    }

    private var manifestURL: URL {
        return self.rootDirectory.appendingPathComponent("manifest.json")
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        for url in [self.rootDirectory, self.scriptsDirectory, self.settingsDirectory, self.modulesDirectory] {
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: self.manifestURL),
              let decoded = try? JSONDecoder().decode([AyuPluginRecord].self, from: data) else {
            return
        }
        self.stateLock.lock()
        self.records = decoded
        self.stateLock.unlock()
    }

    private func saveManifestLocked() {
        guard let data = try? JSONEncoder().encode(self.records) else {
            return
        }
        try? data.write(to: self.manifestURL, options: .atomic)
    }

    private func postStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SGPluginEngine.stateDidChangeNotification, object: self)
        }
    }

    // MARK: - AyuPluginHost

    public var hasActivePlugins: Bool {
        self.stateLock.lock()
        let active = !self.loadedIds.isEmpty
        self.stateLock.unlock()
        return active
    }

    public var activePluginCount: Int {
        self.stateLock.lock()
        let count = self.loadedIds.count
        self.stateLock.unlock()
        return count
    }

    public var isSafeModeEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Self.safeModeDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.safeModeDefaultsKey)
            if newValue {
                self.unloadAllActivePlugins()
            } else {
                self.loadEnabledPluginsAsync()
            }
            self.postStateChanged()
        }
    }

    public func allPlugins() -> [AyuPluginRecord] {
        self.stateLock.lock()
        let copy = self.records
        self.stateLock.unlock()
        return copy
    }

    public func plugin(id: String) -> AyuPluginRecord? {
        self.stateLock.lock()
        let match = self.records.first(where: { $0.id == id })
        self.stateLock.unlock()
        return match
    }

    public func recentLogs() -> [AyuPluginLogEntry] {
        self.stateLock.lock()
        let copy = self.logs
        self.stateLock.unlock()
        return copy
    }

    public func clearLogs() {
        self.stateLock.lock()
        self.logs.removeAll()
        self.stateLock.unlock()
        self.postStateChanged()
    }

    public func startIfNeeded() {
        self.stateLock.lock()
        if self.started {
            self.stateLock.unlock()
            return
        }
        self.started = true
        self.stateLock.unlock()

        if !self.isSafeModeEnabled {
            self.loadEnabledPluginsAsync()
        }
    }

    public func bindAccountContext(_ context: AnyObject) {
        if let accountContext = context as? AccountContext {
            self.activeContext = accountContext
        }
        self.startIfNeeded()
    }

    private func ensureRuntimeInitializedLocked() -> Bool {
        if self.runtime.isInitialized {
            return true
        }
        let bundlePath = Bundle.main.bundlePath
        do {
            try self.runtime.initialize(withBundlePath: bundlePath, extraSearchPath: self.modulesDirectory.path)
            return true
        } catch {
            self.appendLog(level: "error", pluginId: "runtime", message: error.localizedDescription)
            return false
        }
    }

    private func loadEnabledPluginsAsync() {
        self.pythonQueue.async { [weak self] in
            guard let self = self, !self.isSafeModeEnabled else {
                return
            }
            guard self.ensureRuntimeInitializedLocked() else {
                return
            }
            let enabledRecords = self.allPlugins().filter { $0.enabled }
            for record in enabledRecords {
                let _ = self.loadSinglePluginSync(record: record)
            }
            self.postStateChanged()
        }
    }

    private func unloadAllActivePlugins() {
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.stateLock.lock()
            let currentIds = Array(self.loadedIds)
            self.stateLock.unlock()
            for pid in currentIds {
                let _ = self.dispatchPython(command: "unload_plugin", payload: ["plugin_id": pid])
            }
            self.stateLock.lock()
            self.loadedIds.removeAll()
            self.stateLock.unlock()
            self.postStateChanged()
        }
    }

    private func loadSinglePluginSync(record: AyuPluginRecord) -> AyuPluginRecord {
        let scriptURL = self.scriptsDirectory.appendingPathComponent(record.fileName)
        let response = self.dispatchPython(
            command: "load_plugin",
            payload: [
                "plugin_id": record.id,
                "file_path": scriptURL.path,
            ]
        )

        var updated = record
        let ok = (response["ok"] as? Bool) ?? false
        let incompatible = (response["incompatible"] as? Bool) ?? false
        let errorText = response["error"] as? String ?? ""
        let warnings = response["warnings"] as? [String] ?? []

        if let meta = response["metadata"] as? [String: Any] {
            if let name = meta["name"] as? String, !name.isEmpty {
                updated.name = name
            }
            if let author = meta["author"] as? String, !author.isEmpty {
                updated.author = author
            }
            if let version = meta["version"] as? String, !version.isEmpty {
                updated.version = version
            }
            if let desc = meta["description"] as? String {
                updated.descriptionText = desc
            }
        }
        updated.warnings = warnings

        self.stateLock.lock()
        if ok {
            updated.incompatibleReason = nil
            updated.lastError = nil
            self.loadedIds.insert(updated.id)
        } else {
            self.loadedIds.remove(updated.id)
            if incompatible {
                updated.enabled = false
                updated.incompatibleReason = errorText
                updated.lastError = nil
            } else {
                updated.lastError = errorText
            }
        }
        if let idx = self.records.firstIndex(where: { $0.id == updated.id }) {
            self.records[idx] = updated
        } else {
            self.records.append(updated)
        }
        self.saveManifestLocked()
        self.stateLock.unlock()
        return updated
    }

    public func setPluginEnabled(_ pluginId: String, enabled: Bool, completion: ((AyuPluginRecord?) -> Void)? = nil) {
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.stateLock.lock()
            guard let idx = self.records.firstIndex(where: { $0.id == pluginId }) else {
                self.stateLock.unlock()
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            var record = self.records[idx]
            record.enabled = enabled
            if !enabled {
                record.lastError = nil
            }
            self.records[idx] = record
            self.saveManifestLocked()
            self.stateLock.unlock()

            if enabled && !self.isSafeModeEnabled {
                if self.ensureRuntimeInitializedLocked() {
                    record = self.loadSinglePluginSync(record: record)
                }
            } else {
                let _ = self.dispatchPython(command: "unload_plugin", payload: ["plugin_id": pluginId])
                self.stateLock.lock()
                self.loadedIds.remove(pluginId)
                self.stateLock.unlock()
            }

            self.postStateChanged()
            DispatchQueue.main.async {
                completion?(record)
            }
        }
    }

    public func reloadPlugin(_ pluginId: String, completion: ((AyuPluginRecord?) -> Void)? = nil) {
        self.setPluginEnabled(pluginId, enabled: true, completion: completion)
    }

    public func removePlugin(_ pluginId: String) {
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            let _ = self.dispatchPython(command: "unload_plugin", payload: ["plugin_id": pluginId])
            self.stateLock.lock()
            let removed = self.records.first(where: { $0.id == pluginId })
            self.records.removeAll(where: { $0.id == pluginId })
            self.loadedIds.remove(pluginId)
            self.saveManifestLocked()
            self.stateLock.unlock()

            if let removed = removed {
                try? FileManager.default.removeItem(at: self.scriptsDirectory.appendingPathComponent(removed.fileName))
            }
            try? FileManager.default.removeItem(at: self.settingsURL(for: pluginId))
            self.postStateChanged()
        }
    }

    public func readPluginSource(_ pluginId: String) -> String {
        guard let record = self.plugin(id: pluginId) else {
            return ""
        }
        let url = self.scriptsDirectory.appendingPathComponent(record.fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func fetchSettingsSchema(for pluginId: String, completion: @escaping ([AyuPluginSettingItemModel]) -> Void) {
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            guard self.loadedIds.contains(pluginId) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let resp = self.dispatchPython(command: "export_settings_schema", payload: ["plugin_id": pluginId])
            let rawItems = resp["items"] as? [[String: Any]] ?? []
            let models = rawItems.map(Self.decodeSettingItem)
            DispatchQueue.main.async {
                completion(models)
            }
        }
    }

    public func updatePluginSetting(pluginId: String, key: String, value: Any) {
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            let _ = self.dispatchPython(
                command: "apply_setting_change",
                payload: [
                    "plugin_id": pluginId,
                    "key": key,
                    "value": value,
                ]
            )
            self.postStateChanged()
        }
    }

    public func triggerSettingAction(pluginId: String, actionId: String) {
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            let _ = self.dispatchPython(
                command: "trigger_setting_action",
                payload: [
                    "plugin_id": pluginId,
                    "action_id": actionId,
                ]
            )
            self.postStateChanged()
        }
    }

    private static func decodeSettingItem(_ raw: [String: Any]) -> AyuPluginSettingItemModel {
        let type = raw["type"] as? String ?? "text"
        let key = raw["key"] as? String ?? ""
        let text = raw["text"] as? String ?? ""
        let subtext = raw["subtext"] as? String ?? ""
        let rawValue = raw["value"] ?? raw["default"]
        let boolVal = (rawValue as? NSNumber)?.boolValue ?? false
        let strVal = rawValue as? String ?? (rawValue.map { "\($0)" } ?? "")
        let intVal = (rawValue as? NSNumber)?.intValue ?? 0
        let doubleVal = (rawValue as? NSNumber)?.doubleValue ?? 0.0
        return AyuPluginSettingItemModel(
            type: type,
            key: key,
            text: text,
            subtext: subtext,
            boolValue: boolVal,
            stringValue: strVal,
            intValue: intVal,
            doubleValue: doubleVal,
            minValue: (raw["min"] as? NSNumber)?.doubleValue ?? 0.0,
            maxValue: (raw["max"] as? NSNumber)?.doubleValue ?? 100.0,
            stepValue: (raw["step"] as? NSNumber)?.doubleValue ?? 1.0,
            items: raw["items"] as? [String] ?? [],
            accent: (raw["accent"] as? Bool) ?? false,
            red: (raw["red"] as? Bool) ?? false,
            actionId: raw["action_id"] as? String ?? ""
        )
    }

    // MARK: - Install Flow

    public func installPlugin(fromFileURL url: URL, presentationContext: AnyObject?) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let sourceData = try? Data(contentsOf: url),
              let sourceText = String(data: sourceData, encoding: .utf8) else {
            self.presentSimpleAlert(title: nil, text: "Failed to read plugin file.")
            return
        }
        let suggestedName = url.deletingPathExtension().lastPathComponent
        self.installPlugin(sourceText: sourceText, suggestedFileStem: suggestedName, presentationContext: presentationContext)
    }

    public func installPlugin(fromHTTPSURL url: URL, presentationContext: AnyObject?) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else {
                return
            }
            guard error == nil, let data = data, let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                let message = error?.localizedDescription ?? "Download returned empty response"
                self.presentSimpleAlert(title: nil, text: message)
                return
            }
            let stem = url.deletingPathExtension().lastPathComponent
            DispatchQueue.main.async {
                self.installPlugin(sourceText: text, suggestedFileStem: stem.isEmpty ? "plugin" : stem, presentationContext: presentationContext)
            }
        }.resume()
    }

    private func sanitizedPluginId(from stem: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let collapsed = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return collapsed.isEmpty ? "plugin_\(Int(Date().timeIntervalSince1970))" : collapsed
    }

    public func installPlugin(sourceText: String, suggestedFileStem: String, presentationContext: AnyObject?) {
        self.ensureDirectories()
        let pid = self.sanitizedPluginId(from: suggestedFileStem)
        let fileName = "\(pid).plugin"
        let destURL = self.scriptsDirectory.appendingPathComponent(fileName)

        let context = (presentationContext as? AccountContext) ?? self.activeContext
        let previewMeta = Self.parseTopLevelMetadata(from: sourceText, fallbackId: pid)

        let commitInstall: () -> Void = { [weak self] in
            guard let self = self else {
                return
            }
            do {
                try sourceText.write(to: destURL, atomically: true, encoding: .utf8)
            } catch {
                self.presentSimpleAlert(title: nil, text: error.localizedDescription)
                return
            }

            let record = AyuPluginRecord(
                id: pid,
                fileName: fileName,
                name: previewMeta.name,
                author: previewMeta.author,
                version: previewMeta.version,
                descriptionText: previewMeta.description,
                enabled: !self.isSafeModeEnabled
            )

            self.pythonQueue.async {
                if !self.isSafeModeEnabled && self.ensureRuntimeInitializedLocked() {
                    let updated = self.loadSinglePluginSync(record: record)
                    self.postStateChanged()
                    DispatchQueue.main.async {
                        if let incompatible = updated.incompatibleReason {
                            self.presentSimpleAlert(title: updated.name, text: incompatible)
                        } else if let err = updated.lastError {
                            self.presentSimpleAlert(title: updated.name, text: err)
                        } else {
                            let lang = context?.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode ?? "en"
                            self.showBulletin(title: "", subtitle: "Ayu.Plugins.Installed".i18n(lang, args: updated.name), icon: "success")
                        }
                    }
                } else {
                    self.stateLock.lock()
                    if let idx = self.records.firstIndex(where: { $0.id == record.id }) {
                        self.records[idx] = record
                    } else {
                        self.records.append(record)
                    }
                    self.saveManifestLocked()
                    self.stateLock.unlock()
                    self.postStateChanged()
                }
            }
        }

        guard let context = context else {
            commitInstall()
            return
        }

        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let title = "Ayu.Plugins.InstallConfirmTitle".i18n(lang)
            let body = "\(previewMeta.name) v\(previewMeta.version)\n\(previewMeta.author)\n\n" + "Ayu.Plugins.InstallConfirmText".i18n(lang)
            let alert = textAlertController(
                context: context,
                title: title,
                text: body,
                actions: [
                    TextAlertAction(type: .genericAction, title: "Ayu.Plugins.InstallAction".i18n(lang), action: {
                        commitInstall()
                    }),
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}),
                ]
            )
            context.sharedContext.mainWindow?.present(alert, on: .root)
        }
    }

    private static func parseTopLevelMetadata(from source: String, fallbackId: String) -> (name: String, author: String, version: String, description: String) {
        func extractVar(_ varName: String) -> String? {
            let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: varName))\\s*=\\s*[\"']([^\"'\\n]+)[\"']"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let range = NSRange(source.startIndex..., in: source)
            guard let match = regex.firstMatch(in: source, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (
            name: extractVar("__name__") ?? fallbackId,
            author: extractVar("__author__") ?? "Unknown",
            version: extractVar("__version__") ?? "1.0",
            description: extractVar("__description__") ?? ""
        )
    }

    // MARK: - Message & Update Hooks

    public func processOutgoingMessage(_ params: AyuSendHookParams) -> AyuSendHookOutcome {
        guard !self.isSafeModeEnabled, self.hasActivePlugins, self.runtime.isInitialized else {
            return .passThrough
        }

        let entitiesPayload: [[String: Any]] = params.entities.map { entity in
            var dict: [String: Any] = [
                "type": entity.type,
                "offset": entity.offset,
                "length": entity.length,
            ]
            if let url = entity.url {
                dict["url"] = url
            }
            if let lang = entity.language {
                dict["language"] = lang
            }
            return dict
        }

        var rawParams: [String: Any] = [
            "peer": params.peerId,
            "peer_id": params.peerId,
            "message": params.message,
            "silent": params.silent,
            "no_webpage": params.noWebpage,
            "entities": entitiesPayload,
        ]
        if let reply = params.replyToMsgId {
            rawParams["replyToMsg"] = reply
            rawParams["reply_to_msg_id"] = reply
        }

        var outcome: AyuSendHookOutcome = .passThrough
        let semaphore = DispatchSemaphore(value: 0)

        self.pythonQueue.async { [weak self] in
            defer { semaphore.signal() }
            guard let self = self else {
                return
            }
            let result = self.dispatchPython(
                command: "dispatch_send_message_hook",
                payload: [
                    "account": params.account,
                    "params": rawParams,
                ]
            )
            let action = (result["action"] as? String ?? "default").lowercased()
            if action == "cancel" {
                outcome = .cancel
                return
            }
            if action == "modify", let outParams = result["params"] as? [String: Any] {
                var modified = params
                modified.message = outParams["message"] as? String ?? params.message
                modified.silent = (outParams["silent"] as? NSNumber)?.boolValue ?? params.silent
                modified.noWebpage = (outParams["no_webpage"] as? NSNumber)?.boolValue ?? params.noWebpage
                if let replyOut = (outParams["reply_to_msg_id"] as? NSNumber)?.int32Value ?? (outParams["replyToMsg"] as? NSNumber)?.int32Value {
                    modified.replyToMsgId = replyOut
                }
                if let rawOutEntities = outParams["entities"] as? [[String: Any]] {
                    modified.entities = rawOutEntities.compactMap { entry in
                        guard let type = entry["type"] as? String else { return nil }
                        let offset = (entry["offset"] as? NSNumber)?.intValue ?? 0
                        let length = (entry["length"] as? NSNumber)?.intValue ?? 0
                        return AyuPluginEntity(
                            type: type,
                            offset: offset,
                            length: length,
                            url: entry["url"] as? String,
                            language: entry["language"] as? String
                        )
                    }
                }
                outcome = .modify(modified)
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + .seconds(3))
        if waitResult == .timedOut {
            self.appendLog(level: "warn", pluginId: "runtime", message: "Outgoing message hook timed out (>3s); passing message unmodified.")
            return .passThrough
        }
        return outcome
    }

    public func dispatchIncomingMessages(_ events: [AyuIncomingMessageEvent]) {
        guard !events.isEmpty, !self.isSafeModeEnabled, self.hasActivePlugins, self.runtime.isInitialized else {
            return
        }
        self.pythonQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            for event in events {
                let payload: [String: Any] = [
                    "update_name": "receive_message",
                    "account": event.account,
                    "update": [
                        "peer_id": event.peerId,
                        "message_id": event.messageId,
                        "sender_id": event.senderId ?? 0,
                        "text": event.text,
                        "message": event.text,
                        "out": event.isOutgoing,
                        "date": event.date,
                    ],
                ]
                let _ = self.dispatchPython(command: "dispatch_update_hook", payload: payload)
            }
        }
    }

    public func makePluginsController(context: AnyObject) -> AnyObject? {
        guard let accountContext = context as? AccountContext else {
            return nil
        }
        self.bindAccountContext(accountContext)
        return ayuPluginsController(context: accountContext)
    }

    // MARK: - Python Dispatch Helper

    private func dispatchPython(command: String, payload: [String: Any]) -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let payloadString = String(data: data, encoding: .utf8) else {
            return ["ok": false, "error": "Failed to encode payload JSON"]
        }
        let responseString = self.runtime.dispatchCommand(command, payloadJSON: payloadString)
        guard let respData = responseString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            return ["ok": false, "error": "Invalid JSON returned by Python runtime"]
        }
        return parsed
    }

    private func settingsURL(for pluginId: String) -> URL {
        return self.settingsDirectory.appendingPathComponent("\(pluginId).json")
    }

    private func appendLog(level: String, pluginId: String, message: String) {
        self.stateLock.lock()
        self.logs.append(AyuPluginLogEntry(timestamp: Date(), level: level, pluginId: pluginId, message: message))
        if self.logs.count > 300 {
            self.logs.removeFirst(self.logs.count - 300)
        }
        self.stateLock.unlock()
    }

    private func showBulletin(title: String, subtitle: String, icon: String) {
        guard let context = self.activeContext else {
            return
        }
        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let combinedText = title.isEmpty ? subtitle : "\(title)\n\(subtitle)"
            let content: UndoOverlayContent
            switch icon.lowercased() {
            case "success":
                content = .succeed(text: combinedText, timeout: 2.5, customUndoText: nil)
            case "error":
                content = .banned(text: combinedText)
            default:
                content = .info(title: title.isEmpty ? nil : title, text: subtitle, timeout: 2.5, customUndoText: nil)
            }
            let controller = UndoOverlayController(
                presentationData: presentationData,
                content: content,
                elevatedLayout: false,
                action: { _ in return true }
            )
            context.sharedContext.mainWindow?.present(controller, on: .root)
        }
    }

    private func presentSimpleAlert(title: String?, text: String) {
        guard let context = self.activeContext else {
            return
        }
        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: title,
                text: text,
                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            )
            context.sharedContext.mainWindow?.present(alert, on: .root)
        }
    }

    // MARK: - AyuPythonNativeDelegate

    public func pythonLog(withLevel level: String, pluginId: String, message: String) {
        self.appendLog(level: level, pluginId: pluginId, message: message)
        self.postStateChanged()
    }

    public func pythonGetSetting(forPlugin pluginId: String, key: String, defaultJSON: String) -> String {
        let url = self.settingsURL(for: pluginId)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key] else {
            return defaultJSON
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let result = String(data: encoded, encoding: .utf8) else {
            return defaultJSON
        }
        return result
    }

    public func pythonSetSetting(forPlugin pluginId: String, key: String, valueJSON: String) {
        self.ensureDirectories()
        let url = self.settingsURL(for: pluginId)
        var dict: [String: Any] = [:]
        if let existing = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            dict = parsed
        }
        if let valData = valueJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: valData, options: [.fragmentsAllowed]) {
            dict[key] = decoded
        }
        if JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func pythonShowBulletin(withTitle title: String, subtitle: String, icon: String) {
        self.showBulletin(title: title, subtitle: subtitle, icon: icon)
    }

    public func pythonShowAlert(withTitle title: String, message: String, buttonsJSON: String) {
        guard let context = self.activeContext else {
            return
        }
        let buttonsData = buttonsJSON.data(using: .utf8) ?? Data()
        let rawButtons = (try? JSONSerialization.jsonObject(with: buttonsData)) as? [[String: Any]] ?? []
        DispatchQueue.main.async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            var actions: [TextAlertAction] = rawButtons.map { btn in
                let btnTitle = btn["text"] as? String ?? presentationData.strings.Common_OK
                let style = btn["style"] as? String ?? "default"
                let callbackId = btn["id"] as? String ?? ""
                return TextAlertAction(type: style == "default" ? .defaultAction : .genericAction, title: btnTitle, action: { [weak self] in
                    guard let self = self, !callbackId.isEmpty else {
                        return
                    }
                    self.pythonQueue.async {
                        let _ = self.dispatchPython(command: "trigger_alert_callback", payload: ["callback_id": callbackId])
                    }
                })
            }
            if actions.isEmpty {
                actions = [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            }
            let controller = textAlertController(
                context: context,
                title: title.isEmpty ? nil : title,
                text: message,
                actions: actions
            )
            context.sharedContext.mainWindow?.present(controller, on: .root)
        }
    }

    public func pythonSendMessage(withParamsJSON paramsJSON: String) -> String {
        return self.pythonExecuteRequest(withMethod: "messages.sendMessage", paramsJSON: paramsJSON)
    }

    public func pythonExecuteRequest(withMethod method: String, paramsJSON: String) -> String {
        guard let account = self.activeContext?.account else {
            return "{\"ok\":false,\"error\":\"No active Telegram account\"}"
        }
        var responseJSON = "{\"ok\":false,\"error\":\"Request timed out\"}"
        let semaphore = DispatchSemaphore(value: 0)
        let disposable = ayuPluginExecuteRequest(account: account, method: method, paramsJSON: paramsJSON).start(next: { value in
            responseJSON = value
            semaphore.signal()
        })
        let _ = semaphore.wait(timeout: .now() + .seconds(8))
        disposable.dispose()
        return responseJSON
    }

    public func pythonGetCurrentAccountJSON() -> String {
        guard let account = self.activeContext?.account else {
            return "{}"
        }
        var resultJSON = "{}"
        let semaphore = DispatchSemaphore(value: 0)
        let disposable = ayuPluginCurrentUserJSON(account: account).start(next: { value in
            resultJSON = value
            semaphore.signal()
        })
        let _ = semaphore.wait(timeout: .now() + .seconds(2))
        disposable.dispose()
        return resultJSON
    }
}
