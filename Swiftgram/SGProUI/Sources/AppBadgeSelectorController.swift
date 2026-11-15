import Foundation
import SwiftUI
import UIKit
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData
import AccountContext


struct AppBadge: Identifiable, Hashable {
    let id: UUID = .init()
    let displayName: String
    let assetName: String
}

private final class CustomBadgeImagePicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var onPick: ((UIImage) -> Void)?

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [weak self] in
            if let image {
                self?.onPick?(image)
            }
            self?.onPick = nil
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            self?.onPick = nil
        }
    }
}

private func appBadges(_ styles: [(name: String, title: String)]) -> [AppBadge] {
    return styles.filter { !$0.name.hasSuffix("DuckyAppBadge") || SGSimpleSettings.shared.duckyAppIconAvailable }.map { AppBadge(displayName: $0.title, assetName: $0.name) }
}

func getTelegramAppBadges() -> [AppBadge] {
    return appBadges(telegramAppBadgeStyles)
}

func getAyuGramAppBadges() -> [AppBadge] {
    return appBadges(ayuGramAppBadgeStyles)
}

func getSwiftgramAppBadges() -> [AppBadge] {
    return appBadges(swiftgramAppBadgeStyles)
}

func getCustomAppBadges() -> [AppBadge] {
    var list: [AppBadge] = [
        AppBadge(displayName: "Custom Text", assetName: ayuCustomTextBadgeId)
    ]
    if ayuHasCustomBadgeImage() {
        list.append(AppBadge(displayName: "Custom Photo", assetName: ayuCustomImageBadgeId))
    }
    return list
}

func getAvailableAppBadges() -> [AppBadge] {
    return getCustomAppBadges() + getTelegramAppBadges() + getAyuGramAppBadges() + getSwiftgramAppBadges()
}
    
@available(iOS 14.0, *)
struct AppBadgeSettingsView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.lang) var lang: String
    
    @State var selectedAssetName: String
    @State var customText: String = ayuCustomBadgeSettings().text
    @State var customThemeId: String = ayuCustomBadgeSettings().themeId
    @State var customShowIcon: Bool = ayuCustomBadgeSettings().showIcon
    @State var hasCustomImage: Bool = ayuHasCustomBadgeImage()
    @State var previewRevision: Int = 0
    @State var imagePickerHelper = CustomBadgeImagePicker()

    private enum Layout {
        static let cardCorner: CGFloat = 12
        static let imageHeight: CGFloat = 56
        static let columnSpacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 20
    }

    private var columns: [SwiftUI.GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Layout.columnSpacing), count: 2)
    }
    
    init(wrapperController: LegacyController?, context: AccountContext) {
        self.wrapperController = wrapperController
        self.context = context
        
        let current = SGSimpleSettings.shared.customAppBadge
        let available = getAvailableAppBadges()
        if available.contains(where: { $0.assetName == current }) {
            self._selectedAssetName = State(initialValue: current)
        } else {
            self._selectedAssetName = State(initialValue: getTelegramAppBadges().first?.assetName ?? "Components/AppBadge")
        }
    }
    
    private func applyBadge(_ assetName: String) {
        self.selectedAssetName = assetName
        self.previewRevision += 1
        DispatchQueue.main.async {
            SGSimpleSettings.shared.customAppBadge = assetName
            NotificationCenter.default.post(name: Notification.Name("AyuGram.AppIcon.didChange"), object: nil)
        }
    }

    private func saveCustomTextBadge() {
        ayuSetCustomBadgeSettings(text: self.customText, themeId: self.customThemeId, showIcon: self.customShowIcon)
        self.applyBadge(ayuCustomTextBadgeId)
    }

    private func pickCustomBadgeImage() {
        guard let host = self.wrapperController else {
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        self.imagePickerHelper.onPick = { image in
            if ayuSaveCustomBadgeImage(image) {
                self.hasCustomImage = true
                self.applyBadge(ayuCustomImageBadgeId)
            }
        }
        picker.delegate = self.imagePickerHelper
        host.present(picker, animated: true)
    }
    
    var body: some View {
        ScrollView {
            customBadgeEditorSection()
            badgeSection(title: "Telegram", badges: getTelegramAppBadges())
            badgeSection(title: "AyuGram", badges: getAyuGramAppBadges())
            badgeSection(title: "Swiftgram", badges: getSwiftgramAppBadges())
                .padding(.bottom, 24)
        }
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func customBadgeEditorSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CUSTOM BADGE")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, Layout.horizontalPadding + 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Image(uiImage: ayuGramCustomBadgePreview(text: customText, themeId: customThemeId, showIcon: customShowIcon, scale: 3))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        .id("custom-preview-\(previewRevision)-\(customText)-\(customThemeId)-\(customShowIcon)")
                    Spacer()
                }
                .padding(.vertical, 4)

                TextField("TELEGRAM", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customText) { newValue in
                        if newValue.count > 18 {
                            customText = String(newValue.prefix(18))
                        }
                    }

                Toggle("Telegram Plane Icon", isOn: $customShowIcon)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ayuCustomBadgeThemes) { theme in
                            Button {
                                customThemeId = theme.id
                                saveCustomTextBadge()
                            } label: {
                                Text(theme.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(theme.textColor))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        LinearGradient(
                                            colors: theme.colors.map { Color($0) },
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(customThemeId == theme.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        saveCustomTextBadge()
                    } label: {
                        Text("Apply Custom Text")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pickCustomBadgeImage()
                    } label: {
                        Text("Photo Badge")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundColor(.accentColor)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }

                if hasCustomImage {
                    HStack(spacing: 10) {
                        Button {
                            applyBadge(ayuCustomImageBadgeId)
                        } label: {
                            HStack(spacing: 8) {
                                Image(uiImage: ayuGramAppBadgeImage(style: ayuCustomImageBadgeId, scale: 3))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 24)
                                Text(selectedAssetName == ayuCustomImageBadgeId ? "Active Photo Badge" : "Use Photo Badge")
                                    .font(.footnote.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            ayuClearCustomBadgeImage()
                            hasCustomImage = false
                            if selectedAssetName == ayuCustomImageBadgeId {
                                applyBadge(ayuCustomTextBadgeId)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(8)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color(colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
            .cornerRadius(Layout.cardCorner)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCorner)
                    .stroke(selectedAssetName == ayuCustomTextBadgeId || selectedAssetName == ayuCustomImageBadgeId ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .padding(.horizontal, Layout.horizontalPadding)
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func badgeSection(title: String, badges: [AppBadge]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, Layout.horizontalPadding + 4)
            LazyVGrid(columns: columns, alignment: .center, spacing: Layout.columnSpacing) {
                ForEach(badges) { badge in
                    Button {
                        applyBadge(badge.assetName)
                    } label: {
                        VStack(spacing: 8) {
                            Image(uiImage: ayuGramAppBadgeImage(style: badge.assetName, scale: 3))
                                .resizable()
                                .scaledToFit()
                                .frame(height: Layout.imageHeight)
                                .accessibilityHidden(true)

                            Text(badge.displayName)
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
                        .cornerRadius(Layout.cardCorner)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.cardCorner)
                                .stroke(selectedAssetName == badge.assetName ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
        }
        .padding(.top, 24)
    }
    
}

@available(iOS 14.0, *)
public func sgAppBadgeSettingsController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )

    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.title = "AppBadge.Title".i18n(strings.baseLanguageCode)
    
    let swiftUIView = SGSwiftUIView<AppBadgeSettingsView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            AppBadgeSettingsView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
