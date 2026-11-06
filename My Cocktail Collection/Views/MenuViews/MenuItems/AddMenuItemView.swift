//
//  MenuItemView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI
import CoreData

/// Pick one or more cocktails to add to a menu.
struct AddMenuItemView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "drinkName", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))])
    private var drinks: FetchedResults<Drink>
    @FetchRequest private var itemsOnMenu: FetchedResults<MenuItem>

    private let menu: Menu

    @State private var selected: Set<Drink> = []
    @State private var searchText = ""
    @State private var favoritesOnly = false

    init(menu: Menu) {
        self.menu = menu
        _itemsOnMenu = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "menu == %@", menu))
    }

    private var drinksAlreadyOnMenu: Set<Drink> {
        Set(itemsOnMenu.compactMap(\.drink))
    }

    private var visibleDrinks: [Drink] {
        let candidates = favoritesOnly ? drinks.filter(\.isFavorite) : Array(drinks)
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter {
            ($0.drinkName ?? "").localizedCaseInsensitiveContains(searchText)
                || ($0.ingredients ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
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
                if visibleDrinks.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleDrinks) { drink in
                    let isOnMenu = drinksAlreadyOnMenu.contains(drink)
                    let isChecked = isOnMenu || selected.contains(drink)
                    Button {
                        toggle(drink)
                    } label: {
                        ItemRow(
                            drink.drinkName ?? "Unnamed Cocktail",
                            subtitle: isOnMenu ? "Already on this menu" : nil,
                            thumbnail: Thumbnail(data: drink.image, placeholder: .cocktail),
                            isFavorite: drink.isFavorite
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
                Text(menu.menuName ?? "Menu")
            }
        }
        .searchable(text: $searchText, prompt: "Search names and ingredients")
    }

    private var emptyMessage: String {
        if drinks.isEmpty { return "Your collection has no cocktails yet." }
        if favoritesOnly && searchText.isEmpty { return "You haven't marked any cocktails as favorites yet." }
        return favoritesOnly ? "No favorite cocktails match your search." : "No cocktails match your search."
    }

    private func toggle(_ drink: Drink) {
        if selected.contains(drink) {
            selected.remove(drink)
        } else {
            selected.insert(drink)
        }
    }

    private func save() throws {
        for drink in selected {
            let item = MenuItem(context: context)
            item.id = UUID()
            item.menu = menu
            item.drink = drink
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
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
    return AddMenuItemView(menu: menu)
        .environment(\.managedObjectContext, context)
}
