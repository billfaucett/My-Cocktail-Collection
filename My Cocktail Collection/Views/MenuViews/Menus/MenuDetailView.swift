//
//  CocktailMenuDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/1/24.
//


import SwiftUI
import SwiftData

/// A menu's cocktails, in menu order. Shown pushed from the Menus list.
struct MenuDetailView: View {
    @Environment(\.modelContext) private var context
    private let menu: V1.Menu

    @State private var showAddCocktails = false
    @State private var showRename = false
    @State private var isReordering = false
    @State private var favoritesOnly = false
    @State private var savedFileMessage: String?
    @State private var errorMessage: String?

    init(menu: V1.Menu) {
        self.menu = menu
    }

    private var menuName: String { menu.name.isEmpty ? "Menu" : menu.name }

    private var visibleEntries: [V1.MenuEntry] {
        let entries = menu.orderedEntries
        return favoritesOnly ? entries.filter { $0.cocktail?.isFavorite == true } : entries
    }

    var body: some View {
        let entries = visibleEntries

        ListScreen(
            menuName,
            isEmpty: entries.isEmpty,
            emptyState: EmptyState(
                title: "No Cocktails Yet",
                systemImage: "wineglass",
                message: "Add cocktails from your collection to build this menu.",
                actionTitle: "Add Cocktails"
            ),
            addLabel: "Add Cocktails",
            onAdd: { showAddCocktails = true },
            favoritesOnly: $favoritesOnly
        ) {
            Section {
                ForEach(entries) { entry in
                    MenuEntryRow(entry: entry)
                        .favoriteSwipeAction(isFavorite: entry.cocktail?.isFavorite ?? false) {
                            if let cocktail = entry.cocktail {
                                run { try CocktailStore(context: context).toggleFavorite(cocktail) }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                run { try MenuStore(context: context).remove(entry, from: menu) }
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(.red)
                        }
                }
                .onMove(perform: move)
            } header: {
                if isReordering {
                    HStack {
                        Text("Drag to reorder")
                        Spacer()
                        Button("Done") {
                            withAnimation { isReordering = false }
                        }
                        .textCase(nil)
                    }
                }
            } footer: {
                Text("Created \(menu.dateCreated.formatted(date: .long, time: .omitted))")
            }
            .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        } moreMenu: {
            ShareLink(item: MenuExporter.text(for: menu)) {
                Label("Share Menu", systemImage: "square.and.arrow.up")
            }
            .disabled(menu.orderedEntries.isEmpty)
            Button {
                saveToFiles()
            } label: {
                Label("Save to Files", systemImage: "folder")
            }
            .disabled(menu.orderedEntries.isEmpty)
            Button {
                favoritesOnly = false
                withAnimation { isReordering = true }
            } label: {
                Label("Reorder Cocktails", systemImage: "arrow.up.arrow.down")
            }
            .disabled(menu.orderedEntries.count < 2)
            Button {
                showRename = true
            } label: {
                Label("Rename Menu", systemImage: "pencil")
            }
        }
        .sheet(isPresented: $showAddCocktails) {
            AddMenuItemView(menu: menu)
        }
        .sheet(isPresented: $showRename) {
            AddEditMenuView(menu: menu)
        }
        .alert("Menu Saved", isPresented: Binding(
            get: { savedFileMessage != nil },
            set: { if !$0 { savedFileMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(savedFileMessage ?? "")
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Moves one dragged row. Only the full list can be reordered, so offsets match menu order.
    private func move(from source: IndexSet, to destination: Int) {
        guard !favoritesOnly else { return } // offsets would refer to the filtered list
        let entries = menu.orderedEntries
        guard let from = source.first, entries.indices.contains(from) else { return }
        // List destinations count the row's old place; MenuStore wants the index after removal.
        let target = destination > from ? destination - 1 : destination
        run { try MenuStore(context: context).move(entries[from], to: target, in: menu) }
    }

    private func saveToFiles() {
        do {
            let url = try MenuExporter.saveToFiles(menu)
            savedFileMessage = "Saved as \(url.lastPathComponent) in the Menus folder. Find it in the Files app under On My iPhone › My Cocktail Collection."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    let context = container.mainContext
    try? ModelSeeder.seedBuiltIns(context: context, defaults: nil)
    let store = MenuStore(context: context)
    let menu = try! store.addMenu(name: "Friday Night")
    let cocktails = (try? CocktailStore(context: context).cocktails()) ?? []
    try? store.add(Array(cocktails.prefix(3)), to: menu)
    return NavigationStack {
        MenuDetailView(menu: menu)
    }
    .modelContainer(container)
}
