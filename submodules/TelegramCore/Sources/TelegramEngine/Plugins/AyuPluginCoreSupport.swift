import Foundation
import Postbox
import SwiftSignalKit

public struct AyuPluginCoreEntity: Equatable {
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

public func ayuPluginConvertEntities(_ rawEntities: [AyuPluginCoreEntity]) -> [MessageTextEntity] {
    var result: [MessageTextEntity] = []
    result.reserveCapacity(rawEntities.count)
    for item in rawEntities where item.length > 0 && item.offset >= 0 {
        let range = item.offset ..< (item.offset + item.length)
        let entityType: MessageTextEntityType
        switch item.type.lowercased() {
        case "bold":
            entityType = .Bold
        case "italic":
            entityType = .Italic
        case "code":
            entityType = .Code
        case "pre":
            entityType = .Pre(language: item.language?.isEmpty == true ? nil : item.language)
        case "text_url", "url":
            entityType = .TextUrl(url: item.url ?? "")
        case "strike", "strikethrough":
            entityType = .Strikethrough
        case "underline":
            entityType = .Underline
        case "spoiler":
            entityType = .Spoiler
        case "mention":
            entityType = .Mention
        case "hashtag":
            entityType = .Hashtag
        default:
            continue
        }
        result.append(MessageTextEntity(range: range, type: entityType))
    }
    return result
}

private func resolveAyuPluginPeerId(transaction: Transaction, rawPeerId: Int64) -> PeerId {
    if rawPeerId < -1_000_000_000_000 {
        let bareChannelId = -rawPeerId - 1_000_000_000_000
        return PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(bareChannelId))
    }
    if rawPeerId < 0 {
        return PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(-rawPeerId))
    }
    let direct = PeerId(rawPeerId)
    if transaction.getPeer(direct) != nil {
        return direct
    }
    return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(rawPeerId))
}

private func jsonToAny(_ value: JSON) -> Any {
    switch value {
    case .null:
        return NSNull()
    case let .number(num):
        return num
    case let .string(str):
        return str
    case let .bool(flag):
        return flag
    case let .array(items):
        return items.map(jsonToAny)
    case let .dictionary(dict):
        var mapped: [String: Any] = [:]
        for (k, v) in dict {
            mapped[k] = jsonToAny(v)
        }
        return mapped
    }
}

private func encodePluginJSONResponse(_ object: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: []),
          let str = String(data: data, encoding: .utf8) else {
        return "{\"ok\":false,\"error\":\"JSON serialization failed\"}"
    }
    return str
}

private func parseEntitiesFromParams(_ dict: [String: Any]) -> [AyuPluginCoreEntity] {
    guard let list = dict["entities"] as? [[String: Any]] else {
        return []
    }
    return list.compactMap { item in
        guard let type = item["type"] as? String else {
            return nil
        }
        let offset = (item["offset"] as? NSNumber)?.intValue ?? 0
        let length = (item["length"] as? NSNumber)?.intValue ?? 0
        return AyuPluginCoreEntity(
            type: type,
            offset: offset,
            length: length,
            url: item["url"] as? String,
            language: item["language"] as? String
        )
    }
}

public func ayuPluginSendTextMessage(
    account: Account,
    rawPeerId: Int64,
    text: String,
    entities: [AyuPluginCoreEntity] = [],
    replyToMsgId: Int32? = nil,
    silentPosting: Bool = false
) -> Signal<[MessageId?], NoError> {
    return account.postbox.transaction { transaction -> PeerId in
        return resolveAyuPluginPeerId(transaction: transaction, rawPeerId: rawPeerId)
    }
    |> mapToSignal { peerId in
        var attributes: [MessageAttribute] = []
        if silentPosting {
            attributes.append(NotificationInfoMessageAttribute(flags: .muted))
        }
        let convertedEntities = ayuPluginConvertEntities(entities)
        if !convertedEntities.isEmpty {
            attributes.append(TextEntitiesMessageAttribute(entities: convertedEntities))
        }
        let replySubject: EngineMessageReplySubject? = replyToMsgId.map { msgId in
            EngineMessageReplySubject(
                messageId: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: msgId),
                quote: nil,
                innerSubject: nil
            )
        }
        return enqueueMessages(
            account: account,
            peerId: peerId,
            messages: [
                .message(
                    text: text,
                    attributes: attributes,
                    inlineStickers: [:],
                    mediaReference: nil,
                    threadId: nil,
                    replyToMessageId: replySubject,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
            ]
        )
    }
}

public func ayuPluginCurrentUserJSON(account: Account) -> Signal<String, NoError> {
    return account.postbox.transaction { transaction -> String in
        guard let user = transaction.getPeer(account.peerId) as? TelegramUser else {
            return encodePluginJSONResponse([
                "id": account.peerId.toInt64(),
                "first_name": "",
                "last_name": "",
                "username": "",
                "phone": "",
                "is_premium": false
            ])
        }
        return encodePluginJSONResponse([
            "id": user.id.toInt64(),
            "first_name": user.firstName ?? "",
            "last_name": user.lastName ?? "",
            "username": user.username ?? "",
            "phone": user.phone ?? "",
            "is_premium": user.flags.contains(.isPremium)
        ])
    }
}

public func ayuPluginExecuteRequest(account: Account, method: String, paramsJSON: String) -> Signal<String, NoError> {
    let paramsData = paramsJSON.data(using: .utf8) ?? Data()
    let params = (try? JSONSerialization.jsonObject(with: paramsData)) as? [String: Any] ?? [:]
    let engine = TelegramEngine(account: account)

    switch method.lowercased() {
    case "messages.sendmessage":
        guard let rawPeer = (params["peer_id"] as? NSNumber)?.int64Value ?? (params["peer"] as? NSNumber)?.int64Value else {
            return .single(encodePluginJSONResponse(["ok": false, "error": "Missing peer_id"]))
        }
        let text = params["message"] as? String ?? ""
        let replyId = (params["reply_to_msg_id"] as? NSNumber)?.int32Value ?? (params["replyToMsg"] as? NSNumber)?.int32Value
        let silent = (params["silent"] as? NSNumber)?.boolValue ?? false
        let entities = parseEntitiesFromParams(params)
        return ayuPluginSendTextMessage(
            account: account,
            rawPeerId: rawPeer,
            text: text,
            entities: entities,
            replyToMsgId: replyId,
            silentPosting: silent
        )
        |> map { ids in
            let firstId = ids.first??.id ?? 0
            return encodePluginJSONResponse(["ok": true, "result": ["message_id": firstId]])
        }

    case "messages.editmessage":
        guard let rawPeer = (params["peer_id"] as? NSNumber)?.int64Value ?? (params["peer"] as? NSNumber)?.int64Value,
              let msgId = (params["id"] as? NSNumber)?.int32Value ?? (params["message_id"] as? NSNumber)?.int32Value else {
            return .single(encodePluginJSONResponse(["ok": false, "error": "Missing peer_id or id"]))
        }
        let text = params["message"] as? String ?? ""
        let convertedEntities = ayuPluginConvertEntities(parseEntitiesFromParams(params))
        let entitiesAttr = convertedEntities.isEmpty ? nil : TextEntitiesMessageAttribute(entities: convertedEntities)
        let disableWebpage = (params["no_webpage"] as? NSNumber)?.boolValue ?? false

        return account.postbox.transaction { transaction -> PeerId in
            return resolveAyuPluginPeerId(transaction: transaction, rawPeerId: rawPeer)
        }
        |> mapToSignal { peerId in
            let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: msgId)
            return engine.messages.requestEditMessage(
                messageId: messageId,
                text: text,
                media: .keep,
                entities: entitiesAttr,
                richText: nil,
                inlineStickers: [:],
                disableUrlPreview: disableWebpage
            )
            |> map { _ in encodePluginJSONResponse(["ok": true, "result": ["edited": true]]) }
            |> `catch` { err in
                return .single(encodePluginJSONResponse(["ok": false, "error": "\(err)"]))
            }
        }

    case "messages.deletemessages":
        guard let rawPeer = (params["peer_id"] as? NSNumber)?.int64Value ?? (params["peer"] as? NSNumber)?.int64Value else {
            return .single(encodePluginJSONResponse(["ok": false, "error": "Missing peer_id"]))
        }
        var rawIds: [Int32] = []
        if let singleId = (params["id"] as? NSNumber)?.int32Value {
            rawIds = [singleId]
        } else if let list = params["id"] as? [NSNumber] {
            rawIds = list.map { $0.int32Value }
        }
        guard !rawIds.isEmpty else {
            return .single(encodePluginJSONResponse(["ok": false, "error": "Missing message id(s)"]))
        }
        let revoke = (params["revoke"] as? NSNumber)?.boolValue ?? true
        return account.postbox.transaction { transaction -> PeerId in
            return resolveAyuPluginPeerId(transaction: transaction, rawPeerId: rawPeer)
        }
        |> mapToSignal { peerId in
            let ids = rawIds.map { MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: $0) }
            return engine.messages.deleteMessagesInteractively(
                messageIds: ids,
                type: revoke ? .forEveryone : .forLocalPeer
            )
            |> map { encodePluginJSONResponse(["ok": true, "result": ["deleted": ids.count]]) }
        }

    case "help.getappconfig":
        return account.postbox.transaction { transaction -> String in
            let config = currentAppConfiguration(transaction: transaction)
            let dataObj = config.data.map(jsonToAny) ?? [:]
            return encodePluginJSONResponse([
                "ok": true,
                "result": [
                    "hash": config.hash,
                    "config": dataObj
                ]
            ])
        }

    case "users.getfulluser":
        guard let rawUserId = (params["user_id"] as? NSNumber)?.int64Value ?? (params["id"] as? NSNumber)?.int64Value else {
            return .single(encodePluginJSONResponse(["ok": false, "error": "Missing user_id"]))
        }
        let targetPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(rawUserId))
        return engine.peers.fetchAndUpdateCachedPeerData(peerId: targetPeerId)
        |> mapToSignal { _ -> Signal<String, NoError> in
            return account.postbox.transaction { transaction -> String in
                let user = transaction.getPeer(targetPeerId) as? TelegramUser
                let cached = transaction.getPeerCachedData(peerId: targetPeerId) as? CachedUserData
                return encodePluginJSONResponse([
                    "ok": true,
                    "result": [
                        "id": rawUserId,
                        "first_name": user?.firstName ?? "",
                        "last_name": user?.lastName ?? "",
                        "username": user?.username ?? "",
                        "about": cached?.about ?? "",
                        "is_premium": user?.flags.contains(.isPremium) ?? false
                    ]
                ])
            }
        }

    case "account.getme":
        return ayuPluginCurrentUserJSON(account: account)
        |> map { jsonStr in
            let obj = (try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8))) as? [String: Any] ?? [:]
            return encodePluginJSONResponse(["ok": true, "result": obj])
        }

    default:
        return .single(
            encodePluginJSONResponse([
                "ok": false,
                "error": "TL method '\(method)' is unsupported on iOS; pure-Python messages/users/help methods and HTTP requests are supported."
            ])
        )
    }
}
