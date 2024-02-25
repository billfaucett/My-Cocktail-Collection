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
                            Spacer()
                            Text("View")
                        }
                    }
                }
            }
            .navigationTitle("Cocktail Collection")
        }
    }
}

struct CocktailListView_Preview: PreviewProvider {
    static var previews: some View {
        CocktailListView()
    }
}