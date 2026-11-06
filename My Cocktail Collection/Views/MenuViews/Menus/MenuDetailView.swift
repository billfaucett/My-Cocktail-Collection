//
//  CocktailMenuDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/1/24.
//

import SwiftUI
import CoreData

/// A menu's cocktails. Shown pushed from the Menus list.
struct MenuDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject private var menu: Menu
    @FetchRequest private var items: FetchedResults<MenuItem>

    @State private var showAddCocktails = false
    @State private var showRename = false
    @State private var savedFileMessage: String?
    @State private var saveErrorMessage: String?
    @State private var favoritesOnly = false
    /// Bumped when a cocktail's favorite changes, so the filtered list refreshes.
    /// (The menu's fetch only watches menu items, not the cocktails they point to.)
    @State private var favoriteChanges = 0

    init(menu: Menu) {
        _menu = ObservedObject(wrappedValue: menu)
        _items = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "drink.drinkName", ascending: true)],
            predicate: NSPredicate(format: "menu == %@", menu),
            animation: .default
        )
    }

    private var menuName: String { menu.menuName ?? "Menu" }

    private var visibleItems: [MenuItem] {
        _ = favoriteChanges
        return favoritesOnly ? items.filter { $0.drink?.isFavorite == true } : Array(items)
    }

    var body: some View {
        ListScreen(
            menuName,
            isEmpty: visibleItems.isEmpty,
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
                ForEach(visibleItems) { item in
                    MenuItemRow(item: item)
                        .favoriteSwipeAction(isFavorite: item.drink?.isFavorite ?? false) {
                            if let drink = item.drink {
                                DataController.toggleFavorite(drink, context: context)
                                favoriteChanges += 1
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                remove(item)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(.red)
                        }
                }
            } footer: {
                if let date = menu.dateCreated {
                    Text("Created \(date.formatted(date: .long, time: .omitted))")
                }
            }
        } moreMenu: {
            ShareLink(item: MenuExporter.text(for: Array(items), menuName: menuName)) {
                Label("Share Menu", systemImage: "square.and.arrow.up")
            }
            .disabled(items.isEmpty)
            Button {
                saveToFiles()
            } label: {
                Label("Save to Files", systemImage: "folder")
            }
            .disabled(items.isEmpty)
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
        .alert("Couldn't Save Menu", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func remove(_ item: MenuItem) {
        context.delete(item)
        context.saveOrRollback()
    }

    private func saveToFiles() {
        do {
            let url = try MenuExporter.saveToFiles(items: Array(items), menuName: menuName)
            savedFileMessage = "Saved as \(url.lastPathComponent) in the Menus folder. Find it in the Files app under On My iPhone › My Cocktail Collection."
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    DataController.seedCocktails(context: context)
    let menu = Menu(context: context)
    menu.id = UUID()
    menu.menuName = "Friday Night"
    menu.dateCreated = Date()
    let drinks = (try? context.fetch(NSFetchRequest<Drink>(entityName: "Drink"))) ?? []
    for drink in drinks.prefix(3) {
        let item = MenuItem(context: context)
        item.id = UUID()
        item.menu = menu
        item.drink = drink
    }
    return NavigationStack {
        MenuDetailView(menu: menu)
    }
    .environment(\.managedObjectContext, context)
}
