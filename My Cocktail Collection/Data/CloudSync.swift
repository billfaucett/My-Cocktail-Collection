//
//  CloudSync.swift
//  My Cocktail Collection
//
//  Sync and sharing, steps 2 and 4: keeps My Library and My Bar in step across your devices through
//  your private iCloud database, and keeps libraries other people share with you up to date through
//  the shared database. Uses Apple's CloudKit sync engine (CKSyncEngine), one for each database.
//
//  - CloudSyncLedger decides what to send and applies what arrives. It knows nothing about the
//    network, so it can be tested with in-memory databases standing in for devices.
//  - CloudSync owns the sync engines: it tells the ledger when you save, and passes the engines'
//    events (records received, records sent, account changes) to the ledger.
//
//  Rules:
//  - Anything you save is sent. The ledger notices saves from every context except its own.
//  - A change arriving from iCloud doesn't overwrite a change here that's still waiting to be sent;
//    the two meet when this device sends.
//  - If an item is new here but already in iCloud (a built-in on a second device), iCloud's version wins.
//  - If an item changed on two devices, the change sent last wins (whole recipe, not field by field).
//  - Signing out of iCloud keeps your data on the device; it's sent again after signing in.
//  - A library shared with you is kept apart from yours (its own `Library` row). Your changes to it are
//    sent only if its owner lets you edit. If the owner stops sharing, it's removed from this device.
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
        /// The zone is missing: create it, then send again. (Your own zones only.)
        case createZoneAndResend
        /// A temporary problem (network, iCloud busy): the sync engine retries on its own.
        case wait
        /// Nothing more to send: iCloud's version was taken instead.
        case drop
        /// A shared library is gone (the owner stopped sharing or removed you); it was removed here.
        case libraryRemoved
        /// You can no longer edit a shared library; it's now view only here.
        case nowViewOnly
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

    /// Compares the database with the bookkeeping for one database. New items and items whose
    /// identifiers are in `changed` (or whose ingredients or menu entries are) are to be saved;
    /// bookkeeping with no item left means a deletion. Pass nil to only pick up new items and anything
    /// still waiting to be sent (at launch).
    ///
    /// `.private` covers My Library and My Bar. `.shared` covers libraries shared with you that you're
    /// allowed to edit; there, only items you add or change are sent.
    func localChanges(changed: Set<PersistentIdentifier>? = nil, scope: CKDatabase.Scope = .private) throws -> Changes {
        let context = makeContext()
        var unmatched = try syncRecords(scope: scope, in: context)
        var changes = Changes()

        for item in try localItems(scope: scope, in: context) {
            let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: item.zoneID)
            let touched = changed.map { changed in
                changed.contains(item.modelID) || item.childIDs.contains(where: changed.contains)
            } ?? false
            if let record = unmatched.removeValue(forKey: Self.key(for: recordID)) {
                if touched {
                    record.needsUpload = true
                    record.dateModified = Date()
                }
                if record.needsUpload {
                    changes.saves.append(recordID)
                }
            } else if scope == .private || touched {
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
            } else if scope == .private {
                changes.deletes.append(Self.recordID(of: record))
            } else if try library(zoneName: record.zoneName, ownerName: record.zoneOwnerName, in: context)?.canEdit == true {
                changes.deletes.append(Self.recordID(of: record))
            }
        }
        try save(context)
        return changes
    }

    /// The record to send for an item, or nil if the item is gone (or its shared library can't be edited).
    func record(for recordID: CKRecord.ID) throws -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        let context = makeContext()
        guard let sync = try syncRecord(for: recordID, in: context),
              let type = CloudRecordType(rawValue: sync.recordType) else { return nil }
        let fields = sync.systemFields
        let owner = recordID.zoneID.ownerName
        var library: DB.Library?
        if !Self.isOwn(recordID) {
            guard let shared = try self.library(for: recordID.zoneID, in: context), shared.canEdit else { return nil }
            library = shared
        }
        switch type {
        case .style:
            return try CloudRecords.findStyle(id, library: library, in: context)
                .map { CloudRecords.record(for: $0, systemFields: fields, libraryOwner: owner) }
        case .cocktail:
            return try CloudRecords.findCocktail(id, library: library, in: context)
                .map { CloudRecords.record(for: $0, systemFields: fields, libraryOwner: owner) }
        case .menu:
            return try CloudRecords.findMenu(id, library: library, in: context)
                .map { CloudRecords.record(for: $0, systemFields: fields, libraryOwner: owner) }
        case .bottle:
            guard library == nil else { return nil }
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
        let isOwn = Self.isOwn(record.recordID)
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord else { return .resend }
            if sync?.systemFields == nil {
                // New on this device but already in iCloud, e.g. a built-in added by another device.
                let library = isOwn ? nil : try findOrCreateLibrary(for: server.recordID.zoneID, in: context)
                try apply(server, sync: sync, library: library, in: context)
                try save(context)
                return .drop
            }
            // Changed here and on another device: send this device's version on top of iCloud's.
            sync?.systemFields = CloudSystemFields.encode(server)
            try save(context)
            return .resend
        case .zoneNotFound, .userDeletedZone:
            if isOwn {
                return .createZoneAndResend
            }
            try removeLibrary(zoneID: record.recordID.zoneID)
            return .libraryRemoved
        case .permissionFailure where !isOwn:
            try library(for: record.recordID.zoneID, in: context)?.canEdit = false
            sync?.needsUpload = false
            try save(context)
            return .nowViewOnly
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

    /// Applies records and deletions fetched from iCloud: your own zones into My Library and My Bar,
    /// other people's zones into the library they shared with you.
    func applyFetched(modifications: [CKRecord], deletions: [(recordID: CKRecord.ID, recordType: String)]) throws {
        let context = makeContext()

        // A shared library's share record says who owns it and whether you can edit it.
        for share in modifications.compactMap({ $0 as? CKShare }) where !Self.isOwn(share.recordID) {
            let ownerName = share.owner.userIdentity.nameComponents.map(Self.shortName)
            try updateLibrary(zoneID: share.recordID.zoneID, ownerName: ownerName,
                              canEdit: share.currentUserParticipant?.permission == .readWrite, in: context)
        }

        // Only the app's own record types (share records are never items), and never bottles from others.
        let records = modifications
            .filter { CloudRecordType(rawValue: $0.recordType) != nil }
            .filter { Self.isOwn($0.recordID) || $0.recordType != CloudRecordType.bottle.rawValue }
            .sorted(by: Self.inApplyOrder)
        for record in records {
            let sync = try syncRecord(for: record.recordID, in: context)
            if sync?.needsUpload == true { continue } // This device's change is sent first.
            let library = Self.isOwn(record.recordID) ? nil : try findOrCreateLibrary(for: record.recordID.zoneID, in: context)
            try apply(record, sync: sync, library: library, in: context)
        }

        for deletion in deletions {
            guard let type = CloudRecordType(rawValue: deletion.recordType),
                  let id = UUID(uuidString: deletion.recordID.recordName) else { continue }
            if Self.isOwn(deletion.recordID) {
                try CloudRecords.deleteItem(type: type, id: id, in: context)
            } else if let library = try library(for: deletion.recordID.zoneID, in: context) {
                try CloudRecords.deleteItem(type: type, id: id, in: context, library: library)
            }
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

    // MARK: Shared libraries

    /// Records a library you just accepted, before its contents arrive, so it shows up straight away.
    /// Also used when its share record arrives, which may change whether you can edit.
    func libraryAccepted(zoneID: CKRecordZone.ID, ownerName: String?, canEdit: Bool) throws {
        let context = makeContext()
        try updateLibrary(zoneID: zoneID, ownerName: ownerName, canEdit: canEdit, in: context)
        try save(context)
    }

    /// Removes a library shared with you and everything in it (its owner stopped sharing or removed you).
    func removeLibrary(zoneID: CKRecordZone.ID) throws {
        let context = makeContext()
        if let library = try library(for: zoneID, in: context) {
            context.delete(library)
        }
        for record in try syncRecords(scope: .shared, in: context).values
        where record.zoneName == zoneID.zoneName && record.zoneOwnerName == zoneID.ownerName {
            context.delete(record)
        }
        waiting = waiting.filter { $0.key.zoneID != zoneID }
        try save(context)
    }

    /// "Bill's Library", or "Shared Library" when the owner's name isn't known.
    nonisolated static func libraryName(ownerName: String?) -> String {
        guard let name = ownerName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return "Shared Library"
        }
        return name.hasSuffix("s") ? "\(name)' Library" : "\(name)'s Library"
    }

    nonisolated static func shortName(_ components: PersonNameComponents) -> String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return formatter.string(from: components)
    }

    // MARK: Resets

    /// One of your zones was deleted from iCloud (for example from iCloud settings): send everything in it again.
    func forgetZone(_ zoneName: String) throws {
        let context = makeContext()
        for record in try syncRecords(scope: .private, in: context).values where record.zoneName == zoneName {
            record.systemFields = nil
            record.needsUpload = true
        }
        waiting = waiting.filter { !(Self.isOwn($0.key) && $0.key.zoneID.zoneName == zoneName) }
        try save(context)
    }

    /// Signed out of iCloud or switched accounts. Private: forget what was sent (your data stays on the
    /// device). Shared: remove libraries shared with you, since they belong to the iCloud account.
    func resetAll(scope: CKDatabase.Scope = .private) throws {
        let context = makeContext()
        for record in try syncRecords(scope: scope, in: context).values {
            context.delete(record)
        }
        if scope == .shared {
            for library in try context.fetch(FetchDescriptor<DB.Library>()) where !library.isOwned {
                context.delete(library)
            }
        }
        let resetOwn = scope == .private
        waiting = waiting.filter { Self.isOwn($0.key) != resetOwn }
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

    private func apply(_ record: CKRecord, sync: DB.SyncRecord?, library: DB.Library?, in context: ModelContext) throws {
        if try CloudRecords.apply(record, in: context, library: library) {
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
            var library: DB.Library?
            if !Self.isOwn(record.recordID) {
                guard let shared = try self.library(for: record.recordID.zoneID, in: context) else {
                    waiting[record.recordID] = nil // Its library was removed.
                    continue
                }
                library = shared
            }
            if try CloudRecords.apply(record, in: context, library: library) {
                waiting[record.recordID] = nil
            }
        }
    }

    private func updateLibrary(zoneID: CKRecordZone.ID, ownerName: String?, canEdit: Bool, in context: ModelContext) throws {
        let library = try findOrCreateLibrary(for: zoneID, in: context)
        if let ownerName, !ownerName.isEmpty {
            library.ownerName = ownerName
        }
        library.name = Self.libraryName(ownerName: library.ownerName)
        library.canEdit = canEdit
    }

    private struct LocalItem {
        let type: CloudRecordType
        let id: UUID
        let zoneID: CKRecordZone.ID
        let modelID: PersistentIdentifier
        var childIDs: [PersistentIdentifier] = []
    }

    /// What syncs through one database. Private: My Library's types, cocktails and menus, and My Bar.
    /// Shared: the types, cocktails and menus of libraries shared with you that you can edit.
    private func localItems(scope: CKDatabase.Scope, in context: ModelContext) throws -> [LocalItem] {
        let isPrivate = scope == .private
        func zone(_ library: DB.Library?) -> CKRecordZone.ID? {
            if isPrivate {
                return library == nil ? CloudSchema.libraryZoneID() : nil
            }
            guard let library, !library.isOwned, library.canEdit else { return nil }
            return CKRecordZone.ID(zoneName: library.zoneName, ownerName: library.zoneOwnerName)
        }
        var items: [LocalItem] = []
        for style in try context.fetch(FetchDescriptor<DB.SpiritStyle>()) {
            guard let zoneID = zone(style.library) else { continue }
            items.append(LocalItem(type: .style, id: style.id, zoneID: zoneID, modelID: style.persistentModelID))
        }
        for cocktail in try context.fetch(FetchDescriptor<DB.Cocktail>()) {
            guard let zoneID = zone(cocktail.library) else { continue }
            items.append(LocalItem(type: .cocktail, id: cocktail.id, zoneID: zoneID, modelID: cocktail.persistentModelID,
                                   childIDs: (cocktail.ingredients ?? []).map(\.persistentModelID)))
        }
        for menu in try context.fetch(FetchDescriptor<DB.Menu>()) {
            guard let zoneID = zone(menu.library) else { continue }
            items.append(LocalItem(type: .menu, id: menu.id, zoneID: zoneID, modelID: menu.persistentModelID,
                                   childIDs: (menu.entries ?? []).map(\.persistentModelID)))
        }
        if isPrivate {
            for bottle in try context.fetch(FetchDescriptor<DB.Bottle>()) {
                items.append(LocalItem(type: .bottle, id: bottle.id, zoneID: CloudSchema.myBarZoneID,
                                       modelID: bottle.persistentModelID))
            }
        }
        return items
    }

    /// Bookkeeping for your own zones (private) or other people's (shared), keyed by zone owner, zone and record.
    private func syncRecords(scope: CKDatabase.Scope, in context: ModelContext) throws -> [String: DB.SyncRecord] {
        let owner = CKCurrentUserDefaultName
        let wantOwn = scope == .private
        let records = try context.fetch(FetchDescriptor<DB.SyncRecord>()).filter { ($0.zoneOwnerName == owner) == wantOwn }
        return Dictionary(records.map { (Self.key(ownerName: $0.zoneOwnerName, zoneName: $0.zoneName, recordName: $0.recordName), $0) },
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

    private func library(for zoneID: CKRecordZone.ID, in context: ModelContext) throws -> DB.Library? {
        try library(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, in: context)
    }

    private func library(zoneName: String, ownerName: String, in context: ModelContext) throws -> DB.Library? {
        try context.fetch(FetchDescriptor<DB.Library>(predicate: #Predicate {
            $0.zoneName == zoneName && $0.zoneOwnerName == ownerName
        })).first
    }

    private func findOrCreateLibrary(for zoneID: CKRecordZone.ID, in context: ModelContext) throws -> DB.Library {
        if let library = try library(for: zoneID, in: context) {
            return library
        }
        let library = DB.Library(name: Self.libraryName(ownerName: nil), ownerName: "",
                                 zoneName: zoneID.zoneName, zoneOwnerName: zoneID.ownerName)
        context.insert(library)
        return library
    }

    private static func key(for recordID: CKRecord.ID) -> String {
        key(ownerName: recordID.zoneID.ownerName, zoneName: recordID.zoneID.zoneName, recordName: recordID.recordName)
    }

    private static func key(ownerName: String, zoneName: String, recordName: String) -> String {
        "\(ownerName)/\(zoneName)/\(recordName)"
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

// MARK: - Sync engines

@MainActor
final class CloudSync: CKSyncEngineDelegate {
    private static var current: CloudSync?
    private static let log = Logger(subsystem: "Lemursoft.My-Cocktail-Collection", category: "CloudSync")

    let ledger: CloudSyncLedger
    /// Your private database: My Library and My Bar.
    private var privateEngine: CKSyncEngine?
    /// The shared database: libraries other people share with you.
    private var sharedEngine: CKSyncEngine?
    private var cloudContainer: CKContainer?
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
        guard let sync = current else { return }
        sync.status.state = .syncing
        do {
            for engine in sync.engines {
                try await engine.fetchChanges()
                try await engine.sendChanges()
            }
            sync.updateStatusAfterSync()
        } catch {
            sync.status.state = .problem(Self.message(for: error))
        }
    }

    /// Accepts an invitation to someone's library (after tapping its link), then fetches the library.
    static func accept(_ metadata: CKShare.Metadata) async {
        guard let sync = current, let cloudContainer = sync.cloudContainer else { return }
        guard metadata.participantRole != .owner else { return } // The link to your own library.
        do {
            try await cloudContainer.accept(metadata)
            let ownerName = metadata.ownerIdentity.nameComponents.map(CloudSyncLedger.shortName)
            try sync.ledger.libraryAccepted(zoneID: metadata.share.recordID.zoneID, ownerName: ownerName,
                                            canEdit: metadata.participantPermission == .readWrite)
            try await sync.sharedEngine?.fetchChanges()
        } catch {
            log.error("Accepting a shared library failed: \(error.localizedDescription)")
            sync.status.state = .problem("Couldn't open the shared library. \(Self.message(for: error))")
        }
    }

    private init(container: ModelContainer) {
        ledger = CloudSyncLedger(container: container)
    }

    private var engines: [CKSyncEngine] {
        [privateEngine, sharedEngine].compactMap { $0 }
    }

    private func start() {
        let cloudContainer = CKContainer(identifier: CloudSchema.containerIdentifier)
        self.cloudContainer = cloudContainer
        status.state = .checking
        Task { await checkAccount(cloudContainer) }

        let privateState = Self.loadState(from: Self.privateStateURL)
        privateEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: cloudContainer.privateCloudDatabase, stateSerialization: privateState, delegate: self))
        sharedEngine = CKSyncEngine(CKSyncEngine.Configuration(
            database: cloudContainer.sharedCloudDatabase, stateSerialization: Self.loadState(from: Self.sharedStateURL), delegate: self))
        if privateState == nil {
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
        let nothingWaiting = engines.allSatisfy {
            $0.state.pendingRecordZoneChanges.isEmpty && $0.state.pendingDatabaseChanges.isEmpty
        }
        if nothingWaiting {
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
        privateEngine?.state.add(pendingDatabaseChanges: zoneIDs.map { .saveZone(CKRecordZone(zoneID: $0)) })
    }

    /// Checks both databases for changes to send: yours, and shared libraries you can edit.
    private func queueLocalChanges(changed: Set<PersistentIdentifier>?) {
        let pairs: [(CKDatabase.Scope, CKSyncEngine?)] = [(.private, privateEngine), (.shared, sharedEngine)]
        for (scope, engine) in pairs {
            guard let engine else { continue }
            do {
                let changes = try ledger.localChanges(changed: changed, scope: scope)
                guard !changes.isEmpty else { continue }
                engine.state.add(pendingRecordZoneChanges: changes.saves.map { .saveRecord($0) } + changes.deletes.map { .deleteRecord($0) })
            } catch {
                Self.log.error("Couldn't check for changes to send: \(error.localizedDescription)")
            }
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
        let isShared = syncEngine === sharedEngine
        do {
            switch event {
            case .stateUpdate(let update):
                Self.saveState(update.stateSerialization, to: isShared ? Self.sharedStateURL : Self.privateStateURL)
            case .accountChange(let change):
                try handleAccountChange(change, isShared: isShared)
            case .fetchedDatabaseChanges(let changes):
                if isShared {
                    // A shared zone went away: its owner stopped sharing or removed you.
                    for deletion in changes.deletions {
                        try ledger.removeLibrary(zoneID: deletion.zoneID)
                    }
                } else {
                    let ownZones = [CloudSchema.libraryZoneName, CloudSchema.myBarZoneName]
                    for deletion in changes.deletions
                    where deletion.zoneID.ownerName == CKCurrentUserDefaultName && ownZones.contains(deletion.zoneID.zoneName) {
                        try ledger.forgetZone(deletion.zoneID.zoneName)
                        addZones([deletion.zoneID])
                        queueLocalChanges(changed: nil)
                    }
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
        // The item is gone, or its shared library can't be edited: nothing to send.
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
            case .drop, .libraryRemoved, .nowViewOnly:
                break
            }
        }
        for (recordID, error) in sent.failedRecordDeletes {
            switch error.code {
            case .unknownItem, .zoneNotFound:
                try ledger.didDelete(recordID) // Already gone from iCloud.
            case .permissionFailure:
                try ledger.didDelete(recordID) // Not allowed in a shared library; nothing more to send.
            default:
                break
            }
        }
        if !missingZones.isEmpty {
            addZones(Array(missingZones.values))
        }
        if !resend.isEmpty {
            engine.state.add(pendingRecordZoneChanges: resend)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange, isShared: Bool) throws {
        guard !isShared else {
            // Libraries shared with you belong to the iCloud account: remove them when it changes.
            switch change.changeType {
            case .signOut, .switchAccounts:
                try ledger.resetAll(scope: .shared)
            default:
                break
            }
            return
        }
        switch change.changeType {
        case .signIn:
            status.state = .syncing
            addZones()
            queueLocalChanges(changed: nil)
        case .switchAccounts:
            status.state = .syncing
            try ledger.resetAll(scope: .private)
            addZones()
            queueLocalChanges(changed: nil)
        case .signOut:
            status.state = .notSignedIn
            try ledger.resetAll(scope: .private)
        @unknown default:
            break
        }
    }

    // MARK: Saved state

    /// Each engine's own progress (what it has fetched, what's waiting to send), kept between launches.
    private static var privateStateURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("CloudSyncState.json")
    }

    private static var sharedStateURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("CloudSyncSharedState.json")
    }

    private static func loadState(from url: URL) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func saveState(_ state: CKSyncEngine.State.Serialization, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't save the sync state: \(error.localizedDescription)")
        }
    }
}
