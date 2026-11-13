//
//  PartSizeSettingsView.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 6: pick how big a part is, so recipes also show ounces or millilitres.
//  Sync and sharing, step 2c: iCloud sync status, with Sync Now. Step 3: share My Library.
//  Step 4: libraries shared with you.
//

import CloudKit
import SwiftData
import SwiftUI

/// Settings for how recipes are shown. Changes apply straight away.
struct PartSizeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PartSize.storageKey) private var partSize = PartSize.off
    private var syncStatus = CloudSyncStatus.shared
    /// Who My Library is shared with, once checked ("Not shared", "Shared with 2 people").
    @State private var sharingSummary: String?
    @State private var isShared = false
    @State private var isOpeningSharing = false
    @State private var sharingError: String?
    /// The people My Library is shared with.
    @State private var sharedPeople: [LibrarySharing.Person] = []
    /// Libraries other people have shared with you.
    @Query(sort: \DB.Library.name) private var libraries: [DB.Library]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Part Size", selection: $partSize) {
                        ForEach(PartSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Part Size")
                } footer: {
                    Text("Recipes are kept in parts, so they work with any jigger. Pick a size to also see each amount in ounces or millilitres on the recipe screen.")
                }

                if partSize != .off {
                    Section("Example") {
                        ConvertedIngredientRow(text: "2 parts Bourbon", converted: partSize.converted(amount: 2))
                        ConvertedIngredientRow(text: "¾ part Lemon Juice", converted: partSize.converted(amount: 0.75))
                        ConvertedIngredientRow(text: "2 dashes Angostura Bitters", converted: nil)
                    }
                }

                Section {
                    CloudSyncStatusRow(state: syncStatus.state)
                    if syncStatus.state.canSyncNow {
                        Button {
                            Task { await CloudSync.syncNow() }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Your cocktails, menus, spirit types, My Bar and part size stay the same on every device signed in to your Apple ID.")
                }

                Section {
                    LabeledContent("My Library", value: sharingRowText)
                        .accessibilityIdentifier("sharingSummary")
                    ForEach(sharedPeople) { person in
                        LabeledContent {
                            Text(person.detail)
                        } label: {
                            Label(person.name, systemImage: "person.crop.circle")
                        }
                    }
                    Button {
                        Task { await openSharing() }
                    } label: {
                        Label(isShared ? "Manage Sharing…" : "Share My Library…", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(!syncStatus.state.canShare || isOpeningSharing)
                } header: {
                    Text("Sharing")
                } footer: {
                    Text(sharingError ?? "People you invite see your cocktails, menus and spirit types in their app. You choose whether each person can only view or can also edit. My Bar stays private.")
                }

                let sharedWithYou = libraries.filter { !$0.isOwned }
                if !sharedWithYou.isEmpty {
                    Section {
                        ForEach(sharedWithYou) { library in
                            NavigationLink {
                                SharedLibraryView(library: library)
                            } label: {
                                SharedLibraryRow(library: library)
                            }
                        }
                    } header: {
                        Text("Shared With You")
                    } footer: {
                        Text("Libraries other people share with you are kept apart from yours. They disappear if their owner stops sharing.")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About My Cocktail Collection", systemImage: "info.circle")
                    }
                } footer: {
                    Text("\(AppInfo.versionLine()) · \(AppInfo.dataModelLine())")
                }
            }
            .task(id: syncStatus.state.canShare) { await refreshSharing() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension PartSizeSettingsView {
    private var sharingRowText: String {
        guard syncStatus.state.canShare else { return "Needs iCloud sync" }
        return sharingSummary ?? "Checking…"
    }

    /// Asks iCloud who My Library is shared with.
    private func refreshSharing() async {
        guard syncStatus.state.canShare else {
            sharingSummary = nil
            sharedPeople = []
            return
        }
        do {
            let share = try await LibrarySharing.existingShare()
            isShared = share != nil
            sharedPeople = share.map { LibrarySharing.people(in: $0) } ?? []
            sharingSummary = LibrarySharing.summary(participantCount: share.map { LibrarySharing.participantCount(of: $0) })
            sharingError = nil
        } catch {
            sharingError = CloudSync.message(for: error)
        }
    }

    /// Opens Apple's sharing screen, creating the share first if My Library isn't shared yet.
    private func openSharing() async {
        isOpeningSharing = true
        defer { isOpeningSharing = false }
        do {
            let share = try await LibrarySharing.shareForInviting()
            LibrarySharing.presentSharingScreen(for: share) {
                Task { await refreshSharing() }
            }
            await refreshSharing()
        } catch {
            sharingError = CloudSync.message(for: error)
        }
    }
}

/// A library shared with you: its name, whether you can edit it, and how many cocktails it has.
struct SharedLibraryRow: View {
    let library: DB.Library

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(library.name, systemImage: "person.2")
            Text(Self.detail(canEdit: library.canEdit, cocktailCount: library.cocktails?.count ?? 0))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Can edit · 42 cocktails" or "View only · 1 cocktail".
    static func detail(canEdit: Bool, cocktailCount: Int) -> String {
        let access = canEdit ? "Can edit" : "View only"
        return "\(access) · \(cocktailCount) \(cocktailCount == 1 ? "cocktail" : "cocktails")"
    }
}

/// iCloud sync's status: an icon and title, with a line of detail when there's more to say.
struct CloudSyncStatusRow: View {
    let state: CloudSyncState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(state.title, systemImage: state.systemImage)
            if let detail = state.detail() {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("iCloudStatus")
    }
}

/// An ingredient line with its converted amount on the right, as the recipe screen shows it.
struct ConvertedIngredientRow: View {
    let text: String
    let converted: String?
    var isSecondary = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .foregroundStyle(isSecondary ? .secondary : .primary)
            if let converted {
                Spacer(minLength: 12)
                Text(converted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    PartSizeSettingsView()
}

#Preview("iCloud status") {
    List {
        CloudSyncStatusRow(state: .upToDate(Date().addingTimeInterval(-300)))
        CloudSyncStatusRow(state: .syncing)
        CloudSyncStatusRow(state: .notSignedIn)
        CloudSyncStatusRow(state: .problem(CloudSync.message(for: CKError(.networkUnavailable))))
        CloudSyncStatusRow(state: .off)
    }
}
