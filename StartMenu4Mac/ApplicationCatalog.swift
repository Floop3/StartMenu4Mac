import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import Darwin
import CoreServices

// アプリフォルダーの変更だけを通知し、走査やキャッシュ操作は行わない監視専用型です。
private final class ApplicationFolderMonitor: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "StartMenu4Mac.application-folder-events")
    private var isStopped = false
    private let onChange: @Sendable () -> Void

    init(roots: [URL], onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = roots.map(\.path) as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let monitor = Unmanaged<ApplicationFolderMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.onChange()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        queue.sync {
            guard !isStopped else { return }
            isStopped = true
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit { stop() }
}

// A5の互換性判定結果です。`unknown`は、情報不足やRosettaのように安全に結論を出せない状態を表します。
// Codableの独自実装により、将来の未知値がキャッシュに入っても全キャッシュを読めなくしません。
enum AppCompatibilityStatus: String, Codable, Equatable, Sendable {
    case compatible
    case incompatible
    case unknown

    nonisolated init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

// A5で「確実に非対応」と判断できた根拠です。UIでは理由を表示せず、保守と将来の診断用にだけ保存します。
enum AppIncompatibilityReason: String, Codable, Equatable, Sendable {
    case minimumSystemVersion
    case unsupported32BitArchitecture
    case unsupportedNativeArchitecture

    nonisolated init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unsupportedNativeArchitecture
    }
}

// ディスクへ保存できるようCodableに準拠した、アプリ1件分のキャッシュ情報です。
// NSImageは直接JSON化できないため、アイコン自体は保存せず、必要時にpathから取得します。
// Equatableは新旧キャッシュ全体の差分判定、Sendableはバックグラウンド走査との安全な受け渡しに使います。
struct AppCacheEntry: Codable, Equatable, Sendable {
    // 現在の言語環境で表示する、ローカライズ済みのアプリ名です。
    let name: String
    // .appを除いた、ファイルシステム上の元の名前です。
    let originalName: String
    // アプリを起動したりアイコンを得たりするための絶対パスです。
    let path: String
    // 大文字・小文字や文字幅の違いを吸収済みの表示名で、検索高速化に使います。
    let foldedName: String
    // 同じく検索用に正規化した元の名前です。
    let foldedOriginalName: String
    // 前回キャッシュ時の更新日時です。アプリ情報が変化したかの判定に使います。
    let modificationDate: TimeInterval
    // A5の保守的な互換性判定です。Optionalにして、旧キャッシュは安全側の未判定として再走査します。
    let compatibilityStatus: AppCompatibilityStatus?
    // 非対応時だけ保存する理由です。互換性がある・不明な場合はnilです。
    let incompatibilityReason: AppIncompatibilityReason?
    // P4-Bの完全一致復旧に使うBundle IDです。旧キャッシュを読めるようOptionalにします。
    let bundleIdentifier: String?
    // A3の表示用発見位置です。起動用のpathとは分離し、旧キャッシュではnilのまま扱います。
    let discoveryFolderPath: String?
    // A14のジャンル判定に使う、アプリ公式Info.plistのカテゴリ識別子です。
    let categoryIdentifier: String?
    // ローカライズ名を生成したpreferred languagesの署名です。旧キャッシュはnilのため再走査します。
    let localizationSignature: String?

    // Swift 6の既定メインアクター設定下でも、UIを持たない値をバックグラウンド走査から作れる初期化処理です。
    // すべてStringまたはDoubleの不変値なので、スレッドをまたいで受け渡しても共有可変状態は発生しません。
    nonisolated init(
        name: String,
        originalName: String,
        path: String,
        foldedName: String,
        foldedOriginalName: String,
        modificationDate: TimeInterval,
        compatibilityStatus: AppCompatibilityStatus? = nil,
        incompatibilityReason: AppIncompatibilityReason? = nil,
        bundleIdentifier: String? = nil,
        discoveryFolderPath: String? = nil,
        categoryIdentifier: String? = nil,
        localizationSignature: String? = nil
    ) {
        self.name = name
        self.originalName = originalName
        self.path = path
        self.foldedName = foldedName
        self.foldedOriginalName = foldedOriginalName
        self.modificationDate = modificationDate
        self.compatibilityStatus = compatibilityStatus
        self.incompatibilityReason = incompatibilityReason
        self.bundleIdentifier = bundleIdentifier
        self.discoveryFolderPath = discoveryFolderPath
        self.categoryIdentifier = categoryIdentifier
        self.localizationSignature = localizationSignature
    }
}

// 🌟 追加：アプリリストのキャッシュを管理するStore
// app_cache.jsonの読み書きを担当する、インスタンス不要の名前空間です。
enum AppCacheStore {
    // キャッシュファイルを読み込み、復元できなければ空配列を返します。
    static func load() -> [AppCacheEntry] {
        // URL取得・データ読み込み・JSON変換を一続きで安全に試します。
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([AppCacheEntry].self, from: data) else {
            return []
        }
        // 正常に復元できたキャッシュ一覧です。
        return entries
    }

    // アプリ一覧のキャッシュをJSONファイルとして保存します。
    static func save(_ entries: [AppCacheEntry]) {
        // 保存先が取得できない場合は何もせず終了します。
        guard let url = cacheURL else { return }
        // ファイル処理の失敗をcatchで受け止め、アプリ本体を落とさないようにします。
        do {
            // アプリ固有の保存フォルダがなければ作成します。
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Codableの配列をJSONデータへ変換します。
            let data = try JSONEncoder().encode(entries)
            // atomic書き込みで、保存途中の不完全なファイルが残る危険を減らします。
            try data.write(to: url, options: [.atomic])
        } catch {
            // 保存失敗の理由だけをシステムログへ残します。
            NSLog("Failed to save app cache: \(error.localizedDescription)")
        }
    }

    // app_cache.jsonの保存先URLを毎回組み立てます。
    private static var cacheURL: URL? {
        // ユーザーのApplication Support内に、Bundle ID別のフォルダとファイル名を連結します。
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "StartMenu4Mac", isDirectory: true)
            .appendingPathComponent("app_cache.json")
    }
}

// バックグラウンド走査からメインアクターへ返す、P2専用の軽量な結果です。
// NSImageやSwiftUIの状態を含めず、Sendableな値だけに限定することで安全に実行場所をまたげます。
struct ApplicationScanResult: Sendable {
    // 重複除去と名前順ソートを終えた、最新のアプリキャッシュ候補です。
    let entries: [AppCacheEntry]
    // 実際に列挙を開始できたルートフォルダ数です。0なら一時的な権限・ファイルシステム問題を疑います。
    let readableRootCount: Int
    // 走査途中でTaskがキャンセルされたかを示し、不完全な結果でキャッシュを上書きしないために使います。
    let wasCancelled: Bool

    // バックグラウンド処理内から結果を作成できるよう、初期化処理を明示的にnonisolatedにします。
    nonisolated init(entries: [AppCacheEntry], readableRootCount: Int, wasCancelled: Bool) {
        self.entries = entries
        self.readableRootCount = readableRootCount
        self.wasCancelled = wasCancelled
    }
}

struct ApplicationScanIdentity: Equatable, Sendable {
    let generation: Int
    let lifecycle: Int
}

// The catalog delegates scan generation and lifecycle decisions to this pure state so they
// can be verified without constructing the MainActor ObservableObject in XCTest.
struct ApplicationScanIdentityState {
    private(set) var changeGeneration = 0
    private(set) var lifecycleGeneration = 0
    private(set) var scanningGeneration: Int?
    private(set) var lastAccepted: ApplicationScanIdentity?

    mutating func markChanged() {
        changeGeneration += 1
    }

    mutating func stopLifecycle() {
        scanningGeneration = nil
        lifecycleGeneration += 1
    }

    mutating func beginScan() -> ApplicationScanIdentity {
        scanningGeneration = changeGeneration
        return ApplicationScanIdentity(generation: changeGeneration, lifecycle: lifecycleGeneration)
    }

    mutating func finishScan(generation: Int) -> Bool {
        guard scanningGeneration == generation else { return false }
        scanningGeneration = nil
        return true
    }

    mutating func accepts(generation: Int, lifecycle: Int, wasCancelled: Bool) -> Bool {
        guard scanningGeneration == generation,
              changeGeneration == generation,
              lifecycleGeneration == lifecycle,
              !wasCancelled else { return false }
        lastAccepted = ApplicationScanIdentity(generation: generation, lifecycle: lifecycle)
        return true
    }
}

// P2の再帰的なアプリ検出だけを担当するスキャナーです。
// SwiftUI、@State、NSImageには一切触れず、ファイルシステムの読み取りと軽量な文字列生成だけを行います。
// 各関数をnonisolatedにすることで、プロジェクトの既定分離がMainActorでも実際にバックグラウンド実行できます。
enum ApplicationScanner {
#if DEBUG
    static func runA3SelfCheck() {
        let root = URL(fileURLWithPath: "/Applications", isDirectory: true)
        assert(relativeFolderPath(for: URL(fileURLWithPath: "/Applications/Adobe Acrobat DC/Adobe Acrobat.app"), from: root) == "Adobe Acrobat DC")
        assert(relativeFolderPath(for: URL(fileURLWithPath: "/Applications/Safari.app"), from: root) == nil)
        let oldEntry = AppCacheEntry(name: "Legacy", originalName: "Legacy", path: "/Applications/Legacy.app", foldedName: "Legacy", foldedOriginalName: "Legacy", modificationDate: 0)
        assert(oldEntry.discoveryFolderPath == nil)
        assert(AppCategoryGroup.from(identifier: "public.app-category.utilities") == .utilities)
        assert(AppCategoryGroup.from(identifier: "public.app-category.games.action") == .games)
        assert(AppCategoryGroup.from(identifier: nil) == .other)
        assert(AppCategoryGroup.from(identifier: "public.app-category.unknown") == .other)
        assert(oldEntry.localizationSignature == nil)
    }

    #if DEBUG
    // ARM32をlegacyとして扱い、ARM64を含むUniversal Binaryは除外しないことを確認します。
    static func runA5SelfCheck() {
        assert(hasOnlyLegacy32BitArchitecture([12]))
        assert(hasOnlyLegacy32BitArchitecture([7]))
        assert(!hasOnlyLegacy32BitArchitecture([0x0100000c]))
        assert(!hasOnlyLegacy32BitArchitecture([12, 0x0100000c]))
    }
    #endif
#endif

    // 以前のbuildが保存したキャッシュパスについても、別の`.app`内部かを同じ規則で判定します。
    // build 7の誤検出を再走査完了前に除去するため、ApplicationCatalogModelから呼べる入口として公開します。
    nonisolated static func isInsideAnotherApplicationPackage(path: String) -> Bool {
        // キャッシュには旧エイリアスパスが残る場合もあるため、リンク解決・標準化してから祖先を確認します。
        let canonicalURL = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return hasApplicationPackageAncestor(for: canonicalURL)
    }

    // 指定された複数のルートフォルダを再帰走査し、画面とキャッシュへ渡すアプリ情報を返します。
    nonisolated static func scan(
        roots: [URL],
        cachedEntries: [AppCacheEntry]
    ) -> ApplicationScanResult {
        // FileManagerはこの同期走査の中だけで使い、SwiftUI側の状態とは共有しません。
        let fileManager = FileManager.default
        // 旧キャッシュを標準化済み実体パスで引けるDictionaryへ変換し、1アプリごとの線形検索を避けます。
        let cacheByCanonicalPath = Dictionary(
            cachedEntries.map { entry in
                (canonicalPath(forPath: entry.path), entry)
            },
            uniquingKeysWith: { currentEntry, duplicateEntry in
                // 旧キャッシュ自体に重複があれば、更新日時が新しい方だけを再利用候補として残します。
                duplicateEntry.modificationDate > currentEntry.modificationDate
                    ? duplicateEntry
                    : currentEntry
            }
        )
        // アプリ名のローカライズ選択に近いpreferred languagesを、走査全体で同じ署名として使います。
        let localizationSignature = preferredLanguagesSignature

        // 同じアプリが通常パス、エイリアス、シンボリックリンクから複数回見つかることを防ぐ識別子集合です。
        var discoveredApplicationIdentities = Set<String>()
        // 走査で確定したアプリ情報を、最後にまとめてソートするまで保持します。
        var discoveredEntries: [AppCacheEntry] = []
        // ルートごとの列挙開始に成功した回数です。
        var readableRootCount = 0

        // アプリ判定、表示名、更新日時、同一実体判定に必要な属性だけを一度に要求します。
        let requestedResourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isAliasFileKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .localizedNameKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]

        // `/Applications`など、呼び出し側で指定されたルートを優先順に走査します。
        for root in roots {
            // 画面破棄などでTaskが取り消された場合は、次のルートへ進まず不完全結果として返します。
            if Task.isCancelled {
                return ApplicationScanResult(
                    entries: discoveredEntries,
                    readableRootCount: readableRootCount,
                    wasCancelled: true
                )
            }

            // 存在しない`~/Applications`などは正常な環境差として扱い、エラーにせず読み飛ばします。
            var rootIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &rootIsDirectory),
                  rootIsDirectory.boolValue else {
                continue
            }

            // skipsPackageDescendantsは、macOSがパッケージと正しく判定できた項目の内部走査を早期に省く第1段階です。
            // build 7の実機確認では一部`.app`でこの判定だけでは不十分だったため、下のループでも明示的に停止します。
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: requestedResourceKeys,
                options: [.skipsPackageDescendants],
                errorHandler: { inaccessibleURL, error in
                    // 一部の子フォルダを読めなくても走査全体は止めず、原因と場所だけをログへ残します。
                    NSLog("Skipped an inaccessible app folder at \(inaccessibleURL.path): \(error.localizedDescription)")
                    return true
                }
            ) else {
                // ルート自体を列挙できなかった場合も、ほかのアプリフォルダの走査は継続します。
                NSLog("Could not enumerate the app folder at \(root.path)")
                continue
            }
            readableRootCount += 1

            // DirectoryEnumeratorが返す子項目を、深さに関係なく1件ずつ確認します。
            for case let discoveredURL as URL in enumerator {
                // 大きなフォルダの途中でもキャンセルへ応答し、不完全結果でキャッシュを更新しないようにします。
                if Task.isCancelled {
                    return ApplicationScanResult(
                        entries: discoveredEntries,
                        readableRootCount: readableRootCount,
                        wasCancelled: true
                    )
                }

                // 拡張子が`.app`の項目へ到達した時点で、FileManagerへその子孫を列挙しないよう明示します。
                // URLResourceKeyのisPackage判定に依存しないため、macOSがパッケージ扱いしなかった特殊なアプリにも有効です。
                if discoveredURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                    enumerator.skipDescendants()
                }

                // 走査ルート直下の正規`.app`は、OS管理の公開リンクがhidden属性を持つ場合も候補にします。
                // それ以外のhidden項目は従来どおり除外し、隠しフォルダー内の補助アプリを一覧へ戻しません。
                if let isHidden = try? discoveredURL.resourceValues(forKeys: [.isHiddenKey]).isHidden,
                   isHidden == true,
                   (discoveredURL.deletingLastPathComponent().standardizedFileURL != root.standardizedFileURL
                    || discoveredURL.pathExtension.caseInsensitiveCompare("app") != .orderedSame) {
                    continue
                }

                // 通常ファイル、Finderエイリアス、シンボリックリンクを同じ「実体アプリURL」へ解決します。
                guard let applicationURL = resolvedApplicationURL(
                    from: discoveredURL,
                    requestedResourceKeys: requestedResourceKeys
                ) else {
                    // `.app`でない項目や、解決不能なリンクはアプリ一覧へ加えません。
                    continue
                }

                // 実体のファイル識別子を優先し、取得不能なファイルシステムだけ実体パスを代替識別子にします。
                let resourceValues = try? applicationURL.resourceValues(
                    forKeys: Set(requestedResourceKeys)
                )
                let identity = applicationIdentity(
                    for: applicationURL,
                    resourceIdentifier: resourceValues?.fileResourceIdentifier
                )
                // すでに同じ実体を追加済みなら、エイリアスなどからの重複発見なので読み飛ばします。
                guard discoveredApplicationIdentities.insert(identity).inserted else { continue }

                // 解決・標準化済みの絶対パスを、起動と次回キャッシュ照合の共通値として使います。
                let applicationPath = applicationURL.path
                // 起動pathは解決後URLを使い、表示階層だけは列挙元URLから取得します。
                // これによりalias／symlinkの実体解決で親フォルダー情報が消えません。
                let discoveryFolderPath = relativeFolderPath(for: discoveredURL, from: root)
                // アプリパッケージの更新日時を秒数化し、前回キャッシュを再利用できるか判断します。
                let modificationDate = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0

                if let cachedEntry = cacheByCanonicalPath[applicationPath],
                   cachedEntry.modificationDate == modificationDate,
                   cachedEntry.compatibilityStatus != nil,
                   cachedEntry.bundleIdentifier != nil,
                   cachedEntry.categoryIdentifier != nil,
                   cachedEntry.localizationSignature == localizationSignature {
                    // アプリ本体が未変更かつA5判定済みなら、名前と互換性情報の再生成を省略します。
                    // 旧キャッシュのnilは再利用しないため、アップデート後の最初の走査で必ず保守的に再判定されます。
                    // pathだけは必ず今回の実体パスを使い、旧エイリアスパスを新キャッシュへ持ち越しません。
                    discoveredEntries.append(AppCacheEntry(
                        name: cachedEntry.name,
                        originalName: cachedEntry.originalName,
                        path: applicationPath,
                        foldedName: cachedEntry.foldedName,
                        foldedOriginalName: cachedEntry.foldedOriginalName,
                        modificationDate: cachedEntry.modificationDate,
                        compatibilityStatus: cachedEntry.compatibilityStatus,
                        incompatibilityReason: cachedEntry.incompatibilityReason,
                        bundleIdentifier: cachedEntry.bundleIdentifier,
                        discoveryFolderPath: discoveryFolderPath,
                        categoryIdentifier: cachedEntry.categoryIdentifier,
                        localizationSignature: localizationSignature
                    ))
                    continue
                }

                // ファイルシステム上の名前から`.app`だけを除き、翻訳に依存しない元の名前を作ります。
                let originalName = applicationURL.deletingPathExtension().lastPathComponent
                // Finderが使用するローカライズ名を優先し、取得不能時は元のファイル名へ戻します。
                let localizedFileName = resourceValues?.localizedName ?? applicationURL.lastPathComponent
                let localizedName = removingApplicationExtension(from: localizedFileName)
                // 検索のたびに変換処理を行わないよう、大文字小文字・文字幅を正規化して保存します。
                let foldedName = localizedName.folding(
                    options: [.caseInsensitive, .widthInsensitive],
                    locale: .current
                )
                let foldedOriginalName = originalName.folding(
                    options: [.caseInsensitive, .widthInsensitive],
                    locale: .current
                )

                // Info.plistと実行バイナリーを読む判定は、このバックグラウンド走査内で完結させます。
                // 解析失敗を非対応と誤認しないよう、判定不能は必ずunknownとして一覧へ残します。
                let compatibility = compatibility(of: applicationURL)
                let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let categoryIdentifier = Bundle(url: applicationURL)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                // UIへ渡せる軽量な1件分の情報として、今回の走査結果へ追加します。
                discoveredEntries.append(AppCacheEntry(
                    name: localizedName,
                    originalName: originalName,
                    path: applicationPath,
                    foldedName: foldedName,
                    foldedOriginalName: foldedOriginalName,
                    modificationDate: modificationDate,
                    compatibilityStatus: compatibility.status,
                    incompatibilityReason: compatibility.reason,
                    bundleIdentifier: bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil,
                    discoveryFolderPath: discoveryFolderPath,
                    categoryIdentifier: categoryIdentifier,
                    localizationSignature: localizationSignature
                ))
            }
        }

        // 現在の言語に合う自然順で整列し、画面表示と次回キャッシュの順序を一致させます。
        let sortedEntries = discoveredEntries.sorted {
            let nameComparison = $0.name.localizedStandardCompare($1.name)
            if nameComparison == .orderedSame {
                // 同名アプリが複数ある場合はパスを第2基準にし、起動ごとに順番が揺れないようにします。
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            return nameComparison == .orderedAscending
        }
        return ApplicationScanResult(
            entries: sortedEntries,
            readableRootCount: readableRootCount,
            wasCancelled: false
        )
    }

    // 列挙で見つけた項目を、エイリアス・シンボリックリンク解決済みの`.app`実体URLへ変換します。
    nonisolated private static func resolvedApplicationURL(
        from discoveredURL: URL,
        requestedResourceKeys: [URLResourceKey]
    ) -> URL? {
        // まず列挙元URLの種類を確認し、Finderエイリアスの場合だけ専用APIで解決します。
        let discoveredValues = try? discoveredURL.resourceValues(
            forKeys: [.isAliasFileKey, .isSymbolicLinkKey]
        )
        var resolvedURL = discoveredURL
        if discoveredValues?.isAliasFile == true {
            // withoutUIにより、バックグラウンド走査中に接続確認などのダイアログを勝手に表示しません。
            guard let aliasTarget = try? URL(
                resolvingAliasFileAt: discoveredURL,
                options: [.withoutUI, .withoutMounting]
            ) else {
                return nil
            }
            resolvedURL = aliasTarget
        }

        // resolvingSymlinksInPathでリンク先を実体パスへ変え、standardizedFileURLで`.`や`..`も除去します。
        resolvedURL = resolvedURL.resolvingSymlinksInPath().standardizedFileURL
        // 拡張子は大文字小文字を区別せず判定し、`.APP`のような表記も取りこぼしません。
        guard resolvedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }

        // 拡張子だけを偽装した通常ファイルを除き、実際にディレクトリまたはパッケージであることも確認します。
        guard let resolvedValues = try? resolvedURL.resourceValues(
            forKeys: Set(requestedResourceKeys)
        ),
              resolvedValues.isDirectory == true || resolvedValues.isPackage == true else {
            return nil
        }

        // エイリアス解決などにより、列挙元とは別の`.app`内部を直接指すURLになる場合があります。
        // 親階層に別の`.app`がある候補は内部ヘルパーなので、独立したランチャー項目として採用しません。
        guard !hasApplicationPackageAncestor(for: resolvedURL) else {
            return nil
        }
        return resolvedURL
    }

    // 候補アプリ自身を除いた親階層に、別の`.app`パッケージが存在するかを調べます。
    // `Outer.app/Contents/Helpers/Inner.app`ならtrue、`/Applications/Normal.app`ならfalseを返します。
    nonisolated private static func hasApplicationPackageAncestor(for applicationURL: URL) -> Bool {
        // 最初の確認対象は候補自身ではなく、その1つ上のフォルダです。
        var ancestorURL = applicationURL.deletingLastPathComponent()
        // ファイルシステムのルートへ到達するまで、親URLを1階層ずつたどります。
        while ancestorURL.path != "/" {
            // 親のどこかが`.app`なら、この候補は別アプリの内部要素です。
            if ancestorURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return true
            }
            // さらに1つ上へ移動します。標準化済み絶対URLなので、最終的には必ず`/`へ到達します。
            ancestorURL.deleteLastPathComponent()
        }
        return false
    }

    // 同じ実体アプリを、通常パス・エイリアス・シンボリックリンクから重複登録しないためのキーを作ります。
    nonisolated private static func applicationIdentity(
        for applicationURL: URL,
        resourceIdentifier: Any?
    ) -> String {
        if let resourceIdentifier {
            // APFSなどが提供するファイル識別子は、同じ実体なら参照経路が違っても同じ値になります。
            return "resource:\(String(reflecting: resourceIdentifier))"
        }
        // 識別子を提供しないファイルシステムでは、解決・標準化済みパスを安全な代替値にします。
        return "path:\(applicationURL.path)"
    }

    // キャッシュパスを現在の実体パスへそろえ、旧キャッシュでも高速なDictionary照合を可能にします。
    nonisolated private static func canonicalPath(forPath path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    // ルート直下はnil、子フォルダー内だけを相対階層として返します。`.app`内部は列挙前に停止済みです。
    nonisolated private static func relativeFolderPath(for discoveredURL: URL, from root: URL) -> String? {
        let relativeURL = discoveredURL.standardizedFileURL.path
            .replacingOccurrences(of: root.standardizedFileURL.path + "/", with: "")
        let components = relativeURL.split(separator: "/")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    // Finderのローカライズ名から、末尾が実際に`.app`の場合だけ拡張子を取り除きます。
    nonisolated private static func removingApplicationExtension(from name: String) -> String {
        let nameAsPath = name as NSString
        guard nameAsPath.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return name
        }
        return nameAsPath.deletingPathExtension
    }

    // A5の判定結果を値としてまとめ、キャッシュとUIへ同じ組を渡します。
    private struct CompatibilityResult: Sendable {
        let status: AppCompatibilityStatus
        let reason: AppIncompatibilityReason?
    }

    // Info.plistの最低OS条件とMach-Oヘッダーだけを読み、起動・外部プロセス・権限要求は一切行いません。
    nonisolated private static func compatibility(of applicationURL: URL) -> CompatibilityResult {
        let bundle = Bundle(url: applicationURL)
        if let minimumVersion = bundle?.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
           let required = operatingSystemVersion(from: minimumVersion),
           isCurrentOS(olderThan: required) {
            return CompatibilityResult(status: .incompatible, reason: .minimumSystemVersion)
        }

        guard let executableURL = bundle?.executableURL,
              let architectures = machoArchitectures(at: executableURL),
              !architectures.isEmpty else {
            return CompatibilityResult(status: .unknown, reason: nil)
        }

        // CPU番号は標準のUInt32だけで保持し、バックグラウンド走査へ独自列挙型のアクター分離を持ち込みません。
        if Self.hasOnlyLegacy32BitArchitecture(architectures) {
            return CompatibilityResult(status: .incompatible, reason: .unsupported32BitArchitecture)
        }

        let requiresNativeExecution = (bundle?.object(forInfoDictionaryKey: "LSRequiresNativeExecution") as? NSNumber)?.boolValue == true
        if runsOnAppleSilicon {
            if requiresNativeExecution && !architectures.contains(0x0100000c) {
                return CompatibilityResult(status: .incompatible, reason: .unsupportedNativeArchitecture)
            }
            // Intel専用アプリはRosettaで動く場合があるため、A5では非対応にせずunknownに留めます。
            if !architectures.contains(0x0100000c) && architectures.contains(0x01000007) {
                return CompatibilityResult(status: .unknown, reason: nil)
            }
        } else if architectures.contains(0x0100000c) && !architectures.contains(0x01000007) {
            return CompatibilityResult(status: .incompatible, reason: .unsupportedNativeArchitecture)
        }

        return CompatibilityResult(status: .compatible, reason: nil)
    }

    // `13.4`や`14.0.1`を数値の組へ変換し、空文字・文字列混入などは判定不能としてnilを返します。
    nonisolated private static func operatingSystemVersion(from value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 3 else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    // 実行中macOSが必要バージョン未満かを、major/minor/patchの順に比較します。
    nonisolated private static func isCurrentOS(olderThan required: [Int]) -> Bool {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let values = [current.majorVersion, current.minorVersion, current.patchVersion]
        return values.lexicographicallyPrecedes(required)
    }

    // 実行中MacがApple Siliconかをsysctlで問い合わせます。取得不能時は誤非表示を避けるためIntel側の保守条件だけを使います。
    nonisolated private static var runsOnAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    // modern 64-bit architectureが一つもない場合だけ、Intel/PPC/ARMの32-bitを非対応とします。
    nonisolated private static func hasOnlyLegacy32BitArchitecture(_ architectures: Set<UInt32>) -> Bool {
        let hasModernArchitecture = architectures.contains(0x01000007) || architectures.contains(0x0100000c)
        let hasLegacy32BitArchitecture = architectures.contains(7) || architectures.contains(12) || architectures.contains(18)
        return !hasModernArchitecture && hasLegacy32BitArchitecture
    }

    // ローカライズ名のキャッシュ再利用条件に使う、preferred languagesの順序を含む署名です。
    nonisolated private static var preferredLanguagesSignature: String {
        let languages = Locale.preferredLanguages
        return languages.isEmpty ? Locale.current.identifier : languages.joined(separator: "\u{001F}")
    }

    // Mach-OまたはFat Mach-Oの先頭だけを読み、外部の`file`/`lipo`プロセスを使わずCPU_TYPE番号の集合を求めます。
    // 壊れた形式・大きすぎるFatヘッダー・読み取り不能はnilにして、呼び出し側でunknownへ戻します。
    nonisolated private static func machoArchitectures(at executableURL: URL) -> Set<UInt32>? {
        guard let data = try? Data(contentsOf: executableURL, options: [.mappedIfSafe]), data.count >= 8,
              let magic = uint32(in: data, at: 0, littleEndian: false) else { return nil }

        let fatMagic: Set<UInt32> = [0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]
        if fatMagic.contains(magic) {
            let littleEndian = magic == 0xbebafeca || magic == 0xbfbafeca
            guard let count = uint32(in: data, at: 4, littleEndian: littleEndian), count <= 64 else { return nil }
            let entrySize = (magic == 0xcafebabf || magic == 0xbfbafeca) ? 32 : 20
            guard data.count >= 8 + Int(count) * entrySize else { return nil }
            var architectures = Set<UInt32>()
            for index in 0..<Int(count) {
                guard let cpuType = uint32(in: data, at: 8 + index * entrySize, littleEndian: littleEndian) else { return nil }
                architectures.insert(cpuType)
            }
            return architectures
        }

        let littleEndian = magic == 0xcefaedfe || magic == 0xcffaedfe
        let thinMagic: Set<UInt32> = [0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe]
        guard thinMagic.contains(magic), let cpuType = uint32(in: data, at: 4, littleEndian: littleEndian) else { return nil }
        return [cpuType]
    }

    // 指定位置の4バイトを読みます。範囲外アクセスを防いで、壊れた実行ファイルを安全にunknownへ戻せるようにします。
    nonisolated private static func uint32(in data: Data, at offset: Int, littleEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let bytes = data[offset..<(offset + 4)]
        let value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return littleEndian ? value.byteSwapped : value
    }

}

// 走査・監視・cache表示の状態を一元管理し、ContentViewには読み取り専用の一覧を公開します。
@MainActor
final class ApplicationCatalogModel: ObservableObject {
    @Published private(set) var installedApps: [AppItem] = []
    @Published private(set) var successfulScanRevision: Int = 0

    // 既存の優先順を維持し、通常アプリとOS付属アプリの4ルートだけを監視・走査します。
    private static let applicationRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Applications", isDirectory: true)
    ]

    private var applicationFolderMonitor: ApplicationFolderMonitor?
    private var appsAreDirty = false
    private var scanIdentity = ApplicationScanIdentityState()
    private var applicationScanTask: Task<Void, Never>?
    private var applicationRescanDebounceTask: Task<Void, Never>?
    private var isPanelContentVisible = false
    private var isStarted = false
    private let applicationRoots: [URL]
    private let loadCachedEntries: () -> [AppCacheEntry]
    private let saveCachedEntries: ([AppCacheEntry]) -> Void
    private let scanApplications: @Sendable ([URL], [AppCacheEntry]) -> ApplicationScanResult

    deinit {
        // ApplicationFolderMonitor.deinit synchronously stops and releases its stream.
        applicationRescanDebounceTask?.cancel()
        applicationScanTask?.cancel()
    }

    init() {
        applicationRoots = Self.applicationRoots
        loadCachedEntries = { AppCacheStore.load() }
        saveCachedEntries = { AppCacheStore.save($0) }
        scanApplications = { roots, cachedEntries in
            ApplicationScanner.scan(roots: roots, cachedEntries: cachedEntries)
        }
    }

    // Narrow test seam for exercising the real monitor and scanner without touching user cache or app folders.
    init(
        applicationRoots: [URL],
        loadCachedEntries: @escaping () -> [AppCacheEntry],
        saveCachedEntries: @escaping ([AppCacheEntry]) -> Void,
        scanApplications: @escaping @Sendable ([URL], [AppCacheEntry]) -> ApplicationScanResult = { roots, cachedEntries in
            ApplicationScanner.scan(roots: roots, cachedEntries: cachedEntries)
        }
    ) {
        self.applicationRoots = applicationRoots
        self.loadCachedEntries = loadCachedEntries
        self.saveCachedEntries = saveCachedEntries
        self.scanApplications = scanApplications
    }

    // SwiftUIの再表示で複数回呼ばれても、最初の監視・dirty化・即時走査だけを開始します。
    func start() {
        guard !isStarted else { return }
        isStarted = true
        startApplicationFolderMonitoring()
        appsAreDirty = true
        scanIdentity.markChanged()
        requestApplicationRescanIfNeeded(immediate: true)
    }

    // Viewが消える時だけmonitorとTaskを止めます。panel hideではactive scanを止めません。
    func stop() {
        guard isStarted else { return }
        isStarted = false
        stopApplicationFolderMonitoring()
        applicationRescanDebounceTask?.cancel()
        applicationRescanDebounceTask = nil
        applicationScanTask?.cancel()
        applicationScanTask = nil
        scanIdentity.stopLifecycle()
    }

    // パネルが見えた時点でdirtyなら、通常のdebounce付き再走査を要求します。
    func panelDidBecomeVisible() {
        isPanelContentVisible = true
        requestApplicationRescanIfNeeded()
    }

    // 非表示中はdirtyを維持したまま、未実行のdebounceだけを取り消します。
    func panelWillHide() {
        isPanelContentVisible = false
        applicationRescanDebounceTask?.cancel()
        applicationRescanDebounceTask = nil
    }

    // ContentViewが検索開始を検知した時の従来の再走査入口です。探索状態の判断はこのモデルで行います。
    func searchDidBegin() {
        requestApplicationRescanIfNeeded()
    }

    private func startApplicationFolderMonitoring() {
        guard applicationFolderMonitor == nil else { return }
        let lifecycle = scanIdentity.lifecycleGeneration
        applicationFolderMonitor = ApplicationFolderMonitor(roots: applicationRoots) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.scanIdentity.lifecycleGeneration == lifecycle else { return }
                // FSEvents callbackでは走査せず、変更世代とdirtyだけを更新して通常経路へ渡します。
                self.appsAreDirty = true
                self.scanIdentity.markChanged()
                self.requestApplicationRescanIfNeeded()
            }
        }
    }

    private func stopApplicationFolderMonitoring() {
        applicationFolderMonitor?.stop()
        applicationFolderMonitor = nil
    }

    private func requestApplicationRescanIfNeeded(immediate: Bool = false) {
        // hidden中は変更をdirtyのまま保持し、表示または初回起動のimmediateだけを走査可能にします。
        guard appsAreDirty, isPanelContentVisible || immediate else { return }
        guard applicationScanTask == nil else { return }
        applicationRescanDebounceTask?.cancel()
        let lifecycle = scanIdentity.lifecycleGeneration
        if immediate {
            loadApps()
        } else {
            // 連続したFSEventsを700msにまとめ、走査Taskとdebounceの二重起動を防ぎます。
            applicationRescanDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self,
                      !Task.isCancelled,
                      self.scanIdentity.lifecycleGeneration == lifecycle else { return }
                self.applicationRescanDebounceTask = nil
                self.loadApps()
            }
        }
    }

    // P2のcache-first表示を維持し、キャッシュを即時表示してからdetached workerで完全走査します。
    private func loadApps() {
        // 旧キャッシュのうち別アプリパッケージ内部を指す誤検出を、走査完了前にも除外します。
        let storedCacheEntries = loadCachedEntries()
        let cachedEntries = storedCacheEntries.filter { entry in
            !ApplicationScanner.isInsideAnotherApplicationPackage(path: entry.path)
        }
        if cachedEntries.count != storedCacheEntries.count {
            saveCachedEntries(cachedEntries)
        }
        // 有効なキャッシュがあれば、background scanを待たず先に一覧へ反映します。
        if !cachedEntries.isEmpty {
            installedApps = makeAppItems(from: cachedEntries)
        }

        let applicationRoots = self.applicationRoots
        let scanApplications = self.scanApplications
        let scan = scanIdentity.beginScan()
        let scanGeneration = scan.generation
        let lifecycle = scan.lifecycle
        applicationScanTask = Task { [weak self] in
            // 外側Taskのcancelをdetached workerへ伝播し、列挙途中の部分結果を採用しません。
            let worker = Task.detached(priority: .utility) {
                scanApplications(applicationRoots, cachedEntries)
            }
            let scanResult = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard let self else { return }

            // 世代一致のTaskだけが自分の参照を解除し、必要なら次世代の再走査を予約します。
            var shouldRequestRescan = false
            defer {
                if self.scanIdentity.finishScan(generation: scanGeneration) {
                    self.applicationScanTask = nil
                    if shouldRequestRescan {
                        self.requestApplicationRescanIfNeeded()
                    }
                }
            }

            guard self.scanIdentity.accepts(
                generation: scanGeneration,
                lifecycle: lifecycle,
                wasCancelled: Task.isCancelled || scanResult.wasCancelled
            ) else {
                self.appsAreDirty = true
                shouldRequestRescan = true
                return
            }
            // worker／outerのcancel、readable root 0はcacheと一覧を保持しrevisionを進めません。
            guard scanResult.readableRootCount > 0 else {
                NSLog("No application folder could be enumerated; the previous app cache was preserved.")
                self.appsAreDirty = true
                return
            }

            let scannedEntries = scanResult.entries
            if scannedEntries != cachedEntries {
                self.saveCachedEntries(scannedEntries)
            }
            // 空結果も含む完全な走査結果を反映し、ここまで成功した場合だけ完了revisionを進めます。
            installedApps = makeAppItems(from: scannedEntries, reusing: installedApps)
            appsAreDirty = false
            successfulScanRevision += 1
        }
    }

    private func makeAppItems(
        from entries: [AppCacheEntry],
        reusing existingItems: [AppItem] = []
    ) -> [AppItem] {
        // 既存pathを索引化して、同一内容ならAppItemごと、metadata変更だけならiconを再利用します。
        let existingItemsByPath = Dictionary(
            uniqueKeysWithValues: existingItems.map { ($0.path, $0) }
        )
        return entries.map { entry in
            if let existingItem = existingItemsByPath[entry.path],
               existingItem.name == entry.name,
               existingItem.originalName == entry.originalName,
               existingItem.foldedName == entry.foldedName,
               existingItem.foldedOriginalName == entry.foldedOriginalName,
               existingItem.compatibilityStatus == (entry.compatibilityStatus ?? .unknown),
               existingItem.bundleIdentifier == entry.bundleIdentifier,
               existingItem.discoveryFolderPath == entry.discoveryFolderPath,
               existingItem.categoryIdentifier == entry.categoryIdentifier {
                return existingItem
            }
            // 同pathの既存iconがない新規pathだけNSWorkspaceからiconを取得します。
            let icon = existingItemsByPath[entry.path]?.icon
                ?? NSWorkspace.shared.icon(forFile: entry.path)
            return AppItem(
                name: entry.name,
                originalName: entry.originalName,
                path: entry.path,
                icon: icon,
                foldedName: entry.foldedName,
                foldedOriginalName: entry.foldedOriginalName,
                compatibilityStatus: entry.compatibilityStatus ?? .unknown,
                bundleIdentifier: entry.bundleIdentifier,
                discoveryFolderPath: entry.discoveryFolderPath,
                categoryIdentifier: entry.categoryIdentifier
            )
        }
    }
}
