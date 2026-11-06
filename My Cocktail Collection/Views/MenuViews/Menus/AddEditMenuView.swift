//
//  AddEditMenuView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI
import CoreData

struct AddEditMenuView: View {
    @Environment(\.managedObjectContext) private var context

    /// The menu being renamed, or nil when creating a new one.
    private let menu: Menu?
    /// Called with the menu after it's saved, e.g. to open a newly created menu.
    private let onSave: ((Menu) -> Void)?

    @State private var name = ""
    @State private var hasLoaded = false

    /// - Parameters:
    ///   - menu: The menu to rename. Leave out to create a new menu.
    ///   - onSave: Called with the saved menu.
    init(menu: Menu? = nil, onSave: ((Menu) -> Void)? = nil) {
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
        name = menu?.menuName ?? ""
    }

    private func save() throws {
        let target = menu ?? Menu(context: context)
        if menu == nil {
            target.id = UUID()
            target.dateCreated = Date()
        }
        target.menuName = trimmedName

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        onSave?(target)
    }
}

#Preview {
    AddEditMenuView()
        .environment(\.managedObjectContext, DataController(inMemory: true).container.viewContext)
}
