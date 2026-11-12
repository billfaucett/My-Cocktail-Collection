//
//  AddEditMenuView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//


import SwiftUI
import SwiftData

struct AddEditMenuView: View {
    @Environment(\.modelContext) private var context

    /// The menu being renamed, or nil when creating a new one.
    private let menu: DB.Menu?
    /// Called with the menu after it's saved, e.g. to open a newly created menu.
    private let onSave: ((DB.Menu) -> Void)?

    @State private var name = ""
    @State private var hasLoaded = false

    /// - Parameters:
    ///   - menu: The menu to rename. Leave out to create a new menu.
    ///   - onSave: Called with the saved menu.
    init(menu: DB.Menu? = nil, onSave: ((DB.Menu) -> Void)? = nil) {
        self.menu = menu
        self.onSave = onSave
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        FormScreen(
            menu == nil ? "New Menu" : "Rename Menu",
            saveTitle: menu == nil ? "Create" : "Save",
            canSave: !trimmedName.isEmpty,
            onSave: save
        ) {
            Section {
                TextField("Menu name (e.g. Friday Night)", text: $name)
                    .textInputAutocapitalization(.words)
            } footer: {
                if menu == nil {
                    Text("You can add cocktails after creating the menu.")
                }
            }
        }
        .onAppear(perform: loadMenu)
    }

    private func loadMenu() {
        guard !hasLoaded else { return }
        hasLoaded = true
        name = menu?.name ?? ""
    }

    private func save() throws {
        let store = MenuStore(context: context)
        let saved: DB.Menu
        if let menu {
            try store.rename(menu, to: trimmedName)
            saved = menu
        } else {
            saved = try store.addMenu(name: trimmedName)
        }
        onSave?(saved)
    }
}

#Preview {
    AddEditMenuView()
        .modelContainer(try! CocktailModelContainer.make(inMemory: true))
}
