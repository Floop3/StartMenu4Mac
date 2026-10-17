import SwiftUI
import AppKit
// Carbonは、アプリが前面にないときにも受け取れるmacOS標準のグローバルホットキーAPIを提供します。
// SwiftUIやNSEventのローカル監視だけでは他アプリのキー入力を受け取れないため、P1ではこれを使用します。
import Carbon

// A10で終了要求後に残った処理を診断するための最小記録です。
// 利用者の検索語、ピン、パス、設定値は含めず、1KiB未満の固定項目だけを保存します。
private struct ShutdownDiagnostic: Codable {
    let version: String
    let requestedAt: Date
    let phase: String
    let panelVisible: Bool
}

// CarbonのC言語コールバックから、Swift側のアプリ本体へショートカット入力を渡す通知名です。
// 名前を専用にすることで、将来ほかの通知と混同したり衝突したりしないようにします。
extension Notification.Name {
    // 現在設定されているグローバルショートカットが押されたことを、メインアクター上のAppDelegateへ伝える通知です。
    static let startMenuGlobalShortcutPressed = Notification.Name("StartMenu4MacGlobalShortcutPressed")
    // AppDelegateが常駐キー監視で受け取った本体パネル用コマンドを、SwiftUIの一覧へ渡す通知です。
    // 監視の寿命をContentViewの表示状態から分離し、パネルを閉じて再表示してもキー操作を失わないようにします。
    static let startMenuPanelKeyboardCommand = Notification.Name("StartMenu4MacPanelKeyboardCommand")
    // StartMenu本体が非表示へ移る直前に、ContentView固有の一時UI（P6-A展開パネルなど）を閉じる通知です。
    static let startMenuPanelWillHide = Notification.Name("StartMenu4MacPanelWillHide")
    // 他アプリまたはDesktopで左ボタンが解放された事実だけをContentViewへ伝えます。
    // drag中かどうかは送信側で推測せず、ピンの一時状態を持つContentView側で判断します。
    static let startMenuExternalLeftMouseUp = Notification.Name("StartMenu4MacExternalLeftMouseUp")
    // 日本語IMEの未確定文字をReturnで確定した直後、名称保存のsubmitだけを抑止する通知です。
    static let startMenuFolderNameIMECommit = Notification.Name("StartMenu4MacFolderNameIMECommit")
    static let startMenuFolderNameEditingBegan = Notification.Name("StartMenu4MacFolderNameEditingBegan")
    static let startMenuFolderNameEditingEnded = Notification.Name("StartMenu4MacFolderNameEditingEnded")
    static let startMenuFolderNameSubmit = Notification.Name("StartMenu4MacFolderNameSubmit")
    // パネルの表示アニメーションが完了し、検索欄へ条件付きでフォーカスを要求できる状態になったことをContentViewへ伝える通知です。
    static let startMenuPanelDidFinishShowing = Notification.Name("StartMenu4MacPanelDidFinishShowing")
}

// パネルライフサイクル通知のuserInfoキーを共通定義します。
// 生文字列を各送信・受信箇所に散在させず、この定義だけを更新すればキー名の変更が追跡できます。
enum StartMenuPanelLifecycleUserInfoKey {
    static let generation = "generation"
    static let reason = "reason"
}
// キーコードそのものではなく「何をしたいか」を通知で渡すための列挙型です。
// ContentViewはAppKitのキーコードを知る必要がなく、アプリ一覧の操作だけへ集中できます。
enum StartMenuPanelKeyboardCommand: String, Equatable {
    case selectNext
    case selectPrevious
    case openSelectedApp
    case closeStartMenu

    static func command(forKeyCode keyCode: UInt16) -> Self? {
        switch keyCode {
        case 125: return .selectNext       // 下矢印
        case 126: return .selectPrevious   // 上矢印
        case 36: return .openSelectedApp   // Return
        case 53: return .closeStartMenu    // Esc
        default: return nil
        }
    }
}

enum StartMenuPanelKeyboardDisposition: Equatable {
    case forwardToResponder
    case commitIME
    case submitFolderName
    case dispatch(StartMenuPanelKeyboardCommand)

    static func disposition(
        forKeyCode keyCode: UInt16,
        isFieldEditor: Bool,
        hasMarkedText: Bool,
        isFolderNameEditing: Bool
    ) -> Self {
        if isFieldEditor {
            if keyCode == 36 {
                if hasMarkedText { return .commitIME }
                if isFolderNameEditing { return .submitFolderName }
                return .forwardToResponder
            }
            // Up/Down may be owned by the active input method's candidate window; never route them to app selection while composition is marked.
            if hasMarkedText, keyCode == 125 || keyCode == 126 {
                return .forwardToResponder
            }
            // Escは入力中の検索語や編集状態をパネル終了へ誤配送しないよう入力先へ返します。
            if keyCode == 53 { return .forwardToResponder }
            // フォルダー名のカーソル移動をアプリ一覧の選択移動として消費しません。
            if isFolderNameEditing, keyCode == 125 || keyCode == 126 {
                return .forwardToResponder
            }
        }

        if let command = StartMenuPanelKeyboardCommand.command(forKeyCode: keyCode) {
            return .dispatch(command)
        }
        return .forwardToResponder
    }
}

// P1の自由入力式グローバルショートカットを、保存とCarbon登録の両方で使える形にまとめた値です。
// 以前の「4個のenum候補」ではなく、押された通常キーの物理キーコードと修飾キーをそのまま保持します。
// これにより、利用者はSpace以外の文字・数字・記号・矢印・ファンクションキーなども選べます。
struct GlobalShortcut: Codable, Equatable {
    // macOSがキーボード上のキー位置を識別する物理キーコードです。
    // UInt32に統一しておくと、CarbonのRegisterEventHotKeyへ変換せずそのまま渡せます。
    let keyCode: UInt32
    // Command・Option・Control・ShiftをCarbon形式のビット列として保持します。
    // Caps Lockやfnなど、Carbonのグローバルホットキー登録に使わないフラグは保存しません。
    let carbonModifiers: UInt32
    // 設定画面で通常キー部分を説明する表示名です。
    // 例としてSpaceなら「Space」、Kキーなら「K」を保存し、修飾キー記号は表示時に組み立てます。
    let keyDisplayName: String

    // 通常の新規作成で使う初期化処理です。
    // Codable用の独自initを定義しても、アプリ内ではこの3項目を明示して安全に値を作れるようにします。
    init(keyCode: UInt32, carbonModifiers: UInt32, keyDisplayName: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyDisplayName = keyDisplayName
    }

    // 初回起動とリセット操作で使うOption + Spaceです。
    // 「既定値」を1か所に定義することで、各画面や起動処理で値が食い違うことを防ぎます。
    static let optionSpace = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey),
        keyDisplayName: "Space"
    )

    // 設定画面へ表示する完全な組み合わせ名です。
    // macOSで一般的な順序（Control、Option、Shift、Command）の記号を先に並べ、最後に通常キー名を付けます。
    var displayName: String {
        var modifierSymbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 {
            modifierSymbols += "⌃"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            modifierSymbols += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            modifierSymbols += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            modifierSymbols += "⌘"
        }
        return "\(modifierSymbols) \(keyDisplayName)"
    }

    // 誤操作を起こしやすい「修飾キーなしの単独キー」ではないことを確認します。
    // 入力時とStoreの現行スキーマ検証、Carbon登録の共通条件です。
    var hasSupportedModifier: Bool {
        let supportedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return carbonModifiers & supportedModifiers != 0
    }

    // AppKitが渡す実際のキー入力から、保存・登録可能なショートカットを作ります。
    // 修飾キーを1つも含まない入力はnilを返し、入力欄側で警告音を鳴らして記録を続けます。
    static func make(from event: NSEvent) -> GlobalShortcut? {
        // deviceIndependentFlagsMaskで、マウスや機種固有の不要なビットを先に除外します。
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // NSEventの修飾キー表現を、CarbonがRegisterEventHotKeyで要求する値へ1つずつ変換します。
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }

        // 通常キーだけをOS全体で奪わないよう、少なくとも1つの修飾キーを必須にします。
        guard modifiers != 0 else { return nil }

        // event.keyCodeはUInt16ですが、Carbon登録とJSON保存に合わせてUInt32へ広げます。
        let recordedKeyCode = UInt32(event.keyCode)
        // キーコードと入力文字から、人が読める表示名を作ります。
        let recordedKeyName = displayName(for: event)
        return GlobalShortcut(
            keyCode: recordedKeyCode,
            carbonModifiers: modifiers,
            keyDisplayName: recordedKeyName
        )
    }

    // 制御文字になりやすい特殊キーへ明示的な名前を与え、それ以外は実際の入力文字を利用します。
    // 物理キーコードも保存するため、表示名が英字・記号・日本語配列で変わっても登録内容には影響しません。
    private static func displayName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_ANSI_KeypadEnter: return "Keypad Enter"
        case kVK_JIS_Eisu: return "英数"
        case kVK_JIS_Kana: return "かな"
        default:
            // charactersIgnoringModifiersなら、ShiftやOptionで変化した後の文字ではなくキー本来の文字を得られます。
            if let characters = event.charactersIgnoringModifiers,
               !characters.isEmpty,
               characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                return characters.uppercased()
            }
            // 未知の特殊キーでも記録自体を失敗させず、調査可能なキーコードを表示します。
            return "Key \(event.keyCode)"
        }
    }

}

// 登録失敗時に要求値・以前の値・既定値の順で試す、テスト可能な登録ポリシーです。
// 登録APIをクロージャで受け取るため、CarbonやOS状態を変更せず失敗順序を再現できます。
enum GlobalHotkeyRegistrationPolicy {
    static func register(
        requested: GlobalShortcut,
        previous: GlobalShortcut?,
        prepareEventHandler: () -> Bool = { true },
        using registerShortcut: (GlobalShortcut) -> Bool
    ) -> GlobalHotkeyRegistrationResult {
        guard prepareEventHandler() else {
            return GlobalHotkeyRegistrationResult(
                activeShortcut: previous,
                shouldSynchronizeSettings: previous != nil && previous != requested
            )
        }
        var candidates = [requested]
        if let previous, !candidates.contains(previous) {
            candidates.append(previous)
        }
        if !candidates.contains(.optionSpace) {
            candidates.append(.optionSpace)
        }
        let activeShortcut = candidates.first(where: registerShortcut)
        return GlobalHotkeyRegistrationResult(
            activeShortcut: activeShortcut,
            shouldSynchronizeSettings: activeShortcut != nil && activeShortcut != requested
        )
    }
}

struct GlobalHotkeyRegistrationResult: Equatable {
    let activeShortcut: GlobalShortcut?
    let shouldSynchronizeSettings: Bool

    func settingsShortcutToSynchronize(comparedTo requested: GlobalShortcut) -> GlobalShortcut? {
        guard shouldSynchronizeSettings,
              let activeShortcut,
              activeShortcut != requested else { return nil }
        return activeShortcut
    }
}

// アプリが前面にないときでも使える、自由入力式グローバルショートカットの登録と解除を担当するクラスです。
// 設定変更時の再登録に加え、入力欄での記録中だけ監視を安全に一時停止・再開します。
private final class GlobalHotkeyMonitor {
    // Carbonへ登録したショートカットを指す参照です。
    // 登録に成功した場合だけ値を持ち、deinitで確実に登録解除するために保存します。
    private var hotKeyReference: EventHotKeyRef?
    // Carbonイベントハンドラを指す参照です。
    // これも登録解除時に必要になるため、モニターの寿命中は保持します。
    private var eventHandlerReference: EventHandlerRef?
    // 現在macOSへ正常に登録できているショートカットです。
    // 設定変更後の新しい組み合わせが競合した場合、この値へ戻して操作不能にならないようにします。
    private(set) var activeShortcut: GlobalShortcut?
    // 設定画面から最後に要求されたショートカットです。
    // 記録のため監視を停止している間に設定が変わった場合、再開時にこの値を登録します。
    private var requestedShortcut: GlobalShortcut?
    // キー記録欄へ入力中かどうかを表します。
    // trueの間はCarbon登録を外し、入力した組み合わせがStartMenuの開閉として先に消費されないようにします。
    private var isSuspended = false
    // StartMenu専用の4文字識別子「SM4M」を16進数で表した値です。
    // 同じイベント受信先に将来別のホットキーを追加しても、どのキーの通知かを区別できます。
    private static let hotKeySignature: OSType = 0x534D344D
    // この機能内で「現在設定された開閉ショートカット」を表す連番です。
    // 実際のキー内容とは無関係な識別番号で、signatureと組み合わせて自分のCarbonイベントか確認します。
    private static let globalShortcutHotKeyID: UInt32 = 1

    // 指定されたショートカットをmacOSへ登録します。
    // 同じ組み合わせがすでに有効なら、余計な解除・再登録を行わずそのまま維持します。
    @discardableResult
    func register(_ requestedShortcut: GlobalShortcut) -> Bool {
        guard requestedShortcut.hasSupportedModifier else { return false }
        // 一時停止中でも最新の要求値を覚え、記録終了後に同じ値を登録できるようにします。
        self.requestedShortcut = requestedShortcut
        // 記録中はCarbonへ触れず「再開時に登録する予約」として成功扱いにします。
        guard !isSuspended else { return true }
        // 値とCarbon参照の両方が有効なら、余計な解除・再登録を行いません。
        // 一時停止直後は値が同じでも参照だけnilなので、参照の確認も必須です。
        guard activeShortcut != requestedShortcut || hotKeyReference == nil else { return true }

        // 競合時の復元候補として、現在実際に登録されているショートカットを保持します。
        let previousShortcut = activeShortcut
        var didUnregisterPrevious = false
        let result = GlobalHotkeyRegistrationPolicy.register(
            requested: requestedShortcut,
            previous: previousShortcut,
            prepareEventHandler: installEventHandlerIfNeeded
        ) { shortcut in
            // 受信口を準備できた後でだけ旧登録を外し、準備失敗時には以前の登録を維持します。
            if !didUnregisterPrevious {
                unregisterActiveHotKey()
                didUnregisterPrevious = true
            }
            return registerHotKey(shortcut)
        }
        activeShortcut = result.activeShortcut
        AppSettingsModel.shared.setGlobalShortcutRegistrationStatus(
            result.activeShortcut.map(GlobalShortcutRegistrationStatus.active) ?? .unavailable
        )
        if let shortcutToSynchronize = result.settingsShortcutToSynchronize(comparedTo: requestedShortcut) {
            self.requestedShortcut = shortcutToSynchronize
            _ = AppSettingsModel.shared.updateSettings { $0.globalShortcut = shortcutToSynchronize }
        }
        return result.activeShortcut == requestedShortcut && didUnregisterPrevious
    }

    // 設定画面でキー記録を始める直前に、現在のCarbon登録だけを一時解除します。
    // activeShortcutは残すため、キャンセル時や新しい組み合わせの登録失敗時に元の値へ戻せます。
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterActiveHotKey()
        AppSettingsModel.shared.setGlobalShortcutRegistrationStatus(.unavailable)
    }

    // キー記録の確定またはキャンセル後に、最後に要求された組み合わせをCarbonへ登録し直します。
    // 戻り値により、AppDelegateは登録競合時に設定表示を実際の有効値へ戻せます。
    @discardableResult
    func resume() -> Bool {
        guard isSuspended else { return true }
        isSuspended = false
        // 記録中に設定が確定していればrequestedShortcut、キャンセルなら従来のactiveShortcutを使います。
        let shortcutToRestore = requestedShortcut ?? activeShortcut ?? .optionSpace
        return register(shortcutToRestore)
    }

    // Carbonのイベント受信口を、未登録の場合に限って準備します。
    // ショートカットの変更時に毎回作り直す必要はないため、1回だけ登録して使い回します。
    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerReference != nil {
            return true
        }

        // Carbonへ「グローバルホットキーが押された」というイベントだけを渡すよう指定します。
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // C言語形式のイベントハンドラを、アプリ全体のイベント受信先へ登録します。
        // コールバックは任意の実行コンテキストから届く可能性があるため、UIを直接触らず通知だけを送ります。
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                // イベントから、押されたグローバルホットキーの識別子を取り出す入れ物です。
                var receivedHotKeyID = EventHotKeyID()
                // Carbonイベントの直接オブジェクトには、登録時に指定したEventHotKeyIDが格納されています。
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedHotKeyID
                )

                // 識別子を取得できなかったイベントは、自分のショートカットとして扱いません。
                guard parameterStatus == noErr else { return noErr }
                // 同じ受信先に届く将来の別ホットキーや、他のCarbonイベントを誤処理しないよう照合します。
                // Carbonが要求するC形式のコールバックでは動的なSelfを捕捉できないため、
                // ここだけはクラス名を明記して、キャプチャなしの関数ポインタとして登録可能にします。
                guard receivedHotKeyID.signature == GlobalHotkeyMonitor.hotKeySignature,
                      receivedHotKeyID.id == GlobalHotkeyMonitor.globalShortcutHotKeyID else {
                    return noErr
                }

                // AppDelegateはメインアクターで状態を管理しているため、通知も必ずメインアクターから送ります。
                // これにより、Swift 6の厳格な並行性チェックでもUI状態を安全に更新できます。
                Task { @MainActor in
                    NotificationCenter.default.post(name: .startMenuGlobalShortcutPressed, object: nil)
                }
                // noErrは「イベントを正常に処理した」ことをCarbonへ返す値です。
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerReference
        )

        // イベントハンドラの登録に失敗した場合、ホットキー本体は登録できないため理由をログへ残して終了します。
        guard handlerStatus == noErr else {
            NSLog("Failed to install the global shortcut event handler: \(handlerStatus)")
            return false
        }
        return true
    }

    // イベント受信口が準備済みであることを前提に、1つの組み合わせをCarbonへ登録します。
    // 登録に成功した場合だけ、activeShortcutとhotKeyReferenceを新しい値へ更新します。
    @discardableResult
    private func registerHotKey(_ shortcut: GlobalShortcut) -> Bool {
        // 登録するキーの「キーコード」と「修飾キー」を、設定画面で記録された値から取得します。
        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.globalShortcutHotKeyID
        )
        // Carbonが返す参照を一度ローカル変数で受け、成功を確認してからプロパティへ保存します。
        var newHotKeyReference: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyReference
        )

        // 他アプリとのキー競合などで登録できない場合も、アプリは通常どおり起動を続けます。
        // Dock操作は使えるため、ユーザーの作業を止めずに問題をログで追跡できます。
        if registrationStatus != noErr {
            NSLog("Failed to register \(shortcut.displayName) as a global shortcut: \(registrationStatus)")
            return false
        }
        // 成功した組み合わせとCarbon参照を同時に保存し、次回の変更時に安全に解除できるようにします。
        hotKeyReference = newHotKeyReference
        activeShortcut = shortcut
        return true
    }

    // 現在有効なCarbonホットキーだけを解除し、イベント受信口は次の再登録のため残します。
    private func unregisterActiveHotKey() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        hotKeyReference = nil
        // activeShortcutは、Carbonへ現在登録されている値だけを表します。
        activeShortcut = nil
    }

    // GlobalHotkeyMonitorが破棄されるとき、macOSへ登録した資源を漏れなく解除します。
    // isolatedを付けることで、この終了処理もメインアクター上で実行されます。
    // Carbon参照はSendableではないポインタ型なので、Swift 6でも安全に読み取れる実行場所を明示します。
    isolated deinit {
        // ホットキー本体が登録済みの場合だけ、Carbonの登録を解除します。
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        // イベントハンドラが登録済みの場合だけ、対応する受信処理も解除します。
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}

// このファイルは、アプリの起動処理と「スタートメニュー本体のウィンドウ」を管理します。
// SwiftUIだけでは細かなウィンドウ制御が難しいため、画面部品はSwiftUI、
// ウィンドウの表示・非表示や位置決めはAppKitという役割分担になっています。
// @mainは「この型がアプリケーションの開始地点です」とSwiftに伝える印です。
@main
struct StartMenu4MacApp: App {
    // SwiftUIのアプリからAppKitのAppDelegateを利用するための橋渡しです。
    // このプロパティがあることで、下にあるAppDelegateの起動イベントが呼ばれます。
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // bodyは、このアプリが持つSwiftUIの「シーン（ウィンドウのまとまり）」を定義します。
    var body: some Scene {
        // SettingsはmacOS標準の「設定」ウィンドウを表します。
        // 通常のメインウィンドウは作らず、スタートメニュー本体はAppDelegate側でNSPanelとして作ります。
        Settings {
            // 設定ウィンドウの中身としてSettingsViewを表示します。
            SettingsView()
                .onAppear {
                    // アプリメニューからSwiftUI標準Settingsを開く経路でも、floatingパネルが内容へ重ならないよう先に隠します。
                    appDelegate.prepareForSettingsPresentation()
                }
        }
    }
}

// NSStatusItemの既存NSMenuに置く、標準Settingsシーンへの唯一のブリッジです。
private struct StatusMenuSettingsRow: View {
    @Environment(\.openSettings) private var openSettings

    let title: String
    let width: CGFloat
    let appDelegate: AppDelegate

    var body: some View {
        Button {
            SettingsSceneOpenSequence.perform(
                prepareForSettings: { appDelegate.prepareForSettingsPresentation() },
                activateApplication: { NSApp.activate(ignoringOtherApps: true) },
                openSettings: { openSettings() }
            )
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(width: width, height: 22, alignment: .leading)
        .accessibilityLabel(title)
    }
}

// NSPanelを継承した、スタートメニュー専用のパネルクラスです。
// NSPanelは一般的な文書ウィンドウより、補助パネルやフローティングUIに向いています。
class StartMenuPanel: NSPanel {
    // borderlessなNSPanelは標準ではキーウィンドウになれないため、明示的に許可します。
    // キーウィンドウになれることで、検索欄への文字入力と、ContentViewのローカルキー監視の両方を
    // 同じ本体パネルで確実に受け取れます。
    override var canBecomeKey: Bool {
        return true
    }

    // StartMenuを開いた直後に検索欄へ入力フォーカスを渡せるよう、メインウィンドウになることも許可します。
    // `nonactivatingPanel`ではこの通常のアクティブ化経路が使えず、キーイベントが届かない原因になるため、
    // build 19では通常のborderlessパネルとして動作させます。
    override var canBecomeMain: Bool {
        return true
    }
}

// macOSアプリ全体のライフサイクルと、パネルの表示状態を管理するクラスです。
// NSObjectはAppKitとの連携に必要な基底クラス、NSApplicationDelegateは起動などの通知を受け取る約束です。
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // 終了要求後の再入を防ぎ、開閉・通知・設定反映から新しい処理を始めないための一回限りの状態です。
    private var isTerminating = false
    // スタートメニュー本体。起動完了時に必ず生成するため、暗黙的アンラップOptional（!）です。
    var panel: StartMenuPanel!
    // 設定変更通知の購読情報を保持します。保持しておくことで監視の寿命が明確になります。
    var settingsObserver: NSObjectProtocol?
    // アプリ外でのマウス押下と左ボタン解放を検知するグローバルイベントモニターです。
    var globalMouseMonitor: Any?
    // StartMenu本体のキー入力を、アプリのライフサイクルと同じ長さで監視するローカルモニターです。
    // ContentViewのonDisappearに置くと、パネルの非表示・再表示のタイミングで監視が外れるため、
    // build 20ではAppDelegateが強参照で保持します。
    private var panelKeyboardMonitor: Any?
#if DEBUG
    private var localTrackpadGestureDiagnosticMonitor: Any?
    private var globalTrackpadGestureDiagnosticMonitor: Any?
    private let trackpadGestureDiagnosticLogStateLock = NSLock()
    private var isTrackpadGestureDiagnosticLoggingEnabled = false
    private let trackpadGestureDiagnosticLogQueue = DispatchQueue(
        label: "com.Floop.StartMenu4Mac.trackpad-gesture-diagnostic",
        qos: .utility
    )
#endif
    // フォルダー名編集中だけReturnの専用ルーティングを有効にします。
    private var isFolderNameEditingActive = false
    private var folderNameEditingObservers: [NSObjectProtocol] = []
    // Carbonへ登録したグローバルショートカットを保持します。
    // AppDelegateの生存中ずっと保持することで、設定された任意の組み合わせが有効になります。
    private var globalHotkeyMonitor: GlobalHotkeyMonitor?
    // Carbonコールバックから届く通知の購読情報です。
    // 参照を保持することで、AppDelegateが通知の受信を継続できます。
    private var globalShortcutObserver: NSObjectProtocol?
    // 見た目・アニメーションの非同期完了より先に状態遷移を確定するテスト可能な状態機械です。
    private var panelTransitions = PanelTransitionMachine()
    private var panelPresentationState: PanelTransitionMachine.State { panelTransitions.state }

    // パネルを非表示にする操作の理由を区別する列挙型です。
    // 各経路で一意の理由を記録し、ContentViewがキーウィンドウ状態に応じて
    // 検索欄へのフォーカス有無を判断するために使用します。
    // ContentViewから参照できるようinternalにしています。
    enum PanelHideReason: String {
        // Dockアイコンの再クリックから閉じた場合です。
        case dockClick
        // グローバルショートカット（保存済みキー組み合わせ）から閉じた場合です。
        case globalShortcut
        // メニューバーのステータスアイテムから閉じた場合です。
        case menuBarClick
        // キーボードのEscキーから閉じた場合です。
        case escKey
        // 設定画面を開くために閉じた場合です。
        case settingsOpen
        // アプリ起動処理の一環としてパネルとアプリ全体を隠した場合です。
        case appLaunch
        // Finder表示処理の一環としてパネルを隠した場合です。
        case finderReveal
        // パネルの外側をクリックして非アクティブになった場合です。
        case otherAppClick
        // 他アプリがアクティブになり、StartMenuが自動的に閉じた場合です。
        case appResignActive
        // Mission Controlやスペース変更でデスクトップが切り替わった場合です。
        case spaceChange
    }

    // P5-Aの常駐アイコンとメニューです。AppDelegateが保持し、アプリ終了まで解放されないようにします。
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var toggleStatusMenuItem: NSMenuItem?
    // A6でrequiresApprovalの間だけ差し込む継続案内項目です。通常状態ではnilにして既存メニューを維持します。
    private var loginApprovalMenuItem: NSMenuItem?

    // A10の終了要求を最小診断へ記録し、通常の保存処理や待機を行わず即時終了します。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true
        teardownObservers()
#if DEBUG
        stopTrackpadGestureDiagnosticLoggingAndFlush()
#endif
        let diagnostic = ShutdownDiagnostic(
            version: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown",
            requestedAt: Date(),
            phase: "applicationShouldTerminate",
            panelVisible: panel?.isVisible ?? false
        )
        saveShutdownDiagnostic(diagnostic)
        return .terminateNow
    }

    // 登録済み監視を終了時に一度だけ解除します。保存ファイルや利用者データはここでは触りません。
    private func teardownObservers() {
        if let panelKeyboardMonitor { NSEvent.removeMonitor(panelKeyboardMonitor); self.panelKeyboardMonitor = nil }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor); self.globalMouseMonitor = nil }
#if DEBUG
        if let localTrackpadGestureDiagnosticMonitor {
            NSEvent.removeMonitor(localTrackpadGestureDiagnosticMonitor)
            self.localTrackpadGestureDiagnosticMonitor = nil
        }
        if let globalTrackpadGestureDiagnosticMonitor {
            NSEvent.removeMonitor(globalTrackpadGestureDiagnosticMonitor)
            self.globalTrackpadGestureDiagnosticMonitor = nil
        }
#endif
        for observer in folderNameEditingObservers { NotificationCenter.default.removeObserver(observer) }
        folderNameEditingObservers.removeAll()
        if let globalShortcutObserver { NotificationCenter.default.removeObserver(globalShortcutObserver); self.globalShortcutObserver = nil }
        globalHotkeyMonitor?.suspend()
    }

    // 終了診断はApplication Supportへatomic保存し、1KiBを超える場合は記録自体を省略します。
    private func saveShutdownDiagnostic(_ diagnostic: ShutdownDiagnostic) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? JSONEncoder().encode(diagnostic), data.count < 1024 else { return }
        let url = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "StartMenu4Mac", isDirectory: true).appendingPathComponent("shutdown_diagnostic.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch { NSLog("Failed to save shutdown diagnostic: \(error.localizedDescription)") }
    }

    // アプリの起動準備が完了した直後に、macOSから自動的に呼ばれます。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 保存済み設定を共有モデルから一度取得し、初期サイズに利用します。
        let settings = AppSettingsModel.shared.settings

        // 枠線やタイトルバーを持たない、スタートメニュー用パネルを生成します。
        panel = StartMenuPanel(
            // contentRectはパネルの初期位置と初期サイズです。位置は後ほど改めて計算します。
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: settings.windowWidth,
                height: settings.windowHeight
            ),
            // nonactivatingPanelを使うと、見た目は表示されてもキーウィンドウにならない場合があります。
            // A4の上下キー操作は本体パネルをキー入力の宛先にする必要があるため、ここではborderlessだけを
            // 指定し、showPanelAnimated()のactivate呼び出しで通常のアクティブパネルとして表示します。
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // 通常ウィンドウより手前に浮くパネルとして振る舞わせます。
        panel.isFloatingPanel = true
        // ウィンドウの重なり順をfloatingレベルにし、通常ウィンドウより前面へ出します。
        panel.level = .floating
        // 背景の透明表現を可能にするため、パネル自体を不透明扱いにしません。
        panel.isOpaque = false
        // 実際の背景描画はContentViewが担当するので、AppKit側の背景は透明にします。
        panel.backgroundColor = .clear
        // SwiftUI側で影を描くため、NSWindow標準の影は無効化します。
        panel.hasShadow = false
        // ユーザーがドラッグしてパネル位置を動かせないようにします。
        panel.isMovable = false
        
        // 🌟 macOS標準のウィンドウ出現アニメーションを無効化（自前で制御するため）
        panel.animationBehavior = .none
        
        // SwiftUIのContentViewをAppKitのNSViewとして扱うため、NSHostingViewで包みます。
        let hostView = NSHostingView(rootView: ContentView())
        // 作成したSwiftUIビューをパネルの表示内容として設定します。
        panel.contentView = hostView

        // ContentViewの表示状態に依存しない常駐のキー監視を登録します。
        // これをパネル作成直後に1回だけ行い、再表示のたびに二重登録しないようにします。
        installPanelKeyboardMonitor()
#if DEBUG
        installTrackpadGestureDiagnostic()
#endif

        // パネル作成後にメニューバー項目を準備し、操作時に必ず有効な開閉対象があるようにします。
        configureStatusItem()

        // A6では起動直後のServiceManagement反映を少し待ってから1回だけ確認します。
        // 常時ポーリングせず、以降はアプリ復帰・設定表示・登録解除後の明示的な再取得だけで状態を更新します。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            LoginItemModel.shared.refreshStatus()
            self?.evaluateLoginItemApproval()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoginItemStatusDidChange(_:)),
            name: LoginItemModel.statusDidChangeNotification,
            object: LoginItemModel.shared
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // P5-Bでは、起動理由にかかわらずパネルを初期表示しません。
        // SMAppService.mainAppのログイン起動は、環境によって起動直後にアプリをアクティブ化するため、
        // NSApp.isActiveや未文書の起動引数による判別は信頼できません。起動時は常にバックグラウンド待機とし、
        // メニューバー、Dockの再オープン、グローバルショートカットという明示的な利用者操作だけで表示します。
        
        // アプリが非アクティブになった（別アプリへ切り替えた）通知を監視します。
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // AppDelegateのパネル状態はメインアクターだけで変更するため、通知クロージャから安全な実行場所へ戻します。
            Task { @MainActor [weak self] in
                // スタートメニューを閉じ、他のウィンドウがなければアプリ自体も隠します。
                self?.closePanelAnimated(andHideApp: true, hideReason: .appResignActive)
            }
        }

        // Dockや他アプリなど、このアプリの外側へ送られる左右クリックと左ボタン解放を監視します。
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp]) { [weak self] event in
            // AppDelegateが破棄済みなら、操作対象がないため終了します。
            guard let self = self else { return }
            // 外部の左ボタン解放は、パネルを閉じる要求ではなく観測した事実だけを通知します。
            // active判定より先に扱い、外部drag中もStartMenu4Macがactiveのままのケースを取りこぼしません。
            if event.type == .leftMouseUp {
                guard self.panelPresentationState == .opening || self.panelPresentationState == .visible else { return }
                NotificationCenter.default.post(name: .startMenuExternalLeftMouseUp, object: nil)
                return
            }
            // DockでStartMenu自身をクリックした場合は、アプリが再びアクティブになった状態で
            // applicationShouldHandleReopenが開閉を担当します。ここで同じクリックを「外側クリック」と
            // して閉じると、開いた直後に閉じる競合が起きるため、非アクティブ時だけ閉じる処理へ進みます。
            guard !NSApplication.shared.isActive else { return }
            // すでに隠れている、または閉じる途中なら、外側クリックで追加の処理を行う必要はありません。
            guard self.panelPresentationState == .opening || self.panelPresentationState == .visible else { return }
            // 他アプリやデスクトップをクリックして非アクティブになった場合だけ、メニューを閉じます。
            self.closePanelAnimated(andHideApp: false, hideReason: .otherAppClick)
        }

        // CarbonコールバックはUIを直接変更せず、この通知を送ります。
        // 受信側ではメインアクターへ明示的に戻ってから、Dockと共通の開閉処理を呼び出します。
        globalShortcutObserver = NotificationCenter.default.addObserver(
            forName: .startMenuGlobalShortcutPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NotificationCenterのクロージャはSwift 6では非分離扱いのため、
            // パネル状態の変更は必ずメインアクター内へ移してから実行します。
            Task { @MainActor [weak self] in
                self?.togglePanelFromUserAction(source: .globalShortcut)
            }
        }

        // P1で保存された自由入力ショートカットを、アプリ起動中ずっと有効にします。
        // 現行設定は必須ショートカットを保存し、初回値はOption + Spaceです。
        globalHotkeyMonitor = GlobalHotkeyMonitor()
        let configuredShortcut = AppSettingsModel.shared.settings.globalShortcut
        if globalHotkeyMonitor?.register(configuredShortcut) == false,
           let activeShortcut = globalHotkeyMonitor?.activeShortcut {
            // 初回登録でも、競合後に実際に有効となったfallbackを設定へ同期します。
            _ = AppSettingsModel.shared.updateSettings { $0.globalShortcut = activeShortcut }
        }
        
        // Mission Controlの操作などで、現在のデスクトップスペースが変わった通知を監視します。
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NSWorkspaceの通知クロージャもSwift 6では非分離なので、パネル操作前にメインアクターへ戻します。
            Task { @MainActor [weak self] in
                // 別スペースへスタートメニューが残らないように閉じます。
                self?.closePanelAnimated(andHideApp: true, hideReason: .spaceChange)
            }
        }

        // 設定モデルが発行する独自の「設定が変わった」通知を監視します。
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettingsModel.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NotificationCenterのクロージャはSwift 6では非分離扱いなので、
            // パネル位置とCarbon登録を変更する前にメインアクターへ戻ります。
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // 新しいウィンドウサイズや配置設定を、既存のパネルへ即座に反映します。
                self.applyCurrentSettings()
                // 設定画面で記録した組み合わせを、アプリを再起動せずに登録し直します。
                let requestedShortcut = AppSettingsModel.shared.settings.globalShortcut
                if self.globalHotkeyMonitor?.register(requestedShortcut) == false,
                   let activeShortcut = self.globalHotkeyMonitor?.activeShortcut {
                    // 新しい組み合わせが競合した場合は、実際に復元できた組み合わせを設定にも戻します。
                    // これにより、設定画面の表示と実際に使えるショートカットが食い違いません。
                    _ = AppSettingsModel.shared.updateSettings { $0.globalShortcut = activeShortcut }
                }
            }
        }
    }

    // StartMenu本体がキーウィンドウの間だけ、上下・Return・EscをSwiftUIへ中継します。
    // 設定ウィンドウのIME確定を誤って消費しないため、keyWindowがpanelと一致しないイベントは必ず返します。
    private func installPanelKeyboardMonitor() {
        // 起動処理が将来複数回呼ばれても、同じキー入力を複数回処理しないようにします。
        guard panelKeyboardMonitor == nil else { return }

        folderNameEditingObservers = [
            NotificationCenter.default.addObserver(forName: .startMenuFolderNameEditingBegan, object: nil, queue: .main) { [weak self] _ in self?.isFolderNameEditingActive = true },
            NotificationCenter.default.addObserver(forName: .startMenuFolderNameEditingEnded, object: nil, queue: .main) { [weak self] _ in self?.isFolderNameEditingActive = false }
        ]

        panelKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // アプリまたはパネルが破棄済み、非アクティブ、設定画面がキーの場合は、元の宛先へ渡します。
            guard let self,
                  NSApp.isActive,
                  NSApp.keyWindow === self.panel else {
                return event
            }

            // SwiftUIのTextFieldは、編集中だけパネルのfirstResponderへAppKitのフィールドエディター
            // （NSTextView）を設定します。Returnをここでアプリ起動へ変換してnilを返すと、TextFieldの
            // onSubmit/onCommitへイベントが一切届かず、フォルダー名を入力できても確定できません。
            // 検索欄にも独自のonSubmitがあるため、テキスト編集中のReturnは本来の入力欄へ返します。
            let fieldEditor = self.panel?.firstResponder as? NSTextView
            let disposition = StartMenuPanelKeyboardDisposition.disposition(
                forKeyCode: event.keyCode,
                isFieldEditor: fieldEditor?.isFieldEditor == true,
                hasMarkedText: fieldEditor?.hasMarkedText() == true,
                isFolderNameEditing: self.isFolderNameEditingActive
            )

            switch disposition {
            case .forwardToResponder:
                return event
            case .commitIME:
                // marked textを含むReturnは入力先へ返し、同じキーで保存しないよう同期通知します。
                NotificationCenter.default.post(name: .startMenuFolderNameIMECommit, object: self)
                return event
            case .submitFolderName:
                // IME確定後の通常Returnは通知経由で保存し、TextFieldのsubmit競合を避けます。
                NotificationCenter.default.post(name: .startMenuFolderNameSubmit, object: self)
                return nil
            case .dispatch(let command):
                NotificationCenter.default.post(
                    name: .startMenuPanelKeyboardCommand,
                    object: self,
                    userInfo: ["command": command.rawValue]
                )
                return nil
            }
        }
    }

#if DEBUG
    // Issue #1の実機調査専用です。イベントは記録するだけで、加工・消費・合成しません。
    private func installTrackpadGestureDiagnostic() {
        guard localTrackpadGestureDiagnosticMonitor == nil,
              globalTrackpadGestureDiagnosticMonitor == nil else { return }
        trackpadGestureDiagnosticLogStateLock.lock()
        isTrackpadGestureDiagnosticLoggingEnabled = true
        trackpadGestureDiagnosticLogStateLock.unlock()
        let mask: NSEvent.EventTypeMask = [.magnify, .swipe]
        localTrackpadGestureDiagnosticMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.logTrackpadGestureDiagnostic(event, scope: "local")
            return event
        }
        globalTrackpadGestureDiagnosticMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.logTrackpadGestureDiagnostic(event, scope: "global")
        }
        recordTrackpadGestureDiagnosticLine(
            "[TrackpadGestureDiagnostic] started pid=\(ProcessInfo.processInfo.processIdentifier) " +
            "log=\(trackpadGestureDiagnosticLogURL.path)"
        )
    }

    private func logTrackpadGestureDiagnostic(_ event: NSEvent, scope: String) {
        let magnification = event.type == .magnify ? String(Double(event.magnification)) : "n/a"
        let reportedTouchCount = event.allTouches().count
        let panelIsKey = panel != nil && NSApp.keyWindow === panel
        recordTrackpadGestureDiagnosticLine(
            "[TrackpadGestureDiagnostic] scope=\(scope) active=\(NSApp.isActive) panelKey=\(panelIsKey) " +
            "type=\(String(describing: event.type)) phase=\(String(describing: event.phase)) " +
            "magnification=\(magnification) deltaX=\(event.deltaX) deltaY=\(event.deltaY) " +
            "windowNumber=\(event.windowNumber) reportedTouchCount=\(reportedTouchCount)"
        )
    }

    private var trackpadGestureDiagnosticLogURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StartMenu4Mac-trackpad-diagnostic-\(ProcessInfo.processInfo.processIdentifier).log")
    }

    private func recordTrackpadGestureDiagnosticLine(_ line: String) {
        trackpadGestureDiagnosticLogStateLock.lock()
        guard isTrackpadGestureDiagnosticLoggingEnabled else {
            trackpadGestureDiagnosticLogStateLock.unlock()
            return
        }
        NSLog("%@", line)
        let url = trackpadGestureDiagnosticLogURL
        trackpadGestureDiagnosticLogQueue.async {
            let data = Data((line + "\n").utf8)
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                NSLog("[TrackpadGestureDiagnostic] log-write-failed error=%@", error.localizedDescription)
            }
        }
        trackpadGestureDiagnosticLogStateLock.unlock()
    }

    private func stopTrackpadGestureDiagnosticLoggingAndFlush() {
        trackpadGestureDiagnosticLogStateLock.lock()
        isTrackpadGestureDiagnosticLoggingEnabled = false
        trackpadGestureDiagnosticLogStateLock.unlock()

        let drained = DispatchSemaphore(value: 0)
        trackpadGestureDiagnosticLogQueue.async {
            drained.signal()
        }
        if drained.wait(timeout: .now() + 1) == .timedOut {
            NSLog("[TrackpadGestureDiagnostic] log-flush-timed-out")
        }
    }
#endif

    // アプリ終了時にAppKitへ登録したモニターを解除します。
    // AppDelegateが終了まで生存する設計ですが、明示解除して再起動・テスト時の残留を防ぎます。
    deinit {
        if let panelKeyboardMonitor {
            NSEvent.removeMonitor(panelKeyboardMonitor)
        }
#if DEBUG
        if let localTrackpadGestureDiagnosticMonitor {
            NSEvent.removeMonitor(localTrackpadGestureDiagnosticMonitor)
        }
        if let globalTrackpadGestureDiagnosticMonitor {
            NSEvent.removeMonitor(globalTrackpadGestureDiagnosticMonitor)
        }
#endif
    }

    // P5-Aのメニューバーアイコンと、開閉・設定・終了の固定メニューを1回だけ作成します。
    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        guard let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L10n.statusItemAccessibility)
            ?? NSApp.applicationIconImage else { return }
        image.isTemplate = true
        button.image = image
        button.toolTip = "StartMenu4Mac"
        button.setAccessibilityLabel(L10n.statusItemAccessibility)

        let menu = NSMenu()
        menu.delegate = self
        let toggleItem = NSMenuItem(title: L10n.statusMenuOpen, action: #selector(togglePanelFromStatusItem(_:)), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.statusMenuSettings, action: nil, keyEquivalent: "")
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.statusMenuQuit, action: #selector(terminateFromStatusItem(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        // NSMenuとローカライズされた行幅を保ちながら、クリックはSwiftUI標準Settingsシーンへ送ります。
        let menuFont = NSFont.menuFont(ofSize: 0)
        let widestTitle = menu.items
            .filter { !$0.isSeparatorItem }
            .map { ($0.title as NSString).size(withAttributes: [.font: menuFont]).width }
            .max() ?? 0
        let settingsRow = StatusMenuSettingsRow(
            title: L10n.statusMenuSettings,
            width: max(widestTitle + 32, 120),
            appDelegate: self
        )
        let settingsHostingView = NSHostingView(rootView: settingsRow)
        settingsHostingView.frame = NSRect(origin: .zero, size: settingsHostingView.fittingSize)
        settingsItem.view = settingsHostingView

        item.menu = menu
        statusItem = item
        statusMenu = menu
        toggleStatusMenuItem = toggleItem
    }

    // LoginItemModelがOS状態を再取得した結果を受け、メニューの継続案内と1プロセス1回のダイアログを更新します。
    @objc private func handleLoginItemStatusDidChange(_ notification: Notification) {
        evaluateLoginItemApproval()
    }

    // システム設定から戻った直後にも確認します。モデル側の消費済みフラグが同じダイアログの再表示を防ぎます。
    @objc private func handleApplicationDidBecomeActive(_ notification: Notification) {
        LoginItemModel.shared.refreshStatus()
        evaluateLoginItemApproval()
    }

    // requiresApprovalだけを案内対象にして、正常なOFF・初回未登録ではメニューもダイアログも出しません。
    private func evaluateLoginItemApproval() {
        updateLoginApprovalMenuItem()
        guard LoginItemModel.shared.consumeApprovalAlertPresentation() else { return }
        let alert = NSAlert()
        alert.messageText = L10n.loginApprovalAlertTitle
        alert.informativeText = L10n.loginApprovalAlertMessage
        alert.addButton(withTitle: L10n.settingsLoginItemOpenSystemSettings)
        alert.addButton(withTitle: L10n.loginApprovalAlertLater)
        // パネルを表示せず、アプリ標準のモーダルダイアログだけを前面に出します。
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            LoginItemModel.shared.openLoginItemsSystemSettings()
        }
    }

    // 承認待ちの間だけ既存の「開く」と「設定…」の間へ案内項目を差し込み、選択時はOSのログイン項目画面を開きます。
    private func updateLoginApprovalMenuItem() {
        guard let menu = statusMenu else { return }
        if LoginItemModel.shared.requiresApproval {
            guard loginApprovalMenuItem == nil else { return }
            let item = NSMenuItem(title: L10n.statusMenuLoginApproval, action: #selector(openLoginItemApprovalFromStatusItem(_:)), keyEquivalent: "")
            item.target = self
            // 最初の区切り線の直後に置き、通常の設定操作より先に問題へ気づける順序にします。
            menu.insertItem(item, at: min(2, menu.items.count))
            loginApprovalMenuItem = item
        } else if let item = loginApprovalMenuItem {
            menu.removeItem(item)
            loginApprovalMenuItem = nil
        }
    }

    // メニューを開く瞬間だけ状態を反映し、Dock・ショートカット・外側クリック後も正しい文言を表示します。
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu, let item = toggleStatusMenuItem else { return }
        // メニューを開く直前にも状態を確認し、システム設定側の変更を待機中のメニューへ反映します。
        LoginItemModel.shared.refreshStatus()
        updateLoginApprovalMenuItem()
        switch panelPresentationState {
        case .hidden: item.title = L10n.statusMenuOpen; item.isEnabled = true
        case .opening, .visible: item.title = L10n.statusMenuClose; item.isEnabled = true
        case .closing: item.title = L10n.statusMenuClosing; item.isEnabled = false
        }
    }

    @objc private func togglePanelFromStatusItem(_ sender: Any?) { togglePanelFromUserAction(source: .statusItem) }
    // 継続案内からはパネルを開かず、承認操作が必要なログイン項目画面だけを開きます。
    @objc private func openLoginItemApprovalFromStatusItem(_ sender: Any?) { LoginItemModel.shared.openLoginItemsSystemSettings() }
    func prepareForSettingsPresentation() {
        guard !isTerminating else { return }
        // SwiftUI標準の設定シーンを前面にする前に、floatingの本体パネルだけを隠します。
        hidePanelImmediately(reason: .settingsOpen, alsoHideApplication: false)
    }
    @objc private func terminateFromStatusItem(_ sender: Any?) { NSApp.terminate(sender) }

    // 設定画面のショートカット記録欄から、記録の開始・終了を通知される入口です。
    // 入力中に現在のショートカットがStartMenu開閉として発火しないよう、Carbon監視を一時停止します。
    func setGlobalShortcutRecording(_ isRecording: Bool) {
        if isRecording {
            // 同じ入力欄から開始通知が重複しても、GlobalHotkeyMonitor側のguardにより1回だけ停止します。
            globalHotkeyMonitor?.suspend()
            return
        }

        // 記録終了時は、確定済みの新しい値、またはキャンセル前の値を再登録します。
        if globalHotkeyMonitor?.resume() == false,
           let activeShortcut = globalHotkeyMonitor?.activeShortcut {
            // OSや他アプリとの競合で新しい組み合わせを登録できなかった場合、
            // 実際に復元できたショートカットへ設定値も戻し、表示と動作の食い違いを防ぎます。
            _ = AppSettingsModel.shared.updateSettings { $0.globalShortcut = activeShortcut }
        }
    }

    private var shouldAnimatePanelTransitions: Bool {
        AppSettings.shouldAnimate(
            appEnabled: AppSettingsModel.shared.settings.animationsEnabled,
            osReduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            swiftReduceMotion: false
        )
    }

    // Win11風の「少し下からフワッとフェードイン」する表示アニメーションです。
    func showPanelAnimated() {
        guard !isTerminating else { return }
        // hidden以外は、すでに表示中・アニメーション中のため、新しい表示を重ねません。
        // 特にclosing中のDock通知をここで受け付けないことが、閉じた直後の勝手な再表示を防ぎます。
        guard let transitionGeneration = panelTransitions.beginShowing() else { return }
        // まず最終表示位置を確定させます。ここを基準に開始位置を下へずらします。
        positionPanelAboveDock() // 最終的な定位置を計算
        
        // panel.frameを値としてコピーし、アニメーション開始用の矩形を作ります。
        var startFrame = panel.frame
        startFrame.origin.y -= 15 // 🌟 定位置より15ポイント下からスタート
        
        // 透明＆少し下の位置でウィンドウを準備
        // display:falseなので、この時点では不要な再描画を要求せずフレームだけ準備します。
        panel.setFrame(startFrame, display: false)
        // 完全に透明な状態からフェードインさせます。
        panel.alphaValue = 0.0
        // パネルを表示し、同時にキーボード入力を受け取るキーウィンドウにします。
        panel.makeKeyAndOrderFront(nil)
        // 他アプリがアクティブでも、このアプリを前面へ切り替えます。
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        guard shouldAnimatePanelTransitions else {
            var targetFrame = panel.frame
            targetFrame.origin.y += 15
            panel.setFrame(targetFrame, display: true)
            panel.alphaValue = 1.0
            finishPanelShowing(generation: transitionGeneration)
            return
        }

        // アニメーション実行
        // このクロージャ内のanimator()経由の変更を、ひとまとまりのアニメーションとして実行します。
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22 // 開くときは少し早めでサクッと
            context.timingFunction = CAMediaTimingFunction(name: .easeOut) // 徐々にゆっくりになる自然な動き
            
            // 透明度を1へ補間し、徐々に見えるようにします。
            panel.animator().alphaValue = 1.0
            
            // 現在の開始フレームをコピーし、15ポイント上の最終位置を作ります。
            var targetFrame = panel.frame
            targetFrame.origin.y += 15 // 15ポイント上へ動かして定位置に戻る
            panel.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            // NSAnimationContextの完了クロージャは、Swift 6ではメインアクターに属さない処理として扱われます。
            // パネルの状態はAppDelegate（メインアクター）のみが読み書きするため、ここで明示的に戻します。
            Task { @MainActor [weak self] in
                // アニメーション中にAppDelegateが解放される可能性もあるため、安全に参照を取り出します。
                guard let self = self else { return }
                self.finishPanelShowing(generation: transitionGeneration)
            }
        })
    }

    private func finishPanelShowing(generation: Int) {
        guard panelTransitions.finishShowing(generation: generation) else { return }
        NotificationCenter.default.post(name: .startMenuPanelDidFinishShowing, object: nil, userInfo: [StartMenuPanelLifecycleUserInfoKey.generation: generation])
    }

    // パネル非表示の唯一の内部入口です。
    // 状態判定、重複要求処理、世代採番、通知送信、アニメーション開始、
    // 即時非表示、orderOut、alpha復元、.hidden遷移、アプリ非表示までをすべて所有します。
    // closePanelAnimated()とhidePanelImmediately()はanimated引数だけを分ける薄いラッパーです。
    private func beginPanelHiding(
        reason: PanelHideReason,
        alsoHideApplication: Bool,
        animated: Bool,
        intentPolicy: PanelTransitionMachine.HideIntentPolicy = .merge
    ) {
        let request = panelTransitions.beginHiding(
            alsoHideApplication: alsoHideApplication,
            intentPolicy: intentPolicy
        )
        let hideGeneration: Int
        switch request {
        case .mergeExisting:
            return
        case .alreadyHidden(let shouldHideApplication):
            if shouldHideApplication { hideAppIfNoOtherWindows() }
            return
        case .started(let generation):
            hideGeneration = generation
        }

        // 4. startMenuPanelWillHide(generation, reason)を1回だけ送信
        NotificationCenter.default.post(
            name: .startMenuPanelWillHide,
            object: nil,
            userInfo: [
                StartMenuPanelLifecycleUserInfoKey.generation: hideGeneration,
                StartMenuPanelLifecycleUserInfoKey.reason: reason.rawValue
            ]
        )

        // パネルがすでに画面から消えている場合は、アニメーションをスキップして後片付けへ進みます。
        guard panel.isVisible, panel.alphaValue > 0 else {
            finishPanelHiding(generation: hideGeneration)
            return
        }

        if animated && shouldAnimatePanelTransitions {
            // 5a. アニメーション開始 → 完了時に後片付け
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15 // 閉じるときはサッと消す
                context.timingFunction = CAMediaTimingFunction(name: .easeIn) // スッと加速して消える動き

                // 透明度を0まで補間してフェードアウトさせます。
                panel.animator().alphaValue = 0.0

                // 消える動きの目的地として、現在位置より10ポイント下のフレームを作ります。
                var targetFrame = panel.frame
                targetFrame.origin.y -= 10 // 消えるときは10ポイント下に沈む
                panel.animator().setFrame(targetFrame, display: true)

            }, completionHandler: { [weak self] in
                // 表示アニメーションと同様に、完了通知からメインアクターへ戻って状態を更新します。
                // これによりSwift 6で「非分離コンテキストからのEquatable比較」と判定される問題を解消します。
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.finishPanelHiding(generation: hideGeneration)
                }
            })
        } else {
            // 5b. 即時非表示 → 直ちに後片付け
            finishPanelHiding(generation: hideGeneration)
        }
    }

    // 非表示処理の共通後片付けです。beginPanelHiding()からだけ呼ばれます。
    // 世代確認は呼び出し側で完了している前提です。
    private func finishPanelHiding(generation: Int) {
        guard let shouldHideApplication = panelTransitions.finishHiding(generation: generation) else { return }

        // 6. orderOut - 透明になったパネルを画面上から取り除きます。
        panel.orderOut(nil)

        // 7. alphaを次回表示可能な値へ戻します。
        panel.alphaValue = 1.0

        // 保留中のアプリ非表示要求は状態機械で一度だけ消費します。
        if shouldHideApplication { hideAppIfNoOtherWindows() }
    }

    // closePanelAnimatedはbeginPanelHidingへ委譲する薄いラッパーです。
    // 理由の既定値は付けず、全呼び出し元で明示します。
    func closePanelAnimated(
        andHideApp: Bool = false,
        hideReason: PanelHideReason
    ) {
        beginPanelHiding(
            reason: hideReason,
            alsoHideApplication: andHideApp,
            animated: true
        )
    }

    // hidePanelImmediatelyはbeginPanelHidingへ委譲します。
    // Settingsだけは終了中の「アプリも隠す」要求を置き換え、標準設定シーンを開いたアプリが隠れないようにします。
    private func hidePanelImmediately(
        reason: PanelHideReason,
        alsoHideApplication: Bool
    ) {
        beginPanelHiding(
            reason: reason,
            alsoHideApplication: alsoHideApplication,
            animated: false,
            intentPolicy: reason == .settingsOpen ? .replace : .merge
        )
    }

    // hidePanelAndApplicationは従来入口です。P5-A後も「パネルとアプリ全体を隠す」意味は変えません。
    func hidePanelAndApplication(hideReason: PanelHideReason) {
        beginPanelHiding(
            reason: hideReason,
            alsoHideApplication: true,
            animated: false
        )
    }

    
    // スタートメニュー以外に表示中のウィンドウがなければ、アプリ全体を非表示にします。
    func hideAppIfNoOtherWindows() {
        // windows配列の中に条件を満たすものが1つでもあるかcontainsで調べます。
        let hasOtherWindows = NSApp.windows.contains { window in
            // 本体パネルと不可視ウィンドウ、システム内部のステータスバーウィンドウは数えません。
            window != panel && window.isVisible && window.className != "NSStatusBarWindow"
        }
        // 設定画面などが開いていない場合に限り、アプリを隠します。
        if !hasOtherWindows {
            NSApplication.shared.hide(nil)
        }
    }

    // 表示完了時にContentViewが検索欄へフォーカスしてよいかを、
    // 世代と現在の表示状態で判断します。過去の非表示理由を使いません。
    func canFocusSearchField(for generation: Int) -> Bool {
        // 終了中でないこと、世代が一致すること、.visibleであること、
        // アプリがアクティブでパネルがキーウィンドウであることを確認します。
        !isTerminating
            && generation == panelTransitions.generation
            && panelPresentationState == .visible
            && NSApp.isActive
            && NSApp.keyWindow === panel
    }

    // 利用者操作の来源を区別し、閉じる時に正しいPanelHideReasonを使用できるようにします。
    // Dockクリックとショートカットを同じ理由にまとめず、操作元を保持します。
    private enum PanelUserActionSource {
        case dock
        case globalShortcut
        case statusItem

        var hideReason: PanelHideReason {
            switch self {
            case .dock: return .dockClick
            case .globalShortcut: return .globalShortcut
            case .statusItem: return .menuBarClick
            }
        }
    }

    // Dockのアプリアイコンを再クリックしたとき、macOSから呼ばれるデリゲートメソッドです。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dockからの再オープン通知は、グローバルショートカットと同じ状態遷移で処理します。
        // 入口を共通化することで、Dockと現在設定されたショートカットの挙動が食い違わないようにします。
        togglePanelFromUserAction(source: .dock)
        // 標準の再オープン処理は不要で、すべて独自処理済みであることを示します。
        return false
    }

    // Dockクリック、グローバルショートカット、メニューバーのいずれからでも使う、StartMenuの唯一の開閉判断です。
    // sourceを引数で受け取り、閉じる時に正しいPanelHideReasonを使用します。
    // hasVisibleWindowsのようなAppKitの瞬間的な見た目ではなく、アニメーションも含む論理状態を基準にします。
    private func togglePanelFromUserAction(source: PanelUserActionSource) {
        // 状態ごとに、1回の入力が意味する操作を明確に固定します。
        switch panelPresentationState {
        case .hidden:
            // 完全に隠れている場合だけ、表示を開始します。
            showPanelAnimated()
        case .opening, .visible:
            // 表示中または表示途中の入力は、閉じる操作です。sourceから正しい理由を取得します。
            closePanelAnimated(andHideApp: true, hideReason: source.hideReason)
        case .closing:
            // 1回の操作に由来して、閉じる最中に重複通知が届く場合があります。
            // これを新しい操作として表示へ切り替えると「閉じた直後に再び開く」ため、
            // closing中は何もせず、アニメーション完了後の次の操作だけを受け付けます。
            break
        }
    }

    // マウスポインターがある画面のvisibleFrame内へ、A8の左・中央・右設定に従ってパネル全体を配置します。
    func positionPanelAboveDock() {
        let settings = AppSettingsModel.shared.settings
        let targetScreen = screenContainingMouse() ?? NSScreen.main
        guard let targetScreen else { return }
        panel.setFrame(preferredPanelFrame(on: targetScreen, settings: settings), display: true)
    }

    // 副作用なしで最終フレームを計算します。visibleFrameはDock・メニューバーを除き、負座標の副画面もそのまま扱えます。
    private func preferredPanelFrame(on screen: NSScreen, settings: AppSettings) -> NSRect {
        let visibleFrame = screen.visibleFrame
        // Dock・メニューバー回避の上下余白と中央配置の安全余白は従来どおり10ptです。
        let margin: CGFloat = 10
        // 小画面だけは表示幅を一時縮小し、保存済みの希望幅を変更せず画面外を防ぎます。
        let width = min(CGFloat(settings.windowWidth), max(1, visibleFrame.width - margin * 2))
        let height = min(CGFloat(settings.windowHeight), max(1, visibleFrame.height - margin * 2))
        // 左右へ寄せた見た目だけは端に近すぎないよう20ptを基本にします。
        // 小画面で幅が足りない場合は、既存の10ptまで縮めて画面外配置を防ぎます。
        let sideMargin = min(CGFloat(20), max(margin, (visibleFrame.width - width) / 2))
        let requestedX: CGFloat
        switch settings.panelScreenPosition {
        case .left: requestedX = visibleFrame.minX + sideMargin
        case .center: requestedX = visibleFrame.midX - width / 2
        case .right: requestedX = visibleFrame.maxX - width - sideMargin
        }
        // 左右の安全範囲へクランプし、Dock配置や幅変更後もパネルが画面外へ出ないようにします。
        let minimumX = visibleFrame.minX + sideMargin
        let maximumX = visibleFrame.maxX - width - sideMargin
        let x = min(max(requestedX, minimumX), maximumX)
        return NSRect(x: x, y: visibleFrame.minY + margin, width: width, height: height)
    }

    // 現在のマウス座標を含むディスプレイを返します。見つからない場合はnilです。
    func screenContainingMouse() -> NSScreen? {
        // NSEvent.mouseLocationは、全画面共通座標系での現在のポインター位置です。
        let mousePoint = NSEvent.mouseLocation
        // 各画面の矩形を順に調べ、マウス位置を含む最初の画面を返します。
        return NSScreen.screens.first { $0.frame.contains(mousePoint) }
    }

    // 設定画面で値が変わった際、既存パネルのサイズと位置を更新します。
    func applyCurrentSettings() {
        // 最新設定を共有モデルから読み直します。
        let settings = AppSettingsModel.shared.settings
        // 表示中の設定変更ではマウス所在画面へ飛ばさず、現在パネル中心を含む画面内でサイズと位置を同時確定します。
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let targetScreen = NSScreen.screens.first { $0.frame.contains(panelCenter) } ?? screenContainingMouse() ?? NSScreen.main
        guard let targetScreen else { return }
        panel.setFrame(preferredPanelFrame(on: targetScreen, settings: settings), display: true)
    }
}
