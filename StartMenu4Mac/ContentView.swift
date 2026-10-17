import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin
import CoreServices

// UIの定数を管理する構造体
// 数値を一か所に集約し、各ビューで同じサイズ・余白を共有します。
struct Layout {
    // ピン留めアイコンの縦横サイズです。
    static let pinnedIconSize: CGFloat = 56
    // アイコンと名前を含む、ピン留め1マスの横幅です。
    static let pinnedTileWidth: CGFloat = 92
    // ピン留め1マスの高さです。
    static let pinnedTileHeight: CGFloat = 100
    // グリッド内の各マス同士の間隔です。
    static let pinnedGridSpacing: CGFloat = 10
    // アプリとフォルダーで共通に使うアイコン領域の高さです。通常アイコンはこの中で中央に置きます。
    static let pinnedIconAreaHeight: CGFloat = 56
    // アイコン領域と名前領域の間隔です。
    static let pinnedTileSpacing: CGFloat = 6
    // アプリとフォルダーで共通に使う最大2行の名前領域の高さです。
    static let pinnedLabelAreaHeight: CGFloat = 32
    // セクション見出し上側の余白です。
    static let sectionTitleTopPadding: CGFloat = 16
    // セクション見出し下側の余白です。
    static let sectionTitleBottomPadding: CGFloat = 12
}

// P6-Aで、各フォルダータイルの中心Yをピン留め欄座標として親ビューへ返すPreferenceKeyです。
// タイルがスクロール・並べ替えで移動しても、開く位置の基準を常に最新のプレビュー位置へ追従させます。
private struct PinnedFolderTileCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

// 画面で使う文言をローカライズキー経由で取得する窓口です。
// UI側が文字列キーを直接繰り返さず、意味のあるプロパティ名で参照できます。
enum L10n {
    // 以下の各定数は、Localizable.stringsに翻訳があれば翻訳を、なければdefaultValueを使います。
    static let appsTitle = text("apps.title", defaultValue: "アプリケーション")
    static let appsSearchPlaceholder = text("apps.search_placeholder", defaultValue: "アプリを検索...")
    static let recentModeApps = text("recent.mode.apps", defaultValue: "アプリ")
    static let recentModeFiles = text("recent.mode.files", defaultValue: "最近使ったファイル")
    static let recentSearchPlaceholder = text("recent.search.placeholder", defaultValue: "最近使ったファイルを検索...")
    static let recentScope = text("recent.scope", defaultValue: "Spotlight · User Home")
    static let recentLoading = text("recent.loading", defaultValue: "読み込み中…")
    static let recentEmpty = text("recent.empty", defaultValue: "最近使ったファイルはありません")
    static let recentUnavailable = text("recent.unavailable", defaultValue: "最近使ったファイルを利用できません")
    static let recentShowInFinder = text("recent.show_in_finder", defaultValue: "Finderで表示")
    static let recentOpenFailed = text("recent.open_failed", defaultValue: "ファイルを開けませんでした")
    // VoiceOverがAや#を単独の文字ではなく、一覧のセクション見出しとして読むための書式です。
    static func appListSection(_ header: String) -> String {
        String(format: text("apps.section.accessibility", defaultValue: "%@ セクション"), header)
    }
    static let pinnedTitle = text("pinned.title", defaultValue: "ピン留め")
    static let pinApp = text("pin.app", defaultValue: "ピン留め")
    static let unpinApp = text("pin.remove", defaultValue: "ピン留めを解除")
    // A1の右クリックメニューで、Finder上の実体アプリを選択表示する操作名です。
    static let revealInFinder = text("finder.reveal_app", defaultValue: "Finderで表示")
    static let settingsGeneral = text("settings.general", defaultValue: "一般")
    static let settingsLayout = text("settings.layout", defaultValue: "レイアウト")
    static let settingsAppearance = text("settings.appearance", defaultValue: "外観")
    static let settingsWindowWidth = text("settings.window_width", defaultValue: "ウィンドウ幅")
    static let settingsWindowHeight = text("settings.window_height", defaultValue: "ウィンドウ高さ")
    static let settingsAppListWidth = text("settings.app_list_width", defaultValue: "アプリ一覧幅")
    static let settingsHidePinnedAreaWhenEmpty = text("settings.hide_pinned_area_when_empty", defaultValue: "ピンが空のときピン留め欄を隠す")
    static let settingsHidePinnedAreaWhenEmptyHelp = text("settings.hide_pinned_area_when_empty.help", defaultValue: "OFFなら空のピン留め欄を表示します。ONならピンが空の間だけアプリ一覧が全幅になります。")
    static let settingsSelectAppListRowOnPointerHover = text("settings.select_app_list_row_on_pointer_hover", defaultValue: "マウスを重ねたアプリを選択する")
    static let settingsSelectAppListRowOnPointerHoverHelp = text("settings.select_app_list_row_on_pointer_hover.help", defaultValue: "OFFではマウスを重ねても行を強調・選択しません。ONではマウスを動かすと行を強調して選択します。矢印キーによる選択は常に使えます。")
    // P6-Aの展開パネルは、画面幅の途中値ではなく利用者が選んだ列数で安定して配置します。
    static let settingsPinnedFolderColumns = text("settings.pinned_folder_columns", defaultValue: "フォルダー展開の列数")
    static let settingsTheme = text("settings.theme", defaultValue: "テーマ")
    static let settingsThemeSystem = text("settings.theme.system", defaultValue: "オート")
    static let settingsThemeLight = text("settings.theme.light", defaultValue: "ライト")
    static let settingsThemeDark = text("settings.theme.dark", defaultValue: "ダーク")
    static let settingsAppListPosition = text("settings.app_list_position", defaultValue: "アプリ一覧の位置")
    static let settingsPositionLeft = text("settings.position.left", defaultValue: "左")
    static let settingsPositionRight = text("settings.position.right", defaultValue: "右")
    static let settingsPanelScreenPosition = text("settings.panel_screen_position", defaultValue: "StartMenuの画面内位置")
    static let settingsPanelPositionLeft = text("settings.panel_position.left", defaultValue: "左")
    static let settingsPanelPositionCenter = text("settings.panel_position.center", defaultValue: "中央")
    static let settingsPanelPositionRight = text("settings.panel_position.right", defaultValue: "右")
    static let settingsAnimationsEnabled = text("settings.animations_enabled", defaultValue: "アニメーションを有効にする")
    static let settingsAnimationsEnabledHelp = text("settings.animations_enabled.help", defaultValue: "OFFまたはmacOSの「視差効果を減らす」が有効な場合、StartMenu4Mac独自の動きを即時処理します。")
    static let settingsOpenFolder = text("settings.open_folder", defaultValue: "設定フォルダを開く")
    static let settingsShortcut = text("settings.shortcut", defaultValue: "ショートカット")
    static let settingsGlobalShortcut = text("settings.global_shortcut", defaultValue: "StartMenuを開閉")
    static let settingsGlobalShortcutChecking = text("settings.global_shortcut.checking", defaultValue: "グローバルショートカットを確認中")
    static func settingsGlobalShortcutActive(_ shortcut: String) -> String {
        String(format: text("settings.global_shortcut.active", defaultValue: "登録済み: %@"), shortcut)
    }
    static let settingsGlobalShortcutUnavailable = text("settings.global_shortcut.unavailable", defaultValue: "未登録 — Dockとメニューバーは引き続き使用できます")
    // 自由入力式レコーダーの操作条件を、設定画面下部の説明文として表示します。
    static let settingsGlobalShortcutHelp = text("settings.global_shortcut.help", defaultValue: "入力欄をクリックし、修飾キーと通常キーを押します。Escでキャンセルできます。変更はすぐに反映されます。")
    // 記録欄がキー入力を待っている間に表示する短い案内です。
    static let settingsShortcutRecording = text("settings.shortcut.recording", defaultValue: "キーの組み合わせを入力…")
    // 修飾キーなしの単独キーを拒否したとき、次に必要な操作を説明します。
    static let settingsShortcutInvalid = text("settings.shortcut.invalid", defaultValue: "修飾キーも一緒に押してください")
    // 複雑なカスタム設定から、初期値へ戻すボタンの文言です。
    static let settingsShortcutReset = text("settings.shortcut.reset", defaultValue: "Option + Spaceに戻す")
    static let settingsResetSection = text("settings.reset.section", defaultValue: "この項目を既定値へ戻す")
    static let settingsResetAll = text("settings.reset.all", defaultValue: "設定をすべて既定値へ戻す")
    static let settingsResetAllTitle = text("settings.reset.all.title", defaultValue: "設定をリセットしますか？")
    static let settingsResetAllMessage = text("settings.reset.all.message", defaultValue: "settings.json内の設定だけを既定値へ戻します。ピン、キャッシュ、ログイン項目、診断情報、ファイルは変更しません。")
    static let settingsResetConfirm = text("settings.reset.confirm", defaultValue: "設定だけをリセット")
    static let settingsResetCancel = text("settings.reset.cancel", defaultValue: "キャンセル")
    static let settingsResetSaveFailed = text("settings.reset.save_failed", defaultValue: "設定を保存できなかったため、リセットを適用しませんでした。")
    nonisolated static let settingsSaveFailed = text("settings.save_failed", defaultValue: "設定を保存できませんでした。変更は適用されていません。")
    static let settingsErrorDismiss = text("settings.error.dismiss", defaultValue: "閉じる")
    static let settingsLoadUnreadablePreserved = text("settings.load_unreadable_preserved", defaultValue: "設定ファイルを読み込めなかったため、元データを%@へ退避しました。内容を確認してから再試行してください。")
    static let settingsLoadUnreadableUnpreserved = text("settings.load_unreadable_unpreserved", defaultValue: "設定ファイルを読み込めず、元データを退避できませんでした。安全のため設定を保存できません。")
    // P5-Bのログイン時起動設定で使う、OS状態ごとのローカライズ済み文言です。
    static let settingsLaunch = text("settings.launch", defaultValue: "起動")
    static let settingsLoginItemEnabled = text("settings.login_item.enabled", defaultValue: "ログイン時にStartMenu4Macを開く")
    static let settingsLoginItemUpdating = text("settings.login_item.updating", defaultValue: "ログイン時起動の設定を更新中…")
    static let settingsLoginItemRequiresApproval = text("settings.login_item.requires_approval", defaultValue: "macOSでログイン時起動の承認が必要です。システム設定の「ログイン項目」を確認してください。")
    static let settingsLoginItemRegistrationFailed = text("settings.login_item.registration_failed", defaultValue: "ログイン時起動を有効にできませんでした。システム設定の「ログイン項目」を確認して、もう一度お試しください。")
    static let settingsLoginItemUnregistrationFailed = text("settings.login_item.unregistration_failed", defaultValue: "ログイン時起動を無効にできませんでした。システム設定の「ログイン項目」を確認して、もう一度お試しください。")
    static let settingsLoginItemOpenSystemSettings = text("settings.login_item.open_system_settings", defaultValue: "システム設定のログイン項目を開く")
    static let loginApprovalAlertTitle = text("login_approval.alert.title", defaultValue: "ログイン時起動の許可が必要です")
    static let loginApprovalAlertMessage = text("login_approval.alert.message", defaultValue: "StartMenu4Macのログイン時起動はmacOSにより保留されています。許可しない限り、ログイン後に自動起動しません。")
    static let loginApprovalAlertLater = text("login_approval.alert.later", defaultValue: "あとで")
    static let statusMenuLoginApproval = text("status_menu.login_approval", defaultValue: "ログイン時起動の許可が必要")
    static let diagnosticTitle = text("diagnostic.title", defaultValue: "セキュリティ通知の診断")
    static let diagnosticNone = text("diagnostic.none", defaultValue: "直近30分のStartMenu経由起動はありません")
    static let diagnosticBundleIdentifier = text("diagnostic.bundle_identifier", defaultValue: "Bundle ID")
    static let diagnosticLaunchedAt = text("diagnostic.launched_at", defaultValue: "起動時刻")
    static let diagnosticRoute = text("diagnostic.route", defaultValue: "起動経路")
    static let diagnosticHelp = text("diagnostic.help", defaultValue: "通知が再発した時刻とこの1件を照合してください。対象アプリのフルパスや利用履歴は保存しません。")
    static let settingsVisual = text("settings.visual", defaultValue: "表示")
    static let settingsTransparentWindow = text("settings.transparent_window", defaultValue: "半透明設定（レガシー）")
    static let settingsBlurEffect = text("settings.blur_effect", defaultValue: "ぼかし効果（OS問わず有効）")
    static let settingsLiquidGlass = text("settings.liquid_glass", defaultValue: "Liquid Glass（macOS 26 以上で反映）")
    static let settingsAppVisibility = text("settings.app_visibility", defaultValue: "アプリの非表示")
    static let settingsBlacklistEnabled = text("settings.blacklist.enabled", defaultValue: "名前による非表示を有効にする")
    // A5は「確実に非対応」だけを隠す任意機能です。判定不能なアプリが表示され続ける点も説明文で明示します。
    static let settingsHideIncompatibleApps = text("settings.hide_incompatible_apps", defaultValue: "確実に非対応のアプリを隠す")
    static let settingsHideIncompatibleAppsHelp = text("settings.hide_incompatible_apps.help", defaultValue: "OSやアーキテクチャが確実に非対応と判定できたアプリだけを隠します。判定できないアプリは表示されます。")
    static let settingsShowCoreServicesApps = text("settings.show_core_services_apps", defaultValue: "/System/Library/CoreServices内のアプリを表示する")
    static let settingsShowFinder = text("settings.show_finder", defaultValue: "Finderを表示する")
    static let settingsGroupAppsByCategory = text("settings.group_apps_by_category", defaultValue: "ジャンルごとに表示")
    static let settingsGroupAppsByCategoryHelp = text("settings.group_apps_by_category.help", defaultValue: "通常のアプリ一覧をジャンル別に分けます。検索中は従来どおり平坦に表示します。")
    static let appsCategoryDevelopment = text("apps.category.development", defaultValue: "開発")
    static let appsCategoryEducation = text("apps.category.education", defaultValue: "教育")
    static let appsCategoryEntertainment = text("apps.category.entertainment", defaultValue: "エンターテインメント")
    static let appsCategoryFinance = text("apps.category.finance", defaultValue: "ファイナンス")
    static let appsCategoryGames = text("apps.category.games", defaultValue: "ゲーム")
    static let appsCategoryGraphicsDesign = text("apps.category.graphics_design", defaultValue: "グラフィック／デザイン")
    static let appsCategoryMedical = text("apps.category.medical", defaultValue: "医療")
    static let appsCategoryMusic = text("apps.category.music", defaultValue: "音楽")
    static let appsCategoryPhotography = text("apps.category.photography", defaultValue: "写真")
    static let appsCategoryProductivity = text("apps.category.productivity", defaultValue: "仕事効率化")
    static let appsCategorySocialNetworking = text("apps.category.social_networking", defaultValue: "ソーシャルネットワーキング")
    static let appsCategoryUtilities = text("apps.category.utilities", defaultValue: "ユーティリティ")
    static let appsCategoryVideo = text("apps.category.video", defaultValue: "ビデオ")
    static let appsCategoryOther = text("apps.category.other", defaultValue: "その他")
    // P4-Aでは、削除・退避済みピンを自動削除せず、タイル上の恒常的な状態文とVoiceOver説明で知らせます。
    static let pinnedAppNotFound = text("pinned.app_not_found", defaultValue: "アプリが見つかりません")
    static let pinnedAppNotFoundAccessibility = text("pinned.app_not_found.accessibility", defaultValue: "アプリが見つかりません。右クリックメニューからピン留めを解除できます。")
    static let pinnedChooseRecovery = text("pinned.choose_recovery", defaultValue: "復旧先を選択")
    static let pinnedSaveFailed = text("pinned.save_failed", defaultValue: "ピン留めを保存できませんでした。")
    static let pinnedLoadUnreadablePreserved = text("pinned.load_unreadable_preserved", defaultValue: "ピン設定を読み込めなかったため、元データを%@へ退避しました。内容を確認してください。")
    static let pinnedLoadUnreadableUnpreserved = text("pinned.load_unreadable_unpreserved", defaultValue: "ピン設定を読み込めず、元データを退避できませんでした。安全のためピンを保存できません。")
    // P6-Aのフォルダー操作はドラッグを使わず、右クリックから明示して誤操作を防ぎます。
    static let pinnedNewFolder = text("pinned.folder.new", defaultValue: "新しいフォルダーへ移動")
    static let pinnedMoveToFolder = text("pinned.folder.move_to", defaultValue: "フォルダーへ移動")
    static let pinnedExtractFromFolder = text("pinned.folder.extract", defaultValue: "フォルダーから取り出す")
    static let pinnedDissolveFolder = text("pinned.folder.dissolve", defaultValue: "フォルダーを解除")
    static let pinnedRenameFolder = text("pinned.folder.rename", defaultValue: "名前を変更")
    static let pinnedNewFolderName = text("pinned.folder.default_name", defaultValue: "新しいフォルダー")
    static let pinnedFolderClose = text("pinned.folder.close", defaultValue: "閉じる")
    static let pinnedFolderPage = text("pinned.folder.page", defaultValue: "%d / %d ページ")
    static let pinnedDragFolderCandidate = text("pinned.drag.folder_candidate", defaultValue: "フォルダーとしてまとめる")
    static let pinnedDragAddCandidate = text("pinned.drag.add_candidate", defaultValue: "フォルダーへ追加")
    static let settingsBlacklistNewRule = text("settings.blacklist.new_rule", defaultValue: "新しい文字列…")
    static let settingsBlacklistAdd = text("settings.blacklist.add", defaultValue: "追加")
    static let settingsBlacklistRemove = text("settings.blacklist.remove", defaultValue: "削除")
    static let settingsBlacklistReset = text("settings.blacklist.reset", defaultValue: "現在の条件を既定値へ戻す")
    static let statusItemAccessibility = text("status_item.accessibility", defaultValue: "StartMenu4Macメニュー")
    static let statusMenuOpen = text("status_menu.open", defaultValue: "StartMenuを開く")
    static let statusMenuClose = text("status_menu.close", defaultValue: "StartMenuを閉じる")
    static let statusMenuClosing = text("status_menu.closing", defaultValue: "StartMenuを閉じています")
    static let statusMenuSettings = text("status_menu.settings", defaultValue: "設定…")
    static let statusMenuQuit = text("status_menu.quit", defaultValue: "StartMenu4Macを終了")

    // 指定したキーの翻訳文をアプリ本体のローカライズ資源から取得します。
    private static func text(_ key: String, defaultValue: String) -> String {
        // NSLocalizedStringは現在のシステム言語に合うstringsファイルを自動選択します。
        NSLocalizedString(key, tableName: nil, bundle: .main, value: defaultValue, comment: "")
    }
}

// pinned.json全体の構造です。形式バージョンと、並び順を保った項目配列を持ちます。
struct PinnedConfig: Codable, Equatable {
    static let currentVersion = 3

    // 現在の保存形式バージョンです。異なる値は変換せず、読込エラーとして原本を保全します。
    var version: Int = Self.currentVersion
    // ピン留めされた最上位項目を、画面に表示する順番で保持します。フォルダーの子は各項目のchildrenへだけ保存します。
    var items: [PinnedEntry] = []
}

struct FolderOverlayState: Equatable {
    private(set) var folderID: UUID?
    private(set) var originY: CGFloat?

    mutating func open(folderID: UUID, originY: CGFloat?) {
        self.folderID = folderID
        self.originY = originY
    }

    mutating func captureOriginIfMissing(_ value: CGFloat?) {
        guard originY == nil, let value else { return }
        originY = value
    }

    mutating func close() {
        folderID = nil
        originY = nil
    }
}

enum PinnedFolderDropHitRegion {
    static func contains(_ point: CGPoint) -> Bool {
        point.x > 24 && point.x < 68 && point.y > 24 && point.y < 76
    }
}

// 1件がアプリかフォルダーかをJSONへ明示するP6-A用の種別です。
enum PinnedEntryKind: String, Codable, Equatable {
    case application
    case folder
}

// ピン留めの最上位項目と、フォルダー内アプリの両方に使う永続化情報です。
// applicationはpath等を、folderはfolderNameとアプリだけのchildrenを使用します。
struct PinnedEntry: Codable, Equatable, Identifiable {
    // P4-Bではパスが移動しても同じピンを追跡するため、永続UUIDを使います。
    var id: UUID = UUID()
    var kind: PinnedEntryKind = .application
    // アプリ本体の絶対パスです。起動と一意識別の中心になります。
    var path: String
    // ピン追加時に保存されるBundle IDです。現在の読み込み・起動処理ではまだ参照されていません。
    var bundleIdentifier: String?
    // 任意の表示名です。nilなら実際のアプリ名・ファイル名へフォールバックします。
    var displayName: String?
    // folderだけの表示名です。アプリのdisplayNameとは混用せず、名称変更の影響範囲を明確にします。
    var folderName: String?
    // folderだけの子配列です。P6-Aではapplicationだけを許可し、JSONが壊れていても入れ子を画面へ出しません。
    var children: [PinnedEntry]?

    // アプリ項目を作る通常経路です。JSON読み込み時に欠落IDやkindを補う互換処理には使いません。
    init(id: UUID = UUID(), path: String, bundleIdentifier: String?, displayName: String?) {
        self.id = id; self.kind = .application; self.path = path; self.bundleIdentifier = bundleIdentifier; self.displayName = displayName
        self.folderName = nil; self.children = nil
    }
    // 新しいフォルダーは空のまま保存せず、作成時に必ず最初のアプリを渡します。
    init(folderID: UUID = UUID(), name: String, children: [PinnedEntry]) {
        self.id = folderID; self.kind = .folder; self.path = ""; self.bundleIdentifier = nil; self.displayName = nil
        self.folderName = name; self.children = children.filter { $0.kind == .application }
    }
    // UIと操作コードがpathの空文字だけで種別を推測しないための共通窓口です。
    var isFolder: Bool { kind == .folder }
}

private enum PinnedDragOrigin: Equatable {
    case topLevel
    case folder(folderID: UUID)

    var folderID: UUID? {
        if case let .folder(id) = self { return id }
        return nil
    }
}

private struct PinnedDragContext: Equatable {
    let identity: PinnedDragSessionIdentity
    let origin: PinnedDragOrigin

    var entryID: UUID { identity.entryID }

    init(entryID: UUID, origin: PinnedDragOrigin) {
        identity = PinnedDragSessionIdentity(sessionID: UUID(), entryID: entryID)
        self.origin = origin
    }
}

private struct PinnedDragSnapshot: Equatable {
    let identity: PinnedDragSessionIdentity
    let config: PinnedConfig
}

struct PinnedDragSessionIdentity: Equatable {
    let sessionID: UUID
    let entryID: UUID
}

enum PinnedDragCallbackDisposition: Equatable {
    case staleSession
    case rejectedProvider
    case accepted
}

enum PinnedDragCallbackGate {
    static func evaluate(
        providerIdentifier: String?,
        expected: PinnedDragSessionIdentity?,
        active: PinnedDragSessionIdentity?
    ) -> PinnedDragCallbackDisposition {
        guard let expected, active == expected else { return .staleSession }
        guard let providerIdentifier,
              let providerID = UUID(uuidString: providerIdentifier),
              providerID == expected.entryID else { return .rejectedProvider }
        return .accepted
    }
}

enum PinnedConfigTransform {
    struct FolderCreationResult {
        let config: PinnedConfig
        let folder: PinnedEntry
    }

    struct AppUnpinResult {
        let config: PinnedConfig
        let removedFolderID: UUID?
    }

    struct ReconciliationResult {
        let config: PinnedConfig
        let changed: Bool
        let multipleCandidates: [UUID: [AppItem]]
    }

    static func createFolder(from draggedID: UUID, targetID: UUID, folderID: UUID, named name: String, in config: PinnedConfig) -> PinnedConfig? {
        guard draggedID != targetID,
              folderID != draggedID, folderID != targetID,
              Set(config.items.map(\.id)).count == config.items.count,
              let draggedIndex = config.items.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = config.items.firstIndex(where: { $0.id == targetID }),
              config.items[draggedIndex].kind == .application,
              config.items[targetIndex].kind == .application else { return nil }
        let dragged = config.items[draggedIndex]
        let target = config.items[targetIndex]
        let allEntries = config.items.flatMap { [$0] + ($0.children ?? []) }
        let applications = allEntries.filter { $0.kind == .application }
        guard !dragged.path.isEmpty, !target.path.isEmpty,
              dragged.path != target.path,
              Set(allEntries.map(\.id)).count == allEntries.count,
              Set(applications.map(\.path)).count == applications.count,
              !allEntries.contains(where: { $0.id == folderID }) else { return nil }
        var result = config
        result.items.removeAll { $0.id == draggedID || $0.id == targetID }
        result.items.insert(PinnedEntry(folderID: folderID, name: name, children: [target, dragged]), at: min(draggedIndex, targetIndex))
        return result
    }

    // 新規ピンは候補配列だけを変更し、既存path・UUIDと重複させません。
    static func pin(_ entry: PinnedEntry, in config: PinnedConfig) -> PinnedConfig? {
        let existingEntries = config.items.flatMap { [$0] + ($0.children ?? []) }
        guard entry.kind == .application,
              !entry.path.isEmpty,
              !existingEntries.contains(where: { $0.path == entry.path || $0.id == entry.id }) else { return nil }
        var result = config
        result.items.append(entry)
        return result
    }

    // UUIDが一致する最上位タイルだけを1件除去します。
    static func unpin(_ id: UUID, from config: PinnedConfig) -> PinnedConfig? {
        guard let index = config.items.firstIndex(where: { $0.id == id }) else { return nil }
        var result = config
        result.items.remove(at: index)
        return result
    }

    // パス一致の最上位アプリまたはフォルダーchildを1件だけ除去します。
    // 最後のchildを除去した場合は空フォルダーも候補から外します。
    static func unpinApp(at path: String, from config: PinnedConfig) -> AppUnpinResult? {
        if let index = config.items.firstIndex(where: { $0.kind == .application && $0.path == path }) {
            var result = config
            result.items.remove(at: index)
            return AppUnpinResult(config: result, removedFolderID: nil)
        }
        for folderIndex in config.items.indices where config.items[folderIndex].isFolder {
            guard let childIndex = (config.items[folderIndex].children ?? []).firstIndex(where: { $0.path == path }) else { continue }
            var result = config
            let folderID = result.items[folderIndex].id
            result.items[folderIndex].children?.remove(at: childIndex)
            let removesFolder = result.items[folderIndex].children?.isEmpty == true
            if removesFolder { result.items.remove(at: folderIndex) }
            return AppUnpinResult(config: result, removedFolderID: removesFolder ? folderID : nil)
        }
        return nil
    }

    // 指定アプリを同じ最上位位置で包み、子のUUIDをそのまま保持します。
    static func createFolder(containingTopLevelApp id: UUID, folderID: UUID, named name: String, in config: PinnedConfig) -> FolderCreationResult? {
        guard !config.items.contains(where: { $0.id == folderID }),
              let index = config.items.firstIndex(where: { $0.id == id && $0.kind == .application }) else { return nil }
        var result = config
        let child = result.items[index]
        let folder = PinnedEntry(folderID: folderID, name: name, children: [child])
        result.items[index] = folder
        return FolderCreationResult(config: result, folder: folder)
    }

    // 最上位アプリを指定フォルダーの末尾へ移し、同じUUIDの二重配置を防ぎます。
    static func moveTopLevelApp(_ id: UUID, toFolder folderID: UUID, in config: PinnedConfig) -> PinnedConfig? {
        guard let sourceIndex = config.items.firstIndex(where: { $0.id == id && $0.kind == .application }),
              let destinationIndex = config.items.firstIndex(where: { $0.id == folderID && $0.isFolder }),
              id != folderID else { return nil }
        let source = config.items[sourceIndex]
        guard !(config.items[destinationIndex].children ?? []).contains(where: { $0.path == source.path || $0.id == source.id }) else { return nil }
        var result = config
        result.items.remove(at: sourceIndex)
        let adjustedDestinationIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        result.items[adjustedDestinationIndex].children = (result.items[adjustedDestinationIndex].children ?? []) + [source]
        return result
    }

    // 保存形式上の順序を保ち、childをフォルダー直後または指定位置へ取り出します。
    static func extractChild(_ id: UUID, fromFolder folderID: UUID, immediatelyAfterFolder: Bool, config: PinnedConfig) -> PinnedConfig? {
        guard let folderIndex = config.items.firstIndex(where: { $0.id == folderID && $0.isFolder }) else { return nil }
        let targetID = immediatelyAfterFolder ? config.items.dropFirst(folderIndex + 1).first?.id : nil
        return extractChild(id, fromFolder: folderID, beforeTopLevelID: targetID, config: config)
    }

    // フォルダーの子を、元フォルダーが占めていた順序位置へ保ったまま展開します。
    static func dissolveFolder(_ id: UUID, in config: PinnedConfig) -> PinnedConfig? {
        guard let index = config.items.firstIndex(where: { $0.id == id && $0.isFolder }) else { return nil }
        var result = config
        let children = result.items[index].children ?? []
        result.items.remove(at: index)
        result.items.insert(contentsOf: children, at: index)
        return result
    }

    // 指定フォルダーの名称だけを変更し、IDと子配列は維持します。
    static func renameFolder(_ id: UUID, to name: String, in config: PinnedConfig) -> PinnedConfig? {
        guard let index = config.items.firstIndex(where: { $0.id == id && $0.isFolder }) else { return nil }
        var result = config
        result.items[index].folderName = name
        return result
    }

    // 復旧後もentry ID・順序・フォルダー構造を保ち、対象アプリのpathだけを置換します。
    static func replacingPath(for id: UUID, with path: String, in config: PinnedConfig) -> PinnedConfig? {
        var result = config
        if let topLevelIndex = result.items.firstIndex(where: { $0.id == id && $0.kind == .application }) {
            result.items[topLevelIndex].path = path
            return result
        }
        for folderIndex in result.items.indices where result.items[folderIndex].isFolder {
            guard let childIndex = (result.items[folderIndex].children ?? []).firstIndex(where: { $0.id == id && $0.kind == .application }) else { continue }
            result.items[folderIndex].children?[childIndex].path = path
            return result
        }
        return nil
    }

    // 最新走査結果に基づくmissingピン復旧をcandidate上だけで行い、重複候補は確定しません。
    static func reconcileMissingPins(in config: PinnedConfig, missingEntryIDs: Set<UUID>, candidatesByBundleID: [String: [AppItem]]) -> ReconciliationResult {
        var updated = config
        var usedPaths = PinnedRecoveryTransform.applicationPaths(in: updated)
        var changed = false
        var multiple: [UUID: [AppItem]] = [:]
        for itemIndex in updated.items.indices {
            if updated.items[itemIndex].kind == .application {
                changed = reconcileMissingEntry(&updated.items[itemIndex], missingEntryIDs: missingEntryIDs, candidatesByBundleID: candidatesByBundleID, usedPaths: &usedPaths, multiple: &multiple) || changed
            } else if var children = updated.items[itemIndex].children {
                for childIndex in children.indices {
                    changed = reconcileMissingEntry(&children[childIndex], missingEntryIDs: missingEntryIDs, candidatesByBundleID: candidatesByBundleID, usedPaths: &usedPaths, multiple: &multiple) || changed
                }
                updated.items[itemIndex].children = children
            }
        }
        return ReconciliationResult(config: updated, changed: changed, multipleCandidates: multiple)
    }

    private static func reconcileMissingEntry(
        _ entry: inout PinnedEntry,
        missingEntryIDs: Set<UUID>,
        candidatesByBundleID: [String: [AppItem]],
        usedPaths: inout Set<String>,
        multiple: inout [UUID: [AppItem]]
    ) -> Bool {
        guard entry.kind == .application,
              missingEntryIDs.contains(entry.id),
              let bundleID = entry.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !bundleID.isEmpty,
              let matches = candidatesByBundleID[bundleID] else { return false }
        let unique = PinnedRecoveryTransform.unusedCandidates(matches, usedPaths: usedPaths)
        if unique.count > 1 { multiple[entry.id] = unique; return false }
        guard let candidate = unique.first else { return false }
        entry.path = candidate.path
        usedPaths.insert(candidate.path)
        return true
    }

    // 最上位の並べ替えを値変換へまとめ、dropEnteredの表示更新と保存処理を分離します。
    static func moveTopLevel(_ id: UUID, to targetID: UUID, config: PinnedConfig) -> PinnedConfig? {
        var result = config
        guard id != targetID,
              let from = result.items.firstIndex(where: { $0.id == id }),
              let target = result.items.firstIndex(where: { $0.id == targetID }) else { return nil }
        let entry = result.items.remove(at: from)
        result.items.insert(entry, at: min(target, result.items.count))
        return result
    }

    static func moveChild(_ id: UUID, inFolder folderID: UUID, to targetID: UUID, config: PinnedConfig) -> PinnedConfig? {
        var result = config
        guard let folderIndex = result.items.firstIndex(where: { $0.id == folderID && $0.isFolder }),
              var children = result.items[folderIndex].children,
              let from = children.firstIndex(where: { $0.id == id }),
              let target = children.firstIndex(where: { $0.id == targetID }),
              from != target else { return nil }
        let entry = children.remove(at: from)
        // targetは「移動前に対象が占めていた位置」です。元要素を除去した後も、
        // その添字へ挿入すれば、A→BとB→Aの隣接移動が同じ規則で成立します。
        let insertion = min(target, children.count)
        children.insert(entry, at: insertion)
        result.items[folderIndex].children = children
        return result
    }

    static func extractChild(_ id: UUID, fromFolder folderID: UUID, beforeTopLevelID targetID: UUID?, config: PinnedConfig) -> PinnedConfig? {
        var result = config
        guard let folderIndex = result.items.firstIndex(where: { $0.id == folderID && $0.isFolder }),
              var children = result.items[folderIndex].children,
              let childIndex = children.firstIndex(where: { $0.id == id }) else { return nil }
        let child = children.remove(at: childIndex)
        result.items[folderIndex].children = children
        if children.isEmpty { result.items.remove(at: folderIndex) }
        let insertion: Int
        if let targetID, let targetIndex = result.items.firstIndex(where: { $0.id == targetID }) {
            insertion = targetIndex
        } else {
            insertion = result.items.count
        }
        result.items.insert(child, at: insertion)
        return result
    }
}

// missing復旧で保存対象を探す・置き換える処理を、最上位とフォルダーchildで共有します。
// この変換はcandidateだけを返し、保存成功前に画面のPinnedConfigを変更しません。
private enum PinnedRecoveryTransform {
    static func applicationPaths(in config: PinnedConfig, excluding id: UUID? = nil) -> Set<String> {
        let entries = config.items.flatMap { item in
            item.isFolder ? (item.children ?? []) : [item]
        }
        return Set(entries
            .filter { $0.kind == .application && $0.id != id && !$0.path.isEmpty }
            .map(\.path))
    }

    static func unusedCandidates(_ candidates: [AppItem], usedPaths: Set<String>) -> [AppItem] {
        var seenPaths = Set<String>()
        return candidates.filter { candidate in
            !candidate.path.isEmpty
                && !usedPaths.contains(candidate.path)
                && seenPaths.insert(candidate.path).inserted
        }
    }

#if DEBUG
    // 同一候補の二重割り当て防止と、フォルダーchildのpathだけを置換する規則を確認します。
    static func runSelfCheck() {
        let candidate = AppItem(
            name: "Candidate",
            originalName: "Candidate",
            path: "/Applications/Candidate.app",
            icon: NSImage(size: NSSize(width: 1, height: 1)),
            foldedName: "Candidate",
            foldedOriginalName: "Candidate",
            compatibilityStatus: .compatible,
            bundleIdentifier: "com.example.candidate",
            discoveryFolderPath: nil,
            categoryIdentifier: nil
        )
        let missingTop = PinnedEntry(path: "/old/Top.app", bundleIdentifier: candidate.bundleIdentifier, displayName: "Top")
        let missingChild = PinnedEntry(path: "/old/Child.app", bundleIdentifier: candidate.bundleIdentifier, displayName: "Child")
        let folder = PinnedEntry(folderID: UUID(), name: "Folder", children: [missingChild])
        let config = PinnedConfig(items: [missingTop, folder])
        var used = applicationPaths(in: config)
        assert(unusedCandidates([candidate], usedPaths: used).count == 1)
        used.insert(candidate.path)
        assert(unusedCandidates([candidate], usedPaths: used).isEmpty)
        let recovered = PinnedConfigTransform.replacingPath(for: missingChild.id, with: candidate.path, in: config)!
        assert(recovered.items[1].id == folder.id)
        assert(recovered.items[1].folderName == folder.folderName)
        assert(recovered.items[1].children?.map(\.id) == folder.children?.map(\.id))
        assert(recovered.items[1].children?.first?.path == candidate.path)
    }
#endif
}

#if DEBUG
private extension PinnedConfigTransform {
    // ピンの保存候補変換がUUID・順序・入力configを壊さないことを既存Debug自己確認で検証します。
    static func runSelfCheck() {
        let first = PinnedEntry(path: "/Applications/First.app", bundleIdentifier: "com.example.first", displayName: "First")
        let second = PinnedEntry(path: "/Applications/Second.app", bundleIdentifier: "com.example.second", displayName: "Second")
        let child = PinnedEntry(path: "/Applications/Child.app", bundleIdentifier: "com.example.child", displayName: "Child")
        let folder = PinnedEntry(folderID: UUID(), name: "Folder", children: [child])
        let config = PinnedConfig(items: [first, second, folder])
        let originalConfig = config
        func allIDs(_ value: PinnedConfig) -> [UUID] {
            value.items.flatMap { [$0.id] + ($0.children ?? []).map(\.id) }
        }

        let movedTopLevel = moveTopLevel(first.id, to: second.id, config: config)!
        assert(movedTopLevel.items.count == config.items.count)
        assert(Set(movedTopLevel.items.map(\.id)) == Set(config.items.map(\.id)))

        let childTwo = PinnedEntry(path: "/Applications/ChildTwo.app", bundleIdentifier: "com.example.child.two", displayName: "Child Two")
        var folderConfig = config
        folderConfig.items[2].children = [child, childTwo]
        let movedChild = moveChild(child.id, inFolder: folder.id, to: childTwo.id, config: folderConfig)!
        assert(movedChild.items[2].children?.count == 2)
        assert(Set(movedChild.items[2].children!.map(\.id)) == Set([child.id, childTwo.id]))

        let extracted = extractChild(child.id, fromFolder: folder.id, beforeTopLevelID: second.id, config: folderConfig)!
        let flattenedExtracted = extracted.items.flatMap { entry -> [PinnedEntry] in
            [entry] + (entry.children ?? [])
        }
        let extractedMatches = flattenedExtracted.filter { $0.id == child.id }
        assert(extractedMatches.count == 1)
        assert(extracted.items.contains(where: { $0.id == child.id }))

        let pinned = PinnedEntry(path: "/Applications/Added.app", bundleIdentifier: "com.example.added", displayName: "Added")
        let pinnedConfig = pin(pinned, in: config)!
        assert(pinnedConfig.items.count == config.items.count + 1)
        assert(pinnedConfig.items.last?.id == pinned.id)

        let unpinned = unpin(second.id, from: config)!
        assert(!unpinned.items.contains(where: { $0.id == second.id }))
        assert(unpinned.items.map(\.id) == [first.id, folder.id])
        assert(unpinned.items.flatMap { $0.children ?? [] }.map(\.id) == [child.id])

        let created = createFolder(containingTopLevelApp: first.id, folderID: UUID(), named: "Created", in: config)!
        assert(created.folder.children?.map(\.id) == [first.id])
        assert(created.config.items[0].id == created.folder.id)

        let movedIntoFolder = moveTopLevelApp(second.id, toFolder: folder.id, in: config)!
        assert(!movedIntoFolder.items.contains(where: { $0.id == second.id }))
        assert(movedIntoFolder.items.first(where: { $0.id == folder.id })?.children?.map(\.id) == [child.id, second.id])
        assert(Set(allIDs(movedIntoFolder)).count == allIDs(movedIntoFolder).count)

        let extractedChild = extractChild(child.id, fromFolder: folder.id, immediatelyAfterFolder: true, config: config)!
        assert(extractedChild.items.first(where: { $0.id == child.id })?.id == child.id)
        assert(Set(allIDs(extractedChild)).count == allIDs(extractedChild).count)

        let orderedFolder = PinnedEntry(folderID: UUID(), name: "Ordered", children: [child, childTwo])
        var orderedConfig = config
        orderedConfig.items[2] = orderedFolder
        let dissolved = dissolveFolder(orderedFolder.id, in: orderedConfig)!
        assert(dissolved.items.map(\.id) == [first.id, second.id, child.id, childTwo.id])

        let renamed = renameFolder(folder.id, to: "Renamed", in: config)!
        let renamedFolder = renamed.items.first(where: { $0.id == folder.id })!
        assert(renamedFolder.id == folder.id)
        assert(renamedFolder.children?.map(\.id) == [child.id])
        assert(renamedFolder.folderName == "Renamed")

        assert(config == originalConfig)
    }
}
#endif

// P4-Aで永続化せずに扱う、現在の保存パスの利用可否です。
// `missing`はファイルの存在だけで決め、署名・隔離・起動後エラーなどは静的に断定しません。
enum PinnedAppAvailability: Equatable {
    case available
    case missing
}

func makePinnedDragProvider(for id: UUID, in config: PinnedConfig) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerObject(id.uuidString as NSString, visibility: .ownProcess)

    let entry = config.items
        .flatMap { [$0] + ($0.children ?? []) }
        .first(where: { $0.id == id })
    guard let entry, entry.kind == .application, canOpenApplicationPackage(at: entry.path) else {
        return provider
    }

    let appURL = URL(fileURLWithPath: entry.path)
    provider.registerFileRepresentation(
        for: .applicationBundle,
        visibility: .all,
        openInPlace: true
    ) { completion in
        guard canOpenApplicationPackage(at: appURL.path) else {
            let error = NSError(
                domain: "StartMenu4Mac.PinnedDrag",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The pinned application is no longer available."]
            )
            completion(nil, false, error)
            return nil
        }
        completion(appURL, true, nil)
        return nil
    }
    return provider
}

// P4-Aの共通パス判定です。ピンの表示、Finder、起動直前が必ず同じ安全規則を使用します。
// 有効な.appディレクトリなら一覧走査で未検出でもavailableとし、A2/A5や走査中の状態を壊れたピンと誤認しません。
nonisolated func canOpenApplicationPackage(at path: String) -> Bool {
    // 空パスと.app以外を最初に拒否し、URL生成やNSWorkspace起動の対象にしません。
    guard !path.isEmpty,
          URL(fileURLWithPath: path).pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
        return false
    }
    // 存在するディレクトリだけを有効とします。パッケージ内部の署名や権限まではP4-Aで推測しません。
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
}

// 保存済みPinnedEntryと、現在検出できているAppItemを組み合わせた画面表示用の型です。
struct PinnedApp: Identifiable {
    // pinned.jsonから読み込んだ永続データです。
    let entry: PinnedEntry
    // 現在のアプリ一覧に同じパスがあればその情報、見つからなければnilです。
    let app: AppItem?
    // 現時点のパス判定です。pinned.jsonへ保存しないため、同じ場所へ戻したアプリは次の表示評価で自然に復帰します。
    let availability: PinnedAppAvailability

    // UUIDは復旧後も変わらず、通常ピンの位置移動アニメーションも維持します。
    var id: UUID { entry.id }

    // 表示名を「手動名→検出済み名→パス由来名」の優先順位で決定します。
    var name: String {
        // displayNameが設定済みかつ空文字でなければ最優先で使います。
        if let displayName = entry.displayName, !displayName.isEmpty {
            return displayName
        }

        // インストール済み一覧に対応するAppItemがあれば、そのローカライズ名を使います。
        if let app {
            return app.name
        }

        // 見つからないアプリでも名前を表示できるよう、パス末尾から.appを除いて使います。
        return URL(fileURLWithPath: entry.path)
            .deletingPathExtension()
            .lastPathComponent
    }

    // パスに対応するアプリアイコンをmacOSのワークスペース機能から取得します。
    var icon: NSImage {
        PinnedIconCache.image(for: entry.path)
    }

    // UIの操作可否と警告表示が同じ条件を読む短い窓口です。
    var isAvailable: Bool { availability == .available }
}

// SwiftUIの再描画やdropEnteredによる配列更新で、同じピンのNSImageを取り直さないためのプロセス内キャッシュです。
// pinned.jsonへは保存せず、既存のpath・UUID・保存形式には影響させません。
private enum PinnedIconCache {
    private static let storage = NSCache<NSString, NSImage>()

    static func image(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = storage.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        storage.setObject(image, forKey: key)
        return image
    }
}

// pinned.jsonの読み書きを担当します。
enum PinnedStore {
    // P8-Aで空設定と保存ファイル不存在を区別するための読み込み状態です。
    enum LoadState { case missing, loaded, unreadable }
    struct LoadResult {
        let config: PinnedConfig
        let state: LoadState
        let issue: PersistenceLoadIssue?
    }

    private static func unreadableLoadResult(data: Data, url: URL) -> LoadResult {
        LoadResult(
            config: PinnedConfig(),
            state: .unreadable,
            issue: PersistenceRecovery.unreadableIssue(for: data, originalURL: url)
        )
    }

    // 保存済みピン情報と保存状態を分けて返します。壊れたJSONは既定ピン投入対象にしません。
    static func loadResult(applicationSupportDirectory: URL? = nil) -> LoadResult {
        guard let url = configURL(applicationSupportDirectory: applicationSupportDirectory) else {
            NSLog("Could not resolve pinned file URL")
            return LoadResult(config: PinnedConfig(), state: .unreadable, issue: .unreadableUnpreserved)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadResult(config: PinnedConfig(), state: .missing, issue: nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            NSLog("Failed to read pinned settings: %@", error.localizedDescription)
            return LoadResult(config: PinnedConfig(), state: .unreadable, issue: .unreadableUnpreserved)
        }

        return load(data: data, originalURL: url)
    }

    static func load(data: Data, originalURL: URL) -> LoadResult {
        guard PersistenceRecovery.schemaVersion(in: data) == .value(PinnedConfig.currentVersion),
              let config = try? JSONDecoder().decode(PinnedConfig.self, from: data),
              config.version == PinnedConfig.currentVersion else {
            return unreadableLoadResult(data: data, url: originalURL)
        }
        return LoadResult(config: config, state: .loaded, issue: nil)
    }

#if DEBUG
    static func runLoadSelfCheck() {
        assert(PinnedConfig().version == PinnedConfig.currentVersion)
        assert(PersistenceRecovery.schemaVersion(in: try! JSONEncoder().encode(PinnedConfig())) == .value(PinnedConfig.currentVersion))
    }
#endif

    // 現在のピン情報を、人が読めるJSONとして保存します。
    static func save(_ config: PinnedConfig, applicationSupportDirectory: URL? = nil) -> Bool {
        guard let url = configURL(applicationSupportDirectory: applicationSupportDirectory) else { return false }

        // フォルダ作成や書き込みで発生し得るエラーを処理します。
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // JSONへ変換するエンコーダーを作ります。
            let encoder = JSONEncoder()
            // 改行・インデントとキー順を整え、設定ファイルを読みやすくします。
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // PinnedConfigをJSONバイト列へ変換します。
            let data = try encoder.encode(config)
            // 一時ファイル経由の安全な置き換えで保存します。
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            NSLog("Failed to save pinned apps: \(error.localizedDescription)")
            return false
        }
    }

    // pinned.jsonの保存先URLを返します。
    private static func configURL(applicationSupportDirectory: URL?) -> URL? {
        let appSupportURL: URL
        if let applicationSupportDirectory {
            appSupportURL = applicationSupportDirectory
        } else {
            guard let defaultDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                return nil
            }
            appSupportURL = defaultDirectory
        }

        // アプリ固有フォルダ名にはBundle IDを優先使用します。
        let folderName = Bundle.main.bundleIdentifier ?? "StartMenu4Mac"
        return appSupportURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("pinned.json")
    }
}

// アプリの情報をまとめるための設計図
// 実行中の画面で使うアプリ1件分の情報です。アイコンと検索用文字列も保持します。
struct AppItem: Identifiable {
    // この実行中だけ有効な一意IDです。SwiftUIのリスト更新識別に使います。
    let id = UUID()
    // 現在の言語で表示するアプリ名です。
    let name: String
    // ファイル名由来の元のアプリ名です。
    let originalName: String
    // .appパッケージへの絶対パスです。
    let path: String
    // 一覧やピン留めに表示するmacOSのアプリアイコンです。
    let icon: NSImage
    let foldedName: String          // 🌟 検索最適化用の事前変換テキスト
    let foldedOriginalName: String  // 🌟 検索最適化用の事前変換テキスト
    // A5が走査時に確定した互換性です。ピン留め表示はこの値を参照せず、通常一覧だけが利用します。
    let compatibilityStatus: AppCompatibilityStatus
    // P4-Bでmissingピンの候補を完全一致照合するための、走査済みBundle IDです。
    let bundleIdentifier: String?
    // A3で表示する、走査ルートからの相対フォルダー階層です。検索・起動には使いません。
    let discoveryFolderPath: String?
    let categoryIdentifier: String?
    
    // 🌟 タイピングのたびに folding 処理を走らせず、事前生成した文字列で爆速判定
    // 正規化済み検索語が、表示名または元の名前に含まれるか判定します。
    func matches(foldedQuery: String) -> Bool {
        // 空の検索語は全件表示を意味します。
        if foldedQuery.isEmpty { return true }
        // どちらかの名前へ部分一致すれば検索結果に含めます。
        return foldedName.contains(foldedQuery) || foldedOriginalName.contains(foldedQuery)
    }
}

// Appleのカテゴリ識別子を、利用者へ見せる安定したジャンルへまとめます。
enum AppCategoryGroup: CaseIterable, Equatable {
    case development, education, entertainment, finance, games, graphicsDesign, medical, music, photography, productivity, socialNetworking, utilities, video, other

    static func from(identifier: String?) -> AppCategoryGroup {
        guard let identifier else { return .other }
        if identifier == "public.app-category.games" || identifier.hasPrefix("public.app-category.games.") { return .games }
        switch identifier {
        case "public.app-category.developer-tools": return .development
        case "public.app-category.education": return .education
        case "public.app-category.entertainment": return .entertainment
        case "public.app-category.finance": return .finance
        case "public.app-category.graphics-design": return .graphicsDesign
        case "public.app-category.medical": return .medical
        case "public.app-category.music": return .music
        case "public.app-category.photography": return .photography
        case "public.app-category.productivity": return .productivity
        case "public.app-category.social-networking": return .socialNetworking
        case "public.app-category.utilities": return .utilities
        case "public.app-category.video": return .video
        default: return .other
        }
    }

    var title: String {
        switch self {
        case .development: return L10n.appsCategoryDevelopment
        case .education: return L10n.appsCategoryEducation
        case .entertainment: return L10n.appsCategoryEntertainment
        case .finance: return L10n.appsCategoryFinance
        case .games: return L10n.appsCategoryGames
        case .graphicsDesign: return L10n.appsCategoryGraphicsDesign
        case .medical: return L10n.appsCategoryMedical
        case .music: return L10n.appsCategoryMusic
        case .photography: return L10n.appsCategoryPhotography
        case .productivity: return L10n.appsCategoryProductivity
        case .socialNetworking: return L10n.appsCategorySocialNetworking
        case .utilities: return L10n.appsCategoryUtilities
        case .video: return L10n.appsCategoryVideo
        case .other: return L10n.appsCategoryOther
        }
    }
}

// P3で通常一覧を描画するためだけの画面内セクションです。
// キャッシュ形式へ見出し情報を保存せず、表示の直前にだけ組み立てます。
struct AppListSection: Identifiable {
    // A〜Z、0-9、#のいずれかです。表示順の判定とSwiftUIの識別子に共用します。
    let header: String
    // 見出しの下に表示するアプリと、平坦なfilteredAppsでの選択用番号の組です。
    let apps: [IndexedAppItem]

    // アプリIDとは接頭辞を分け、ScrollViewReaderなどのID衝突を防ぎます。
    var id: String { "section-\(header)" }
}

// 見出しをまたいでも、キーボード操作の番号を連続させる補助型です。
struct IndexedAppItem: Identifiable {
    // 既存のアイコン、パス、表示名を持つ実際のアプリ項目です。
    let app: AppItem
    // filteredApps内の番号です。見出し自身は番号を持たず、選択対象にもなりません。
    let filteredIndex: Int

    // アプリ行のIDは従来どおりAppItemのUUIDを使い、スクロール先の安定性を保ちます。
    var id: UUID { app.id }
}

// スタートメニュー本体を構成するメインのSwiftUIビューです。
private struct ApplicationCatalogRevisionObserver: ViewModifier {
    let revision: Int
    let onChange: (Int) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: revision) { _, newRevision in
            onChange(newRevision)
        }
    }
}

private struct AppListSelectionRevisionObserver: ViewModifier {
    let displayedIDs: [UUID]
    let selectedIndex: Int?
    let onReconcile: (Int?) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: displayedIDs) { oldIDs, newIDs in
            onReconcile(AppListSelectionModel.reconciledIndex(
                current: selectedIndex,
                previousIDs: oldIDs,
                currentIDs: newIDs
            ))
        }
    }
}

// 初回ピン投入の条件と保存順を共有し、隔離ストレージからも再起動・再評価を検証できるようにします。
enum DefaultPinSeedPolicy {
    @discardableResult
    static func seedIfNeeded(
        loadState: PinnedStore.LoadState,
        alreadySeeded: Bool,
        candidates: [PinnedEntry],
        persistPins: (PinnedConfig) -> Bool,
        markSeeded: () -> Void
    ) -> Bool {
        guard !alreadySeeded, loadState == .missing, !candidates.isEmpty else { return false }
        guard persistPins(PinnedConfig(items: candidates)) else { return false }
        markSeeded()
        return true
    }
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    // A4では同じ添字でも選択元を分け、hover離脱がキーボード選択を消さないようにします。
    private enum AppListSelectionSource { case none, keyboard, pointer }
    private enum AppListMode: Hashable { case apps, recent }
    // 設定値の変更を監視し、サイズ・配色・配置を自動再描画します。
    @ObservedObject private var settingsModel = AppSettingsModel.shared
    @StateObject private var applicationCatalog = ApplicationCatalogModel()
    @StateObject private var recentFilesCatalog = RecentFilesCatalog()
    private let recentFileActions = RecentFileActions.workspace
    @State private var didStartRecentFilesCatalog = false
    @State private var appListMode: AppListMode = .apps
    @State private var selectedRecentIndex: Int?
    @State private var recentOpenFailed = false
    private var installedApps: [AppItem] { applicationCatalog.installedApps }
    // 保存済みピン留め設定の、現在の画面内コピーです。
    @State private var pinnedConfig: PinnedConfig = PinnedConfig()
    // P8-Aの初回投入を、このContentViewのライフサイクル中に一度だけ評価します。
    @State private var didEvaluateDefaultPinSeed = false
    // P6-Aの展開先フォルダーです。nilは通常のピン領域を操作できる状態を表します。
    @State private var folderOverlayState = FolderOverlayState()
    private var openedFolderID: UUID? { folderOverlayState.folderID }
    // フォルダー名を直接編集している間だけtrueにし、通常の見出しと入力欄を切り替えます。
    @State private var isEditingFolderName = false
    // キャンセル時に保存済み名称を壊さないよう、入力途中の文字列は永続データと分離します。
    @State private var folderNameDraft = ""
    // 編集開始時の対象UUIDを保持します。展開ビューの再描画でopenedFolderIDが一時的に変化しても、
    // Enter確定が別フォルダーやnilへ向かわないようにします。
    @State private var editingFolderID: UUID?
    // IME変換確定用Returnの直後にSwiftUI submitが発火しても、名称保存を1回だけ抑止します。
    @State private var suppressNextFolderNameSubmit = false
    // 展開パネルの名称入力へ確実にキーボードフォーカスを渡し、macOSのEnterをonSubmitへ届けます。
    @FocusState private var isFolderNameFocused: Bool
    // フォルダーごとのプレビュー中心Yです。保存せず、現在のピン留め欄レイアウトから毎回得ます。
    @State private var pinnedFolderTileCenterY: [UUID: CGFloat] = [:]

    var animationsEnabled: Bool {
        AppSettings.shouldAnimate(
            appEnabled: settingsModel.settings.animationsEnabled,
            osReduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            swiftReduceMotion: accessibilityReduceMotion
        )
    }

#if DEBUG
    static func runA3SelfCheck() {
        ApplicationScanner.runA3SelfCheck()
        ApplicationScanner.runA5SelfCheck()
        PinnedRecoveryTransform.runSelfCheck()
        runKeyboardOrderingSelfCheck()
    }

    static func runKeyboardOrderingSelfCheck() {
        func item(_ name: String) -> AppItem {
            AppItem(name: name, originalName: name, path: "/Applications/\(name).app", icon: NSImage(size: NSSize(width: 1, height: 1)), foldedName: name, foldedOriginalName: name, compatibilityStatus: .compatible, bundleIdentifier: nil, discoveryFolderPath: nil, categoryIdentifier: nil)
        }
        let sections = makeAppListSections(from: [item(".Hidden"), item("Alpha"), item("Beta")])
        let ordered = sections.flatMap { $0.apps }
        assert(ordered.map { $0.app.name } == ["Alpha", "Beta", ".Hidden"])
        assert(ordered.enumerated().allSatisfy { $0.element.filteredIndex == $0.offset })
    }
#endif
    
    // 現在ドラッグしているピン留めアプリのパスです。
    @State private var pinnedDragContext: PinnedDragContext?
    // P6-Bのドラッグ開始時スナップショットです。session identityも保持し、旧callbackが新しいsnapshotを消さないようにします。
    @State private var pinnedDragSnapshot: PinnedDragSnapshot?
    // アプリ同士／既存フォルダー中央へ滞在中のフォルダー化候補です。候補中は保存しません。
    @State private var folderDropCandidateID: UUID?
    // 中央へ入った直後に確定させず、約0.6秒の滞在を確認するためのキャンセル可能タイマーです。
    @State private var folderCandidateWorkItem: DispatchWorkItem?
    // マウスが重なっている最上位ピン項目（アプリまたはフォルダー）のUUIDです。
    @State private var hoveredPinnedID: UUID?
    // 最新走査で複数候補だったmissingピンだけを右クリックへ提示します。永続化しません。
    @State private var recoveryCandidates: [UUID: [AppItem]] = [:]
    // 読み込み復旧・移行・ユーザー操作の保存失敗を一つの共通Alertで知らせます。
    @State private var pinnedPersistenceErrorMessage: String?
    // 元データを退避できなかった場合は、セッション中のピン保存を保護します。
    @State private var pinnedPersistenceWriteProtected = false
    @State private var pinnedPersistenceWriteProtectionMessage: String?

    private var pinnedPersistenceAlertTitle: String {
        pinnedPersistenceErrorMessage ?? L10n.pinnedSaveFailed
    }
    // マウスが重なっているアプリ一覧項目のパスです。
    @State private var hoveredAppPath: String?
    @State private var searchWasNonEmpty = false
    
    // 検索欄へ入力されている現在の文字列です。
    @State private var searchText: String = ""
    // 検索欄がキーボードフォーカスを持つかをSwiftUIから制御します。
    @FocusState private var isSearchFocused: Bool
    
    // キーボード操作で現在選択されている検索結果の添字です。
    @State private var selectedIndex: Int? = nil
    @State private var appListSelectionSource: AppListSelectionSource = .none
    // 値を増やすことでScrollViewReaderへスクロール実行のきっかけを与えます。
    @State private var keyboardScrollTrigger: Int = 0
    // 実際のマウス移動があった後だけhover選択を許可し、キーボード操作で解除します。
    @State private var pointerHoverSelectionGate = PointerHoverSelectionGate()
    // マウス移動を監視するAppKitローカルイベントモニターです。
    @State private var pointerActivityMonitor: Any?
    // 表示完了通知で検索欄へフォーカスを予約する、取消可能なDispatchWorkItemです。
    // 非表示通知でcancelし、古い世代のフォーカス要求が実行されないようにします。
    @State private var searchFocusWorkItem: DispatchWorkItem?
    // 同一世代の通知や再予約で、古いWorkItemが最新予約へ干渉しないことを識別するトークンです。
    @State private var searchFocusReservationID = UUID()
    // 最後に受信した非表示通知の世代番号です。古い表示完了通知を拒否するために使用します。
    @State private var lastPanelHideGeneration = 0

    
    // A2の名前条件とA5の互換性条件を適用した、通常一覧と検索の共通入力配列です。
    // installedAppsとキャッシュは変更せず、設定変更だけで即時に表示を戻せるよう画面直前で絞り込みます。
    var displayableApps: [AppItem] {
        let blacklist = settingsModel.settings.appNameBlacklist
        // A2を先に適用します。機能全体がオフ・有効条件なしの場合は、この段階では全アプリを残します。
        let enabledRules = blacklist.isEnabled
            ? blacklist.rules.filter(\.isEnabled).map { normalizedBlacklistText($0.text) }.filter { !$0.isEmpty }
            : []
        let nameFilteredApps = installedApps.filter { app in
            // CoreServicesは走査対象へ含めたうえで、補助アプリ一括表示とFinder個別表示を分離します。
            // FinderだけはshowFinderで制御し、CoreServices全体をOFFにしても表示できます。
            let isCoreServicesApp = app.path.hasPrefix("/System/Library/CoreServices/")
            let isFinder = app.path == "/System/Library/CoreServices/Finder.app"
            guard (!isCoreServicesApp || settingsModel.settings.showCoreServicesApps || (isFinder && settingsModel.settings.showFinder)),
                  (!isFinder || settingsModel.settings.showFinder) else { return false }
            // 表示名と.app由来名だけへ部分一致判定を行い、親フォルダ名を含むパスは照合しません。
            return !enabledRules.contains { rule in app.foldedName.contains(rule) || app.foldedOriginalName.contains(rule) }
        }
        // A5を最後に適用します。OFFなら即時に全件を戻し、ONでもunknownとcompatibleは絶対に隠しません。
        guard settingsModel.settings.hideDefinitelyIncompatibleApps else { return nameFilteredApps }
        return nameFilteredApps.filter { $0.compatibilityStatus != .incompatible }
    }

    // 検索ロジックを最適化し、A2適用済みの配列だけを検索対象にします。
    // そのため、通常一覧で隠れたアプリは検索結果にも現れません。
    var filteredApps: [AppItem] {
        // 未入力時はフィルター処理をせず、全アプリをそのまま返します。
        if searchText.isEmpty {
            return displayableApps
        } else {
            // 大文字・小文字と全角・半角の違いを吸収した検索語へ変換します。
            let foldedQuery = searchText.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            // 事前に正規化してある各アプリ名へ部分一致検索を行います。
            return displayableApps.filter { $0.matches(foldedQuery: foldedQuery) }
        }
    }

    // 空でない検索中だけtrueです。検索結果は短時間で比較する用途なので、P3では見出しを挟みません。
    var isSearching: Bool { !searchText.isEmpty }

    // P3の通常一覧用に、既存のソート済み配列をA〜Z、0-9、#へ振り分けます。
    var visibleAppSections: [AppListSection] { Self.makeAppListSections(from: filteredApps) }

    // A14では検索していないときだけ、同じ見出し構造をジャンルへ切り替えます。
    var visibleCategorySections: [AppListSection] {
        let grouped = Dictionary(grouping: filteredApps) { AppCategoryGroup.from(identifier: $0.categoryIdentifier) }
        var filteredIndex = 0
        return AppCategoryGroup.allCases.compactMap { group in
            guard let apps = grouped[group], !apps.isEmpty else { return nil }
            let indexed = apps.map { app in
                defer { filteredIndex += 1 }
                return IndexedAppItem(app: app, filteredIndex: filteredIndex)
            }
            return AppListSection(header: group.title, apps: indexed)
        }
    }

    // 画面に表示されるアプリ行と、keyboardが操作する順番を常に同じにします。
    var displayedApps: [AppItem] {
        if isSearching { return filteredApps }
        let sections = settingsModel.settings.groupAppsByCategory
            ? visibleCategorySections
            : visibleAppSections
        return sections.flatMap { $0.apps.map(\.app) }
    }

    private var visibleRecentFiles: [RecentFileItem] {
        guard recentFilesFeatureAvailable,
              case let .loaded(items) = recentFilesCatalog.state else { return [] }
        guard !searchText.isEmpty else { return items }
        let query = searchText.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        return items.filter {
            $0.name.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current).contains(query)
        }
    }

    private var recentFilesFeatureAvailable: Bool {
        FeatureFlags.recentFilesEnabled && settingsModel.settings.recentFilesEnabled
    }

    private var visibleRecentFileIDs: [String] { visibleRecentFiles.map(\.id) }
    
    // 保存済みピン情報を、現在のインストール情報と結合して表示用配列にします。
    var pinnedApps: [PinnedApp] {
        // パスからAppItemを高速に引けるDictionaryを一度作ります。
        let appsByPath = Dictionary(uniqueKeysWithValues: installedApps.map { ($0.path, $0) })
        // pinned.jsonの順番を保ったまま、それぞれに対応するAppItemを添えます。
        return pinnedConfig.items.filter { $0.kind == .application }.map { entry in
            // app == nilだけでは走査中・A2/A5で隠れた正常アプリもあるため、保存パスを直接確認します。
            PinnedApp(
                entry: entry,
                // 通常ピンは旧来のパスIDで移動アニメーションを維持し、空・重複だけを安全IDへ退避します。
                app: appsByPath[entry.path],
                availability: canOpenApplicationPackage(at: entry.path) ? .available : .missing
            )
        }
    }

    // 展開中フォルダーを現在の保存状態から引き直します。解除・移動の直後も古い値を保持しません。
    var openedFolder: PinnedEntry? {
        guard let openedFolderID,
              let folder = pinnedConfig.items.first(where: { $0.id == openedFolderID && $0.isFolder }) else { return nil }
        return folder
    }
    
    // ピン留めグリッドの列構成です。領域幅に応じて同じ幅の列数を自動調整します。
    var pinnedGridColumns: [GridItem] {
        [
            // adaptiveは利用可能な横幅へ収まるだけ列を増減します。
            GridItem(
                .adaptive(minimum: Layout.pinnedTileWidth, maximum: Layout.pinnedTileWidth),
                spacing: Layout.pinnedGridSpacing,
                alignment: .top
            )
        ]
    }
    
    // キーボードで選択中の一覧行に使う背景色です。
    var selectionFill: Color {
        // 暗い背景では白、明るい背景では黒を薄く重ねてコントラストを作ります。
        if settingsModel.resolvedColorScheme == .dark {
            return Color.white.opacity(0.14)
        } else {
            return Color.black.opacity(0.08)
        }
    }
    
    // マウスが重なった項目に使う、選択色より控えめな背景色です。
    var hoverFill: Color {
        if settingsModel.resolvedColorScheme == .dark {
            return Color.white.opacity(0.08)
        } else {
            return Color.black.opacity(0.06)
        }
    }
    
    // メニュー全体の最背面へ適用する背景スタイルを、現在の設定から決めます。
    var surfaceBackground: AnyShapeStyle {
        // 単純な半透明設定では、標準背景色へ指定不透明度を適用します。
        if settingsModel.settings.isTransparent {
            let opacity = settingsModel.settings.transparentIntensity
            return AnyShapeStyle(Color(NSColor.windowBackgroundColor).opacity(opacity))
        }
        
        // ぼかしのMaterialはbody内で別途描画するため、ここでは透明にします。
        if settingsModel.settings.usesBlurEffect {
            return AnyShapeStyle(Color.clear)
        }
        
        // Liquid Glass風表示も対応OSでは別レイヤーが描くため透明にします。
        if settingsModel.settings.usesLiquidGlass {
            // 実行中OSのバージョンを安全に判定します。
            if #available(macOS 26, *) {
                return AnyShapeStyle(Color.clear)
            } else {
                return AnyShapeStyle(Color(NSColor.windowBackgroundColor))
            }
        }
        
        // 特殊効果を使わない場合は、macOS標準のウィンドウ背景色です。
        return AnyShapeStyle(Color(NSColor.windowBackgroundColor))
    }
    
    // 左右それぞれの内容領域へ敷く色を決めます。
    var panelSurfaceColor: Color {
        // 半透明・ぼかし時は、最背面の効果を見せるため内容領域を透明にします。
        if settingsModel.settings.isTransparent || settingsModel.settings.usesBlurEffect {
            return Color.clear
        }
        
        if settingsModel.settings.usesLiquidGlass {
            if #available(macOS 26, *) {
                return Color.clear
            } else {
                return Color(NSColor.windowBackgroundColor)
            }
        }
        
        // 特殊効果がない場合は通常の背景色を返します。
        return Color(NSColor.windowBackgroundColor)
    }
    
    // Liquid Glass風レイヤーに重ねる白色の濃さを、テーマと設定強度から計算します。
    var liquidGlassTint: Color {
        // 0〜1のユーザー設定値です。
        let intensity = settingsModel.settings.liquidGlassIntensity
        // ダークモードでは少し強め、ライトモードでは少し控えめに白を重ねます。
        if settingsModel.resolvedColorScheme == .dark {
            return Color.white.opacity(0.08 + (0.20 * intensity))
        } else {
            return Color.white.opacity(0.06 + (0.16 * intensity))
        }
    }
    
    // Liquid Glass風の縁へ、斜め方向の光沢を描く再利用可能なビューです。
    var liquidGlassHighlight: some View {
        // 本体と同じ角丸形状の枠線を作ります。
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            // 単色ではなく、場所によって明るさが変わるグラデーション枠を描きます。
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.4
            )
            // ごく弱いぼかしで、硬すぎないハイライトにします。
            .blur(radius: 0.2)
    }
    
    // 🌟 数字（1〜5）を5段階のぼかしマテリアルに変換するプロパティ
    // 設定の1〜5という数値を、SwiftUIが提供する5種類のMaterialへ変換します。
    var selectedBlurMaterial: Material {
        // 保存値はDoubleですが、段階選択なのでIntへ変換して分岐します。
        switch Int(settingsModel.settings.blurEffectLevel) {
        case 1: return .ultraThinMaterial
        case 2: return .thinMaterial
        case 3: return .regularMaterial
        case 4: return .thickMaterial
        case 5: return .ultraThickMaterial
        default: return .regularMaterial
        }
    }
    
    // 設定と現在のピン・ドラッグ状態から、ピン留め欄を隠せるかを一か所で判定します。
    var shouldHidePinnedArea: Bool {
        settingsModel.settings.hidePinnedAreaWhenEmpty
            && pinnedConfig.items.isEmpty
            && pinnedDragContext == nil
            && pinnedDragSnapshot == nil
    }

    // メニューの無関係な空白をクリックしたとき、検索入力とポインター由来の表示状態を解除します。
    func clearFocusFromUnrelatedClick() {
        isSearchFocused = false
        hoveredAppPath = nil
        hoveredPinnedID = nil
        selectedIndex = nil
        appListSelectionSource = .none
    }

    #if DEBUG
    static func runPinnedDragSelfCheck() {
        PinnedConfigTransform.runSelfCheck()
    }
    #endif

    // スタートメニュー本体のビュー階層と、表示中のイベント処理を定義します。
    var body: some View {
        // 背景効果と実際の内容を、奥から手前へ重ねるコンテナです。
        ZStack {
            // 子ビューに覆われていないStartMenuの空白をクリックした場合も、入力フォーカスだけを解除します。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearFocusFromUnrelatedClick() }
            // Liquid Glass風表示が選択されている場合の背景レイヤーです。
            if settingsModel.settings.usesLiquidGlass {
                // macOS 26以上でのみ、この描画処理を実行します。
                if #available(macOS 26, *) {
                    // メニュー外形と同じ角丸長方形をベースにします。
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        // 背後を透かしてぼかす薄いMaterialを塗ります。
                        .fill(.ultraThinMaterial)
                        // 強度設定に応じた明るい色を追加で重ねます。
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(liquidGlassTint)
                                .blendMode(.screen)
                        )
                        // 先ほど定義した光沢枠を重ねます。
                        .overlay(liquidGlassHighlight)
                        // 輪郭を見失わないための薄い白枠を追加します。
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        )
                        // 斜め方向の明暗を加え、ガラスらしい奥行きを表現します。
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.16),
                                            Color.clear,
                                            Color.black.opacity(0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blendMode(.overlay)
                        )
                        // 複数のブレンド結果を一つの描画グループとして合成します。
                        .compositingGroup()
                }
            } else if settingsModel.settings.usesBlurEffect {
                // 🌟 独立した「ぼかし効果」（5段階マテリアルを反映）
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selectedBlurMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // アプリ一覧とピン留め領域を左右へ並べます。
            HStack(spacing: 0) {
                // 設定値に応じて、左右の表示順序だけを切り替えます。
                if shouldHidePinnedArea {
                    appListView
                } else if settingsModel.settings.appListPosition == .left {
                    // 左：アプリ一覧、中央：区切り線、右：ピン留めです。
                    appListView
                    Divider()
                        .contentShape(Rectangle())
                        .onTapGesture { clearFocusFromUnrelatedClick() }
                    pinnedAreaView
                } else {
                    // 右配置設定では、同じ2ビューの順番を逆にします。
                    pinnedAreaView
                    Divider()
                        .contentShape(Rectangle())
                        .onTapGesture { clearFocusFromUnrelatedClick() }
                    appListView
                }
            }
        }
        // 設定値に従ってメニュー全体の固定サイズを決めます。
        .frame(width: settingsModel.settings.windowWidth, height: settingsModel.settings.windowHeight)
        // 背景効果の設定に応じた、メニュー全体の最背面を描きます。
        .background(surfaceBackground)
        // メニュー内へプレーンテキストがドロップされた場合の共通終了処理です。
        .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
            // StartMenu外へ落とした場合は、開始時スナップショットへ戻し、仮配置を保存しません。
            endPinnedDrag(rollback: true)
            // ドロップを受理したことをSwiftUIへ返します。
            return true
        }
        // 内容を16ポイント角丸の外形で切り抜きます。
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // メニューを背景から浮かせるため、下方向へ広がる影を付けます。
        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
        // 設定で確定した配色を、配下の全SwiftUIビューへ適用します。
        .environment(\.colorScheme, settingsModel.resolvedColorScheme)
        // ビューが画面の表示階層へ現れた際に実行される初期化処理です。
        .onAppear {
            applicationCatalog.start()
            startRecentFilesCatalogIfEnabled()
            loadPinnedConfiguration()
            
            // マウス操作による選択切り替えの監視も開始します。
            startPointerActivityMonitor()
        }
        // ビューが画面から外れる際、作成した監視処理を後片付けします。
        .onDisappear {
            // キーボード監視はAppDelegateがアプリ終了まで管理します。
            // ここでは、このビュー固有のマウスモニターと遅延処理だけを停止します。
            stopPointerActivityMonitor()
            searchFocusWorkItem?.cancel()
            searchFocusWorkItem = nil
            searchFocusReservationID = UUID()
            applicationCatalog.stop()
            // Spotlight keeps one live query while the feature is enabled, including while the panel is hidden.
            // The setting toggle owns cancellation; reopening the panel must not rebuild the query.
        }
        // 表示アニメーションが完了し、パネルが表示状態になったことをAppDelegateから通知された時だけ、
        // 検索欄へフォーカスを予約します。これにより、設定画面などのキーウィンドウ通知による
        // 検索欄への不要なフォーカス復帰を防止します。
        // generationだけを読み、lastPanelHideGenerationとcanFocusSearchField(for:)で条件付きフォーカスへ変更しました。
        .onReceive(NotificationCenter.default.publisher(for: .startMenuPanelDidFinishShowing)) { notification in
            // 1. generationを安全に取得。欠落している場合は無視します。
            guard let userInfo = notification.userInfo,
                  let newGeneration = userInfo[StartMenuPanelLifecycleUserInfoKey.generation] as? Int else { return }
            // 2. generation > lastPanelHideGenerationを確認。非表示より古い表示通知を拒否します。
            guard newGeneration > lastPanelHideGeneration else { return }
            applicationCatalog.panelDidBecomeVisible()
            // 3. 既存searchFocusWorkItemをcancelしてnil化。前の予約が残らないようにします。
            searchFocusWorkItem?.cancel()
            searchFocusWorkItem = nil
            let reservationID = UUID()
            searchFocusReservationID = reservationID
            // 4. 新しいDispatchWorkItemを作成して保持。次のメインループで実行します。
            let workItem = DispatchWorkItem {
                // 5. 自分自身が最新予約であり、キャンセル済みでないことを確認します。
                // 共有プロパティのWorkItemを参照しないため、古い予約が新しい予約へ干渉しません。
                guard reservationID == searchFocusReservationID else { return }
                // 6. generation > lastPanelHideGenerationを再確認。実行直前でも有効であることを確認します。
                guard newGeneration > lastPanelHideGeneration else { return }
                // 7. AppDelegate.canFocusSearchField(for: generation)を確認。
                //    ContentViewはpanelTransitionGenerationやpanelPresentationStateを直接参照しません。
                guard (NSApp.delegate as? AppDelegate)?.canFocusSearchField(for: newGeneration) == true else { return }
                // 8. 条件を満たす場合だけisSearchFocused = true。
                isSearchFocused = true
                // 9. 自分が最新予約の場合だけ、実行後に保持参照をnil化します。
                searchFocusWorkItem = nil
            }
            searchFocusWorkItem = workItem
            // 次のメインループで実行。即座にフォーカスを予約せず、他のUI更新が完了するのを待ちます。
            DispatchQueue.main.async(execute: workItem)
        }
        // アプリ外で左ボタンが解放された場合だけ、残っているピンdragの一時状態を開始前へ戻します。
        // 通常の外部クリック、検索、選択、展開フォルダー、パネル表示状態には触れません。
        .onReceive(NotificationCenter.default.publisher(for: .startMenuExternalLeftMouseUp)) { _ in
            // 内部drop完了後など、drag情報とsnapshotが既に消えていれば何もしません。
            guard pinnedDragContext != nil || pinnedDragSnapshot != nil else { return }
            // 外部終了中の仮配置は保存せず、drag開始時に保存した画面上の順序へ戻します。
            endPinnedDrag(rollback: true)
        }
        // AppDelegateがStartMenuを隠す全経路から受け取ります。
        // ContentView自体は生存したままのためonDisappearだけに任せず、一時UIを必ず解除します。
        // generationとreasonを安全に取得し、古い世代の重複後片付けを防止します。
        .onReceive(NotificationCenter.default.publisher(for: .startMenuPanelWillHide)) { notification in
            // 1. generationとreasonを安全に取得。欠落している場合は世代確認をスキップします。
            let userInfo = notification.userInfo as? [String: Any] ?? [:]
            if let newGeneration = userInfo[StartMenuPanelLifecycleUserInfoKey.generation] as? Int {
                // 2. 同じ世代の重複後片付けを防止。lastPanelHideGenerationを更新済みならスキップします。
                guard newGeneration > lastPanelHideGeneration else { return }
                // 3. lastPanelHideGenerationを更新。古い表示完了通知を拒否できるようにします。
                lastPanelHideGeneration = newGeneration
            }
            // 4. searchFocusWorkItemをcancelしてnil化。予約中のフォーカス要求を取り消します。
            searchFocusWorkItem?.cancel()
            searchFocusWorkItem = nil
            searchFocusReservationID = UUID()
            applicationCatalog.panelWillHide()
            // 5. isSearchFocused = false。検索欄のフォーカスを解除します。
            isSearchFocused = false
            // 6. ドラッグ開始時スナップショットを復元し、ドラッグ関連の一時状態を終了します。
            endPinnedDrag(rollback: true)
            // 7. 一覧選択とhoverを解除します。
            hoveredAppPath = nil
            pointerHoverSelectionGate.reset()
            selectedIndex = nil
            appListSelectionSource = .none
            // 9. フォルダー名編集中状態と展開フォルダーを既存の安全なヘルパーで閉じます。
            closeOpenedFolder()
        }
        // 日本語IMEの変換確定Returnと名称保存Returnを分離します。次のReturnでは通常どおり保存します。
        .onReceive(NotificationCenter.default.publisher(for: .startMenuFolderNameIMECommit)) { _ in
            if isEditingFolderName {
                suppressNextFolderNameSubmit = true
                // IMEによっては変換確定Returnでsubmitを発火しないため、次の操作まで抑止を残しません。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    suppressNextFolderNameSubmit = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startMenuFolderNameSubmit)) { _ in
            suppressNextFolderNameSubmit = false
            commitFolderName()
        }
        .modifier(AppListSelectionRevisionObserver(
            displayedIDs: displayedApps.map(\.id),
            selectedIndex: selectedIndex
        ) { reconciledIndex in
            selectedIndex = reconciledIndex
            if reconciledIndex == nil {
                appListSelectionSource = .none
            } else {
                keyboardScrollTrigger += 1
            }
        })
        .modifier(ApplicationCatalogRevisionObserver(revision: applicationCatalog.successfulScanRevision) {
            successfulApplicationScanDidChange($0)
        })
        // A2の全体設定・条件が変わると、選択対象の件数も変わるため先頭へ安全に戻します。
        .onChange(of: settingsModel.settings.appNameBlacklist) { _, _ in
            selectedIndex = nil
            appListSelectionSource = .none
            hoveredAppPath = nil
            keyboardScrollTrigger += 1
        }
        .onChange(of: settingsModel.settings.selectAppListRowOnPointerHover) { _, enabled in
            if !enabled {
                hoveredAppPath = nil
                hoveredPinnedID = nil
                if appListSelectionSource == .pointer {
                    selectedIndex = nil
                    appListSelectionSource = .none
                }
            }
        }
        .onChange(of: settingsModel.settings.groupAppsByCategory) { _, _ in
            selectedIndex = nil
            appListSelectionSource = .none
            hoveredAppPath = nil
            keyboardScrollTrigger += 1
        }
        .alert(
            pinnedPersistenceAlertTitle,
            isPresented: Binding(
                get: { pinnedPersistenceErrorMessage != nil },
                set: { if !$0 { pinnedPersistenceErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { pinnedPersistenceErrorMessage = nil }
        }
    }
    
    // 左右分割のうち、検索欄とインストール済みアプリ一覧を表示する領域です。
    var appListView: some View {
        // 見出し、検索欄、スクロール一覧を上から縦に並べます。
        VStack(spacing: 0) {
            // アプリ一覧領域のタイトルです。
            Text(L10n.appsTitle)
                .font(.headline)
                .padding(.top, Layout.sectionTitleTopPadding)
                .onTapGesture { clearFocusFromUnrelatedClick() }
                .padding(.bottom, Layout.sectionTitleBottomPadding)

            if recentFilesFeatureAvailable {
                recentModePicker
            }
            
            // 検索文字列を入力する、装飾を独自指定したテキスト欄です。
            TextField(appListMode == .recent && recentFilesFeatureAvailable ? L10n.recentSearchPlaceholder : L10n.appsSearchPlaceholder, text: $searchText)
                // 標準の枠を使わず、後続modifierで外観を作ります。
                .textFieldStyle(.plain)
                // 入力文字と背景の間に内側余白を設けます。
                .padding(7)
                // macOS標準のコントロール背景色を使用します。
                .background(Color(NSColor.controlBackgroundColor))
                // 背景の四隅を丸めます。
                .cornerRadius(6)
                // 薄い境界線を重ね、入力欄の範囲を明確にします。
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
                // isSearchFocusedと実際の入力フォーカスを結び付けます。
                .focused($isSearchFocused)
                // 検索欄でReturnを押した場合も、選択中アプリを起動します。
                .onSubmit {
                    if appListMode == .recent { openSelectedRecentFile() }
                    else { executeSelectedApp() }
                }
            
            // ScrollViewReaderにより、選択中の行へプログラムからスクロールできます。
            ScrollViewReader { proxy in
                // アプリ一覧が領域より長い場合に縦スクロール可能にします。
                ScrollView {
                    // LazyVStackは画面付近の行だけを生成し、大量のアプリでも負荷を抑えます。
                    LazyVStack(spacing: 2) {
                        if appListMode == .recent && recentFilesFeatureAvailable {
                            recentFilesListContent
                        } else if appListMode == .recent {
                            EmptyView()
                        } else if isSearching {
                            // 検索中は従来どおり平坦な結果だけを出し、視線移動と操作規則を増やしません。
                            ForEach(Array(displayedApps.enumerated()), id: \.element.id) { index, app in
                                appRow(app: app, filteredIndex: index)
                            }
                        } else if settingsModel.settings.groupAppsByCategory {
                            ForEach(visibleCategorySections) { section in
                                appSectionHeader(section.header)
                                ForEach(section.apps) { indexedApp in
                                    appRow(app: indexedApp.app, filteredIndex: indexedApp.filteredIndex)
                                }
                            }
                        } else {
                            // 通常時だけ空でない見出しを固定順に表示します。
                            ForEach(visibleAppSections) { section in
                                appSectionHeader(section.header)
                                // filteredIndexは見出しをまたいで連番なので、上下キーは見出しで停止しません。
                                ForEach(section.apps) { indexedApp in
                                    appRow(app: indexedApp.app, filteredIndex: indexedApp.filteredIndex)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                // スクロール用トリガーが変わったら、選択行が見える位置へ移動します。
                .onChange(of: keyboardScrollTrigger) { _, _ in
                    if appListMode == .recent,
                       recentFilesFeatureAvailable,
                       let selectedRecentIndex,
                       visibleRecentFiles.indices.contains(selectedRecentIndex) {
                        withAnimation(animationsEnabled ? .easeInOut(duration: 0.1) : nil) {
                            proxy.scrollTo(visibleRecentFiles[selectedRecentIndex].id, anchor: .center)
                        }
                    } else if appListMode == .apps,
                              let selectedIndex,
                              displayedApps.indices.contains(selectedIndex) {
                        // 短いアニメーションで選択行を領域中央へスクロールします。
                        withAnimation(animationsEnabled ? .easeInOut(duration: 0.1) : nil) {
                            proxy.scrollTo(displayedApps[selectedIndex].id, anchor: .center)
                        }
                    }
                }
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { clearFocusFromUnrelatedClick() }
                )
            }
        }
        // 一覧領域だけは設定された固定幅にします。
        .frame(width: shouldHidePinnedArea ? settingsModel.settings.windowWidth : settingsModel.settings.appListWidth)
        // 高さはメニュー全体まで広げます。
        .frame(maxHeight: .infinity)
        // 選択中の背景効果に合う内容面の色を使います。
        .background(panelSurfaceColor)
        .onReceive(NotificationCenter.default.publisher(for: .startMenuPanelKeyboardCommand), perform: handlePanelKeyboardCommand)
        .onChange(of: searchText) { oldValue, newValue in
            searchTextDidChange(from: oldValue, to: newValue)
        }
        .onChange(of: settingsModel.settings.recentFilesEnabled) { _, enabled in recentFilesSettingDidChange(enabled) }
        .onChange(of: appListMode) { _, mode in appListModeDidChange(mode) }
        .onChange(of: visibleRecentFileIDs) { _, _ in recentFilesDidChange() }
        .alert(L10n.recentOpenFailed, isPresented: $recentOpenFailed) {
            Button(L10n.settingsErrorDismiss, role: .cancel) { recentOpenFailed = false }
        }
    }

    private var recentModePicker: some View {
        Picker("", selection: $appListMode) {
            Text(L10n.recentModeApps).tag(AppListMode.apps)
            Text(L10n.recentModeFiles).tag(AppListMode.recent)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .accessibilityLabel(L10n.appsTitle)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var recentFilesListContent: some View {
        Text(L10n.recentScope)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .padding(.horizontal, 14)
            .accessibilityLabel(L10n.recentScope)
        switch recentFilesCatalog.state {
        case .idle, .loading:
            recentStatusText(L10n.recentLoading)
        case .loaded:
            if visibleRecentFiles.isEmpty {
                recentStatusText(L10n.recentEmpty)
            } else {
                ForEach(Array(visibleRecentFiles.enumerated()), id: \.element.id) { index, item in
                    recentFileRow(item: item, index: index)
                }
            }
        case .failed:
            recentStatusText(L10n.recentUnavailable)
        }
    }

    private func recentStatusText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
            .accessibilityLabel(value)
    }

    @ViewBuilder
    private func recentFileRow(item: RecentFileItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(selectedRecentIndex == index ? (settingsModel.resolvedColorScheme == .dark ? .white : .black) : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedRecentIndex == index ? selectionFill : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRecentIndex = index
            openRecentFile(item)
        }
        .contextMenu {
            Button(L10n.recentShowInFinder) {
                guard FeatureFlags.recentFilesEnabled else { return }
                recentFileActions.revealInFinder(item.url)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .id(item.id)
    }

    // P3の控えめな見出し行です。アプリ行とは分離し、クリック、hover、ドラッグの対象にしません。
    @ViewBuilder
    func appSectionHeader(_ header: String) -> some View {
        Text(header)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 3)
            .padding(.horizontal, 14)
            // VoiceOverには、単なる文字ではなく一覧の区切りであることを説明します。
            .accessibilityLabel(L10n.appListSection(header))
            .accessibilityAddTraits(.isHeader)
    }

    // 見出しの有無にかかわらず再利用する、アプリ1行の操作と見た目です。
    // filteredIndexはfilteredAppsだけを基準とするため、P3追加後も既存の選択・起動・スクロール規則を変えません。
    @ViewBuilder
    func appRow(app: AppItem, filteredIndex: Int) -> some View {
        HStack(spacing: 12) {
            // AppKitのNSImageをSwiftUIのImageとして、アプリ行の固定サイズへ収めます。
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            // 選択番号は見出しではなくアプリだけに対応するため、選択色もfilteredIndexで判定します。
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundColor(selectedIndex == filteredIndex ? (settingsModel.resolvedColorScheme == .dark ? .white : .black) : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if settingsModel.settings.showAppDiscoveryFolder, let folderPath = app.discoveryFolderPath {
                    Text(folderPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(
                selectedIndex == filteredIndex ? selectionFill : (settingsModel.settings.selectAppListRowOnPointerHover && hoveredAppPath == app.path ? hoverFill : Color.clear)
            )
        )
        // 透明な余白も、従来どおりクリック・hover対象に含めます。
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.plainText],
            delegate: PinnedFolderAreaDropDelegate(
                dragIdentity: pinnedDragContext?.identity,
                dragContext: $pinnedDragContext,
                sourceFolderID: pinnedDragContext?.origin.folderID,
                pinnedConfig: $pinnedConfig,
                snapshot: $pinnedDragSnapshot,
                save: savePinnedCandidate,
                hoveredID: $hoveredPinnedID,
                folderCandidateID: $folderDropCandidateID,
                folderCandidateWorkItem: $folderCandidateWorkItem
            )
        )
        .onHover { hovering in
            // 実際にポインターが動いていない場合は、画面更新による誤選択を防ぎます。
            guard pointerHoverSelectionGate.allowsHoverSelection else { return }
            guard settingsModel.settings.selectAppListRowOnPointerHover else { return }
            if hovering {
                hoveredAppPath = app.path
                selectedIndex = filteredIndex
                appListSelectionSource = .pointer
            } else if hoveredAppPath == app.path {
                hoveredAppPath = nil
                if appListSelectionSource == .pointer {
                    selectedIndex = nil; appListSelectionSource = .none
                }
            }
        }
        // クリック時はアプリだけを選択・起動し、見出しへ選択状態を渡しません。
        .onTapGesture {
            selectedIndex = filteredIndex
            appListSelectionSource = .pointer
            executeSelectedApp(app)
        }
        // アプリ一覧では、ピン操作とFinder表示をまとめた専用メニューを出します。
        .contextMenu { appListContextMenu(for: app) }
        // ScrollViewReaderの対象は従来から変わらずアプリ行です。
        .id(app.id)
    }

    // 名前の先頭を正規化して、P3の3種の見出しへ分類します。
    // 先頭空白、全角文字、アクセント付き英字、大文字小文字の差を吸収します。
    static func sectionHeader(for appName: String) -> String {
        let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .uppercased()
        guard let firstScalar = normalizedName.unicodeScalars.first else { return "#" }
        if firstScalar.value >= 65 && firstScalar.value <= 90 { return String(Character(firstScalar)) }
        if firstScalar.value >= 48 && firstScalar.value <= 57 { return "0-9" }
        return "#"
    }

    // P2で確定した名前順を各見出し内で保ったまま、表示用のセクションだけを組み立てます。
    static func makeAppListSections(from apps: [AppItem]) -> [AppListSection] {
        // 見出しの固定順を先に定義し、該当項目がない見出しは最後に除外します。
        // Stringの範囲は列挙できないため、英字列をCharacter配列へしてから各見出し文字列を作ります。
        let headerOrder = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["0-9", "#"]
        var appsByHeader = Dictionary(uniqueKeysWithValues: headerOrder.map { ($0, [IndexedAppItem]()) })
        for app in apps {
            appsByHeader[Self.sectionHeader(for: app.name), default: []].append(IndexedAppItem(app: app, filteredIndex: 0))
        }
        // 画面上のセクション順へ並べた後で連番を振り、表示順を選択順の正本にします。
        var displayIndex = 0
        return headerOrder.compactMap { header in
            guard let sectionApps = appsByHeader[header], !sectionApps.isEmpty else { return nil }
            let indexedApps = sectionApps.map { item in
                defer { displayIndex += 1 }
                return IndexedAppItem(app: item.app, filteredIndex: displayIndex)
            }
            return AppListSection(header: header, apps: indexedApps)
        }
    }
    
    // ピン留めしたアプリをアイコングリッドで表示する領域です。
    var pinnedAreaView: some View {
        // P6-Aでは通常グリッドの上へ、Windows 11風のフォルダー展開パネルを同じ領域内で重ねます。
        // 別ウインドウにしないため、表示中のStartMenuのサイズ・テーマ・閉じる経路をそのまま共有できます。
        ZStack(alignment: .top) {
            // ピンが領域を超えた場合にスクロール可能にします。
            ScrollView {
                // 画面幅に応じて列数が変わる遅延生成グリッドです。
                LazyVGrid(columns: pinnedGridColumns, alignment: .center, spacing: Layout.pinnedGridSpacing) {
                    // 保存されている最上位順を維持し、アプリとフォルダーを同じ大きさのタイルとして混在表示します。
                    ForEach(pinnedConfig.items) { entry in
                        if entry.isFolder {
                            pinnedFolderTile(entry)
                        } else {
                            pinnedAppTile(makePinnedApp(from: entry))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            // ScrollViewが占めるタイル外の空白だけを解除対象にし、タイルの操作へ重ねません。
            .onTapGesture { clearFocusFromUnrelatedClick() }
            // 展開パネルはピン留め欄だけを基準に中央配置します。アプリ一覧を含むStartMenu全体ではなく、
            // フォルダーを開いた元の領域の中央へ留めるため、一覧の左右配置設定でも視線がずれません。
            if let folder = openedFolder {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { closeOpenedFolder() }
                GeometryReader { geometry in
                    let safeMargin: CGFloat = 30
                    let cardHeight = folderOverlayHeight(folder, availableSize: geometry.size)
                    // 通常は開いたプレビューの中心Yをそのまま使います。取得前だけは領域中央を安全な初期値にします。
                    let requestedY = folderOverlayState.originY ?? geometry.size.height / 2
                    let minimumY = safeMargin + cardHeight / 2
                    let maximumY = geometry.size.height - safeMargin - cardHeight / 2
                    // カードが上下へはみ出す場合だけ、左右と同じ30pt余白を残す位置へ補正します。
                    let correctedY = minimumY <= maximumY
                        ? min(max(requestedY, minimumY), maximumY)
                        : geometry.size.height / 2
                    // GeometryReaderは子を左上基準で配置するため、カードの中心座標を明示します。
                    // Xはピン留め欄の真ん中、Yはプレビュー位置を基準にし、必要なときだけ安全余白へクランプします。
                    pinnedFolderOverlay(folder, availableSize: geometry.size)
                        .position(
                            x: geometry.size.width / 2,
                            y: correctedY
                        )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        // ピン留め側は、一覧以外の残り幅と全高を使用します。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelSurfaceColor)
        // GeometryReaderが返す各タイルの中心Yを受け取り、展開パネルの通常Y位置に使います。
        .coordinateSpace(name: "pinnedArea")
        .onPreferenceChange(PinnedFolderTileCenterPreferenceKey.self) {
            pinnedFolderTileCenterY = $0
            if let id = folderOverlayState.folderID {
                folderOverlayState.captureOriginIfMissing($0[id])
            }
        }
        // 空白部分を含む領域全体について、操作時の形状を長方形として扱わせます。
        .contentShape(Rectangle())
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { clearFocusFromUnrelatedClick() }
        )
    }
    
    // MARK: - 機能

    private func handlePanelKeyboardCommand(_ notification: Notification) {
        guard let rawCommand = notification.userInfo?["command"] as? String,
              let command = StartMenuPanelKeyboardCommand(rawValue: rawCommand) else { return }
        switch command {
        case .selectNext:
            appListMode == .recent ? moveRecentSelection(direction: 1) : moveSelection(direction: 1)
        case .selectPrevious:
            appListMode == .recent ? moveRecentSelection(direction: -1) : moveSelection(direction: -1)
        case .openSelectedApp:
            appListMode == .recent ? openSelectedRecentFile() : executeSelectedApp()
        case .closeStartMenu:
            if openedFolderID != nil { closeOpenedFolder() }
            else { (NSApp.delegate as? AppDelegate)?.hidePanelAndApplication(hideReason: .escKey) }
        }
    }

    private func searchTextDidChange(from oldValue: String, to newValue: String) {
        if appListMode == .recent {
            selectedRecentIndex = nil
        } else {
            selectedIndex = nil
            appListSelectionSource = .none
        }
        keyboardScrollTrigger += 1
        if appListMode == .apps && oldValue.isEmpty && !newValue.isEmpty && !searchWasNonEmpty {
            searchWasNonEmpty = true
            applicationCatalog.searchDidBegin()
        } else if newValue.isEmpty {
            searchWasNonEmpty = false
        }
    }

    private func recentFilesSettingDidChange(_ enabled: Bool) {
        if enabled && recentFilesFeatureAvailable {
            startRecentFilesCatalogIfEnabled()
        } else {
            stopRecentFilesCatalog()
            appListMode = .apps
            selectedRecentIndex = nil
            selectedIndex = nil
            appListSelectionSource = .none
            hoveredAppPath = nil
            keyboardScrollTrigger += 1
        }
    }

    private func appListModeDidChange(_ mode: AppListMode) {
        guard mode != .recent || recentFilesFeatureAvailable else {
            appListMode = .apps
            stopRecentFilesCatalog()
            return
        }
        AppListSelectionModel.clearSelectionsForModeChange(
            appSelection: &selectedIndex,
            recentSelection: &selectedRecentIndex
        )
        appListSelectionSource = .none
        hoveredAppPath = nil
        keyboardScrollTrigger += 1
        guard mode == .apps else { return }
        if !searchText.isEmpty && !searchWasNonEmpty {
            searchWasNonEmpty = true
            applicationCatalog.searchDidBegin()
        }
    }

    private func recentFilesDidChange() {
        selectedRecentIndex = nil
        keyboardScrollTrigger += 1
    }

    private func startRecentFilesCatalogIfEnabled() {
        guard recentFilesFeatureAvailable, !didStartRecentFilesCatalog else { return }
        didStartRecentFilesCatalog = true
        recentFilesCatalog.start()
    }

    private func stopRecentFilesCatalog() {
        recentFilesCatalog.stop()
        didStartRecentFilesCatalog = false
        selectedRecentIndex = nil
    }

    private func moveRecentSelection(direction: Int) {
        guard appListMode == .recent,
              recentFilesFeatureAvailable,
              let newIndex = AppListSelectionModel.movedIndex(
                current: selectedRecentIndex,
                direction: direction,
                itemCount: visibleRecentFiles.count
              ) else { return }
        pointerHoverSelectionGate.noteKeyboardSelection()
        selectedRecentIndex = newIndex
        keyboardScrollTrigger += 1
    }

    private func openSelectedRecentFile() {
        guard recentFilesFeatureAvailable,
              appListMode == .recent,
              let selectedRecentIndex,
              visibleRecentFiles.indices.contains(selectedRecentIndex) else { return }
        openRecentFile(visibleRecentFiles[selectedRecentIndex])
    }

    private func openRecentFile(_ item: RecentFileItem) {
        guard recentFilesFeatureAvailable else { return }
        guard recentFileActions.open(item.url) else {
            recentOpenFailed = true
            return
        }
        // ファイルを開く要求が成功した後にだけStartMenuを閉じ、操作順を保ちます。
        (NSApp.delegate as? AppDelegate)?.hidePanelAndApplication(hideReason: .appLaunch)
    }
    
    // 上下矢印キーに応じ、検索結果内の選択位置を安全に移動します。
    func moveSelection(direction: Int) {
        guard let newIndex = AppListSelectionModel.movedIndex(
            current: selectedIndex,
            direction: direction,
            itemCount: displayedApps.count
        ) else { return }
        // キーボード移動でポインターhover権を明示的に解除します。
        // 同じ位置に静止したポインターが再描画後のhoverで選択を奪うことはなく、次の実移動で再び有効になります。
        pointerHoverSelectionGate.noteKeyboardSelection()
        selectedIndex = newIndex
        appListSelectionSource = .keyboard
        hoveredAppPath = nil
        // 選択行が見えるようスクロール処理を発火させます。
        keyboardScrollTrigger += 1
    }
    
    // マウスが「いま実際に動いている」ことを検出する監視を開始します。
    func startPointerActivityMonitor() {
        // このアプリ内へ届くmouseMovedイベントを監視します。
        pointerActivityMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            pointerHoverSelectionGate.notePointerMovement()
            // マウスイベント自体は通常どおり他のUIへも渡します。
            return event
        }
    }
    
    // マウス移動監視と関連する予約処理をすべて後片付けします。
    func stopPointerActivityMonitor() {
        // 登録済みモニターがある場合のみAppKitから削除します。
        if let monitor = pointerActivityMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // 参照をnilにして、監視がない状態を明示します。
        pointerActivityMonitor = nil
        pointerHoverSelectionGate.reset()
    }
    
    // 現在選択されている検索結果のアプリを起動します。
    func executeSelectedApp(_ explicitlyActivatedApp: AppItem? = nil) {
        // 行クリックではState反映前の古いselectedIndexを使わず、押された行を優先します。
        guard let app = AppListSelectionModel.itemToActivate(
            explicitItem: explicitlyActivatedApp,
            selectedIndex: selectedIndex,
            items: displayedApps
        ) else { return }
        
        // 実際の起動とメニュー非表示は共通関数へ任せます。
        openApp(at: app.path)
    }

    // アプリ一覧の右クリックメニューに含める、ピン留め状態に応じた操作を1つ返します。
    // A1以降もこの関数はピン操作だけを担当し、Finder操作とは責務を分離します。
    @ViewBuilder
    func pinMenuItem(for app: AppItem) -> some View {
        // すでにピン留め済みかどうかで、解除または追加ボタンを切り替えます。
        if isPinned(app) {
            // ピン留め済みなら解除ボタンを表示します。
            Button(L10n.unpinApp) {
                // 最上位かフォルダー内かをUI側で分岐させず、同じパスを保存ツリー全体から解除します。
                unpinApp(at: app.path)
            }
        } else {
            // 未登録ならピン留めボタンを表示します。
            Button(L10n.pinApp) {
                pin(app)
            }
        }
    }

    // 最上位アプリのメニューへP6-Aの明示操作を追加します。ドラッグによるフォルダー作成はP6-Bまで導入しません。
    @ViewBuilder
    func folderMoveMenuItems(for entry: PinnedEntry) -> some View {
        Button(L10n.pinnedNewFolder) { createFolder(containingTopLevelApp: entry.id) }
        let destinationFolders = pinnedConfig.items.filter { $0.isFolder && $0.id != entry.id }
        if !destinationFolders.isEmpty {
            Menu(L10n.pinnedMoveToFolder) {
                ForEach(destinationFolders) { folder in
                    Button(folder.folderName?.isEmpty == false ? folder.folderName! : L10n.pinnedNewFolderName) {
                        moveTopLevelApp(id: entry.id, toFolder: folder.id)
                    }
                }
            }
        }
    }

    // アプリ一覧の右クリックメニューです。既存のピン操作の後へ、Finder表示を区切って追加します。
    @ViewBuilder
    func appListContextMenu(for app: AppItem) -> some View {
        // ピン留め／解除は従来の共通部品を再利用し、既存の動作を変えません。
        pinMenuItem(for: app)
        Divider()
        // 一覧のアプリも念のため有効性を確認し、走査完了後に削除された場合は安全に無効化します。
        Button(L10n.revealInFinder) {
            revealInFinder(at: app.path)
        }
        .disabled(!canRevealInFinder(at: app.path))
    }

    // ピン留めタイルの右クリックメニューです。解除を先頭へ置き、Finder表示を下側へ続けます。
    // 壊れたピンでも利用者が整理できるよう、無効化するのはFinder操作だけに限定します。
    @ViewBuilder
    func pinnedAppContextMenu(for pinnedApp: PinnedApp) -> some View {
        // 最初の操作は常に有効な解除とし、壊れたピンも右クリックから確実に整理できます。
        Button(L10n.unpinApp) {
            unpin(id: pinnedApp.entry.id)
        }
        Divider()
        // 解除の下へFinder表示を置きます。P4の復旧はまだ行わないため、無効な保存パスは選択不能です。
        Button(L10n.revealInFinder) {
            revealInFinder(at: pinnedApp.entry.path)
        }
        .disabled(!pinnedApp.isAvailable)
        Divider()
        // 子アプリには表示しない最上位操作です。フォルダー内かどうかは呼び出し元で分けます。
        folderMoveMenuItems(for: pinnedApp.entry)
        recoveryMenu(for: pinnedApp.entry.id)
    }

    // フォルダーの解除は子を元の位置へ同じ順番で戻すため、誤ってピンを失わない可逆操作です。
    @ViewBuilder
    func pinnedFolderContextMenu(_ folder: PinnedEntry) -> some View {
        // openFolderで編集状態を初期化するため、先に開いてから名称編集へ切り替えます。
        Button(L10n.pinnedRenameFolder) { openFolder(folder); beginFolderNameEditing(folder) }
        Button(L10n.pinnedDissolveFolder) { dissolveFolder(id: folder.id) }
    }

    // 展開パネル内の子アプリでは、最上位用の新規フォルダー作成ではなく取り出しだけを示します。
    @ViewBuilder
    func folderChildContextMenu(_ child: PinnedEntry, folderID: UUID) -> some View {
        Button(L10n.pinnedExtractFromFolder) { extractChild(id: child.id, fromFolder: folderID) }
        Divider()
        Button(L10n.revealInFinder) { revealInFinder(at: child.path) }
            .disabled(!canRevealInFinder(at: child.path))
        recoveryMenu(for: child.id)
    }

    // 最上位とフォルダーchildの右クリックから、同じ一時候補を選べるようにします。
    @ViewBuilder
    func recoveryMenu(for id: UUID) -> some View {
        if let candidates = recoveryCandidates[id], !candidates.isEmpty {
            Divider()
            Menu(L10n.pinnedChooseRecovery) {
                ForEach(candidates) { candidate in
                    Button("\(candidate.name) — \(shortPath(candidate.path))") {
                        recoverPinnedApp(id: id, with: candidate)
                    }
                }
            }
        }
    }
    
    // 保存済みアプリ項目を、現在の走査結果と結合した表示モデルへ変換します。
    // フォルダー内でもP4-Aのパス判定とP4-Bの復旧候補表示を同じモデルで使うため、最上位専用の状態を持たせません。
    func makePinnedApp(from entry: PinnedEntry) -> PinnedApp {
        let app = installedApps.first(where: { $0.path == entry.path })
        return PinnedApp(entry: entry, app: app, availability: canOpenApplicationPackage(at: entry.path) ? .available : .missing)
    }

    // 内部並べ替え用のUUIDは、このアプリのプロセス内だけへ公開します。
    func pinnedDragProvider(for id: UUID) -> NSItemProvider {
        makePinnedDragProvider(for: id, in: pinnedConfig)
    }

    private func beginPinnedDrag(entryID: UUID, origin: PinnedDragOrigin) -> NSItemProvider {
        // まれな重複onDrag開始でも、前の仮配置を次sessionのsnapshotへ混ぜません。
        endPinnedDrag(rollback: true)
        let context = PinnedDragContext(entryID: entryID, origin: origin)
        pinnedDragContext = context
        pinnedDragSnapshot = PinnedDragSnapshot(identity: context.identity, config: pinnedConfig)
        hoveredPinnedID = nil
        folderDropCandidateID = nil
        return pinnedDragProvider(for: entryID)
    }

    private func endPinnedDrag(rollback: Bool) {
        if rollback, let snapshot = pinnedDragSnapshot {
            pinnedConfig = snapshot.config
        }
        pinnedDragContext = nil
        pinnedDragSnapshot = nil
        hoveredPinnedID = nil
        folderDropCandidateID = nil
        folderCandidateWorkItem?.cancel()
        folderCandidateWorkItem = nil
    }

    // Windows 11の「中身が見えるコンテナ」に合わせ、先頭最大4件のアプリアイコンを2×2で縮小表示するフォルダータイルです。
    // 内部プレビューは共通iconAreaへ収め、通常アプリとlabelAreaの開始位置を揃えます。
    func pinnedFolderTile(_ folder: PinnedEntry) -> some View {
        let previewEntries = Array((folder.children ?? []).prefix(4))
        return VStack(spacing: Layout.pinnedTileSpacing) {
            // 元の56ptフォルダー枠を維持し、Y方向は常に上端へ固定します。
            VStack(spacing: 0) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 2), spacing: 4) {
                    ForEach(previewEntries) { child in
                        Image(nsImage: PinnedIconCache.image(for: child.path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    }
                }
                // Grid全体を40ptへ固定し、件数に関係なく上端へ配置します。
                .frame(height: 40, alignment: .top)
            }
            // 18ptアイコンなら4件でも2×2が40ptへ収まり、親フォルダー枠を押し広げません。
            .frame(width: 40, height: 40)
            .padding(8)
            .frame(width: Layout.pinnedIconAreaHeight, height: Layout.pinnedIconAreaHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(settingsModel.settings.selectAppListRowOnPointerHover && folderDropCandidateID == folder.id ? hoverFill : Color.primary.opacity(0.10))
            )
            Text(folder.folderName?.isEmpty == false ? folder.folderName! : L10n.pinnedNewFolderName)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(width: Layout.pinnedTileWidth, height: Layout.pinnedLabelAreaHeight, alignment: .center)
        }
        .frame(width: Layout.pinnedTileWidth, height: Layout.pinnedTileHeight)
        .contentShape(Rectangle())
        // 通常アプリタイルと同じ共通hover状態を使い、名前と透明余白を含むタイル全体を反応範囲にします。
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    ((settingsModel.settings.selectAppListRowOnPointerHover && pinnedDragContext?.entryID == folder.id) || (settingsModel.settings.selectAppListRowOnPointerHover && (hoveredPinnedID == folder.id || folderDropCandidateID == folder.id)))
                    ? hoverFill : Color.clear
                )
        )
        .onHover { hovering in
            // 自身のドラッグ中は既存のドラッグ表示を優先し、通常hoverを上書きしません。
            guard pinnedDragContext?.entryID != folder.id else {
                hoveredPinnedID = nil
                return
            }
            // 設定OFFでは、ピン留めフォルダーも通常のポインターhover色を表示しません。
            guard settingsModel.settings.selectAppListRowOnPointerHover else { return }
            // 遅れて届いた別タイルの離脱イベントで、現在のhover対象を消さないようにします。
            if hovering {
                hoveredPinnedID = folder.id
            } else if hoveredPinnedID == folder.id {
                hoveredPinnedID = nil
            }
        }
        .onTapGesture { openFolder(folder) }
        // P6-Bではフォルダーも最上位の並べ替え対象です。展開パネル内の子はここへ到達しません。
        .onDrag {
            beginPinnedDrag(entryID: folder.id, origin: .topLevel)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: PinnedAppDropDelegate(
                targetID: folder.id,
                dragIdentity: pinnedDragContext?.identity,
                dragContext: $pinnedDragContext,
                hoveredID: $hoveredPinnedID,
                pinnedConfig: $pinnedConfig,
                animationsEnabled: animationsEnabled,
                save: savePinnedCandidate,
                snapshot: $pinnedDragSnapshot,
                folderCandidateID: $folderDropCandidateID,
                targetKind: folder.kind,
                finalizeFolderDrop: finalizeTopLevelFolderDrop,
                folderCandidateWorkItem: $folderCandidateWorkItem,
                folderID: nil,
                sourceFolderID: pinnedDragContext?.origin.folderID
            )
        )
        .contextMenu { pinnedFolderContextMenu(folder) }
        // タイル自身の中心を、親のピン留め欄座標系で送ります。見た目を変えない透明背景を使います。
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PinnedFolderTileCenterPreferenceKey.self,
                    value: [folder.id: proxy.frame(in: .named("pinnedArea")).midY]
                )
            }
        )
        .accessibilityLabel(folder.folderName?.isEmpty == false ? folder.folderName! : L10n.pinnedNewFolderName)
    }

    // 展開カードの高さを、列数設定と子アプリ数から副作用なく計算します。
    // 同じ値を描画とY方向クランプで共有し、見た目の高さと安全余白の計算がずれないようにします。
    func folderOverlayHeight(_ folder: PinnedEntry, availableSize: CGSize) -> CGFloat {
        let safeMargin: CGFloat = 30
        let columnCount = min(6, max(3, settingsModel.settings.pinnedFolderColumnCount))
        let childCount = folder.children?.count ?? 0
        let visibleRows = max(1, min(4, Int(ceil(Double(min(childCount, 16)) / Double(columnCount)))))
        let preferredHeight = 64 + CGFloat(visibleRows) * Layout.pinnedTileHeight + CGFloat(max(0, visibleRows - 1)) * Layout.pinnedGridSpacing + 20
        let maximumHeight = max(180, availableSize.height - safeMargin * 2)
        return min(maximumHeight, max(210, preferredHeight))
    }

    // 展開パネルはピン領域内に留め、一覧領域やStartMenuの外へはみ出させません。
    // 子アイコンはページ相当のまとまりを縦に連続配置するため、macOS標準のホイール／トラックパッドで自由に縦スクロールできます。
    func pinnedFolderOverlay(_ folder: PinnedEntry, availableSize: CGSize) -> some View {
        // 30ptは従来の12ptの2.5倍です。小さな画面では親領域を超えないよう、同じ値を最大高さ計算にも使います。
        let outerMargin: CGFloat = 30
        // 展開パネルはWindows 11風の4列を基準にします。親GeometryReaderの提案幅へ列数を委ねると、
        // レイアウト途中の0に近い幅で1列と計算され、少数アプリでも不必要に縦長になる問題がありました。
        let columnCount = min(6, max(3, settingsModel.settings.pinnedFolderColumnCount))
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: Layout.pinnedGridSpacing), count: columnCount)
        let overlayHeight = folderOverlayHeight(folder, availableSize: availableSize)
        return VStack(spacing: 12) {
            HStack {
                Spacer()
                if isEditingFolderName {
                    TextField("", text: $folderNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .multilineTextAlignment(.center)
                        .focused($isFolderNameFocused)
                        // onCommitだけに依存せず、macOS SwiftUIのsubmitイベントでも保存します。
                        .onSubmit(of: .text) {
                            if suppressNextFolderNameSubmit {
                                suppressNextFolderNameSubmit = false
                            } else {
                                commitFolderName()
                            }
                        }
                        // ReturnはIMEの変換確定を含むため、onKeyPressで横取りしません。
                        // AppKitのフィールドエディターへ渡し、変換完了後にonSubmitだけで保存します。
                        .onAppear { isFolderNameFocused = true }
                } else {
                    Text(folder.folderName?.isEmpty == false ? folder.folderName! : L10n.pinnedNewFolderName)
                        .font(.headline)
                        .onTapGesture { beginFolderNameEditing(folder) }
                }
                Spacer()
                Button(action: closeOpenedFolder) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.pinnedFolderClose)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            ScrollView {
                // 16件ずつを視覚的なページとして縦に分けます。ページ間の余白により、自由スクロール中も境界を見失いません。
                let pages = Array((folder.children ?? []).chunked(into: 16))
                LazyVStack(spacing: 18) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, page in
                        LazyVGrid(columns: gridColumns, alignment: .center, spacing: Layout.pinnedGridSpacing) {
                            ForEach(page) { child in
                                pinnedAppTile(makePinnedApp(from: child), folderID: folder.id)
                            }
                        }
                        if pages.count > 1 {
                            Text(String(format: L10n.pinnedFolderPage, pageIndex + 1, pages.count))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        // 行数で決めた高さだけを使うため、1行なら小さく、5行以上なら上限で止めてスクロールへ切り替わります。
        // GeometryReader全体を埋めず、外側30ptを引いた実寸カードに固定します。
        .frame(width: max(1, availableSize.width - outerMargin * 2), height: overlayHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    // ピン留めアプリ1件分の、アイコン・名前・操作・ドラッグ機能を持つタイルを作ります。
    func pinnedAppTile(_ pinnedApp: PinnedApp, folderID: UUID? = nil) -> some View {
        // アイコンと名前を縦方向に並べます。
        VStack(spacing: Layout.pinnedTileSpacing) {
            // アプリのNSImageアイコンを表示します。
            Image(nsImage: pinnedApp.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Layout.pinnedIconSize, height: Layout.pinnedIconSize)
                .frame(width: Layout.pinnedIconAreaHeight, height: Layout.pinnedIconAreaHeight, alignment: .center)
            
            // アイコンの下へアプリ名を最大2行で表示します。
            Text(pinnedApp.name)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Layout.pinnedTileWidth, height: Layout.pinnedLabelAreaHeight, alignment: .center)
        }
        // すべてのタイルを同じ固定サイズにそろえます。
        .frame(width: Layout.pinnedTileWidth, height: Layout.pinnedTileHeight)
        // タイル内の透明部分も操作対象にします。
        .contentShape(Rectangle())
        // ドラッグ中またはhover中だけ、薄い角丸背景を表示します。
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    ((settingsModel.settings.selectAppListRowOnPointerHover && pinnedDragContext?.entryID == pinnedApp.entry.id) || (settingsModel.settings.selectAppListRowOnPointerHover && (hoveredPinnedID == pinnedApp.entry.id || folderDropCandidateID == pinnedApp.entry.id)))
                    ? hoverFill : Color.clear
                )
        )
        // 壊れたピンは警告色だけに依存せず、標準警告シンボルと状態文を重ねて明示します。
        // 固定グリッド寸法と名前の2行領域は変えず、通常タイルとのレイアウト差を作りません。
        .overlay(alignment: .bottom) {
            if !pinnedApp.isAvailable {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(L10n.pinnedAppNotFound)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .accessibilityHidden(true)
            }
        }
        // 自身をドラッグしている間は半透明にして、移動元を視覚的に示します。
        .opacity(pinnedDragContext?.entryID == pinnedApp.entry.id ? 0.4 : (pinnedApp.isAvailable ? 1.0 : 0.62))
        // ポインターの出入りに応じてhover対象を更新します。
        .onHover { hovering in
            // 自分自身をドラッグ中ならhover表示を出さず終了します。
            guard pinnedDragContext?.entryID != pinnedApp.entry.id else {
                hoveredPinnedID = nil
                return
            }
            // 設定OFFでは、ピン留めアプリも通常のポインターhover色を表示しません。
            guard settingsModel.settings.selectAppListRowOnPointerHover else { return }
            // 入ったときはパスを保存し、離れたときはnilにします。
            hoveredPinnedID = hovering ? pinnedApp.entry.id : nil
        }
        // 壊れたピンのクリックは何も起動せず、パネルも閉じません。存在する場合もopenApp側で直前に再確認します。
        .onTapGesture {
            guard pinnedApp.isAvailable else { return }
            openApp(at: pinnedApp.entry.path)
        }
        // タイルを別位置へドラッグ可能にします。
        .onDrag {
            beginPinnedDrag(
                entryID: pinnedApp.entry.id,
                origin: folderID.map(PinnedDragOrigin.folder) ?? .topLevel
            )
        }
        // 別タイルがここへ入った際の並べ替え処理を専用Delegateへ任せます。
        .onDrop(
            of: [UTType.plainText],
            delegate: PinnedAppDropDelegate(
                targetID: pinnedApp.entry.id,
                dragIdentity: pinnedDragContext?.identity,
                dragContext: $pinnedDragContext,
                hoveredID: $hoveredPinnedID,
                pinnedConfig: $pinnedConfig,
                animationsEnabled: animationsEnabled,
                save: savePinnedCandidate,
                snapshot: $pinnedDragSnapshot,
                folderCandidateID: $folderDropCandidateID,
                targetKind: pinnedApp.entry.kind,
                finalizeFolderDrop: finalizeTopLevelFolderDrop,
                folderCandidateWorkItem: $folderCandidateWorkItem,
                folderID: folderID,
                sourceFolderID: pinnedDragContext?.origin.folderID
            )
        )
        // 右クリックではFinder表示と解除を分け、壊れたピンでも解除だけは可能にします。
        .contextMenu {
            if let folderID {
                folderChildContextMenu(pinnedApp.entry, folderID: folderID)
            } else {
                pinnedAppContextMenu(for: pinnedApp)
            }
        }
        // VoiceOverでは状態文と、解除可能であることを名前に続けて伝えます。
        .accessibilityLabel(pinnedApp.isAvailable
            ? pinnedApp.name
            : "\(pinnedApp.name)。\(L10n.pinnedAppNotFoundAccessibility)")
    }
    
    // 指定したアプリが現在のピン配列に含まれているかをパスで判定します。
    func isPinned(_ app: AppItem) -> Bool {
        // 最上位とすべてのフォルダー内を確認し、同一アプリを複数箇所へ重複登録しません。
        pinnedConfig.items.contains { entry in
            entry.path == app.path || (entry.children ?? []).contains(where: { $0.path == app.path })
        }
    }
    
    // 未登録のアプリをピン留め配列の末尾へ追加します。
    func pin(_ app: AppItem) {
        // 二重登録を防ぐため、登録済みなら何もしません。
        guard !isPinned(app) else { return }
        
        // アプリパスをBundle初期化で扱えるfile URLへ変換します。
        let url = URL(fileURLWithPath: app.path)
        // アプリパッケージのInfo.plistからBundle Identifierを取得します。
        let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        // 永続化に必要なピン情報を作ります。表示名の上書きは現在未設定です。
        let entry = PinnedEntry(
            path: app.path,
            bundleIdentifier: bundleIdentifier,
            displayName: nil
        )
        
        // 純粋変換のcandidateを1回だけ保存し、成功後にだけ画面へ反映します。
        guard let candidate = PinnedConfigTransform.pin(entry, in: pinnedConfig) else { return }
        _ = savePinnedCandidate(candidate)
    }
    
    // 指定パスに一致するピン留め項目をすべて削除します。
    func unpin(id: UUID) {
        guard let candidate = PinnedConfigTransform.unpin(id, from: pinnedConfig) else { return }
        _ = savePinnedCandidate(candidate)
    }

    // アプリ一覧の「ピン留め解除」用です。最上位だけでなく全フォルダーの子を探索して1件だけ除去します。
    // 最後の子を失ったフォルダーは保存しないP6-A規則に従って削除し、展開中なら同時に閉じます。
    func unpinApp(at path: String) {
        guard let result = PinnedConfigTransform.unpinApp(at: path, from: pinnedConfig),
              savePinnedCandidate(result.config) else { return }
        if let removedFolderID = result.removedFolderID, openedFolderID == removedFolderID { closeOpenedFolder() }
    }

    // 最上位アプリ1件を、その位置のまま最初の子としてフォルダー化します。
    // 空フォルダーを作らないので、保存中断や再起動後に用途不明のタイルだけが残りません。
    func createFolder(containingTopLevelApp id: UUID) {
        guard let result = PinnedConfigTransform.createFolder(containingTopLevelApp: id, folderID: UUID(), named: L10n.pinnedNewFolderName, in: pinnedConfig),
              savePinnedCandidate(result.config) else { return }
        openFolder(result.folder)
        beginFolderNameEditing(result.folder)
    }

    // 明示した既存フォルダーへ最上位アプリを移し、移動元だけを最上位配列から除去します。
    // 事前に子内重複も確認し、壊れたJSONや連続クリックで同じアプリを二重保存しません。
    func moveTopLevelApp(id: UUID, toFolder folderID: UUID) {
        guard let candidate = PinnedConfigTransform.moveTopLevelApp(id, toFolder: folderID, in: pinnedConfig) else { return }
        _ = savePinnedCandidate(candidate)
    }

    // フォルダー内アプリを、フォルダーがある最上位位置の直後へ戻します。子の相対順序は残った配列で維持します。
    func extractChild(id: UUID, fromFolder folderID: UUID) {
        guard let candidate = PinnedConfigTransform.extractChild(id, fromFolder: folderID, immediatelyAfterFolder: true, config: pinnedConfig) else { return }
        let removesFolder = !candidate.items.contains(where: { $0.id == folderID })
        guard savePinnedCandidate(candidate) else { return }
        if removesFolder { closeOpenedFolder() }
    }

    // フォルダーを解除すると、子アプリをフォルダーが占めていた位置へ同順で展開します。
    func dissolveFolder(id: UUID) {
        guard let candidate = PinnedConfigTransform.dissolveFolder(id, in: pinnedConfig) else { return }
        guard savePinnedCandidate(candidate) else { return }
        closeOpenedFolder()
    }

    // 展開開始時に保存済み名称を下書きへ複製し、編集のキャンセルが永続値へ漏れないようにします。
    func openFolder(_ folder: PinnedEntry) {
        withAnimation(animationsEnabled ? .easeInOut(duration: 0.18) : nil) {
            folderOverlayState.open(folderID: folder.id, originY: pinnedFolderTileCenterY[folder.id])
            isEditingFolderName = false
            folderNameDraft = folder.folderName?.isEmpty == false ? folder.folderName! : L10n.pinnedNewFolderName
        }
    }

    func closeOpenedFolder() {
        isEditingFolderName = false
        isFolderNameFocused = false
        editingFolderID = nil
        NotificationCenter.default.post(name: .startMenuFolderNameEditingEnded, object: nil)
        withAnimation(animationsEnabled ? .easeInOut(duration: 0.18) : nil) {
            folderOverlayState.close()
        }
    }

    func beginFolderNameEditing(_ folder: PinnedEntry) {
        folderNameDraft = folder.folderName?.isEmpty == false ? folder.folderName! : L10n.pinnedNewFolderName
        editingFolderID = folder.id
        isEditingFolderName = true
        NotificationCenter.default.post(name: .startMenuFolderNameEditingBegan, object: nil)
        // TextField生成後にフォーカスを要求し、クリック編集と右クリック編集の両方を統一します。
        DispatchQueue.main.async { isFolderNameFocused = true }
    }

    // 前後空白を除いた空文字は保存せず、元の名称のまま編集だけ閉じます。過度に長い名称も256文字で上限を設けます。
    func commitFolderName() {
        let name = String(folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        guard !name.isEmpty,
              let editingFolderID,
              let candidate = PinnedConfigTransform.renameFolder(editingFolderID, to: name, in: pinnedConfig) else {
            isEditingFolderName = false
            return
        }
        // 保存成功まで名称・編集状態を変更せず、失敗時に保存済みに見える状態を残しません。
        guard savePinnedCandidate(candidate) else { return }
        isEditingFolderName = false
        isFolderNameFocused = false
        self.editingFolderID = nil
        NotificationCenter.default.post(name: .startMenuFolderNameEditingEnded, object: nil)
    }

    // candidateを保存し、成功した場合だけ画面へコミットします。失敗理由はStoreのログへ残します。
    func savePinnedCandidate(_ candidate: PinnedConfig) -> Bool {
        persistPinnedCandidate(candidate, reportFailure: true)
    }

    private func loadPinnedConfiguration() {
        let pinnedLoad = PinnedStore.loadResult()
        pinnedConfig = pinnedLoad.config
        pinnedPersistenceWriteProtected = pinnedLoad.issue?.allowsOverwrite == false
        var loadMessage: String?
        switch pinnedLoad.issue {
        case .unreadablePreserved(let backupURL):
            loadMessage = String(format: L10n.pinnedLoadUnreadablePreserved, backupURL.lastPathComponent)
        case .unreadableUnpreserved:
            loadMessage = L10n.pinnedLoadUnreadableUnpreserved
        case nil:
            loadMessage = nil
        }
        pinnedPersistenceErrorMessage = loadMessage
        pinnedPersistenceWriteProtectionMessage = pinnedPersistenceWriteProtected ? loadMessage : nil
        seedDefaultPinsIfNeeded(loadState: pinnedLoad.state)
    }

    // 自動復旧などユーザー操作ではない保存失敗は、画面へ割り込み通知を出さず再走査へ委ねます。
    private func persistPinnedCandidate(_ candidate: PinnedConfig, reportFailure: Bool) -> Bool {
        guard !pinnedPersistenceWriteProtected else {
            pinnedPersistenceErrorMessage = pinnedPersistenceWriteProtectionMessage
            return false
        }
        let committed = PersistenceCommit.save(
            candidate,
            persist: { value in PinnedStore.save(value) },
            publish: { pinnedConfig = $0 }
        )
        guard committed else {
            if reportFailure { pinnedPersistenceErrorMessage = L10n.pinnedSaveFailed }
            return false
        }
        if reportFailure { pinnedPersistenceErrorMessage = nil }
        return true
    }

    // P8-Aの候補をBundle IDだけで解決し、安全な実在.appだけを初回に追加します。
    // 空配列や旧settingsだけを初回とみなさず、pinned.jsonがmissingであることを必須にします。
    func seedDefaultPinsIfNeeded(loadState: PinnedStore.LoadState) {
        guard !didEvaluateDefaultPinSeed else { return }
        didEvaluateDefaultPinSeed = true
        guard settingsModel.settings.didSeedDefaultPins != true, loadState == .missing else { return }

        let candidates: [(String, String)] = [
            ("com.apple.Safari", "Safari"),
            ("com.apple.AppStore", "App Store"),
            ("com.apple.finder", "Finder"),
            ("com.apple.systempreferences", "システム設定")
        ]
        let resolved: [PinnedEntry] = candidates.compactMap { bundleID, fallbackName in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  url.pathExtension.lowercased() == "app",
                  FileManager.default.fileExists(atPath: url.path),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let bundle = Bundle(url: url), bundle.bundleIdentifier == bundleID else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? fallbackName
            return PinnedEntry(path: url.path, bundleIdentifier: bundleID, displayName: name)
        }
        _ = DefaultPinSeedPolicy.seedIfNeeded(
            loadState: loadState,
            alreadySeeded: settingsModel.settings.didSeedDefaultPins == true,
            candidates: resolved,
            persistPins: { self.savePinnedCandidate($0) },
            markSeeded: { _ = settingsModel.updateSettings { $0.didSeedDefaultPins = true } }
        )
    }

    // P6-Bのドロップ確定処理です。アプリ同士なら対象を先、ドラッグ元を後にした新規フォルダーを作り、
    // 既存フォルダーならドラッグ元アプリを子配列末尾へ追加します。候補中は呼ばれず、保存はここで一度だけ行います。
    func finalizeTopLevelFolderDrop(draggedID: UUID, targetID: UUID) -> Bool {
        guard let targetIndex = pinnedConfig.items.firstIndex(where: { $0.id == targetID }),
              let draggedIndex = pinnedConfig.items.firstIndex(where: { $0.id == draggedID }),
              draggedID != targetID,
              pinnedConfig.items[draggedIndex].kind == .application else { return false }
        var candidate = pinnedConfig
        if candidate.items[targetIndex].kind == .folder {
            let dragged = candidate.items[draggedIndex]
            guard !(candidate.items[targetIndex].children ?? []).contains(where: { $0.path == dragged.path }) else { return false }
            candidate.items.remove(at: draggedIndex)
            let adjustedTarget = draggedIndex < targetIndex ? targetIndex - 1 : targetIndex
            candidate.items[adjustedTarget].children = (candidate.items[adjustedTarget].children ?? []) + [dragged]
        } else {
            guard let transformed = PinnedConfigTransform.createFolder(
                from: draggedID, targetID: targetID, folderID: UUID(), named: L10n.pinnedNewFolderName, in: candidate
            ) else { return false }
            candidate = transformed
        }
        return savePinnedCandidate(candidate)
    }

    private func successfulApplicationScanDidChange(_ revision: Int) {
        guard revision > 0 else { return }
        reconcileMissingPins(using: applicationCatalog.installedApps)
    }

    // 最新走査済みアプリだけをBundle ID完全一致で照合し、missingピンを安全に自動復旧します。
    // 候補なし・IDなし・複数候補・別ピン使用中は保存内容を変更しません。
    func reconcileMissingPins(using apps: [AppItem]) {
        var index: [String: [AppItem]] = [:]
        for app in apps where canOpenApplicationPackage(at: app.path) {
            guard let id = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { continue }
            index[id, default: []].append(app)
        }
        let entries = pinnedConfig.items.flatMap { item in item.isFolder ? (item.children ?? []) : [item] }
        let missingEntryIDs = Set(entries
            .filter { $0.kind == .application && !canOpenApplicationPackage(at: $0.path) }
            .map(\.id))
        let transformed = PinnedConfigTransform.reconcileMissingPins(in: pinnedConfig, missingEntryIDs: missingEntryIDs, candidatesByBundleID: index)
        if transformed.changed, !persistPinnedCandidate(transformed.config, reportFailure: false) {
            // 自動復旧が保存できなかった場合は、未保存のcandidateを候補表示へ混ぜません。
            recoveryCandidates = [:]
            return
        }
        let committedPaths = PinnedRecoveryTransform.applicationPaths(in: pinnedConfig)
        recoveryCandidates = transformed.multipleCandidates.mapValues { candidates in
            candidates.filter { !committedPaths.contains($0.path) }
        }.filter { !$0.value.isEmpty }
    }

    // 利用者が複数候補から選んだ直前に、存在・Bundle ID・他ピン使用を再確認して1件だけ復旧します。
    func recoverPinnedApp(id: UUID, with candidate: AppItem) {
        guard recoveryCandidates[id]?.contains(where: { $0.path == candidate.path && $0.bundleIdentifier == candidate.bundleIdentifier }) == true,
              canOpenApplicationPackage(at: candidate.path),
              let candidateConfig = PinnedConfigTransform.replacingPath(for: id, with: candidate.path, in: pinnedConfig),
              let recoveredEntry = candidateConfig.items
                  .flatMap({ item in item.isFolder ? (item.children ?? []) : [item] })
                  .first(where: { $0.id == id }),
              recoveredEntry.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) == candidate.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              candidate.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              !PinnedRecoveryTransform.applicationPaths(in: candidateConfig, excluding: id).contains(candidate.path) else { return }
        guard savePinnedCandidate(candidateConfig) else { return }
        recoveryCandidates[id] = nil
    }

    // 候補名が同じ場合も判別できるよう、末尾3階層だけを右クリックメニューへ添えます。
    func shortPath(_ path: String) -> String { URL(fileURLWithPath: path).pathComponents.suffix(3).joined(separator: "/") }

    // Finderで安全に選択表示できる、現在存在する.appパッケージかを確認します。
    // メニューの有効／無効判定と実行直前の最終確認で共用し、判定規則を一か所に固定します。
    func canRevealInFinder(at path: String) -> Bool {
        // P4-Aのピン表示・起動と共通の関数を使い、Finderだけ異なる判定になることを防ぎます。
        canOpenApplicationPackage(at: path)
    }

    // 指定された実体アプリをFinderで選択状態にして表示します。
    // メニューを開いた後に削除・移動される可能性があるため、パネルを閉じる前に必ず有効性を再確認します。
    func revealInFinder(at path: String) {
        guard canRevealInFinder(at: path) else {
            // 失敗は通常「実行直前に移動・削除された」状態なので、画面状態を変えずログだけを残します。
            NSLog("Cannot reveal a missing or invalid app in Finder: \(path)")
            return
        }
        // P0で統合済みの共通処理を使い、Finderへ移る前にパネルと本体を一貫して非表示にします。
        (NSApp.delegate as? AppDelegate)?.hidePanelAndApplication(hideReason: .finderReveal)
        // P2で確定した実体パスをURLへ変換し、Finderを前面にして対象.appを選択させます。
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    
    // 指定した.appをmacOS標準機能で起動し、スタートメニューを隠します。
    func openApp(at path: String) {
        // メニューを開いた後やタイルを押した直前に削除されても、診断・非表示・起動要求へ進ませません。
        guard canOpenApplicationPackage(at: path) else {
            NSLog("Cannot launch a missing or invalid app package: \(path)")
            return
        }
        // フォルダー内から起動した場合も、パネル非表示より先に展開状態を解除し、次回表示へ持ち越しません。
        closeOpenedFolder()
        // 文字列パスを、アプリ起動に使えるfile URLへ変換します。
        let appURL = URL(fileURLWithPath: path)
        // A7の最小診断を、実際の起動要求より先に1件だけ上書き保存します。
        LaunchDiagnosticModel.shared.recordLaunch(of: appURL)
        // A7-Bでは、汎用URLオープンではなく「この.appを起動する」意図を明示する公開APIを使います。
        // 環境変数・追加引数・権限回避設定は渡さず、既存と同じ通常起動だけを要求します。
        let configuration = NSWorkspace.OpenConfiguration()
        PanelLaunchOrdering.launchThenClose(
            launch: {
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                    // 完了通知は並行キューで届くため、UIを変更せず失敗理由だけを診断用ログへ残します。
                    if let error { NSLog("Failed to launch app with application-specific API: \(error.localizedDescription)") }
                }
            },
            close: {
                // 起動要求を発行した直後、完了通知を待たずにStartMenuを隠します。
                (NSApp.delegate as? AppDelegate)?.closePanelAnimated(andHideApp: true, hideReason: .appLaunch)
            }
        )
    }
}

// P6-Aの展開パネル内で、固定上限のアイコン群を縦方向のページ単位へ分割する補助です。
// 空配列は空ページを作らず、最終ページは不足枠を詰めずにLazyVGridへ渡します。
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// ピン留めタイル間のドラッグ＆ドロップによる並べ替えを処理するDelegateです。
private struct PinnedAppDropDelegate: DropDelegate {
    // 現在ドロップ先になっているタイルの内部識別子です。
    let targetID: UUID
    let dragIdentity: PinnedDragSessionIdentity?
    @Binding var dragContext: PinnedDragContext?
    // ContentViewが持つhover先の内部識別子を双方向で参照します。
    @Binding var hoveredID: UUID?
    // 並べ替えるピン設定配列そのものへの双方向参照です。
    @Binding var pinnedConfig: PinnedConfig
    let animationsEnabled: Bool
    // 並べ替え結果を永続化するため、呼び出し元から渡される関数です。
    let save: (PinnedConfig) -> Bool
    @Binding var snapshot: PinnedDragSnapshot?
    @Binding var folderCandidateID: UUID?
    let targetKind: PinnedEntryKind
    let finalizeFolderDrop: (UUID, UUID) -> Bool
    @Binding var folderCandidateWorkItem: DispatchWorkItem?
    let folderID: UUID?
    let sourceFolderID: UUID?

    private var isCurrentSession: Bool {
        guard let dragIdentity else { return false }
        return $dragContext.wrappedValue?.identity == dragIdentity
    }

    private func resetTransientState(for identity: PinnedDragSessionIdentity) {
        guard $dragContext.wrappedValue?.identity == identity else { return }
        if $snapshot.wrappedValue?.identity == identity { $snapshot.wrappedValue = nil }
        folderCandidateID = nil
        folderCandidateWorkItem?.cancel()
        folderCandidateWorkItem = nil
        $dragContext.wrappedValue = nil
        hoveredID = nil
    }

    private func rollbackAndReset(for identity: PinnedDragSessionIdentity) {
        guard $dragContext.wrappedValue?.identity == identity else { return }
        if let snapshot = $snapshot.wrappedValue, snapshot.identity == identity {
            pinnedConfig = snapshot.config
        }
        resetTransientState(for: identity)
    }

    @discardableResult
    private func updateFolderCandidate(info: DropInfo) -> Bool {
        guard isCurrentSession,
              let dragIdentity,
              folderID == nil,
              dragIdentity.entryID != targetID,
              pinnedConfig.items.contains(where: { $0.id == dragIdentity.entryID && $0.kind == .application }),
              targetKind == .application || targetKind == .folder,
              PinnedFolderDropHitRegion.contains(info.location) else {
            if folderCandidateID == targetID { folderCandidateID = nil }
            folderCandidateWorkItem?.cancel()
            folderCandidateWorkItem = nil
            return false
        }
        if folderCandidateWorkItem != nil || folderCandidateID == targetID { return true }
        let candidate = DispatchWorkItem {
            guard self.$dragContext.wrappedValue?.identity == dragIdentity else { return }
            self.folderCandidateID = self.targetID
        }
        folderCandidateWorkItem = candidate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: candidate)
        return true
    }

    // ドラッグ項目がこのタイルの領域へ入った瞬間に呼ばれます。
    func dropEntered(info: DropInfo) {
        guard isCurrentSession, let draggedID = dragIdentity?.entryID else { return }
        // 実際にドラッグ元がある場合だけ、このタイルをhover表示にします。
        hoveredID = targetID

        // フォルダー内は子配列だけを対象にし、中央hoverのフォルダー化を行いません。
        if let folderID,
           sourceFolderID == folderID,
           draggedID != targetID,
           let candidate = PinnedConfigTransform.moveChild(draggedID, inFolder: folderID, to: targetID, config: pinnedConfig) {
            withAnimation(animationsEnabled ? .spring(response: 0.3, dampingFraction: 0.8) : nil) {
                pinnedConfig = candidate
            }
            folderCandidateID = nil
            return
        }

        // 中央へ入ったアプリだけをフォルダー化候補にします。外縁は既存の並べ替えとして扱います。
        if updateFolderCandidate(info: info) { return }
        folderCandidateWorkItem?.cancel()
        folderCandidateWorkItem = nil
        folderCandidateID = nil

        // 移動元・移動先が有効かつ別項目なら、既存順序を値変換してから画面へ反映します。
        guard let candidate = PinnedConfigTransform.moveTopLevel(draggedID, to: targetID, config: pinnedConfig) else {
            return
        }

        // 配列の並べ替えを、A12の設定に従うバネアニメーションとともに画面へ反映します。
        withAnimation(animationsEnabled ? .spring(response: 0.3, dampingFraction: 0.8) : nil) {
            pinnedConfig = candidate
        }
    }

    // ドラッグ項目がこのタイル領域から外れた際に呼ばれます。
    func dropExited(info: DropInfo) {
        guard isCurrentSession else { return }
        // 現在のhover先が自分なら、hover状態を解除します。
        if hoveredID == targetID {
            hoveredID = nil
        }
        if folderCandidateID == targetID { folderCandidateID = nil }
        folderCandidateWorkItem?.cancel()
        folderCandidateWorkItem = nil
    }

    // ドラッグ中の操作種別を「移動」としてシステムへ提示します。
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isCurrentSession else { return nil }
        _ = updateFolderCandidate(info: info)
        return DropProposal(operation: .move)
    }

    // ユーザーがドロップを完了した際に呼ばれ、最終状態を保存します。
    func performDrop(info: DropInfo) -> Bool {
        guard let identity = dragIdentity,
              $dragContext.wrappedValue?.identity == identity,
              $snapshot.wrappedValue?.identity == identity else { return false }
        // プレーンテキスト形式を提供する最初のドラッグ項目を取得します。
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            rollbackAndReset(for: identity)
            return false
        }
        
        // 非同期callbackまでの間に候補時間が経過しても、drop時点のユーザー意図を維持します。
        let candidateID = folderCandidateID
        // providerからNSStringを非同期に読み込み、その完了コールバック内で後処理します。
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            // SwiftUI状態の変更と保存をメインキューで行います。
            DispatchQueue.main.async {
                let activeIdentity = self.$dragContext.wrappedValue?.identity
                switch PinnedDragCallbackGate.evaluate(
                    providerIdentifier: object as? String,
                    expected: identity,
                    active: activeIdentity
                ) {
                case .staleSession:
                    // cancelまたは別drag開始後のcallbackは、新しいsession stateへ触れません。
                    return
                case .rejectedProvider:
                    guard self.$snapshot.wrappedValue?.identity == identity else { return }
                    self.rollbackAndReset(for: identity)
                    return
                case .accepted:
                    guard self.$snapshot.wrappedValue?.identity == identity else { return }
                }
                if let sourceFolderID = self.sourceFolderID, self.folderID == nil {
                    guard let candidate = PinnedConfigTransform.extractChild(
                        identity.entryID,
                        fromFolder: sourceFolderID,
                        beforeTopLevelID: self.targetID,
                        config: self.pinnedConfig
                    ), self.save(candidate) else {
                        self.rollbackAndReset(for: identity)
                        return
                    }
                } else if let candidateID, candidateID == self.targetID {
                    guard self.finalizeFolderDrop(identity.entryID, candidateID) else {
                        self.rollbackAndReset(for: identity)
                        return
                    }
                } else {
                    // 外縁で確定した仮配置だけを一度保存します。
                    guard self.save(self.pinnedConfig) else {
                        self.rollbackAndReset(for: identity)
                        return
                    }
                }
                self.resetTransientState(for: identity)
            }
        }
        // ドロップ要求を受理したことを即座に返します。
        return true
    }
}

private struct PinnedFolderAreaDropDelegate: DropDelegate {
    let dragIdentity: PinnedDragSessionIdentity?
    @Binding var dragContext: PinnedDragContext?
    let sourceFolderID: UUID?
    @Binding var pinnedConfig: PinnedConfig
    @Binding var snapshot: PinnedDragSnapshot?
    let save: (PinnedConfig) -> Bool
    @Binding var hoveredID: UUID?
    @Binding var folderCandidateID: UUID?
    @Binding var folderCandidateWorkItem: DispatchWorkItem?

    private var isCurrentSession: Bool {
        guard let dragIdentity else { return false }
        return $dragContext.wrappedValue?.identity == dragIdentity
    }

    private func resetTransientState(for identity: PinnedDragSessionIdentity) {
        guard $dragContext.wrappedValue?.identity == identity else { return }
        if $snapshot.wrappedValue?.identity == identity { $snapshot.wrappedValue = nil }
        $dragContext.wrappedValue = nil
        hoveredID = nil
        folderCandidateID = nil
        folderCandidateWorkItem?.cancel()
        folderCandidateWorkItem = nil
    }

    private func rollbackAndReset(for identity: PinnedDragSessionIdentity) {
        guard $dragContext.wrappedValue?.identity == identity else { return }
        if let snapshot = $snapshot.wrappedValue, snapshot.identity == identity {
            pinnedConfig = snapshot.config
        }
        resetTransientState(for: identity)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isCurrentSession else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let identity = dragIdentity,
              $dragContext.wrappedValue?.identity == identity,
              $snapshot.wrappedValue?.identity == identity else { return false }
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            rollbackAndReset(for: identity)
            return false
        }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            DispatchQueue.main.async {
                let activeIdentity = self.$dragContext.wrappedValue?.identity
                switch PinnedDragCallbackGate.evaluate(
                    providerIdentifier: object as? String,
                    expected: identity,
                    active: activeIdentity
                ) {
                case .staleSession:
                    return
                case .rejectedProvider:
                    guard self.$snapshot.wrappedValue?.identity == identity else { return }
                    self.rollbackAndReset(for: identity)
                    return
                case .accepted:
                    guard self.$snapshot.wrappedValue?.identity == identity else { return }
                }
                guard let sourceFolderID = self.sourceFolderID,
                      let candidate = PinnedConfigTransform.extractChild(
                    identity.entryID,
                    fromFolder: sourceFolderID,
                    beforeTopLevelID: nil,
                    config: self.pinnedConfig
                ), self.save(candidate) else {
                    self.rollbackAndReset(for: identity)
                    return
                }
                self.resetTransientState(for: identity)
            }
        }
        return true
    }
}
