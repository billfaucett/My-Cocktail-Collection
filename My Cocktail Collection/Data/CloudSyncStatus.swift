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
}

// MARK: - Settings sync

/// Somewhere settings are kept: UserDefaults on this device, or iCloud key-value storage.
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}
extension NSUbiquitousKeyValueStore: SettingsStore {}

/// Keeps a few settings (part size) the same on every device. Screens keep using `@AppStorage`;
/// this copies values between UserDefaults and iCloud key-value storage.
@MainActor
final class SettingsSync {
    /// The settings that follow you between devices.
    static let syncedKeys = [PartSize.storageKey]

    private static var current: SettingsSync?

    let local: SettingsStore
    let cloud: SettingsStore
    let keys: [String]
    private var observers: [NSObjectProtocol] = []

    init(local: SettingsStore, cloud: SettingsStore, keys: [String] = SettingsSync.syncedKeys) {
        self.local = local
        self.cloud = cloud
        self.keys = keys
    }

    /// Starts copying settings. Called once at launch; never in tests or previews.
    static func start() {
        guard current == nil else { return }
        let store = NSUbiquitousKeyValueStore.default
        let sync = SettingsSync(local: UserDefaults.standard, cloud: store)
        current = sync
        store.synchronize()
        sync.mergeAtLaunch()

        let center = NotificationCenter.default
        sync.observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                 object: store, queue: .main) { notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { sync.cloudDidChange(keys: changed) }
        })
        sync.observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                                 object: UserDefaults.standard, queue: .main) { _ in
            MainActor.assumeIsolated { sync.localDidChange() }
        })
    }

    /// At launch: iCloud's value wins when it has one (set on another device); otherwise this device's goes up.
    func mergeAtLaunch() {
        for key in keys {
            if let value = cloud.object(forKey: key) {
                if !Self.same(value, local.object(forKey: key)) { local.set(value, forKey: key) }
            } else if let value = local.object(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }
    }

    /// Settings changed on another device. `changedKeys` nil means anything may have changed.
    func cloudDidChange(keys changedKeys: [String]?) {
        for key in keys where changedKeys?.contains(key) ?? true {
            let value = cloud.object(forKey: key)
            if !Self.same(value, local.object(forKey: key)) { local.set(value, forKey: key) }
        }
    }

    /// A setting changed on this device.
    func localDidChange() {
        for key in keys {
            let value = local.object(forKey: key)
            if !Self.same(value, cloud.object(forKey: key)) { cloud.set(value, forKey: key) }
        }
    }

    private static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        (lhs as? NSObject) == (rhs as? NSObject)
    }
}
