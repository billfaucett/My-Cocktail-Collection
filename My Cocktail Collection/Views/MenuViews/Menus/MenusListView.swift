//
//  MenusListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI
import CoreData

struct MenusListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Menu.dateCreated, ascending: false)], animation: .default)
    private var menus: FetchedResults<Menu>
    @FetchRequest(sortDescriptors: [])
    private var menuItems: FetchedResults<MenuItem>

    @State private var path: [Menu] = []
    @State private var showCreateMenu = false
    @State private var showSavedFiles = false
    @State private var menuToDelete: Menu?
    @State private var confirmDeleteAll = false

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
                        MenuListRow(menu: menu, cocktailCount: cocktailCount(for: menu))
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
            .navigationDestination(for: Menu.self) { menu in
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
                "\(menu.menuName ?? "This menu") will be deleted. The cocktails on it stay in your collection."
            } onDelete: { menu in
                delete(menu)
            }
            .alert("Delete All Menus?", isPresented: $confirmDeleteAll) {
                Button("Delete", role: .destructive) {
                    DataController.deleteStuff(context: context)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes every menu and its cocktail list. Your cocktail recipes are not affected.")
            }
        }
    }

    private func cocktailCount(for menu: Menu) -> Int {
        menuItems.filter { $0.menu == menu }.count
    }

    /// Deletes a menu and its cocktail entries (the recipes themselves are kept).
    private func delete(_ menu: Menu) {
        menuItems.filter { $0.menu == menu }.forEach { context.delete($0) }
        context.delete(menu)
        context.saveOrRollback()
    }
}

#Preview {
    let context = DataController(inMemory: true).container.viewContext
    for (name, daysAgo) in [("Friday Night", 0), ("Holiday Party", 30)] {
        let menu = Menu(context: context)
        menu.id = UUID()
        menu.menuName = name
        menu.dateCreated = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
    }
    return MenusListView()
        .environment(\.managedObjectContext, context)
}
