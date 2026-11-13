//
//  PartSizeSettingsView.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 6: pick how big a part is, so recipes also show ounces or millilitres.
//  Sync and sharing, step 2c: iCloud sync status, with Sync Now.
//

import CloudKit
import SwiftUI

/// Settings for how recipes are shown. Changes apply straight away.
struct PartSizeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PartSize.storageKey) private var partSize = PartSize.off
    private var syncStatus = CloudSyncStatus.shared

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
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About My Cocktail Collection", systemImage: "info.circle")
                    }
                } footer: {
                    Text("\(AppInfo.versionLine()) · \(AppInfo.dataModelLine())")
                }
            }
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
