import Foundation

public struct AyuPluginEntity: Codable, Equatable {
    public var type: String
    public var offset: Int
    public var length: Int
    public var url: String?
    public var language: String?

    public init(type: String, offset: Int, length: Int, url: String? = nil, language: String? = nil) {
        self.type = type
        self.offset = offset
        self.length = length
        self.url = url
        self.language = language
    }
}

public struct AyuSendHookParams: Codable, Equatable {
    public var account: Int64
    public var peerId: Int64
    public var message: String
    public var replyToMsgId: Int32?
    public var silent: Bool
    public var noWebpage: Bool
    public var entities: [AyuPluginEntity]

    public init(
        account: Int64,
        peerId: Int64,
        message: String,
        replyToMsgId: Int32? = nil,
        silent: Bool = false,
        noWebpage: Bool = false,
        entities: [AyuPluginEntity] = []
    ) {
        self.account = account
        self.peerId = peerId
        self.message = message
        self.replyToMsgId = replyToMsgId
        self.silent = silent
        self.noWebpage = noWebpage
        self.entities = entities
    }
}

public enum AyuSendHookOutcome: Equatable {
    case passThrough
    case modify(AyuSendHookParams)
    case cancel
}

public struct AyuIncomingMessageEvent: Codable, Equatable {
    public var account: Int64
    public var peerId: Int64
    public var messageId: Int32
    public var senderId: Int64?
    public var text: String
    public var isOutgoing: Bool
    public var date: Int32

    public init(
        account: Int64,
        peerId: Int64,
        messageId: Int32,
        senderId: Int64? = nil,
        text: String,
        isOutgoing: Bool,
        date: Int32
    ) {
        self.account = account
        self.peerId = peerId
        self.messageId = messageId
        self.senderId = senderId
        self.text = text
        self.isOutgoing = isOutgoing
        self.date = date
    }
}

public protocol AyuPluginHost: AnyObject {
    var hasActivePlugins: Bool { get }
    var activePluginCount: Int { get }
    var isSafeModeEnabled: Bool { get set }

    func startIfNeeded()
    func bindAccountContext(_ context: AnyObject)
    func processOutgoingMessage(_ params: AyuSendHookParams) -> AyuSendHookOutcome
    func dispatchIncomingMessages(_ events: [AyuIncomingMessageEvent])
    func installPlugin(fromFileURL url: URL, presentationContext: AnyObject?)
    func makePluginsController(context: AnyObject) -> AnyObject?
}

public final class AyuPluginBridge {
    public static let shared = AyuPluginBridge()

    private let lock = NSLock()
    private var host: AyuPluginHost?

    private init() {}

    public func registerHost(_ host: AyuPluginHost) {
        self.lock.lock()
        self.host = host
        self.lock.unlock()
    }

    private func currentHost() -> AyuPluginHost? {
        self.lock.lock()
        let current = self.host
        self.lock.unlock()
        return current
    }

    public var hasActivePlugins: Bool {
        return self.currentHost()?.hasActivePlugins ?? false
    }

    public var activePluginCount: Int {
        return self.currentHost()?.activePluginCount ?? 0
    }

    public var isSafeModeEnabled: Bool {
        get {
            return self.currentHost()?.isSafeModeEnabled ?? false
        }
        set {
            self.currentHost()?.isSafeModeEnabled = newValue
        }
    }

    public func startIfNeeded() {
        self.currentHost()?.startIfNeeded()
    }

    public func bindAccountContext(_ context: AnyObject) {
        self.currentHost()?.bindAccountContext(context)
    }

    public func processOutgoingMessage(_ params: AyuSendHookParams) -> AyuSendHookOutcome {
        guard let host = self.currentHost(), host.hasActivePlugins, !host.isSafeModeEnabled else {
            return .passThrough
        }
        return host.processOutgoingMessage(params)
    }

    public func dispatchIncomingMessages(_ events: [AyuIncomingMessageEvent]) {
        guard !events.isEmpty, let host = self.currentHost(), host.hasActivePlugins, !host.isSafeModeEnabled else {
            return
        }
        host.dispatchIncomingMessages(events)
    }

    public func installPlugin(fromFileURL url: URL, presentationContext: AnyObject? = nil) {
        self.currentHost()?.installPlugin(fromFileURL: url, presentationContext: presentationContext)
    }

    public func makePluginsController(context: AnyObject) -> AnyObject? {
        return self.currentHost()?.makePluginsController(context: context)
    }
}
