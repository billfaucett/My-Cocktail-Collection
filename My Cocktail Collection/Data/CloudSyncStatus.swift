//
//  CloudSyncStatus.swift
//  My Cocktail Collection
//
//  Sync and sharing, step 2c: what Settings shows about iCloud sync, and settings that follow you
//  to every device (through iCloud key-value storage).
//

import Foundation
import Observation

// MARK: - Status

/// Where iCloud sync stands, as shown in Settings.
enum CloudSyncState: Equatable {
    /// Sync isn't running (previews and tests).
    case off
    case checking
    case notSignedIn
    /// iCloud is restricted or temporarily unavailable.
    case unavailable
    case syncing
    case upToDate(Date)
    /// Something needs attention, e.g. no connection or iCloud storage full. Changes wait meanwhile.
    case problem(String)

    var title: String {
        switch self {
        case .off: return "Off"
        case .checking: return "Checking iCloud…"
        case .notSignedIn: return "Not signed in to iCloud"
        case .unavailable: return "iCloud isn't available"
        case .syncing: return "Syncing…"
        case .upToDate: return "Up to date"
        case .problem: return "Waiting to sync"
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "icloud.slash"
        case .checking, .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .notSignedIn, .unavailable: return "exclamationmark.icloud"
        case .upToDate: return "checkmark.icloud"
        case .problem: return "exclamationmark.icloud"
        }
    }

    func detail(now: Date = Date()) -> String? {
        switch self {
        case .off:
            return nil
        case .checking, .syncing:
            return nil
        case .notSignedIn:
            return "Sign in to iCloud in the Settings app to keep your collection on all your devices. Everything stays on this device meanwhile."
        case .unavailable:
            return "iCloud is restricted or temporarily unavailable. Your collection stays on this device and syncs when iCloud is back."
        case .upToDate(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return now.timeIntervalSince(date) < 60 ? "Last synced just now" : "Last synced \(formatter.localizedString(for: date, relativeTo: now))"
        case .problem(let message):
            return message
        }
    }

    /// Shown while the device is offline.
    static let offlineMessage = "No internet connection. Your changes are saved on this device and will sync when you're back online."

    /// The state after the device goes offline or comes back online, or nil to leave it as it is.
    /// Offline is only worth saying when sync would otherwise run; back online clears it.
    func afterNetworkChange(isOnline: Bool) -> CloudSyncState? {
        if isOnline {
            return self == .problem(Self.offlineMessage) ? .syncing : nil
        }
        switch self {
        case .off, .notSignedIn, .unavailable: return nil
        case .checking, .syncing, .upToDate, .problem: return .problem(Self.offlineMessage)
        }
    }

    /// Whether sharing can be set up: signed in to iCloud, with sync running.
    var canShare: Bool {
        switch self {
        case .syncing, .upToDate, .problem: return true
        case .off, .checking, .notSignedIn, .unavailable: return false
        }
    }

    /// Whether "Sync Now" makes sense.
    var canSyncNow: Bool {
        switch self {
        case .upToDate, .problem: return true
        case .off, .checking, .notSignedIn, .unavailable, .syncing: return false
        }
    }
}

/// The current sync status, observed by Settings. Updated by `CloudSync`.
@MainActor
@Observable
final class CloudSyncStatus {
    static let shared = CloudSyncStatus()

    var state: CloudSyncState = .off
    /// Something to tell you once, e.g. that a library is no longer shared with you.
    var notice: String?
}

// MARK: - Settings sync

/// Somewhere settings are kept: UserDefaults on this device, or iCloud key-value storage.
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}
extension NSUbiquitousKeyValueStore: SettingsStore {}

/// Keeps a few settings (part size, deleted built-ins) the same on every device. Screens keep using
/// `@AppStorage`; this copies values between UserDefaults and iCloud key-value storage.
@MainActor
final class SettingsSync {
    /// Settings where the latest value wins.
    static let syncedKeys = [PartSize.storageKey]
    /// Lists that only grow, merged from every device (deleted built-ins).
    static let unionKeys = [BuiltInDeletions.key]

    private static var current: SettingsSync?

    let local: SettingsStore
    let cloud: SettingsStore
    let keys: [String]
    let unionKeys: [String]
    private var observers: [NSObjectProtocol] = []

    init(local: SettingsStore, cloud: SettingsStore, keys: [String] = SettingsSync.syncedKeys,
         unionKeys: [String] = SettingsSync.unionKeys) {
        self.local = local
        self.cloud = cloud
        self.keys = keys
        self.unionKeys = unionKeys
    }

    /// Starts copying settings. Called once at launch; never in tests or previews. `onListsChanged` runs
    /// after the launch merge and whenever another device adds to a list (to remove deleted built-ins).
    static func start(onListsChanged: @escaping @MainActor () -> Void) {
        guard current == nil else { return }
        let store = NSUbiquitousKeyValueStore.default
        let sync = SettingsSync(local: UserDefaults.standard, cloud: store)
        current = sync
        store.synchronize()
        sync.mergeAtLaunch()
        onListsChanged()

        let center = NotificationCenter.default
        sync.observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                 object: store, queue: .main) { notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated {
                if sync.cloudDidChange(keys: changed) { onListsChanged() }
            }
        })
        sync.observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                                 object: UserDefaults.standard, queue: .main) { _ in
            MainActor.assumeIsolated { sync.localDidChange() }
        })
    }

    /// At launch: iCloud's value wins when it has one (set on another device); otherwise this device's goes up.
    /// Lists are combined.
    func mergeAtLaunch() {
        for key in keys {
            if let value = cloud.object(forKey: key) {
                if !Self.same(value, local.object(forKey: key)) { local.set(value, forKey: key) }
            } else if let value = local.object(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }
        unionKeys.forEach { _ = mergeList($0) }
    }

    /// Settings changed on another device. `changedKeys` nil means anything may have changed.
    /// Returns true if a list here gained entries.
    @discardableResult
    func cloudDidChange(keys changedKeys: [String]?) -> Bool {
        for key in keys where changedKeys?.contains(key) ?? true {
            let value = cloud.object(forKey: key)
            if !Self.same(value, local.object(forKey: key)) { local.set(value, forKey: key) }
        }
        var listsChanged = false
        for key in unionKeys where changedKeys?.contains(key) ?? true {
            listsChanged = mergeList(key) || listsChanged
        }
        return listsChanged
    }

    /// A setting changed on this device.
    func localDidChange() {
        for key in keys {
            let value = local.object(forKey: key)
            if !Self.same(value, cloud.object(forKey: key)) { cloud.set(value, forKey: key) }
        }
        unionKeys.forEach { _ = mergeList($0) }
    }

    /// Combines a list from both places and writes the result wherever it's missing entries.
    /// Returns true if this device's list gained entries.
    private func mergeList(_ key: String) -> Bool {
        let here = local.object(forKey: key) as? [String] ?? []
        let there = cloud.object(forKey: key) as? [String] ?? []
        let combined = Set(here).union(there).sorted()
        if Set(there) != Set(combined) { cloud.set(combined, forKey: key) }
        guard Set(here) != Set(combined) else { return false }
        local.set(combined, forKey: key)
        return true
    }

    private static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        (lhs as? NSObject) == (rhs as? NSObject)
    }
}
