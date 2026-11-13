//
//  MenusListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//


import SwiftUI
import SwiftData

/// The Menus tab. Reads the new SwiftData database (data model refactor, phase 5).
struct MenusListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DB.Menu.dateCreated, order: .reverse, animation: .default)
    private var allMenus: [DB.Menu]
    /// Only My Library; libraries shared with you are shown separately.
    private var menus: [DB.Menu] { allMenus.filter { $0.library == nil } }

    @State private var path: [DB.Menu] = []
    @State private var showCreateMenu = false
    @State private var showSavedFiles = false
    @State private var menuToDelete: DB.Menu?
    @State private var confirmDeleteAll = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ListScreen(
                "Menus",
                isEmpty: menus.isEmpty,
                emptyState: EmptyState(
                    title: "No Menus Yet",
                    systemImage: "menucard",
                    message: "Create a menu for a party or a night in, then add cocktails from your collection.",
                    actionTitle: "Create a Menu"
                ),
                addLabel: "New Menu",
                onAdd: { showCreateMenu = true }
            ) {
                ForEach(menus) { menu in
                    NavigationLink(value: menu) {
                        MenuListRow(menu: menu)
                    }
                    .deleteSwipeAction { menuToDelete = menu }
                }
            } moreMenu: {
                Button {
                    showSavedFiles = true
                } label: {
                    Label("Saved Menu Files", systemImage: "folder")
                }
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label("Delete All Menus", systemImage: "trash")
                }
                .disabled(menus.isEmpty)
            }
            .navigationDestination(for: DB.Menu.self) { menu in
                MenuDetailView(menu: menu)
            }
            .sheet(isPresented: $showCreateMenu) {
                AddEditMenuView { newMenu in
                    path.append(newMenu)
                }
            }
            .sheet(isPresented: $showSavedFiles) {
                DocPicker(url: URL.documentsDirectory)
            }
            .confirmDelete($menuToDelete, title: "Delete Menu?") { menu in
                "\(menu.name) will be deleted. The cocktails on it stay in your collection."
            } onDelete: { menu in
                run { try MenuStore(context: context).delete(menu) }
            }
            .alert("Delete All Menus?", isPresented: $confirmDeleteAll) {
                Button("Delete", role: .destructive) {
                    run { try MenuStore(context: context).deleteAll() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes every menu and its cocktail list. Your cocktail recipes are not affected.")
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
    let store = MenuStore(context: container.mainContext)
    _ = try? store.addMenu(name: "Holiday Party")
    _ = try? store.addMenu(name: "Friday Night")
    return MenusListView()
        .modelContainer(container)
}
