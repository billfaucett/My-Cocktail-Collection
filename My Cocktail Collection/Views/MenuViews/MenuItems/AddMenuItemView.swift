//
//  MenuItemView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//


import SwiftUI
import SwiftData

/// Pick one or more cocktails to add to a menu.
struct AddMenuItemView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \V1.Cocktail.name) private var cocktails: [V1.Cocktail]

    private let menu: V1.Menu

    @State private var selected: Set<UUID> = []
    @State private var searchText = ""
    @State private var favoritesOnly = false

    init(menu: V1.Menu) {
        self.menu = menu
    }

    private var cocktailsOnMenu: Set<UUID> {
        Set((menu.entries ?? []).compactMap { $0.cocktail?.id })
    }

    private var visibleCocktails: [V1.Cocktail] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return cocktails
            .filter { cocktail in
                if favoritesOnly && !cocktail.isFavorite { return false }
                if query.isEmpty { return true }
                return cocktail.name.localizedCaseInsensitiveContains(query)
                    || (cocktail.ingredients ?? []).contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let onMenu = cocktailsOnMenu

        FormScreen(
            "Add Cocktails",
            saveTitle: selected.isEmpty ? "Add" : "Add (\(selected.count))",
            canSave: !selected.isEmpty,
            onSave: save
        ) {
            Section {
                FavoritesToggle(isOn: $favoritesOnly)
            }

            Section {
                if visibleCocktails.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleCocktails) { cocktail in
                    let isOnMenu = onMenu.contains(cocktail.id)
                    let isChecked = isOnMenu || selected.contains(cocktail.id)
                    Button {
                        toggle(cocktail)
                    } label: {
                        ItemRow(
                            cocktail.name,
                            subtitle: isOnMenu ? "Already on this menu" : cocktail.baseStyle?.name,
                            thumbnail: Thumbnail(data: cocktail.photo, placeholder: .cocktail),
                            isFavorite: cocktail.isFavorite
                        ) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isOnMenu ? Color.secondary : (isChecked ? Color.accentColor : Color.secondary))
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(isOnMenu)
                }
            } header: {
                Text(menu.name)
            } footer: {
                Text("New cocktails go at the end of the menu. You can reorder them afterwards.")
            }
        }
        .searchable(text: $searchText, prompt: "Search names and ingredients")
    }

    private var emptyMessage: String {
        if cocktails.isEmpty { return "Your collection has no cocktails yet." }
        if favoritesOnly && searchText.isEmpty { return "You haven't marked any cocktails as favorites yet." }
        return favoritesOnly ? "No favorite cocktails match your search." : "No cocktails match your search."
    }

    private func toggle(_ cocktail: V1.Cocktail) {
        if selected.contains(cocktail.id) {
            selected.remove(cocktail.id)
        } else {
            selected.insert(cocktail.id)
        }
    }

    /// Adds the picked cocktails in alphabetical order.
    private func save() throws {
        let picked = cocktails
            .filter { selected.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try MenuStore(context: context).add(picked, to: menu)
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    let context = container.mainContext
    try? ModelSeeder.seedBuiltIns(context: context, defaults: nil)
    let menu = try! MenuStore(context: context).addMenu(name: "Friday Night")
    return AddMenuItemView(menu: menu)
        .modelContainer(container)
}
