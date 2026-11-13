//
//  CloudSync.swift
//  My Cocktail Collection
//
//  Sync and sharing, step 2b: keeps My Library and My Bar in step across your devices through your
//  private iCloud database, using Apple's CloudKit sync engine (CKSyncEngine).
//
//  - CloudSyncLedger decides what to send and applies what arrives. It knows nothing about the
//    network, so it can be tested with two in-memory databases standing in for two devices.
//  - CloudSync owns the sync engine: it tells the ledger when you save, and passes the engine's
//    events (records received, records sent, account changes) to the ledger.
//
//  Rules:
//  - Anything you save is sent. The ledger notices saves from every context except its own.
//  - A change arriving from iCloud doesn't overwrite a change here that's still waiting to be sent;
//    the two meet when this device sends.
//  - If an item is new here but already in iCloud (a built-in on a second device), iCloud's version wins.
//  - If an item changed on two devices, the change sent last wins (whole recipe, not field by field).
//  - Signing out of iCloud keeps your data on the device; it's sent again after signing in.
//

import CloudKit
import Foundation
import OSLog
import SwiftData

// MARK: - Ledger

@MainActor
final class CloudSyncLedger {
    /// What to do with a record iCloud refused to save.
    enum FailedSaveAction: Equatable {
        /// Send it again (after updating its iCloud details).
        case resend
        /// The zone is missing: create it, then send again.
        case createZoneAndResend
        /// A temporary problem (network, iCloud busy): the sync engine retries on its own.
        case wait
        /// Nothing more to send: iCloud's version was taken instead.
        case drop
    }

    struct Changes: Equatable {
        var saves: [CKRecord.ID] = []
        var deletes: [CKRecord.ID] = []
        var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
    }

    /// The bookkeeping for one record, for tests and diagnostics.
    struct Bookkeeping: Equatable {
        var needsUpload: Bool
        var hasSystemFields: Bool
    }

    private let container: ModelContainer
    /// The context the ledger is saving right now, so its own saves aren't mistaken for yours.
    private(set) var savingContext: ModelContext?
    /// Records that arrived before something they link to. They're applied again after each fetch.
    private(set) var waiting: [CKRecord.ID: CKRecord] = [:]

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Your changes

    /// Compares the database with the bookkeeping. New items and items whose identifiers are in `changed`
    /// (or whose ingredients or menu entries are) are to be saved; bookkeeping with no item left means a
    /// deletion. Pass nil to only pick up new items and anything still waiting to be sent (at launch).
    func localChanges(changed: Set<PersistentIdentifier>? = nil) throws -> Changes {
        let context = makeContext()
        var unmatched = try ownSyncRecords(in: context)
        var changes = Changes()

        for item in try localItems(in: context) {
            let recordID = CloudRecords.recordID(for: item.id, type: item.type)
            if let record = unmatched.removeValue(forKey: Self.key(for: recordID)) {
                if let changed, changed.contains(item.modelID) || item.childIDs.contains(where: changed.contains) {
                    record.needsUpload = true
                    record.dateModified = Date()
                }
                if record.needsUpload {
                    changes.saves.append(recordID)
                }
            } else {
                let record = DB.SyncRecord(recordType: item.type.rawValue, recordName: recordID.recordName,
                                           zoneName: recordID.zoneID.zoneName, zoneOwnerName: recordID.zoneID.ownerName)
                record.needsUpload = true
                context.insert(record)
                changes.saves.append(recordID)
            }
        }

        // Bookkeeping with no item: the item was deleted here.
        for record in unmatched.values {
            if record.systemFields == nil {
                context.delete(record) // It never reached iCloud, so there's nothing to delete there.
            } else {
                changes.deletes.append(Self.recordID(of: record))
            }
        }
        try save(context)
        return changes
    }

    /// The record to send for an item, or nil if the item is gone.
    func record(for recordID: CKRecord.ID) throws -> CKRecord? {
        guard Self.isOwn(recordID), let id = UUID(uuidString: recordID.recordName) else { return nil }
        let context = makeContext()
        guard let sync = try syncRecord(for: recordID, in: context),
              let type = CloudRecordType(rawValue: sync.recordType) else { return nil }
        let fields = sync.systemFields
        switch type {
        case .style:
            return try CloudRecords.findStyle(id, library: nil, in: context).map { CloudRecords.record(for: $0, systemFields: fields) }
        case .cocktail:
            return try CloudRecords.findCocktail(id, library: nil, in: context).map { CloudRecords.record(for: $0, systemFields: fields) }
        case .menu:
            return try CloudRecords.findMenu(id, library: nil, in: context).map { CloudRecords.record(for: $0, systemFields: fields) }
        case .bottle:
            return try CloudRecords.findBottle(id, in: context).map { CloudRecords.record(for: $0, systemFields: fields) }
        }
    }

    // MARK: Sent

    /// iCloud saved a record: keep its details for the next change.
    func didSave(_ record: CKRecord) throws {
        let context = makeContext()
        let sync = try syncRecord(for: record.recordID, in: context) ?? insertSyncRecord(for: record, in: context)
        sync.systemFields = CloudSystemFields.encode(record)
        sync.needsUpload = false
        try save(context)
    }

    /// iCloud deleted a record (or it was already gone).
    func didDelete(_ recordID: CKRecord.ID) throws {
        let context = makeContext()
        if let sync = try syncRecord(for: recordID, in: context) {
            context.delete(sync)
        }
        try save(context)
    }

    func resolveFailedSave(_ record: CKRecord, error: CKError) throws -> FailedSaveAction {
        let context = makeContext()
        let sync = try syncRecord(for: record.recordID, in: context)
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord else { return .resend }
            if sync?.systemFields == nil {
                // New on this device but already in iCloud, e.g. a built-in added by another device.
                try apply(server, sync: sync, in: context)
                try save(context)
                return .drop
            }
            // Changed here and on another device: send this device's version on top of iCloud's.
            sync?.systemFields = CloudSystemFields.encode(server)
            try save(context)
            return .resend
        case .zoneNotFound, .userDeletedZone:
            return .createZoneAndResend
        case .unknownItem:
            // Deleted from iCloud while it still exists here: send it as a new record.
            sync?.systemFields = nil
            try save(context)
            return .resend
        default:
            return .wait
        }
    }

    // MARK: Received

    /// Applies records and deletions fetched from iCloud. Only My Library and My Bar for now;
    /// libraries shared with you arrive in step 4.
    func applyFetched(modifications: [CKRecord], deletions: [(recordID: CKRecord.ID, recordType: String)]) throws {
        let context = makeContext()
        let records = modifications.filter { Self.isOwn($0.recordID) }.sorted(by: Self.inApplyOrder)
        for record in records {
            let sync = try syncRecord(for: record.recordID, in: context)
            if sync?.needsUpload == true { continue } // This device's change is sent first.
            try apply(record, sync: sync, in: context)
        }
        for deletion in deletions where Self.isOwn(deletion.recordID) {
            guard let type = CloudRecordType(rawValue: deletion.recordType),
                  let id = UUID(uuidString: deletion.recordID.recordName) else { continue }
            try CloudRecords.deleteItem(type: type, id: id, in: context)
            if let sync = try syncRecord(for: deletion.recordID, in: context) {
                context.delete(sync)
            }
            waiting[deletion.recordID] = nil
        }
        try retryWaiting(in: context)
        try save(context)
    }

    /// Applies again any records that were waiting for something they link to.
    func retryWaiting() throws {
        guard !waiting.isEmpty else { return }
        let context = makeContext()
        try retryWaiting(in: context)
        try save(context)
    }

    // MARK: Resets

    /// A zone was deleted from iCloud (for example from iCloud settings): send everything in it again.
    func forgetZone(_ zoneName: String) throws {
        let context = makeContext()
        for record in try ownSyncRecords(in: context).values where record.zoneName == zoneName {
            record.systemFields = nil
            record.needsUpload = true
        }
        waiting = waiting.filter { $0.key.zoneID.zoneName != zoneName }
        try save(context)
    }

    /// Signed out of iCloud or switched accounts: forget what was sent. Your data stays on the device.
    func resetAll() throws {
        let context = makeContext()
        for record in try ownSyncRecords(in: context).values {
            context.delete(record)
        }
        waiting.removeAll()
        try save(context)
    }

    func bookkeeping(for recordID: CKRecord.ID) throws -> Bookkeeping? {
        try syncRecord(for: recordID, in: makeContext()).map {
            Bookkeeping(needsUpload: $0.needsUpload, hasSystemFields: $0.systemFields != nil)
        }
    }

    // MARK: Helpers

    /// A fresh context for each job, so it always reads what's saved now.
    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func save(_ context: ModelContext) throws {
        guard context.hasChanges else { return }
        savingContext = context
        defer { savingContext = nil }
        try context.save()
    }

    private func apply(_ record: CKRecord, sync: DB.SyncRecord?, in context: ModelContext) throws {
        if try CloudRecords.apply(record, in: context) {
            waiting[record.recordID] = nil
        } else {
            waiting[record.recordID] = record
        }
        let sync = sync ?? insertSyncRecord(for: record, in: context)
        sync.systemFields = CloudSystemFields.encode(record)
        sync.needsUpload = false
    }

    private func retryWaiting(in context: ModelContext) throws {
        for record in waiting.values.sorted(by: Self.inApplyOrder) {
            if try syncRecord(for: record.recordID, in: context)?.needsUpload == true {
                waiting[record.recordID] = nil // Changed here since; this device's version will be sent.
                continue
            }
            if try CloudRecords.apply(record, in: context) {
                waiting[record.recordID] = nil
            }
        }
    }

    private struct LocalItem {
        let type: CloudRecordType
        let id: UUID
        let modelID: PersistentIdentifier
        var childIDs: [PersistentIdentifier] = []
    }

    /// Everything that syncs: My Library's types, cocktails and menus, and My Bar.
    private func localItems(in context: ModelContext) throws -> [LocalItem] {
        var items: [LocalItem] = []
        for style in try context.fetch(FetchDescriptor<DB.SpiritStyle>()) where style.library == nil {
            items.append(LocalItem(type: .style, id: style.id, modelID: style.persistentModelID))
        }
        for cocktail in try context.fetch(FetchDescriptor<DB.Cocktail>()) where cocktail.library == nil {
            items.append(LocalItem(type: .cocktail, id: cocktail.id, modelID: cocktail.persistentModelID,
                                   childIDs: (cocktail.ingredients ?? []).map(\.persistentModelID)))
        }
        for menu in try context.fetch(FetchDescriptor<DB.Menu>()) where menu.library == nil {
            items.append(LocalItem(type: .menu, id: menu.id, modelID: menu.persistentModelID,
                                   childIDs: (menu.entries ?? []).map(\.persistentModelID)))
        }
        for bottle in try context.fetch(FetchDescriptor<DB.Bottle>()) {
            items.append(LocalItem(type: .bottle, id: bottle.id, modelID: bottle.persistentModelID))
        }
        return items
    }

    private func ownSyncRecords(in context: ModelContext) throws -> [String: DB.SyncRecord] {
        let owner = CKCurrentUserDefaultName
        let records = try context.fetch(FetchDescriptor<DB.SyncRecord>(predicate: #Predicate { $0.zoneOwnerName == owner }))
        return Dictionary(records.map { (Self.key(zoneName: $0.zoneName, recordName: $0.recordName), $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    private func syncRecord(for recordID: CKRecord.ID, in context: ModelContext) throws -> DB.SyncRecord? {
        let name = recordID.recordName
        let zone = recordID.zoneID.zoneName
        let owner = recordID.zoneID.ownerName
        var descriptor = FetchDescriptor<DB.SyncRecord>(predicate: #Predicate {
            $0.recordName == name && $0.zoneName == zone && $0.zoneOwnerName == owner
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func insertSyncRecord(for record: CKRecord, in context: ModelContext) -> DB.SyncRecord {
        let sync = DB.SyncRecord(recordType: record.recordType, recordName: record.recordID.recordName,
                                 zoneName: record.recordID.zoneID.zoneName, zoneOwnerName: record.recordID.zoneID.ownerName)
        context.insert(sync)
        return sync
    }

    private static func key(for recordID: CKRecord.ID) -> String {
        key(zoneName: recordID.zoneID.zoneName, recordName: recordID.recordName)
    }

    private static func key(zoneName: String, recordName: String) -> String {
        "\(zoneName)/\(recordName)"
    }

    private static func recordID(of record: DB.SyncRecord) -> CKRecord.ID {
        CKRecord.ID(recordName: record.recordName,
                    zoneID: CKRecordZone.ID(zoneName: record.zoneName, ownerName: record.zoneOwnerName))
    }

    private static func isOwn(_ recordID: CKRecord.ID) -> Bool {
        recordID.zoneID.ownerName == CKCurrentUserDefaultName
    }

    private static func inApplyOrder(_ lhs: CKRecord, _ rhs: CKRecord) -> Bool {
        (CloudRecordType(rawValue: lhs.recordType)?.applyOrder ?? 9) < (CloudRecordType(rawValue: rhs.recordType)?.applyOrder ?? 9)
    }
}

// MARK: - Sync engine

@MainActor
final class CloudSync: CKSyncEngineDelegate {
    private static var current: CloudSync?
    private static let log = Logger(subsystem: "Lemursoft.My-Cocktail-Collection", category: "CloudSync")

    let ledger: CloudSyncLedger
    private var engine: CKSyncEngine?
    private var saveObserver: NSObjectProtocol?
    private let status = CloudSyncStatus.shared
    /// Why the last send left changes waiting (no connection, storage full), shown in Settings.
    private var waitingReason: String?

    /// Starts syncing. Called once at launch; never in tests or previews.
    static func start(container: ModelContainer) {
        guard current == nil else { return }
        let sync = CloudSync(container: container)
        current = sync
        sync.start()
    }

    /// Fetches and sends now, from the Sync Now button in Settings.
    static func syncNow() async {
        guard let sync = current, let engine = sync.engine else { return }
        sync.status.state = .syncing
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            sync.updateStatusAfterSync()
        } catch {
            sync.status.state = .problem(Self.message(for: error))
        }
    }

    private init(container: ModelContainer) {
        ledger = CloudSyncLedger(container: container)
    }

    private func start() {
        let savedState = Self.loadState()
        let cloudContainer = CKContainer(identifier: CloudSchema.containerIdentifier)
        let database = cloudContainer.privateCloudDatabase
        status.state = .checking
        Task { await checkAccount(cloudContainer) }
        engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: savedState, delegate: self))
        if savedState == nil {
            addZones()
        }
        queueLocalChanges(changed: nil)

        // Every save, from any context, may hold changes to send. The ledger's own saves are skipped.
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] notification in
            let identifiers = Self.identifiers(in: notification)
            let savedContext = notification.object as? ModelContext
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let savedContext, savedContext === self.ledger.savingContext { return }
                    Task { @MainActor in self.queueLocalChanges(changed: identifiers) }
                }
            } else {
                Task { @MainActor [weak self] in self?.queueLocalChanges(changed: identifiers) }
            }
        }
    }

    private func checkAccount(_ cloudContainer: CKContainer) async {
        do {
            switch try await cloudContainer.accountStatus() {
            case .available:
                if status.state == .checking { status.state = .syncing }
            case .noAccount:
                status.state = .notSignedIn
            case .restricted, .temporarilyUnavailable, .couldNotDetermine:
                status.state = .unavailable
            @unknown default:
                status.state = .unavailable
            }
        } catch {
            status.state = .unavailable
        }
    }

    /// Up to date once nothing is waiting to be sent; otherwise say why it's waiting.
    private func updateStatusAfterSync() {
        guard let engine else { return }
        if engine.state.pendingRecordZoneChanges.isEmpty && engine.state.pendingDatabaseChanges.isEmpty {
            waitingReason = nil
            status.state = .upToDate(Date())
        } else if let waitingReason {
            status.state = .problem(waitingReason)
        }
    }

    /// A short explanation of a sync error for Settings.
    nonisolated static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return "No internet connection. Your changes are saved on this device and will sync when you're back online."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free up space in iCloud to keep syncing; your changes are saved on this device."
        case .notAuthenticated:
            return "Sign in to iCloud in the Settings app to sync."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is busy. Syncing will try again shortly."
        default:
            return error.localizedDescription
        }
    }

    private func addZones(_ zoneIDs: [CKRecordZone.ID] = [CloudSchema.libraryZoneID(), CloudSchema.myBarZoneID]) {
        engine?.state.add(pendingDatabaseChanges: zoneIDs.map { .saveZone(CKRecordZone(zoneID: $0)) })
    }

    private func queueLocalChanges(changed: Set<PersistentIdentifier>?) {
        guard let engine else { return }
        do {
            let changes = try ledger.localChanges(changed: changed)
            guard !changes.isEmpty else { return }
            engine.state.add(pendingRecordZoneChanges: changes.saves.map { .saveRecord($0) } + changes.deletes.map { .deleteRecord($0) })
        } catch {
            Self.log.error("Couldn't check for changes to send: \(error.localizedDescription)")
        }
    }

    nonisolated private static func identifiers(in notification: Notification) -> Set<PersistentIdentifier> {
        var identifiers = Set<PersistentIdentifier>()
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        for key in keys {
            identifiers.formUnion(notification.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? [])
        }
        return identifiers
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        do {
            switch event {
            case .stateUpdate(let update):
                Self.saveState(update.stateSerialization)
            case .accountChange(let change):
                try handleAccountChange(change)
            case .fetchedDatabaseChanges(let changes):
                let ownZones = [CloudSchema.libraryZoneName, CloudSchema.myBarZoneName]
                for deletion in changes.deletions
                where deletion.zoneID.ownerName == CKCurrentUserDefaultName && ownZones.contains(deletion.zoneID.zoneName) {
                    try ledger.forgetZone(deletion.zoneID.zoneName)
                    addZones([deletion.zoneID])
                    queueLocalChanges(changed: nil)
                }
            case .fetchedRecordZoneChanges(let changes):
                try ledger.applyFetched(modifications: changes.modifications.map(\.record),
                                        deletions: changes.deletions.map { (recordID: $0.recordID, recordType: $0.recordType) })
            case .sentRecordZoneChanges(let sent):
                try handleSent(sent, engine: syncEngine)
            case .didFetchChanges:
                try ledger.retryWaiting()
                updateStatusAfterSync()
            case .didSendChanges:
                updateStatusAfterSync()
            case .willFetchChanges, .willSendChanges:
                if status.state != .notSignedIn { status.state = .syncing }
            case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
                break
            @unknown default:
                break
            }
        } catch {
            Self.log.error("Handling a sync event failed: \(error.localizedDescription)")
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.recordToSend(recordID, engine: syncEngine)
        }
    }

    private func recordToSend(_ recordID: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
        do {
            if let record = try ledger.record(for: recordID) {
                return record
            }
        } catch {
            Self.log.error("Couldn't build a record to send: \(error.localizedDescription)")
        }
        // The item is gone: nothing to send.
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) throws {
        for record in sent.savedRecords {
            try ledger.didSave(record)
        }
        for recordID in sent.deletedRecordIDs {
            try ledger.didDelete(recordID)
        }

        var resend: [CKSyncEngine.PendingRecordZoneChange] = []
        var missingZones: [String: CKRecordZone.ID] = [:]
        for failure in sent.failedRecordSaves {
            switch try ledger.resolveFailedSave(failure.record, error: failure.error) {
            case .resend:
                resend.append(.saveRecord(failure.record.recordID))
            case .createZoneAndResend:
                missingZones[failure.record.recordID.zoneID.zoneName] = failure.record.recordID.zoneID
                resend.append(.saveRecord(failure.record.recordID))
            case .wait:
                waitingReason = Self.message(for: failure.error)
            case .drop:
                break
            }
        }
        for (recordID, error) in sent.failedRecordDeletes where [CKError.Code.unknownItem, .zoneNotFound].contains(error.code) {
            try ledger.didDelete(recordID) // Already gone from iCloud.
        }
        if !missingZones.isEmpty {
            addZones(Array(missingZones.values))
        }
        if !resend.isEmpty {
            engine.state.add(pendingRecordZoneChanges: resend)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) throws {
        switch change.changeType {
        case .signIn:
            status.state = .syncing
            addZones()
            queueLocalChanges(changed: nil)
        case .switchAccounts:
            status.state = .syncing
            try ledger.resetAll()
            addZones()
            queueLocalChanges(changed: nil)
        case .signOut:
            status.state = .notSignedIn
            try ledger.resetAll()
        @unknown default:
            break
        }
    }

    // MARK: Saved state

    /// The sync engine's own progress (what it has fetched, what's waiting to send), kept between launches.
    private static var stateURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("CloudSyncState.json")
    }

    private static func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func saveState(_ state: CKSyncEngine.State.Serialization) {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            log.error("Couldn't save the sync state: \(error.localizedDescription)")
        }
    }
}
