//
//  MenuItemView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI

struct AddMenuItemView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Drink.drinkName, ascending: true)]) var drinks: FetchedResults<Drink>
    @State private var selectedCocktail: Drink?
    //@State private var menuItem: MenuItem?
    
    var menu: Menu?
    
    var body: some View {
        VStack {
            HStack{
                Text("Add cocktail to menu: \(menu?.menuName ?? "No Menu")")
            }
            Picker(selection: $selectedCocktail, label: Text("Select a Cocktail")) {
                Text("Select a Cocktail")
                    .tag(nil as Drink?)
                ForEach(drinks) { drink in
                    Text(drink.drinkName ?? "")
                        .tag(drink as Drink?)
                }
            }
            Button("Save") {
                saveMenuItem()
            }
        }
    }
    
    func saveMenuItem() {
        guard let selectedCocktail = selectedCocktail else {
            return
        }
        let menuItem = MenuItem(context: context)
        menuItem.id = UUID()
        menuItem.menu = menu
        menuItem.drink = selectedCocktail
        
        do {
            try context.save()
            refreshObjects()
            dismiss()
        } catch {
            print("Error saving menu item: \(error.localizedDescription)")
        }
    }
    
    func refreshObjects() {
        context.refreshAllObjects()
    }
}

struct MenuItemView_Preview: PreviewProvider {
    static var previews: some View {
        AddMenuItemView()
    }
}
