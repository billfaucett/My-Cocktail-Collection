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

    init(menu: Menu) {
        self.menu = menu
        _itemsOnMenu = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "menu == %@", menu))
    }

    private var drinksAlreadyOnMenu: Set<Drink> {
        Set(itemsOnMenu.compactMap(\.drink))
    }

    private var visibleDrinks: [Drink] {
        guard !searchText.isEmpty else { return Array(drinks) }
        return drinks.filter {
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
                if visibleDrinks.isEmpty {
                    Text(drinks.isEmpty ? "Your collection has no cocktails yet." : "No cocktails match your search.")
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
                            thumbnail: Thumbnail(data: drink.image, placeholder: .cocktail)
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
