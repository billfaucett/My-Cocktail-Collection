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
    
    var body: some View {
        NavigationView{
            VStack {
                List(drinks) { drink in
                    NavigationLink(destination: CocktailDetailView(drinkID: drink.objectID)) {
                        HStack {
                            Text(drink.drinkName ?? "Unknown")
                                .font(.headline)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Cocktail Collection")
        }
    }
}

struct CocktailListView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        
        let drink1 = Drink(context: context)
        drink1.drinkName = "Mojito"
        
        let drink2 = Drink(context: context)
        drink2.drinkName = "Cosmopolitan"
        
        try? context.save()
        
        return CocktailListView()
            .environment(\.managedObjectContext, context)
    }
}
