import AppKit
import Combine
import CoreServices
import Foundation

struct RecentFileItem: Identifiable, Equatable, Sendable {
    nonisolated let url: URL
    nonisolated let lastUsedDate: Date

    nonisolated init(url: URL, lastUsedDate: Date) {
        self.url = url
        self.lastUsedDate = lastUsedDate
    }

    nonisolated var id: String { url.standardizedFileURL.path }
    nonisolated var name: String { url.lastPathComponent }
}

enum RecentFilesState: Equatable {
    case idle
    case loading
    case loaded([RecentFileItem])
    case failed
}

@MainActor
struct RecentFileActions {
    let open: (URL) -> Bool
    let revealInFinder: (URL) -> Void

    static var workspace: RecentFileActions {
        RecentFileActions(
            open: { NSWorkspace.shared.open($0) },
            revealInFinder: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        )
    }
}

struct RecentFilesQueryRecord: Sendable {
    nonisolated let url: URL
    nonisolated let lastUsedDate: Date?

    nonisolated init(url: URL, lastUsedDate: Date?) {
        self.url = url
        self.lastUsedDate = lastUsedDate
    }
}

struct RecentFilesQuerySnapshot: Sendable {
    nonisolated let initialGatherComplete: Bool
    nonisolated let sequence: UInt64
    nonisolated let records: [RecentFilesQueryRecord]

    nonisolated init(initialGatherComplete: Bool, records: [RecentFilesQueryRecord], sequence: UInt64 = 0) {
        self.initialGatherComplete = initialGatherComplete
        self.sequence = sequence
        self.records = records
    }
}

enum RecentFilesSpotlightPredicate {
    static func make() -> NSPredicate {
        NSPredicate(format: "%K LIKE '*'", kMDItemFSName as String)
    }
}

struct RecentFilesNotificationSequence: Sendable {
    nonisolated let initialGatherComplete: Bool
    nonisolated let sequence: UInt64
}

final class RecentFilesNotificationGate: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var stopped = false
    nonisolated(unsafe) private var initialGatherComplete = false
    nonisolated(unsafe) private var sequence: UInt64 = 0

    nonisolated init() {}

    // This lock-backed helper owns no actor-bound cleanup; keep destruction nonisolated.
    nonisolated deinit {}

    nonisolated func beginNotification(isInitialGatherCompletion: Bool) -> RecentFilesNotificationSequence? {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return nil }
        if isInitialGatherCompletion {
            initialGatherComplete = true
        }
        guard initialGatherComplete else { return nil }
        sequence &+= 1
        return RecentFilesNotificationSequence(
            initialGatherComplete: initialGatherComplete,
            sequence: sequence
        )
    }

    nonisolated func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    nonisolated var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped
    }
}

@MainActor
protocol RecentFilesQuerying: AnyObject {
    func start(onSnapshot: @escaping @MainActor (RecentFilesQuerySnapshot) -> Void) -> Bool
    func stop()
}

@MainActor
final class RecentFilesCatalog: ObservableObject {
    @Published private(set) var state: RecentFilesState = .idle

    private let queryFactory: @MainActor () -> any RecentFilesQuerying
    private let initialGatherTimeout: Duration
    private let processRecords: @Sendable ([RecentFilesQueryRecord]) -> [RecentFileItem]
    // MainActor methods own all writes; nonisolated teardown only cancels Sendable tasks and schedules query.stop back to MainActor.
    nonisolated(unsafe) private var query: (any RecentFilesQuerying)?
    nonisolated(unsafe) private var initialGatherTimeoutTask: Task<Void, Never>?
    nonisolated(unsafe) private var processingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var snapshotGeneration: UInt64 = 0
    private var lastSnapshotSequence: UInt64 = 0
    private var initialGatherCompleted = false

    nonisolated deinit {
        initialGatherTimeoutTask?.cancel()
        processingTask?.cancel()
        if let activeQuery = query {
            Task { @MainActor in activeQuery.stop() }
        }
    }

    convenience init() {
        self.init(queryFactory: { SpotlightRecentFilesQuery() })
    }

    init(
        queryFactory: @escaping @MainActor () -> any RecentFilesQuerying,
        initialGatherTimeout: Duration = .seconds(30),
        processRecords: @escaping @Sendable ([RecentFilesQueryRecord]) -> [RecentFileItem] = {
            RecentFilesCatalog.visibleItems(from: $0)
        }
    ) {
        self.queryFactory = queryFactory
        self.initialGatherTimeout = initialGatherTimeout
        self.processRecords = processRecords
    }

    func start() {
        guard query == nil else { return }

        generation &+= 1
        let requestGeneration = generation
        let newQuery = queryFactory()
        query = newQuery
        initialGatherCompleted = false
        lastSnapshotSequence = 0
        state = .loading

        let didStart = newQuery.start { [weak self, weak newQuery] snapshot in
            guard let self,
                  let newQuery,
                  self.generation == requestGeneration,
                  self.query === newQuery else { return }
            if snapshot.sequence > 0 {
                guard snapshot.sequence > self.lastSnapshotSequence else { return }
                self.lastSnapshotSequence = snapshot.sequence
            }
            guard snapshot.initialGatherComplete else { return }
            self.initialGatherCompleted = true
            self.initialGatherTimeoutTask?.cancel()
            self.initialGatherTimeoutTask = nil
            self.process(snapshot.records, for: requestGeneration)
        }

        if !didStart, generation == requestGeneration, query === newQuery {
            newQuery.stop()
            query = nil
            state = .failed
            return
        }

        if didStart, !initialGatherCompleted {
            let timeout = initialGatherTimeout
            initialGatherTimeoutTask = Task { [weak self, weak newQuery] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                guard let self,
                      let newQuery,
                      self.generation == requestGeneration,
                      self.query === newQuery,
                      !self.initialGatherCompleted else { return }
                self.generation &+= 1
                self.snapshotGeneration &+= 1
                self.processingTask?.cancel()
                self.processingTask = nil
                self.initialGatherTimeoutTask = nil
                self.query = nil
                newQuery.stop()
                self.state = .failed
            }
        }
    }

    func stop() {
        generation &+= 1
        snapshotGeneration &+= 1
        initialGatherCompleted = false
        initialGatherTimeoutTask?.cancel()
        initialGatherTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        let activeQuery = query
        query = nil
        activeQuery?.stop()
        state = .idle
    }

    private func process(_ records: [RecentFilesQueryRecord], for requestGeneration: UInt64) {
        snapshotGeneration &+= 1
        let requestSnapshotGeneration = snapshotGeneration
        processingTask?.cancel()

        let processor = processRecords
        let worker = Task.detached(priority: .utility) {
            processor(records)
        }
        processingTask = Task { [weak self] in
            let items = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard let self,
                  !Task.isCancelled,
                  self.generation == requestGeneration,
                  self.snapshotGeneration == requestSnapshotGeneration else { return }
            self.processingTask = nil
            self.state = .loaded(items)
        }
    }

    nonisolated private static func visibleItems(from records: [RecentFilesQueryRecord]) -> [RecentFileItem] {
        var newestByPath: [String: RecentFileItem] = [:]

        for record in records {
            if Task.isCancelled { return [] }
            guard let date = record.lastUsedDate else { continue }
            let url = record.url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  !isInsideApplicationBundle(url) else { continue }

            let item = RecentFileItem(url: url, lastUsedDate: date)
            if let existing = newestByPath[item.id], existing.lastUsedDate >= date { continue }
            newestByPath[item.id] = item
        }

        return newestByPath.values
            .sorted {
                if $0.lastUsedDate != $1.lastUsedDate {
                    return $0.lastUsedDate > $1.lastUsedDate
                }
                return $0.id < $1.id
            }
            .prefix(50)
            .map { $0 }
    }

    nonisolated private static func isInsideApplicationBundle(_ url: URL) -> Bool {
        var ancestor = url.deletingLastPathComponent()
        while ancestor.path != "/" {
            if ancestor.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: ancestor.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return true
                }
            }
            ancestor.deleteLastPathComponent()
        }
        return false
    }
}

@MainActor
private final class SpotlightRecentFilesQuery: RecentFilesQuerying {
    private let metadataQuery = NSMetadataQuery()
    private let resultOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "StartMenu4Mac.recent-files-metadata-results"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let notificationGate = RecentFilesNotificationGate()
    private lazy var snapshotReader = RecentFilesMetadataSnapshotReader(query: metadataQuery)
    private var observers: [NSObjectProtocol] = []
    private var onSnapshot: (@MainActor (RecentFilesQuerySnapshot) -> Void)?
    private var isStopped = false

    func start(onSnapshot: @escaping @MainActor (RecentFilesQuerySnapshot) -> Void) -> Bool {
        guard !isStopped else { return false }
        self.onSnapshot = onSnapshot
        metadataQuery.searchScopes = [NSMetadataQueryUserHomeScope]
        metadataQuery.predicate = RecentFilesSpotlightPredicate.make()
        metadataQuery.operationQueue = resultOperationQueue

        observers = [
            addObserver(for: .NSMetadataQueryDidFinishGathering, isInitialGatherCompletion: true),
            addObserver(for: .NSMetadataQueryDidUpdate, isInitialGatherCompletion: false)
        ]

        return metadataQuery.start()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        notificationGate.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        let reader = snapshotReader
        resultOperationQueue.addOperation {
            reader.stopQuery()
        }
        onSnapshot = nil
    }

    private func addObserver(
        for notification: Notification.Name,
        isInitialGatherCompletion: Bool
    ) -> NSObjectProtocol {
        let gate = notificationGate
        let reader = snapshotReader
        return NotificationCenter.default.addObserver(
            forName: notification,
            object: metadataQuery,
            queue: nil
        ) { [weak self] _ in
            guard let notificationState = gate.beginNotification(
                isInitialGatherCompletion: isInitialGatherCompletion
            ) else { return }
            let snapshot = reader.makeSnapshot(
                initialGatherComplete: notificationState.initialGatherComplete,
                sequence: notificationState.sequence
            )
            guard gate.isActive else { return }
            Task { @MainActor [weak self] in
                guard gate.isActive, let self, !self.isStopped else { return }
                self.onSnapshot?(snapshot)
            }
        }
    }
}

private final class RecentFilesMetadataSnapshotReader: @unchecked Sendable {
    nonisolated(unsafe) private let query: NSMetadataQuery

    nonisolated init(query: NSMetadataQuery) {
        self.query = query
    }

    nonisolated func stopQuery() {
        query.stop()
    }

    nonisolated func makeSnapshot(initialGatherComplete: Bool, sequence: UInt64) -> RecentFilesQuerySnapshot {
        let records = query.results.compactMap { result -> RecentFilesQueryRecord? in
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let date = item.value(forAttribute: kMDItemLastUsedDate as String) as? Date else { return nil }
            return RecentFilesQueryRecord(url: URL(fileURLWithPath: path), lastUsedDate: date)
        }
        return RecentFilesQuerySnapshot(
            initialGatherComplete: initialGatherComplete,
            records: records,
            sequence: sequence
        )
    }
}
