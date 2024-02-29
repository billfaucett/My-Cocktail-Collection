//
//  CocktailListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

struct CocktailListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var drinks: FetchedResults<Drink>
    @FetchRequest(sortDescriptors: []) var spirits: FetchedResults<Spirit>
    @State private var selectedBaseSpirit: Spirit?
    @State private var searchText = ""
    @State private var isSearching = false
    var isPreview = false
    
    var body: some View {
        NavigationView{
            VStack {
                Text("Filter by Base Spirit")
                    .font(.caption)
                Picker ("Selected Base Spirit", selection: $selectedBaseSpirit) {
                    Text("Show All").tag(nil as Spirit?)
                    ForEach(spirits) { spirit in
                        Text(spirit.spiritName ?? "")
                            .tag(spirit as Spirit?)
                    }
                }
                
              /*  Divider()
                VStack {
                    HStack {
                        VStack {
                            TextField("Search Cocktails", text: $searchText)
                                .padding(.horizontal)
                        }
                        Spacer()
                        Button ("Search") {
                            isSearching = true
                        }
                    }
                }
                .padding() */
                
                List(filteredDrinks()) { drink in
                    NavigationLink(destination: CocktailDetailView(drinkID: drink.objectID)) {
                        HStack {
                            Text(drink.drinkName ?? "Unknown")
                                .font(.headline)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("My Cocktail Collection")
        }
    }
    
    private func filteredDrinks() -> [Drink] {
        if let baseSpirit = selectedBaseSpirit {
            return drinks.filter { $0.baseSpirit == baseSpirit.id }
        }
        
        if isSearching && !searchText.isEmpty {
            return drinks.filter { $0.drinkName?.localizedCaseInsensitiveContains(searchText) ?? false }
        }
        
        else {
            return Array(drinks)
        }
    }
}

struct CocktailListView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        
        let spirit1 = Spirit(context: context)
        spirit1.id = UUID()
        spirit1.spiritName = "Rum"
        let spirit2 = Spirit(context: context)
        spirit2.id = UUID()
        spirit2.spiritName = "Vodka"
        
        let drink1 = Drink(context: context)
        drink1.drinkName = "Mojito"
        drink1.baseSpirit = spirit1.id
        let drink2 = Drink(context: context)
        drink2.drinkName = "Cosmopolitan"
        drink2.baseSpirit = spirit2.id
        
        try? context.save()
        
        return CocktailListView(isPreview: true)
            .environment(\.managedObjectContext, context)
    }
}
