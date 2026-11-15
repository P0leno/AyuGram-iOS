import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ProgressNavigationButtonNode
import AccountContext
import CountrySelectionUI
import PhoneNumberFormat
import DebugSettingsUI
import MessageUI
import AuthenticationServices
import Postbox
import SGKeychainBackupManager
import SGStrings
import UniformTypeIdentifiers

private struct RestorableSessionBackup: Codable {
    var name: String? = nil
    var date: Date = Date()
    let accountRecord: AccountRecord<TelegramAccountManagerTypes.Attribute>

    var peerIdInternal: Int64 {
        var userId: Int64 = 0
        for attribute in self.accountRecord.attributes {
            if case let .backupData(backupData) = attribute, let backupPeerId = backupData.data?.peerId {
                userId = backupPeerId
                break
            }
        }
        return userId
    }

    var userId: Int64 {
        return PeerId(self.peerIdInternal).id._internalGetInt64Value()
    }
}

private final class AuthBackupDocumentPicker: UIDocumentPickerViewController, UIDocumentPickerDelegate {
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

public final class AuthorizationSequencePhoneEntryController: ViewController, MFMailComposeViewControllerDelegate, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controllerNode: AuthorizationSequencePhoneEntryControllerNode {
        return self.displayNode as! AuthorizationSequencePhoneEntryControllerNode
    }
    
    private var validLayout: ContainerViewLayout?
    
    private let sharedContext: SharedAccountContext
    private var account: UnauthorizedAccount?
    private let apiId: Int32
    private let apiHash: String
    private let isTestingEnvironment: Bool
    private let otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)])
    private let network: Network
    private let presentationData: PresentationData
    private let openUrl: (String) -> Void
    
    private let back: () -> Void
    
    private var currentData: (Int32, String?, String)?
        
    var codeNode: ASDisplayNode {
        return self.controllerNode.codeNode
    }
    
    var numberNode: ASDisplayNode {
        return self.controllerNode.numberNode
    }
    
    var buttonNode: ASDisplayNode {
        return self.controllerNode.buttonNode
    }
    
    public var inProgress: Bool = false {
        didSet {
            self.updateNavigationItems()
            self.controllerNode.inProgress = self.inProgress
            self.confirmationController?.inProgress = self.inProgress
        }
    }
    public var loginWithNumber: ((String, Bool) -> Void)?
    public var loginWithPasskey: ((AuthorizationPasskeyData, Bool) -> Void)?
    var accountUpdated: ((UnauthorizedAccount) -> Void)?
    
    weak var confirmationController: PhoneConfirmationController?
    
    private let termsDisposable = MetaDisposable()
    
    private let hapticFeedback = HapticFeedback()
    private var isManualPasskeyAttempt = false
    
    public init(sharedContext: SharedAccountContext, account: UnauthorizedAccount?, countriesConfiguration: CountriesConfiguration? = nil, apiId: Int32, apiHash: String, isTestingEnvironment: Bool, otherAccountPhoneNumbers: ((String, AccountRecordId, Bool)?, [(String, AccountRecordId, Bool)]), network: Network, presentationData: PresentationData, openUrl: @escaping (String) -> Void, back: @escaping () -> Void) {
        self.sharedContext = sharedContext
        self.account = account
        self.apiId = apiId
        self.apiHash = apiHash
        self.isTestingEnvironment = isTestingEnvironment
        self.otherAccountPhoneNumbers = otherAccountPhoneNumbers
        self.network = network
        self.presentationData = presentationData
        self.openUrl = openUrl
        self.back = back
                
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: AuthorizationSequenceController.navigationBarTheme(presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)))
        
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        
        self.hasActiveInput = true
        
        self.statusBar.statusBarStyle = presentationData.theme.intro.statusBarStyle.style
        self.attemptNavigation = { _ in
            return false
        }
        self.navigationBar?.backPressed = {
            back()
        }
        
        if !otherAccountPhoneNumbers.1.isEmpty {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "___close", style: .plain, target: self, action: #selector(self.cancelPressed))
        }
        
        if let countriesConfiguration {
            AuthorizationSequenceCountrySelectionController.setupCountryCodes(countries: countriesConfiguration.countries, codesByPrefix: countriesConfiguration.countriesByPrefix)
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.termsDisposable.dispose()
    }
    
    @objc private func cancelPressed() {
        self.back()
    }
    
    func updateNavigationItems() {
        guard let layout = self.validLayout, layout.size.width < 360.0 else {
            return
        }
                
        if self.inProgress {
            let item = UIBarButtonItem(customDisplayNode: ProgressNavigationButtonNode(color: self.presentationData.theme.rootController.navigationBar.accentTextColor))
            self.navigationItem.rightBarButtonItem = item
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Next, style: .done, target: self, action: #selector(self.nextPressed))
        }
    }
    
    public func updateData(countryCode: Int32, countryName: String?, number: String) {
        self.currentData = (countryCode, countryName, number)
        if self.isNodeLoaded {
            self.controllerNode.codeAndNumber = (countryCode, countryName, number)
        }
    }
    
    private var shouldAnimateIn = false
    private var transitionInArguments: (buttonFrame: CGRect, buttonTitle: String, animationSnapshot: UIView, textSnapshot: UIView)?
    
    func animateWithSplashController(_ controller: AuthorizationSequenceSplashController) {
        self.shouldAnimateIn = true
        
        if let animationSnapshot = controller.animationSnapshot, let textSnapshot = controller.textSnaphot {
            self.transitionInArguments = (controller.buttonFrame, controller.buttonTitle, animationSnapshot, textSnapshot)
        }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = AuthorizationSequencePhoneEntryControllerNode(sharedContext: self.sharedContext, account: self.account, strings: self.presentationData.strings, theme: self.presentationData.theme, debugAction: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.view.endEditing(true)
            self?.present(debugController(sharedContext: strongSelf.sharedContext, context: nil, modal: true), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }, hasOtherAccounts: self.otherAccountPhoneNumbers.0 != nil)
        self.controllerNode.accountUpdated = { [weak self] account in
            guard let strongSelf = self else {
                return
            }
            strongSelf.account = account
            strongSelf.accountUpdated?(account)
        }
        self.controllerNode.retryPasskey = { [weak self] in
            guard let self else {
                return
            }
            self.loadAndPresentPasskey(force: true)
        }
        self.controllerNode.loginWithSavedAccount = { [weak self] in
            guard let self else {
                return
            }
            self.presentSavedAccountsLogin()
        }
        self.refreshSavedAccountsCount()
        
        if let (code, name, number) = self.currentData {
            self.controllerNode.codeAndNumber = (code, name, number)
        }
        self.displayNodeDidLoad()
        
        self.controllerNode.view.disableAutomaticKeyboardHandling = [.forward, .backward]
        
        self.controllerNode.selectCountryCode = { [weak self] in
            if let strongSelf = self {
                let controller = AuthorizationSequenceCountrySelectionController(strings: strongSelf.presentationData.strings, theme: strongSelf.presentationData.theme, glass: true)
                controller.completeWithCountryCode = { code, name in
                    if let strongSelf = self, let currentData = strongSelf.currentData {
                        strongSelf.updateData(countryCode: Int32(code), countryName: name, number: currentData.2)
                        strongSelf.controllerNode.activateInput()
                    }
                }
                controller.dismissed = { 
                    self?.controllerNode.activateInput()
                }
                strongSelf.push(controller)
            }
        }
        self.controllerNode.checkPhone = { [weak self] in
            self?.nextPressed()
        }
        
        if let account = self.account {
            loadServerCountryCodes(accountManager: sharedContext.accountManager, engine: TelegramEngineUnauthorized(account: account), completion: { [weak self] in
                if let strongSelf = self {
                    strongSelf.controllerNode.updateCountryCode()
                }
            })
        } else {
            self.controllerNode.updateCountryCode()
        }
        
        self.loadAndPresentPasskey(force: false)
    }
    
    private func loadAndPresentPasskey(force: Bool) {
        if #available(iOS 16.0, *) {
            self.isManualPasskeyAttempt = force
            Task { @MainActor [weak self] in
                guard let self, let account = self.account else {
                    return
                }
                
                let decodeBase64: (String) -> Data? = { string in
                    var string = string.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    while string.count % 4 != 0 {
                        string.append("=")
                    }
                    return Data(base64Encoded: string)
                }
                
                let engine = TelegramEngineUnauthorized(account: account)
                let passkeyDataString = await engine.auth.requestPasskeyLoginData(apiId: self.apiId, apiHash: self.apiHash).get()
                guard let passkeyDataString, let passkeyData = passkeyDataString.data(using: .utf8) else {
                    self.isManualPasskeyAttempt = false
                    return
                }
                guard let params = try? JSONSerialization.jsonObject(with: passkeyData) as? [String: Any] else {
                    self.isManualPasskeyAttempt = false
                    return
                }
                guard let pkDict = params["publicKey"] as? [String: Any] else {
                    self.isManualPasskeyAttempt = false
                    return
                }
                let relyingPartyIdentifier = (pkDict["rpId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "telegram.org"
                guard let challengeBase64 = pkDict["challenge"] as? String else {
                    self.isManualPasskeyAttempt = false
                    return
                }
                guard let challengeData = decodeBase64(challengeBase64) else {
                    self.isManualPasskeyAttempt = false
                    return
                }
                
                let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
                let platformKeyRequest = platformProvider.createCredentialAssertionRequest(challenge: challengeData)
                let authController = ASAuthorizationController(authorizationRequests: [platformKeyRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                if force {
                    authController.performRequests()
                } else {
                    authController.performRequests(options: [.preferImmediatelyAvailableCredentials])
                }
            }
        }
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        self.isManualPasskeyAttempt = false
        Task { @MainActor [weak self] in
            guard let self, let account = self.account else {
                return
            }
            
            let encodeBase64URL: (Data) -> String = { data in
                var string = data.base64EncodedString()
                string = string
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                string = string.replacingOccurrences(of: "=", with: "")
                return string
            }
            
            if #available(iOS 17.0, *) {
                if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                    guard let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8) else {
                        return
                    }
                    guard let userHandle = String(data: credential.userID, encoding: .utf8) else {
                        return
                    }
                    let passkey = AuthorizationPasskeyData(
                        id: encodeBase64URL(credential.credentialID),
                        clientData: clientData,
                        authenticatorData: credential.rawAuthenticatorData,
                        signature: credential.signature,
                        userHandle: userHandle
                    )
                    self.loginWithPasskey?(passkey, self.controllerNode.syncContacts)
                    
                    /*if let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8), let attestationObject = credential.rawAttestationObject {
                        let passkey = await component.context.engine.auth.requestCreatePasskey(id: encodeBase64URL(credential.credentialID), clientData: clientData, attestationObject: attestationObject).get()
                        if let passkey {
                            if self.passkeysData == nil {
                                self.passkeysData = []
                                self.passkeysData?.insert(passkey, at: 0)
                            }
                            self.state?.updated(transition: .immediate)
                        }
                    }*/
                    let _ = account
                    let _ = credential
                }
            }
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let wasManualAttempt = self.isManualPasskeyAttempt
        self.isManualPasskeyAttempt = false

        let nsError = error as NSError
        self.controllerNode.updateDisplayPasskeyLoginOption()
        if let validLayout = self.validLayout {
            self.containerLayoutUpdated(validLayout, transition: .immediate)
        }

        if nsError.domain == ASAuthorizationError.errorDomain && nsError.code == ASAuthorizationError.canceled.rawValue {
            return
        }

        if wasManualAttempt {
            let locale = self.presentationData.strings.baseLanguageCode
            let message = "Keychain.PasskeyFallbackMessage".i18n(locale, args: error.localizedDescription)
            let alert = textAlertController(
                sharedContext: self.sharedContext,
                title: self.presentationData.strings.Passkeys_Title,
                text: message,
                actions: [
                    TextAlertAction(type: .defaultAction, title: "Keychain.SavedAccountsAction".i18n(locale), action: { [weak self] in
                        self?.presentSavedAccountsLogin()
                    }),
                    TextAlertAction(type: .genericAction, title: "Keychain.RetryPasskey".i18n(locale), action: { [weak self] in
                        self?.loadAndPresentPasskey(force: true)
                    }),
                    TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_Cancel, action: {})
                ]
            )
            self.present(alert, in: .window(.root))
        }
    }
    
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = self.view.window?.windowScene else {
            preconditionFailure()
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
    
    public func updateCountryCode() {
        self.controllerNode.updateCountryCode()
    }
    
    private var animatingIn = false
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if self.shouldAnimateIn {
            self.animatingIn = true
            if let (buttonFrame, buttonTitle, animationSnapshot, textSnapshot) = self.transitionInArguments {
                self.controllerNode.willAnimateIn(buttonFrame: buttonFrame, buttonTitle: buttonTitle, animationSnapshot: animationSnapshot, textSnapshot: textSnapshot)
            }
            Queue.mainQueue().justDispatch {
                self.controllerNode.activateInput()
            }
        } else {
            self.controllerNode.activateInput()
        }
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.animatingIn {
            self.controllerNode.activateInput()
        }
        self.refreshSavedAccountsCount()
    }
    
    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let confirmationController = self.confirmationController {
            confirmationController.transitionOut()
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let hadLayout = self.validLayout != nil
        self.validLayout = layout
        
        if !hadLayout {
            self.updateNavigationItems()
        }
    
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
        
        if self.shouldAnimateIn, let inputHeight = layout.inputHeight, inputHeight > 0.0 {
            if let (buttonFrame, buttonTitle, animationSnapshot, textSnapshot) = self.transitionInArguments {
                self.shouldAnimateIn = false
                self.controllerNode.animateIn(buttonFrame: buttonFrame, buttonTitle: buttonTitle, animationSnapshot: animationSnapshot, textSnapshot: textSnapshot)
            }
        }
    }
    
    public func dismissConfirmation() {
        self.confirmationController?.dismissAnimated()
        self.confirmationController = nil
    }
    
    @objc func nextPressed() {
        guard self.confirmationController == nil else {
            return
        }
        let (_, _, number) = self.controllerNode.codeAndNumber
        if !number.isEmpty {
            let logInNumber = cleanPhoneNumber(self.controllerNode.currentNumber, removePlus: true)
            var existing: (String, AccountRecordId)?
            for (number, id, isTestingEnvironment) in self.otherAccountPhoneNumbers.1 {
                if isTestingEnvironment == self.isTestingEnvironment && cleanPhoneNumber(number, removePlus: true) == logInNumber {
                    existing = (number, id)
                }
            }
            
            if let (_, id) = existing {
                var actions: [TextAlertAction] = []
                if let (current, _, _) = self.otherAccountPhoneNumbers.0, logInNumber != cleanPhoneNumber(current, removePlus: true) {
                    actions.append(TextAlertAction(type: .genericAction, title: self.presentationData.strings.Login_PhoneNumberAlreadyAuthorizedSwitch, action: { [weak self] in
                        self?.sharedContext.switchToAccount(id: id, fromSettingsController: nil, withChatListController: nil)
                        self?.back()
                    }))
                }
                actions.append(TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {}))
                self.present(textAlertController(sharedContext: self.sharedContext, title: nil, text: self.presentationData.strings.Login_PhoneNumberAlreadyAuthorized, actions: actions), in: .window(.root))
            } else {
                // MARK: Swiftgram
                if (number == "0000000000") {
                    self.sharedContext.beginNewAuth(testingEnvironment: true)
                    return
                }
                if let validLayout = self.validLayout, validLayout.size.width > 320.0 {
                    let (code, formattedNumber) = self.controllerNode.formattedCodeAndNumber

                    let confirmationController = PhoneConfirmationController(theme: self.presentationData.theme, strings: self.presentationData.strings, code: code, number: formattedNumber, sourceController: self)
                    confirmationController.proceed = { [weak self] in
                        if let strongSelf = self {
                            strongSelf.loginWithNumber?(strongSelf.controllerNode.currentNumber, strongSelf.controllerNode.syncContacts)
                        }
                    }
                    (self.navigationController as? NavigationController)?.presentOverlay(controller: confirmationController, inGlobal: true, blockInteraction: true)
                    self.confirmationController = confirmationController
                } else {
                    var actions: [TextAlertAction] = []
                    actions.append(TextAlertAction(type: .genericAction, title: self.presentationData.strings.Login_Edit, action: {}))
                    actions.append(TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Login_Yes, action: { [weak self] in
                        if let strongSelf = self {
                            strongSelf.loginWithNumber?(strongSelf.controllerNode.currentNumber, strongSelf.controllerNode.syncContacts)
                        }
                    }))
                    self.present(textAlertController(sharedContext: self.sharedContext, title: logInNumber, text: self.presentationData.strings.Login_PhoneNumberConfirmation, actions: actions), in: .window(.root))
                }
            }
        } else {
            self.hapticFeedback.error()
            self.controllerNode.animateError()
        }
    }
    
    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - Keychain / Face ID Saved Account Login & Encrypted Import

    private func loadRestorableBackups() -> [RestorableSessionBackup] {
        guard let entries = try? KeychainBackupManager.shared.getAllSessons() else {
            return []
        }
        let decoder = JSONDecoder()
        return entries
            .compactMap { try? decoder.decode(RestorableSessionBackup.self, from: $0) }
            .filter { $0.peerIdInternal != 0 }
            .sorted { $0.date > $1.date }
    }

    private func refreshSavedAccountsCount() {
        let count = self.loadRestorableBackups().count
        if self.isNodeLoaded {
            self.controllerNode.updateSavedAccountsCount(count)
            if let validLayout = self.validLayout {
                self.containerLayoutUpdated(validLayout, transition: .immediate)
            }
        }
    }

    private func presentSavedAccountsLogin() {
        self.view.endEditing(true)
        let locale = self.presentationData.strings.baseLanguageCode
        let backups = self.loadRestorableBackups()

        let sheet = ActionSheetController(presentationData: self.presentationData)
        var items: [ActionSheetItem] = []

        if !backups.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for backup in backups {
                let displayName = backup.name ?? "ID \(backup.userId)"
                let title = "\(displayName) (\(formatter.string(from: backup.date)))"
                items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.restoreKeychainBackup(backup)
                }))
            }
        }

        items.append(ActionSheetButtonItem(title: "Keychain.ImportEncryptedFile".i18n(locale), color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            self?.presentEncryptedBackupPicker()
        }))

        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func restoreKeychainBackup(_ backup: RestorableSessionBackup) {
        let locale = self.presentationData.strings.baseLanguageCode
        let reason = "Keychain.FaceIDReason".i18n(locale, args: backup.name ?? "ID \(backup.userId)")

        KeychainBackupManager.shared.authenticateWithBiometrics(reason: reason) { [weak self] authResult in
            guard let self else {
                return
            }
            switch authResult {
            case let .failure(error):
                let alert = textAlertController(
                    sharedContext: self.sharedContext,
                    title: "Keychain.SavedAccountsTitle".i18n(locale),
                    text: error.localizedDescription,
                    actions: [
                        TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})
                    ]
                )
                self.present(alert, in: .window(.root))
            case .success:
                var importAttributes = backup.accountRecord.attributes
                importAttributes.removeAll { attribute in
                    if case .sortOrder = attribute {
                        return true
                    }
                    return false
                }

                let targetPeerId = backup.peerIdInternal
                let sharedContext = self.sharedContext
                let signal = sharedContext.accountManager.transaction { transaction -> AccountRecordId in
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
                    return targetRecordId
                }
                |> deliverOnMainQueue

                let _ = signal.startStandalone()
            }
        }
    }

    private func presentEncryptedBackupPicker() {
        let picker = AuthBackupDocumentPicker(forOpeningContentTypes: [.data, .item], asCopy: true)
        picker.delegate = picker
        picker.allowsMultipleSelection = false
        picker.picked = { [weak self] url in
            guard let self, let data = try? Data(contentsOf: url) else {
                return
            }
            self.promptEncryptedBackupPassphrase(for: data)
        }
        self.present(picker, animated: true)
    }

    private func promptEncryptedBackupPassphrase(for data: Data) {
        let locale = self.presentationData.strings.baseLanguageCode
        let alert = UIAlertController(
            title: "Keychain.ImportEncryptedTitle".i18n(locale),
            message: "Keychain.ImportPassphrasePrompt".i18n(locale),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.isSecureTextEntry = true
            textField.placeholder = "Keychain.PassphrasePlaceholder".i18n(locale)
        }
        alert.addAction(UIAlertAction(title: self.presentationData.strings.Common_Cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: self.presentationData.strings.Common_OK, style: .default, handler: { [weak self, weak alert] _ in
            guard let self else {
                return
            }
            let passphrase = alert?.textFields?.first?.text ?? ""
            do {
                _ = try KeychainBackupManager.shared.importEncryptedBackup(data, passphrase: passphrase)
                self.refreshSavedAccountsCount()
                self.presentSavedAccountsLogin()
            } catch {
                let errAlert = textAlertController(
                    sharedContext: self.sharedContext,
                    title: "Keychain.ImportEncryptedTitle".i18n(locale),
                    text: error.localizedDescription,
                    actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {})]
                )
                self.present(errAlert, in: .window(.root))
            }
        }))
        self.present(alert, animated: true)
    }
}
