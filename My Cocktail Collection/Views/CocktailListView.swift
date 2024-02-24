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
        VStack {
            List(drinks) { drink in
                HStack {
                    Text(drink.drinkName ?? "Unknown")
                    Button("View"){
                        //To Do
                    }
                }
            }
        }
    }
}

struct CocktailListView_Preview: PreviewProvider {
    static var previews: some View {
        CocktailListView()
    }
}
