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
    @State private var menuItem: MenuItem?
    
    var menuId: UUID?
    
    var body: some View {
        VStack {
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
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
    
    func saveMenuItem() {
        menuItem?.menuId = menuId
        menuItem?.drink = selectedCocktail
        
        try? context.save()
        dismiss()
    }
}

struct MenuItemView_Preview: PreviewProvider {
    static var previews: some View {
        AddMenuItemView()
    }
}
