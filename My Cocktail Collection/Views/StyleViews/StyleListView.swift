//
//  StyleListView.swift
//  My Cocktail Collection
//
//  The Styles tab: every style, grouped by family. Tap a style to edit it, or + to add one.
//  Part of the data model refactor (phase 5): reads the new SwiftData database.
//

import SwiftUI
import SwiftData

struct StyleListView: View {
    @Environment(\.modelContext) private var context
    @Query private var styles: [V1.SpiritStyle]

    @State private var searchText = ""
    @State private var showAddStyle = false
    @State private var styleToEdit: V1.SpiritStyle?
    @State private var styleToDelete: V1.SpiritStyle?
    @State private var errorMessage: String?
    #if DEBUG
    @State private var confirmReimport = false
    #endif

    /// Styles matching the search, in display order: by family, built-ins first, then yours A–Z.
    private var visibleStyles: [V1.SpiritStyle] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? styles : styles.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.family.displayName.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted(by: StyleStore.displayOrder)
    }

    var body: some View {
        let visible = visibleStyles

        NavigationStack {
            ListScreen(
                "Spirits",
                isEmpty: visible.isEmpty,
                emptyState: styles.isEmpty
                    ? EmptyState(title: "No Spirit Types Yet", systemImage: "square.stack.3d.up",
                                 message: "Types group the bottles in My Bar and set each cocktail's base spirit.", actionTitle: "Add a Type")
                    : EmptyState(title: "No Matches", systemImage: "magnifyingglass",
                                 message: "No types or families match your search."),
                addLabel: "Add Type",
                onAdd: { showAddStyle = true }
            ) {
                ForEach(SpiritFamily.allCases) { family in
                    let familyStyles = visible.filter { $0.family == family }
                    if !familyStyles.isEmpty {
                        Section {
                            ForEach(familyStyles) { style in
                                Button {
                                    styleToEdit = style
                                } label: {
                                    StyleRow(style: style)
                                }
                                .foregroundStyle(.primary)
                                .deleteSwipeAction { styleToDelete = style }
                            }
                        } header: {
                            Label(family.displayName, systemImage: family.symbolName)
                        }
                    }
                }
            } moreMenu: {
                #if DEBUG
                Button(role: .destructive) {
                    confirmReimport = true
                } label: {
                    Label("Re-import Old Data (Debug)", systemImage: "arrow.triangle.2.circlepath")
                }
                #endif
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search types and families")
            .sheet(isPresented: $showAddStyle) {
                AddEditStyleView()
            }
            .sheet(item: $styleToEdit) { style in
                AddEditStyleView(style: style)
            }
            .confirmDelete($styleToDelete, title: "Delete Type?") { style in
                "\(style.name) will be removed. Bottles and cocktails that use it keep everything else and just lose this type."
            } onDelete: { style in
                do {
                    try StyleStore(context: context).delete(style)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            #if DEBUG
            .alert("Re-import Old Data?", isPresented: $confirmReimport) {
                Button("Re-import", role: .destructive) {
                    do {
                        try AppStartup.resetAndReimport(context)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Debug builds only. Empties the new database and copies the old one in again. The old database isn't changed.")
            }
            #endif
        }
    }
}

/// One style: its name, what uses it, and a badge for styles you added.
struct StyleRow: View {
    let style: V1.SpiritStyle

    private var usage: String {
        let bottles = style.bottles?.count ?? 0
        let cocktails = style.cocktails?.count ?? 0
        var parts: [String] = []
        if bottles > 0 { parts.append(bottles == 1 ? "1 bottle" : "\(bottles) bottles") }
        if cocktails > 0 { parts.append(cocktails == 1 ? "1 cocktail" : "\(cocktails) cocktails") }
        return parts.isEmpty ? "Not used yet" : parts.joined(separator: " · ")
    }

    var body: some View {
        ItemRow(style.name, subtitle: usage) {
            if !style.isBuiltIn {
                Badge("Yours", color: .accentColor)
            }
        }
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    try? StyleStore(context: container.mainContext).addStyle(name: "Overproof Rum", family: .rum)
    return StyleListView()
        .modelContainer(container)
}
