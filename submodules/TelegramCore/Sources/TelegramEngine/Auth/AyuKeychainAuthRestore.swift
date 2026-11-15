import Foundation
import Postbox
import SwiftSignalKit

public struct AyuRestorableKeychainSession: Equatable {
    public let name: String?
    public let date: Date
    public let userId: Int64
    public let rawData: Data

    public init(name: String?, date: Date, userId: Int64, rawData: Data) {
        self.name = name
        self.date = date
        self.userId = userId
        self.rawData = rawData
    }
}

private struct AyuDecodedKeychainSession: Codable {
    var name: String? = nil
    var date: Date = Date()
    let accountRecord: AccountRecord<TelegramAccountManagerTypes.Attribute>

    var peerIdInternal: Int64 {
        for attribute in self.accountRecord.attributes {
            if case let .backupData(backupData) = attribute, let backupPeerId = backupData.data?.peerId {
                return backupPeerId
            }
        }
        return 0
    }

    var userId: Int64 {
        return PeerId(self.peerIdInternal).id._internalGetInt64Value()
    }
}

public func ayuParseRestorableKeychainSessions(from entries: [Data]) -> [AyuRestorableKeychainSession] {
    let decoder = JSONDecoder()
    return entries.compactMap { data -> AyuRestorableKeychainSession? in
        guard let decoded = try? decoder.decode(AyuDecodedKeychainSession.self, from: data), decoded.peerIdInternal != 0 else {
            return nil
        }
        return AyuRestorableKeychainSession(
            name: decoded.name,
            date: decoded.date,
            userId: decoded.userId,
            rawData: data
        )
    }
    .sorted { $0.date > $1.date }
}

public func ayuRestoreKeychainSession(
    rawData: Data,
    accountManager: AccountManager<TelegramAccountManagerTypes>
) -> Signal<Void, NoError> {
    guard let decoded = try? JSONDecoder().decode(AyuDecodedKeychainSession.self, from: rawData), decoded.peerIdInternal != 0 else {
        return .complete()
    }

    var importAttributes = decoded.accountRecord.attributes
    importAttributes.removeAll { attribute in
        if case .sortOrder = attribute {
            return true
        }
        return false
    }

    let targetPeerId = decoded.peerIdInternal
    return accountManager.transaction { transaction -> Void in
        let records = transaction.getRecords()
        let existing = records.first { record in
            var recordPeerId: Int64 = 0
            for attribute in record.attributes {
                if case let .backupData(backupData) = attribute {
                    recordPeerId = backupData.data?.peerId ?? 0
                }
            }
            return recordPeerId == targetPeerId
        }

        let nextSortOrder = (records.map({ record -> Int32 in
            for attribute in record.attributes {
                if case let .sortOrder(sortOrder) = attribute {
                    return sortOrder.order
                }
            }
            return 0
        }).max() ?? 0) + 1
        importAttributes.append(.sortOrder(AccountSortOrderAttribute(order: nextSortOrder)))

        let targetRecordId: AccountRecordId
        if let existing {
            targetRecordId = existing.id
            transaction.updateRecord(targetRecordId, { _ in
                return AccountRecord(id: targetRecordId, attributes: importAttributes, temporarySessionId: nil)
            })
        } else {
            targetRecordId = transaction.createRecord(importAttributes)
        }
        transaction.setCurrentId(targetRecordId)
        transaction.removeAuth()
    }
}
