import AppKit
import Combine
import SwiftUI
// Escapeキーの物理キーコードを、数値の直書きではなくmacOS SDKの定数で判定するために使います。
import Carbon
// P5-Bでは、macOSが管理するログイン項目の実登録状態を取得・変更するために使います。
import ServiceManagement

// このファイルは、設定値の定義・保存・読み込みと、設定画面のUIをまとめています。
// 大きく分けて AppSettings（JSONへ保存するデータ）、AppSettingsModel（画面との橋渡し）、
// LoginItemModel（macOSのログイン項目状態）、AppSettingsStore（ファイル保存）、SettingsView（設定画面）の5層です。

// A2の各非表示条件です。UUIDにより、同じ文字列を編集しなくてもSwiftUIが行を安定して識別できます。
struct AppNameBlacklistRule: Codable, Equatable, Identifiable {
    // JSONへ永続化する一意IDです。並べ替えや有効・無効の切り替えでも同じ条件を追跡します。
    var id: UUID = UUID()
    // 利用者が入力した条件文字列です。表示用の元の表記をそのまま保持します。
    var text: String
    // falseの条件は保存したまま照合だけを停止し、後から再利用できます。
    var isEnabled: Bool = true
}

// A11のリセット対象をSettingsViewと候補生成で共有します。保存形式へは追加しません。
enum SettingsResetGroup {
    case layout, appearance, shortcut, appVisibility, all
}

enum FeatureFlags {
    // Keep Recent Files implemented, but ship it disabled until the product has a reliable source of results.
    static let recentFilesEnabled = false
}

enum GlobalShortcutRegistrationStatus: Equatable {
    case notAttempted
    case active(GlobalShortcut)
    case unavailable
}

extension AppSettings {
    // AppSettings()の既定値から指定グループだけを置き換え、他の設定と内部状態を保持します。
    func resetCandidate(for group: SettingsResetGroup) -> AppSettings {
        let defaults = AppSettings()
        var candidate = self
        switch group {
        case .layout:
            candidate.windowWidth = defaults.windowWidth
            candidate.windowHeight = defaults.windowHeight
            candidate.appListWidth = defaults.appListWidth
            candidate.pinnedFolderColumnCount = defaults.pinnedFolderColumnCount
            candidate.hidePinnedAreaWhenEmpty = defaults.hidePinnedAreaWhenEmpty
            candidate.selectAppListRowOnPointerHover = defaults.selectAppListRowOnPointerHover
        case .appearance:
            candidate.themeMode = defaults.themeMode
            candidate.appListPosition = defaults.appListPosition
            candidate.panelScreenPosition = defaults.panelScreenPosition
            candidate.animationsEnabled = defaults.animationsEnabled
            candidate.isTransparent = defaults.isTransparent
            candidate.transparentIntensity = defaults.transparentIntensity
            candidate.usesBlurEffect = defaults.usesBlurEffect
            candidate.blurEffectLevel = defaults.blurEffectLevel
            candidate.usesLiquidGlass = defaults.usesLiquidGlass
            candidate.liquidGlassIntensity = defaults.liquidGlassIntensity
        case .shortcut:
            candidate.globalShortcut = defaults.globalShortcut
        case .appVisibility:
            candidate.appNameBlacklist = defaults.appNameBlacklist
            candidate.hideDefinitelyIncompatibleApps = defaults.hideDefinitelyIncompatibleApps
            candidate.recentFilesEnabled = defaults.recentFilesEnabled
            candidate.showCoreServicesApps = defaults.showCoreServicesApps
            candidate.showFinder = defaults.showFinder
            candidate.groupAppsByCategory = defaults.groupAppsByCategory
            candidate.showAppDiscoveryFolder = defaults.showAppDiscoveryFolder
        case .all:
            let seededPins = didSeedDefaultPins
            candidate = defaults
            candidate.didSeedDefaultPins = seededPins
        }
        return candidate
    }

    #if DEBUG
    // 永続化やUIを触らず、グループ境界と既定ピン投入防止だけを検証します。
    static func runResetSelfCheck() {
        let defaults = AppSettings()
        assert(defaults.usesBlurEffect)
        assert(defaults.globalShortcut == .optionSpace)
        let encodedDefaults = try! JSONEncoder().encode(defaults)
        assert((try? JSONDecoder().decode(AppSettings.self, from: encodedDefaults)) == defaults)
        assert(AppSettings.shouldAnimate(appEnabled: true, osReduceMotion: false, swiftReduceMotion: false))
        assert(!AppSettings.shouldAnimate(appEnabled: false, osReduceMotion: false, swiftReduceMotion: false))
        assert(!AppSettings.shouldAnimate(appEnabled: true, osReduceMotion: true, swiftReduceMotion: false))
        assert(!AppSettings.shouldAnimate(appEnabled: true, osReduceMotion: false, swiftReduceMotion: true))
        var settings = AppSettings()
        settings.windowWidth = 999
        settings.themeMode = .dark
        settings.didSeedDefaultPins = true
        let layout = settings.resetCandidate(for: .layout)
        assert(layout.windowWidth == AppSettings().windowWidth)
        assert(layout.themeMode == .dark)
        let all = settings.resetCandidate(for: .all)
        assert(all.didSeedDefaultPins == true)
        let appearance = settings.resetCandidate(for: .appearance)
        assert(appearance.animationsEnabled)
        assert(!defaults.showAppDiscoveryFolder)
        var visibleFolderSetting = AppSettings()
        visibleFolderSetting.showAppDiscoveryFolder = true
        assert(!visibleFolderSetting.resetCandidate(for: .appVisibility).showAppDiscoveryFolder)
        assert(!visibleFolderSetting.resetCandidate(for: .all).showAppDiscoveryFolder)
        assert(visibleFolderSetting.resetCandidate(for: .layout).showAppDiscoveryFolder)
    }
    #endif
}

// A2の機能全体と条件配列をひとまとめにして保存する設定です。
struct AppNameBlacklistSettings: Codable, Equatable {
    // falseなら、登録済みの条件を保持したまま通常一覧の非表示を一括停止します。
    var isEnabled: Bool = true
    // 名前の部分一致に使う条件を、利用者が登録した順番で保存します。
    var rules: [AppNameBlacklistRule] = []

    // 初回と「既定値へ戻す」で使う2つの条件です。空配列は利用者の意図として尊重します。
    static let defaultValue = AppNameBlacklistSettings(rules: [
        AppNameBlacklistRule(text: "Uninstall"),
        AppNameBlacklistRule(text: "アンインストール")
    ])
}

// 条件の追加・重複判定・画面表示時の照合で共通に使う正規化です。
// 大文字小文字と全角半角を吸収し、前後の空白や改行だけの条件は空文字にします。
func normalizedBlacklistText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
}

// 現行スキーマで保存する設定値をひとまとめにしたデータ構造です。
// CodableによりJSONへ変換でき、Equatableにより変更前後の値を比較できます。
struct AppSettings: Codable, Equatable {
    static let currentVersion = 14

    // アプリ全体の配色モードを表す選択肢です。
    // StringはJSON保存時の値、CaseIterableは全選択肢の列挙、IdentifiableはSwiftUIでの識別に使います。
    enum ThemeMode: String, CaseIterable, Codable, Identifiable {
        // macOSの外観に従うモードです。
        case system
        // 常に明るい配色を使うモードです。
        case light
        // 常に暗い配色を使うモードです。
        case dark
        
        // 各caseの文字列表現を、そのまま一意な識別子として使います。
        var id: String { rawValue }
        
        // ThemeModeをSwiftUIのColorSchemeへ変換します。
        // systemだけはOSへ任せる意味でnilを返します。
        var colorScheme: ColorScheme? {
            switch self {
            case .system:
                return nil
            case .light:
                return .light
            case .dark:
                return .dark
            }
        }
    }
    
    // アプリ一覧をメニューの左右どちらへ置くかを表します。
    enum AppListPosition: String, CaseIterable, Codable, Identifiable {
        // アプリ一覧を左側へ配置します。
        case left
        // アプリ一覧を右側へ配置します。
        case right
        
        // 保存に使う文字列をSwiftUI上の識別子としても利用します。
        var id: String { rawValue }
    }
    // A8でパネル全体を対象画面のどこへ置くかを表します。AppListPositionはパネル内部の一覧位置なので別設定です。
    enum PanelScreenPosition: String, CaseIterable, Codable, Identifiable {
        case left, center, right
        var id: String { rawValue }
    }
    
    // 設定ファイル形式のバージョンです。
    var version: Int = Self.currentVersion
    // スタートメニュー全体の初期幅です。単位はSwiftUI/AppKitのポイントで、Retina画面の物理ピクセル数とは異なります。
    var windowWidth: Double = 810
    // スタートメニュー全体の初期高さです。
    var windowHeight: Double = 725
    // 左右のうちアプリ一覧側へ割り当てる幅です。
    var appListWidth: Double = 255
    // 初期テーマはmacOSの外観に追従します。
    var themeMode: ThemeMode = .system
    // 初期状態ではアプリ一覧を左側へ置きます。
    var appListPosition: AppListPosition = .left
    // パネル全体の既定配置は中央です。
    var panelScreenPosition: PanelScreenPosition = .center
    // P6-Aの展開パネルに使う列数です。
    var pinnedFolderColumnCount: Int = 4
    // グローバルショートカットの保存値です。
    var globalShortcut: GlobalShortcut = .optionSpace
    var appNameBlacklist: AppNameBlacklistSettings = .defaultValue
    var hideDefinitelyIncompatibleApps: Bool = true
    // Recent Files query is independently switchable; it never changes the installed-app catalog.
    var recentFilesEnabled: Bool = true
    // nilは既定ピン投入の判定がまだ行われていない状態を表す、現在のモデル上の意味を持つ値です。
    var didSeedDefaultPins: Bool? = nil
    // CoreServices配下の補助アプリを通常一覧へ含めるか。既存利用者の表示を変えないため既定OFFです。
    var showCoreServicesApps: Bool = false
    // FinderはCoreServices内でも利用頻度が高いため、補助アプリ一括表示とは独立して既定ONにします。
    var showFinder: Bool = true
    // ONのとき、保存済みピンが0件の間だけピン留め欄と区切り線を隠します。
    var hidePinnedAreaWhenEmpty: Bool = false
    var selectAppListRowOnPointerHover: Bool = false
    // アプリ独自の明示的なアニメーションを有効にする設定です。
    var animationsEnabled: Bool = true
    // A14のジャンル別表示です。
    var groupAppsByCategory: Bool = false
    // A3追加修正。子フォルダー名を表示するかを保持します。
    var showAppDiscoveryFolder: Bool = false
    
    // 単純な半透明背景を使用するかどうかです。
    var isTransparent: Bool = false
    // 半透明背景の不透明度です。0が完全透明、1が完全不透明です。
    var transparentIntensity: Double = 0.725
    
    // SwiftUIのMaterialを利用したぼかし背景を使用するかどうかです。
    var usesBlurEffect: Bool = true
    // ぼかし素材の段階を数値で保持します。
    var blurEffectLevel: Double = 3.0 // 🌟 1.0 〜 5.0 の5段階
    
    // macOS 26向けのLiquid Glass風表示を使用するかどうかです。
    var usesLiquidGlass: Bool = false
    // Liquid Glass風の白い色味を重ねる強度です。
    var liquidGlassIntensity: Double = 0.725

    static func shouldAnimate(appEnabled: Bool, osReduceMotion: Bool, swiftReduceMotion: Bool) -> Bool {
        appEnabled && !osReduceMotion && !swiftReduceMotion
    }
}

// 設定の読み書きと、SwiftUI画面への変更通知を担当する共有モデルです。
// @MainActorにより、UIに関係する状態変更が必ずメインスレッドで行われます。
@MainActor
final class AppSettingsModel: ObservableObject {
    // アプリ全体で同じ設定状態を共有するシングルトンインスタンスです。
    static let shared = AppSettingsModel()
    // AppDelegateなどCombineを直接監視しない箇所へ変更を知らせる独自通知名です。
    static let didChangeNotification = Notification.Name("StartMenu4MacSettingsDidChange")
    
    // 保存成功後だけ外部へ公開し、すべての変更をupdateSettings経由に統一します。
    @Published private(set) var settings: AppSettings
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var globalShortcutRegistrationStatus: GlobalShortcutRegistrationStatus = .notAttempted
    private let settingsWriteProtected: Bool
    private let settingsWriteProtectionMessage: String?
    
    // 外部から複数のモデルを作れないよう、初期化処理をprivateにしています。
    private init() {
        #if DEBUG
            PersistenceRecovery.runSelfCheck()
            AppSettings.runResetSelfCheck()
            AppSettingsStore.runLoadSelfCheck()
            PinnedStore.runLoadSelfCheck()
            ContentView.runPinnedDragSelfCheck()
            ContentView.runA3SelfCheck()
        #endif
        // 起動時に保存済み設定を読み込み、なければ既定値を使用します。
        let loadResult = AppSettingsStore.loadResult()
        settings = loadResult.settings
        settingsWriteProtected = loadResult.issue?.allowsOverwrite == false
        var loadMessage: String?
        switch loadResult.issue {
        case .unreadablePreserved(let backupURL):
            loadMessage = String(format: L10n.settingsLoadUnreadablePreserved, backupURL.lastPathComponent)
        case .unreadableUnpreserved:
            loadMessage = L10n.settingsLoadUnreadableUnpreserved
        case nil:
            loadMessage = nil
        }
        persistenceErrorMessage = loadMessage
        settingsWriteProtectionMessage = settingsWriteProtected ? loadMessage : nil
    }
    
    // 候補を保存できた場合だけ画面と通知へ反映し、失敗時は現在値を維持します。
    @discardableResult
    func updateSettings(
        failureMessage: String = L10n.settingsSaveFailed,
        _ mutate: (inout AppSettings) -> Void
    ) -> Bool {
        guard !settingsWriteProtected else {
            persistenceErrorMessage = settingsWriteProtectionMessage
            return false
        }
        var candidate = settings
        mutate(&candidate)
        guard candidate != settings else { return true }
        guard PersistenceCommit.save(candidate, persist: { AppSettingsStore.save($0) }, publish: { settings = $0 }) else {
            persistenceErrorMessage = failureMessage
            return false
        }
        persistenceErrorMessage = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return true
    }

    func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    func setGlobalShortcutRegistrationStatus(_ status: GlobalShortcutRegistrationStatus) {
        globalShortcutRegistrationStatus = status
    }

    // SwiftUIの各入力を、保存成功後にだけ確定するBindingへ変換します。
    func binding<Value>(for keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in
                _ = self.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }

    func applyReset(_ group: SettingsResetGroup) {
        let candidate = settings.resetCandidate(for: group)
        _ = updateSettings(failureMessage: L10n.settingsResetSaveFailed) { $0 = candidate }
    }
    
    // 🌟 削除の代わりに、設定フォルダを開く関数
    func openSettingsFolder() {
        // 実際のFinder操作は保存場所を知っているStoreへ任せます。
        AppSettingsStore.openFolder()
    }

    // A2機能全体のオン・オフを保存します。条件そのものは削除しません。
    func setAppNameBlacklistEnabled(_ isEnabled: Bool) {
        _ = updateSettings { candidate in
            var blacklist = candidate.appNameBlacklist
            blacklist.isEnabled = isEnabled
            candidate.appNameBlacklist = blacklist
        }
    }

    // 指定した条件だけの有効・無効を切り替えます。見つからないIDは安全に無視します。
    func setAppNameBlacklistRuleEnabled(id: UUID, isEnabled: Bool) {
        _ = updateSettings { candidate in
            var blacklist = candidate.appNameBlacklist
            guard let index = blacklist.rules.firstIndex(where: { $0.id == id }) else { return }
            blacklist.rules[index].isEnabled = isEnabled
            candidate.appNameBlacklist = blacklist
        }
    }

    // 空文字は拒否し、正規化後の重複は新規追加せず既存ルールを再有効化します。
    @discardableResult
    func addAppNameBlacklistRule(_ text: String) -> Bool {
        let normalizedText = normalizedBlacklistText(text)
        guard !normalizedText.isEmpty else { return false }
        return updateSettings { candidate in
            var blacklist = candidate.appNameBlacklist
            if let index = blacklist.rules.firstIndex(where: { normalizedBlacklistText($0.text) == normalizedText }) {
                blacklist.rules[index].isEnabled = true
            } else {
                blacklist.rules.append(AppNameBlacklistRule(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            candidate.appNameBlacklist = blacklist
        }
    }

    // 指定した条件だけを削除します。誤削除しても既定値リセットまたは再追加で復元できます。
    func removeAppNameBlacklistRule(id: UUID) {
        _ = updateSettings { candidate in
            var blacklist = candidate.appNameBlacklist
            blacklist.rules.removeAll { $0.id == id }
            candidate.appNameBlacklist = blacklist
        }
    }

    // 条件配列と全体有効化を、A2の既定状態へまとめて戻します。
    func resetAppNameBlacklistToDefaults() {
        _ = updateSettings { $0.appNameBlacklist = .defaultValue }
    }
}

// P5-Bのログイン時起動を、設定JSONと独立して管理する共有モデルです。
// ログイン項目はmacOSのシステム設定でも変更できるため、希望値をsettings.jsonへ複製するとOS状態とずれます。
// このモデルは常にSMAppService.mainApp.statusを読み直し、macOSが返す実登録状態を画面表示の正とします。
@MainActor
final class LoginItemModel: ObservableObject {
    // A6では、OS状態の変化をAppDelegateのダイアログとメニューバーへ渡すために専用通知を使います。
    static let statusDidChangeNotification = Notification.Name("StartMenu4MacLoginItemStatusDidChange")
    // 複数のSettingsViewが現れても同じ登録処理を共有し、register/unregisterの二重発行を防ぎます。
    static let shared = LoginItemModel()
    // 最後に取得したmacOSの登録状態です。enabledだけをトグルONとして扱います。
    @Published private(set) var status: SMAppService.Status
    // trueの間はトグルを無効化し、連打で登録と解除が競合しないようにします。
    @Published private(set) var isUpdating = false
    // register/unregisterが失敗したときだけ、利用者向けの短い説明を保持します。技術詳細はNSLogへ残します。
    @Published private(set) var errorMessage: String?
    // 同一プロセス中に「あとで」を選んだ直後、アプリ復帰通知で同じダイアログを重ねないための消費済みフラグです。
    private var hasPresentedApprovalAlert = false

    // enabledだけをONとして表示します。requiresApprovalは承認待ちの補足と組み合わせ、ONと誤認させません。
    var isEnabled: Bool { status == .enabled }
    // macOSの承認待ちでは、システム設定のログイン項目を確認する導線を表示します。
    var requiresApproval: Bool { status == .requiresApproval }

    private init() {
        // 初回表示も保存値ではなく、読み取り時点のmacOS状態から始めます。
        status = SMAppService.mainApp.status
    }

    // 設定画面、アプリ復帰、起動遅延確認、登録・解除完了のすべてで使うOS状態の共通再取得入口です。
    // enabled・notRegistered・notFoundでは案内せず、requiresApprovalだけをAppDelegateへ通知します。
    func refreshStatus() {
        let updatedStatus = SMAppService.mainApp.status
        guard status != updatedStatus else { return }
        status = updatedStatus
        NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: self)
    }

    // requiresApprovalのときだけ、起動中に一度だけダイアログ表示権を返します。
    // register/unregister中は結果が確定していないため保留し、notRegisteredとnotFoundは利用者の正常なOFF・初期状態として催促しません。
    func consumeApprovalAlertPresentation() -> Bool {
        guard !isUpdating, requiresApproval, !hasPresentedApprovalAlert else { return false }
        hasPresentedApprovalAlert = true
        return true
    }

    // トグル操作をmacOSの登録・解除へ変換します。JSONのBoolを書き換えるBindingではありません。
    func setEnabled(_ shouldEnable: Bool) {
        // 処理中だけは新しい要求を発行しません。notFoundは未登録相当として扱い、オン操作でアプリ自身が登録を試みます。
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer {
            // 成功・失敗のどちらでも最後にOS状態を読み直し、推測でトグルを戻さないようにします。
            isUpdating = false
            refreshStatus()
        }
        do {
            // register/unregisterは同じ直列処理で1回だけ実行し、直後のrefreshStatusで最終結果を確定します。
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // OSエラーの生文は設定画面を過度に技術的にしないためログへ残し、UIには操作別の要約だけを表示します。
            NSLog("Failed to \(shouldEnable ? "register" : "unregister") login item: \(error.localizedDescription)")
            errorMessage = shouldEnable ? L10n.settingsLoginItemRegistrationFailed : L10n.settingsLoginItemUnregistrationFailed
        }
    }

    // 承認待ちの次の操作として、macOS標準のログイン項目設定を開きます。
    func openLoginItemsSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

// A7で通知時刻と照合するため、StartMenu経由で最後に起動した1件だけを短期間保持します。
// アプリ一覧・フルパス・長期履歴は保存せず、次の起動操作で必ず上書きします。
struct LastLaunchDiagnostic: Codable {
    let displayName: String
    let bundleIdentifier: String
    let launchedAt: Date
    let route: String
}

@MainActor
final class LaunchDiagnosticModel: ObservableObject {
    static let shared = LaunchDiagnosticModel()
    private static let storageKey = "StartMenu4MacLastLaunchDiagnostic"
    // 通知再発との時刻照合に十分で、不要な利用履歴を残さない30分だけを有効期間にします。
    private static let retentionInterval: TimeInterval = 30 * 60
    @Published private(set) var latest: LastLaunchDiagnostic?

    private init() {
        latest = Self.loadCurrentDiagnostic()
    }

    // NSWorkspace.openの直前に記録し、通知が出た場合も「StartMenuが何を起動しようとしたか」を失いません。
    func recordLaunch(of appURL: URL) {
        let bundle = Bundle(url: appURL)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let identifier = bundle?.bundleIdentifier ?? "(unknown)"
        let diagnostic = LastLaunchDiagnostic(displayName: name, bundleIdentifier: identifier, launchedAt: Date(), route: "StartMenu")
        latest = diagnostic
        guard let data = try? JSONEncoder().encode(diagnostic) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadCurrentDiagnostic() -> LastLaunchDiagnostic? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let diagnostic = try? JSONDecoder().decode(LastLaunchDiagnostic.self, from: data),
              Date().timeIntervalSince(diagnostic.launchedAt) <= retentionInterval else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return nil
        }
        return diagnostic
    }
}

// 設定JSONファイルに対する入出力を担当します。
// enumを名前空間として使っており、インスタンスを作らずstatic関数だけを呼びます。
enum AppSettingsStore {
    enum LoadState {
        case missing
        case loaded
        case unreadable
    }

    struct LoadResult {
        let settings: AppSettings
        let state: LoadState
        let issue: PersistenceLoadIssue?
    }

    private static func unreadableLoadResult(data: Data, url: URL) -> LoadResult {
        LoadResult(
            settings: AppSettings(),
            state: .unreadable,
            issue: PersistenceRecovery.unreadableIssue(for: data, originalURL: url)
        )
    }

    // 現在版のsettings.jsonだけを復元し、現行版以外や不正値は未読込として原本を保全します。
    static func loadResult(applicationSupportDirectory: URL? = nil) -> LoadResult {
        guard let url = configURL(applicationSupportDirectory: applicationSupportDirectory) else {
            NSLog("Could not resolve settings file URL")
            return LoadResult(settings: AppSettings(), state: .unreadable, issue: .unreadableUnpreserved)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadResult(settings: AppSettings(), state: .missing, issue: nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            NSLog("Failed to read settings: %@", error.localizedDescription)
            return LoadResult(settings: AppSettings(), state: .unreadable, issue: .unreadableUnpreserved)
        }

        return load(data: data, originalURL: url)
    }

    static func load(data: Data, originalURL: URL) -> LoadResult {
        guard PersistenceRecovery.schemaVersion(in: data) == .value(AppSettings.currentVersion) else {
            return unreadableLoadResult(data: data, url: originalURL)
        }
        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            guard settings.version == AppSettings.currentVersion,
                  settings.globalShortcut.hasSupportedModifier else {
                return unreadableLoadResult(data: data, url: originalURL)
            }
            return LoadResult(settings: settings, state: .loaded, issue: nil)
        } catch {
            NSLog("Failed to decode current settings schema: %@", error.localizedDescription)
            return unreadableLoadResult(data: data, url: originalURL)
        }
    }

#if DEBUG
    // 現在スキーマの必須キーと厳密なdecodeだけを確認します。
    static func runLoadSelfCheck() {
        assert(AppSettings().version == AppSettings.currentVersion)
        let settings = AppSettings()
        let data = try! JSONEncoder().encode(settings)
        assert((try? JSONDecoder().decode(AppSettings.self, from: data)) == settings)

        var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "globalShortcut")
        let missingRequiredSetting = try! JSONSerialization.data(withJSONObject: object)
        assert((try? JSONDecoder().decode(AppSettings.self, from: missingRequiredSetting)) == nil)

        for mismatchedVersion in [AppSettings.currentVersion - 1, AppSettings.currentVersion + 1] {
            object["version"] = mismatchedVersion
            let mismatchedSchema = try! JSONSerialization.data(withJSONObject: object)
            assert(PersistenceRecovery.schemaVersion(in: mismatchedSchema) != .value(AppSettings.currentVersion))
        }
    }
#endif
    
    // 現在のAppSettingsをsettings.jsonとして保存します。
    @discardableResult
    static func save(_ settings: AppSettings, applicationSupportDirectory: URL? = nil) -> Bool {
        // 保存先URLを作れない環境では、何もせず終了します。
        guard let url = configURL(applicationSupportDirectory: applicationSupportDirectory) else { return false }
        
        // ファイル操作は失敗し得るため、do-catchでエラーを捕捉します。
        do {
            // Application Support内の保存フォルダがなければ、途中階層ごと作成します。
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Swiftの値をJSONデータへ変換するエンコーダーを作ります。
            let encoder = JSONEncoder()
            // 人が読める改行・インデントと、キー順の安定化を指定します。
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // AppSettingsを実際のJSONバイト列へ変換します。
            let data = try encoder.encode(settings)
            // atomic指定により、一時ファイル経由で安全に置き換え、途中までの破損を防ぎます。
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            // 保存に失敗してもアプリを終了させず、macOSのログへ理由を残します。
            NSLog("Failed to save settings: \(error.localizedDescription)")
            return false
        }
    }
    
    // 🌟 Finderで設定ファイルのある場所を開く関数
    static func openFolder() {
        // 保存先を取得できなければFinder操作を行いません。
        guard let url = configURL() else { return }
        // フォルダを開き、settings.json を選択（ハイライト）状態にする
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
    
    // settings.jsonの完全な保存先URLを組み立てる計算プロパティです。
    private static func configURL(applicationSupportDirectory: URL? = nil) -> URL? {
        // 現在のユーザー専用Application Supportフォルダを取得します。
        let appSupportURL: URL
        if let applicationSupportDirectory {
            appSupportURL = applicationSupportDirectory
        } else {
            guard let defaultDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                // OSから保存先が得られなかった場合はnilを返します。
                return nil
            }
            appSupportURL = defaultDirectory
        }
        
        // 通常はBundle IDをフォルダ名にし、取得不能時だけアプリ名を代替値にします。
        let folderName = Bundle.main.bundleIdentifier ?? "StartMenu4Mac"
        // Application Support／アプリ固有フォルダ／settings.jsonというURLを順に連結します。
        return appSupportURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

// SwiftUIの設定画面内で使う「ショートカット記録欄」のAppKit実装です。
// SwiftUI標準のTextFieldは文字列入力向けで、CommandやOptionを含む生のキーイベント記録には向かないため、
// NSViewを直接使ってkeyDownとperformKeyEquivalentの両方を受け取ります。
private final class ShortcutRecorderNSView: NSView {
    // 記録していないときに表示する、現在保存済みのショートカットです。
    private var shortcut: GlobalShortcut = .optionSpace
    // 入力待ちの間に表示するローカライズ済みメッセージです。
    private var recordingPrompt = ""
    // 修飾キーなしの入力を拒否した直後に表示するローカライズ済みメッセージです。
    private var invalidPrompt = ""
    // 現在このビューがキー入力を記録中かどうかです。
    // Carbon監視の一時停止と必ず対になるため、開始・終了処理以外からは変更しません。
    private(set) var isRecording = false

    // ビュー中央へショートカット名や案内文を表示する、編集不能のテキスト部品です。
    private let valueLabel: NSTextField = {
        // labelWithStringならカーソルや文字選択を持たず、表示専用のNSTextFieldを作れます。
        let label = NSTextField(labelWithString: "")
        // ショートカット記号を入力欄の中央へ配置します。
        label.alignment = .center
        // 通常文字とキー記号が安定した幅で見えるよう、システムの等幅フォントを使用します。
        label.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Auto Layout用の制約をコードで設定するため、自動生成されるサイズ制約を無効にします。
        label.translatesAutoresizingMaskIntoConstraints = false
        // 長い案内文がはみ出す場合は末尾を省略し、設定画面全体の幅を押し広げないようにします。
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    // 有効な組み合わせが記録されたとき、SwiftUIのBindingへ値を渡す処理です。
    var onShortcutRecorded: ((GlobalShortcut) -> Void)?
    // 記録開始・終了をAppDelegateへ伝え、Carbon監視を停止・再開する処理です。
    var onRecordingChanged: ((Bool) -> Void)?

    // コードからだけ作成するビューなので、frame指定の初期化処理で見た目と制約を準備します。
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 独自に枠線を描くため、AppKit標準のフォーカスリングは重ねません。
        focusRingType = .none
        // 中央ラベルを子ビューとして追加します。
        addSubview(valueLabel)
        // ラベルの上下左右に余白を確保しながら、記録欄いっぱいに配置します。
        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        // VoiceOverから単なる装飾ではなく、操作できるボタンとして認識できるようにします。
        setAccessibilityRole(.button)
    }

    // Storyboardやxibから生成する設計ではないため、この初期化経路は利用しません。
    required init?(coder: NSCoder) {
        nil
    }

    // Auto Layoutが高さを決める際の基準です。macOS標準の入力欄に近い28ポイントを使います。
    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 28)
    }

    // NSTextFieldではない独自NSViewでも、クリック後にキーボード入力を受け取れるよう明示します。
    override var acceptsFirstResponder: Bool {
        true
    }

    // SwiftUI側の設定値や翻訳が変わるたびに、表示内容を安全に同期します。
    func update(shortcut: GlobalShortcut, recordingPrompt: String, invalidPrompt: String) {
        self.shortcut = shortcut
        self.recordingPrompt = recordingPrompt
        self.invalidPrompt = invalidPrompt
        // 記録中の案内文を、SwiftUIの再描画で保存値へ戻してしまわないようにします。
        if !isRecording {
            valueLabel.stringValue = shortcut.displayName
            setAccessibilityValue(shortcut.displayName)
        }
    }

    // 背景と枠線をAppKitのシステム色で描き、ライト・ダーク両方の外観へ追従します。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 0.5ポイント内側へ入れることで、1ポイントの枠線がビュー外へ欠けるのを防ぎます。
        let drawingRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: drawingRect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        // 記録中だけアクセントカラーと太い枠にし、現在キー入力を待っていることを視覚的にも示します。
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()
    }

    // 利用者が記録欄をクリックしたら、このビューをキー入力先（First Responder）にします。
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    // First Responderになれた時点で、表示更新とCarbon監視の一時停止を開始します。
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        beginRecordingIfNeeded()
        return true
    }

    // ほかの入力欄をクリックした場合も、記録状態とCarbon一時停止を必ず終了させます。
    override func resignFirstResponder() -> Bool {
        endRecordingIfNeeded()
        return super.resignFirstResponder()
    }

    // Commandを含む入力はメニューコマンドとして先に扱われる場合があるため、等価キー判定の段階でも捕捉します。
    // 記録中に処理できたイベントだけtrueを返し、通常時のアプリメニュー操作は妨げません。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordedKeyEvent(event)
        return true
    }

    // メニュー相当でない通常のキー入力は、このkeyDownから共通の記録処理へ渡します。
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordedKeyEvent(event)
    }

    // 設定ウィンドウが閉じられてビューが外された場合も、Carbon監視を停止したまま残しません。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endRecordingIfNeeded()
        }
    }

    // 記録開始を1回だけ実行し、現在の組み合わせではなく入力案内を表示します。
    private func beginRecordingIfNeeded() {
        guard !isRecording else { return }
        isRecording = true
        valueLabel.stringValue = recordingPrompt
        setAccessibilityValue(recordingPrompt)
        needsDisplay = true
        // この通知を先に送ることで、直後に現在の組み合わせを押してもStartMenuの開閉には使われません。
        onRecordingChanged?(true)
    }

    // 記録終了を1回だけ実行し、確定済みの表示とCarbon監視を元へ戻します。
    private func endRecordingIfNeeded() {
        guard isRecording else { return }
        isRecording = false
        valueLabel.stringValue = shortcut.displayName
        setAccessibilityValue(shortcut.displayName)
        needsDisplay = true
        onRecordingChanged?(false)
    }

    // Escapeによるキャンセル、入力条件の検証、有効値の確定を一元管理します。
    private func handleRecordedKeyEvent(_ event: NSEvent) {
        // Escapeはショートカットとして保存せず、変更前の値を維持したまま記録を終了します。
        if Int(event.keyCode) == kVK_Escape {
            window?.makeFirstResponder(nil)
            return
        }

        // GlobalShortcut側でNSEventをCarbon登録可能な値へ変換し、修飾キーの有無も検証します。
        guard let recordedShortcut = GlobalShortcut.make(from: event) else {
            // 単独キーは誤操作につながるため保存せず、理由を表示して次の入力を待ちます。
            valueLabel.stringValue = invalidPrompt
            setAccessibilityValue(invalidPrompt)
            NSSound.beep()
            return
        }

        // SwiftUIのBindingへ新しい値を渡します。didSetによりJSON保存とCarbon再登録が続けて行われます。
        shortcut = recordedShortcut
        onShortcutRecorded?(recordedShortcut)
        // First Responderを外すとresignFirstResponderが呼ばれ、記録終了とCarbon監視再開が必ず対になります。
        window?.makeFirstResponder(nil)
    }
}

// AppKit製のShortcutRecorderNSViewを、SwiftUIのForm内で使うための橋渡しです。
private struct ShortcutRecorderView: NSViewRepresentable {
    // 設定モデルのショートカット値を読み書きするBindingです。
    @Binding var shortcut: GlobalShortcut

    // SwiftUIが最初に画面を組み立てる際、実際のAppKitビューを1個作成します。
    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let recorderView = ShortcutRecorderNSView(frame: .zero)
        configure(recorderView)
        return recorderView
    }

    // 設定値や言語が更新された際、既存のAppKitビューを作り直さず内容だけ同期します。
    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        configure(nsView)
    }

    // 作成時と更新時に共通する値・コールバックの設定を、1か所へまとめます。
    private func configure(_ recorderView: ShortcutRecorderNSView) {
        recorderView.update(
            shortcut: shortcut,
            recordingPrompt: L10n.settingsShortcutRecording,
            invalidPrompt: L10n.settingsShortcutInvalid
        )
        // 有効な組み合わせが記録されたら、Bindingを通じてAppSettingsへ即座に保存します。
        recorderView.onShortcutRecorded = { recordedShortcut in
            shortcut = recordedShortcut
        }
        // 記録中だけCarbon監視を止める役割は、Carbonモニターを所有するAppDelegateへ任せます。
        recorderView.onRecordingChanged = { isRecording in
            (NSApp.delegate as? AppDelegate)?.setGlobalShortcutRecording(isRecording)
        }
    }
}

// macOS標準の設定ウィンドウへ表示するSwiftUIビューです。
struct SettingsView: View {
    // 共有モデルを観察し、値が変わったら画面を自動更新します。
    @ObservedObject private var model = AppSettingsModel.shared
    // ログイン時起動はJSON設定とは別のOS管理状態なので、専用の共有モデルを観察します。
    @ObservedObject private var loginItemModel = LoginItemModel.shared
    // A2の新規条件を入力中だけ保持する一時値です。追加成功後に空へ戻し、settings.jsonへは保存しません。
    @State private var newBlacklistRuleText: String = ""
    @State private var showingFullResetConfirmation = false
    // 幅・高さの入力欄で、数値を小数部なしで表示するための書式設定です。
    private let widthFormatter: NumberFormatter = {
        // NumberFormatterのインスタンスを作成します。
        let formatter = NumberFormatter()
        // 一般的な10進数の表示形式を指定します。
        formatter.numberStyle = .decimal
        // ウィンドウ寸法を整数表示にするため、小数部の最大桁数を0にします。
        formatter.maximumFractionDigits = 0
        // 設定済みのformatterを、このプロパティの初期値として返します。
        return formatter
    }()
    
    // 設定画面全体のUI階層を宣言します。
    var body: some View {
        TabView {
            settingsForm { generalSection }.tabItem { Label(L10n.settingsGeneral, systemImage: "gearshape") }
            settingsForm { layoutSection }.tabItem { Label(L10n.settingsLayout, systemImage: "rectangle.split.2x1") }
            settingsForm { appearanceSection }.tabItem { Label(L10n.settingsAppearance, systemImage: "paintbrush") }
            settingsForm { appVisibilitySection }.tabItem { Label(L10n.settingsAppVisibility, systemImage: "square.grid.2x2") }
            settingsForm { shortcutSection }.tabItem { Label(L10n.settingsShortcut, systemImage: "keyboard") }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(L10n.settingsResetAllTitle, isPresented: $showingFullResetConfirmation) {
            Button(L10n.settingsResetCancel, role: .cancel) {}
            Button(L10n.settingsResetConfirm, role: .destructive) { model.applyReset(.all) }
        } message: {
            Text(L10n.settingsResetAllMessage)
        }
        .environment(\.colorScheme, model.resolvedColorScheme)
        .onAppear { loginItemModel.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemModel.refreshStatus()
        }
    }

    @ViewBuilder
    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            if let error = model.persistenceErrorMessage {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button(L10n.settingsOpenFolder) {
                            model.openSettingsFolder()
                        }
                        .buttonStyle(.borderless)
                        Button(L10n.settingsErrorDismiss) {
                            model.dismissPersistenceError()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            content()
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        Section(L10n.settingsLaunch) {
            Toggle(L10n.settingsLoginItemEnabled, isOn: Binding(get: { loginItemModel.isEnabled }, set: { loginItemModel.setEnabled($0) })).disabled(loginItemModel.isUpdating)
            if loginItemModel.isUpdating { ProgressView().controlSize(.small) }
            if let error = loginItemModel.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if loginItemModel.requiresApproval {
                Text(L10n.settingsLoginItemRequiresApproval).font(.caption).foregroundStyle(.secondary)
            }
            if loginItemModel.requiresApproval { Button(L10n.settingsLoginItemOpenSystemSettings) { loginItemModel.openLoginItemsSystemSettings() } }
        }
        Section {
            Button(L10n.settingsOpenFolder) { model.openSettingsFolder() }
            Button(L10n.settingsResetAll, role: .destructive) { showingFullResetConfirmation = true }
        }
    }

    @ViewBuilder
    private var layoutSection: some View {
        Section(L10n.settingsLayout) {
            dimensionField(L10n.settingsWindowWidth, value: model.binding(for: \.windowWidth))
            dimensionField(L10n.settingsWindowHeight, value: model.binding(for: \.windowHeight))
            dimensionField(L10n.settingsAppListWidth, value: model.binding(for: \.appListWidth))
            Picker(L10n.settingsAppListPosition, selection: model.binding(for: \.appListPosition)) {
                Text(L10n.settingsPositionLeft).tag(AppSettings.AppListPosition.left)
                Text(L10n.settingsPositionRight).tag(AppSettings.AppListPosition.right)
            }.pickerStyle(.segmented)
            Picker(L10n.settingsPanelScreenPosition, selection: Binding(get: { model.settings.panelScreenPosition }, set: { value in
                _ = model.updateSettings { $0.panelScreenPosition = value }
            })) {
                Text(L10n.settingsPanelPositionLeft).tag(AppSettings.PanelScreenPosition.left)
                Text(L10n.settingsPanelPositionCenter).tag(AppSettings.PanelScreenPosition.center)
                Text(L10n.settingsPanelPositionRight).tag(AppSettings.PanelScreenPosition.right)
            }.pickerStyle(.segmented)
            Picker(L10n.settingsPinnedFolderColumns, selection: Binding(get: { model.settings.pinnedFolderColumnCount }, set: { value in
                _ = model.updateSettings { $0.pinnedFolderColumnCount = value }
            })) {
                Text("3").tag(3); Text("4").tag(4); Text("5").tag(5); Text("6").tag(6)
            }.pickerStyle(.segmented)
            Toggle(L10n.settingsHidePinnedAreaWhenEmpty, isOn: Binding(get: { model.settings.hidePinnedAreaWhenEmpty }, set: { value in
                _ = model.updateSettings { $0.hidePinnedAreaWhenEmpty = value }
            }))
            Text(L10n.settingsHidePinnedAreaWhenEmptyHelp).font(.caption).foregroundStyle(.secondary)
            Toggle(L10n.settingsSelectAppListRowOnPointerHover, isOn: Binding(get: { model.settings.selectAppListRowOnPointerHover }, set: { value in
                _ = model.updateSettings { $0.selectAppListRowOnPointerHover = value }
            }))
            Text(L10n.settingsSelectAppListRowOnPointerHoverHelp).font(.caption).foregroundStyle(.secondary)
            resetButton(.layout)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section(L10n.settingsAppearance) {
            Picker(L10n.settingsTheme, selection: model.binding(for: \.themeMode)) {
                Text(L10n.settingsThemeSystem).tag(AppSettings.ThemeMode.system)
                Text(L10n.settingsThemeLight).tag(AppSettings.ThemeMode.light)
                Text(L10n.settingsThemeDark).tag(AppSettings.ThemeMode.dark)
            }.pickerStyle(.segmented)
            Toggle(L10n.settingsAnimationsEnabled, isOn: Binding(get: { model.settings.animationsEnabled }, set: { value in
                _ = model.updateSettings { $0.animationsEnabled = value }
            }))
            Text(L10n.settingsAnimationsEnabledHelp).font(.caption).foregroundStyle(.secondary)
            Toggle(L10n.settingsTransparentWindow, isOn: Binding(get: { model.settings.isTransparent }, set: { newValue in
                _ = model.updateSettings { candidate in
                    candidate.isTransparent = newValue
                    if newValue {
                        candidate.usesBlurEffect = false
                        candidate.usesLiquidGlass = false
                    }
                }
            }))
            if model.settings.isTransparent {
                Slider(value: model.binding(for: \.transparentIntensity), in: 0.0...1.0, step: 0.01)
            }
            Toggle(L10n.settingsBlurEffect, isOn: Binding(get: { model.settings.usesBlurEffect }, set: { newValue in
                _ = model.updateSettings { candidate in
                    candidate.usesBlurEffect = newValue
                    if newValue {
                        candidate.isTransparent = false
                        candidate.usesLiquidGlass = false
                    }
                }
            }))
            if model.settings.usesBlurEffect {
                Slider(value: model.binding(for: \.blurEffectLevel), in: 1.0...5.0, step: 1.0)
            }
            Toggle(L10n.settingsLiquidGlass, isOn: Binding(get: { model.settings.usesLiquidGlass }, set: { newValue in
                _ = model.updateSettings { candidate in
                    candidate.usesLiquidGlass = newValue
                    if newValue {
                        candidate.isTransparent = false
                        candidate.usesBlurEffect = false
                    }
                }
            }))
            if model.settings.usesLiquidGlass {
                Slider(value: model.binding(for: \.liquidGlassIntensity), in: 0.0...1.0, step: 0.01)
            }
            resetButton(.appearance)
        }
    }

    @ViewBuilder
    private var appVisibilitySection: some View {
        Section(L10n.settingsAppVisibility) {
            if FeatureFlags.recentFilesEnabled {
                Toggle(LocalizedStringKey("settings.recent_files_enabled"), isOn: model.binding(for: \.recentFilesEnabled))
                Text(LocalizedStringKey("settings.recent_files_help")).font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L10n.settingsGroupAppsByCategory, isOn: Binding(get: { model.settings.groupAppsByCategory }, set: { value in
                _ = model.updateSettings { $0.groupAppsByCategory = value }
            }))
            Text(L10n.settingsGroupAppsByCategoryHelp).font(.caption).foregroundStyle(.secondary)
            Toggle(L10n.settingsHideIncompatibleApps, isOn: Binding(get: { model.settings.hideDefinitelyIncompatibleApps }, set: { value in
                _ = model.updateSettings { $0.hideDefinitelyIncompatibleApps = value }
            }))
            Text(L10n.settingsHideIncompatibleAppsHelp).font(.caption).foregroundStyle(.secondary)
            Toggle(L10n.settingsShowCoreServicesApps, isOn: Binding(get: { model.settings.showCoreServicesApps }, set: { value in
                _ = model.updateSettings { $0.showCoreServicesApps = value }
            }))
            Toggle(L10n.settingsShowFinder, isOn: Binding(get: { model.settings.showFinder }, set: { value in
                _ = model.updateSettings { $0.showFinder = value }
            }))
            Toggle(L10n.settingsBlacklistEnabled, isOn: Binding(get: { model.settings.appNameBlacklist.isEnabled }, set: { model.setAppNameBlacklistEnabled($0) }))
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.settings.appNameBlacklist.rules) { rule in
                        HStack(spacing: 8) {
                            Text(rule.text).lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { model.setAppNameBlacklistRuleEnabled(id: rule.id, isEnabled: $0) })).labelsHidden()
                            Button(L10n.settingsBlacklistRemove) { model.removeAppNameBlacklistRule(id: rule.id) }
                        }
                    }
                }
            }.frame(maxHeight: 132)
            TextField(L10n.settingsBlacklistNewRule, text: $newBlacklistRuleText).textFieldStyle(.roundedBorder).onSubmit { addBlacklistRuleFromInput() }
            Button(L10n.settingsBlacklistAdd) { addBlacklistRuleFromInput() }.disabled(normalizedBlacklistText(newBlacklistRuleText).isEmpty)
            Button(L10n.settingsBlacklistReset) { model.resetAppNameBlacklistToDefaults() }
            resetButton(.appVisibility)
        }
    }

    @ViewBuilder
    private var shortcutSection: some View {
        Section(L10n.settingsShortcut) {
            HStack { Text(L10n.settingsGlobalShortcut); Spacer(); ShortcutRecorderView(shortcut: Binding(get: { model.settings.globalShortcut }, set: { value in
                _ = model.updateSettings { $0.globalShortcut = value }
            })).frame(width: 210, height: 28) }
            Text(L10n.settingsGlobalShortcutHelp).font(.caption).foregroundStyle(.secondary)
            switch model.globalShortcutRegistrationStatus {
            case .notAttempted:
                Label(L10n.settingsGlobalShortcutChecking, systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
            case .active(let shortcut):
                Label(L10n.settingsGlobalShortcutActive(shortcut.displayName), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .unavailable:
                Label(L10n.settingsGlobalShortcutUnavailable, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            Button(L10n.settingsShortcutReset) { model.applyReset(.shortcut) }.disabled(model.settings.globalShortcut == .optionSpace)
        }
        Section {
            Button(L10n.settingsOpenFolder) { model.openSettingsFolder() }
        }
    }

    private func dimensionField(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField("", value: value, formatter: widthFormatter).frame(width: 80).multilineTextAlignment(.trailing); Text("px").foregroundStyle(.secondary) }
    }

    // 入力欄の文字列をモデルへ渡し、保存に成功した場合だけ入力欄を空へ戻します。
    func addBlacklistRuleFromInput() {
        guard !normalizedBlacklistText(newBlacklistRuleText).isEmpty else { return }
        guard model.addAppNameBlacklistRule(newBlacklistRuleText) else { return }
        newBlacklistRuleText = ""
    }

    @ViewBuilder
    private func resetButton(_ group: SettingsResetGroup) -> some View {
        Button(L10n.settingsResetSection) {
            model.applyReset(group)
        }
    }
}

// AppSettingsModelへ、画面表示に使う「確定済み配色」を追加する拡張です。
extension AppSettingsModel {
    // system設定も含め、最終的にlightまたはdarkのどちらかを必ず返します。
    var resolvedColorScheme: ColorScheme {
        // 保存されているテーマ設定ごとに処理を分けます。
        switch settings.themeMode {
        case .system:
            // 現在のAppKit外観がdarkAquaに最も近ければ、ダークモードと判定します。
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return .dark
            }
            // darkAquaでなければライトモードとして扱います。
            return .light
        case .light:
            // 明示的なライト設定は、そのままlightを返します。
            return .light
        case .dark:
            // 明示的なダーク設定は、そのままdarkを返します。
            return .dark
        }
    }
}
