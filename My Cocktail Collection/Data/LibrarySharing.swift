//
//  LibrarySharing.swift
//  My Cocktail Collection
//
//  Sync and sharing, step 3: share My Library with people you choose.
//
//  My Library (types, cocktails, menus) lives in one iCloud zone, so it's shared as a whole with one
//  zone-wide share. Only people you invite can open it (no public link), and you set each person to
//  view only or can edit. Apple's sharing screen (UICloudSharingController) handles inviting, changing
//  permissions, removing people and stopping sharing. My Bar is in a different zone and is never shared.
//

import CloudKit
import OSLog
import UIKit

@MainActor
enum LibrarySharing {
    /// What invitations and the sharing screen call the library.
    nonisolated static let shareTitle = "Cocktail Library"

    nonisolated private static let log = Logger(subsystem: "Lemursoft.My-Cocktail-Collection", category: "LibrarySharing")
    /// Keeps the sharing screen's delegate alive while it's open (the screen only holds it weakly).
    private static var activeDelegate: SharingDelegate?

    static var container: CKContainer {
        CKContainer(identifier: CloudSchema.containerIdentifier)
    }

    /// The zone-wide share always has this record ID.
    nonisolated static var shareRecordID: CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: CloudSchema.libraryZoneID())
    }

    // MARK: Finding and creating the share

    /// My Library's share, or nil if it isn't shared.
    static func existingShare() async throws -> CKShare? {
        do {
            return try await container.privateCloudDatabase.record(for: shareRecordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// The share to invite people to, created if it doesn't exist yet (with nobody in it).
    static func shareForInviting() async throws -> CKShare {
        if let share = try await existingShare() {
            return share
        }
        let database = container.privateCloudDatabase
        // The zone normally exists already (sync creates it); saving it again is harmless.
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: CloudSchema.libraryZoneID())], deleting: [])
        let share = CKShare(recordZoneID: CloudSchema.libraryZoneID())
        configure(share)
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CKError(.internalError)
        }
        return saved
    }

    /// Only people you invite can open it, and it's called "Cocktail Library".
    nonisolated static func configure(_ share: CKShare) {
        share[CKShare.SystemFieldKey.title] = shareTitle
        share.publicPermission = .none
    }

    // MARK: Who it's shared with

    /// People invited, not counting you.
    nonisolated static func participantCount(of share: CKShare) -> Int {
        share.participants.filter { $0.role != .owner }.count
    }

    /// "Not shared", "No one invited yet", "Shared with 1 person", "Shared with 3 people".
    nonisolated static func summary(participantCount: Int?) -> String {
        switch participantCount {
        case nil: return "Not shared"
        case 0?: return "No one invited yet"
        case 1?: return "Shared with 1 person"
        case let count?: return "Shared with \(count) people"
        }
    }

    // MARK: Sharing screen

    /// Opens Apple's sharing screen over whatever is showing: invite people, set view only or can edit,
    /// remove people, or stop sharing. `onChange` runs when the share is saved or sharing stops.
    static func presentSharingScreen(for share: CKShare, onChange: @escaping @MainActor () -> Void) {
        guard let presenter = topViewController() else {
            log.error("No screen to show sharing over")
            return
        }
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        let delegate = SharingDelegate(onChange: onChange)
        activeDelegate = delegate
        controller.delegate = delegate
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
        let onChange: @MainActor () -> Void

        init(onChange: @escaping @MainActor () -> Void) {
            self.onChange = onChange
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            LibrarySharing.shareTitle
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            LibrarySharing.log.error("Saving the share failed: \(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            MainActor.assumeIsolated { onChange() }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            MainActor.assumeIsolated { onChange() }
        }
    }
}
