//
//  CocktailDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData

struct CocktailDetailView: View {
    @Environment(\.managedObjectContext) var context
    let drinkID: NSManagedObjectID
    
    var body: some View {
        let drink = context.object(with: drinkID) as! Drink
        
        NavigationView{
            VStack {
                Section {
                    VStack {
                        Text(drink.drinkName!)
                            .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                            .padding(.horizontal)
                        Text("Ingredient List:")
                            .font(.caption)
                            .padding()
                        Text(drink.ingredients!)
                            .frame(width: 300, height: 300)
                        Text("Directions:")
                            .font(.caption)
                            .padding(.horizontal)
                        Text(drink.method!)
                            .frame(width: 300, height: 300)
                    }
                }
                VStack {
                    HStack {
                        Button("Delete Drink") {
                            context.delete(drink)
                        }
                        .foregroundColor(.red)
                        Spacer()
                    }
                }
                .padding()
            }
        }
    }
}

struct CocktailDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        let drink = Drink(context: context)
        drink.drinkName = "Mocktail"
        drink.ingredients = "Ingredient 1, Ingredient 2"
        drink.method = "Mix ingredients and serve chilled."
        return CocktailDetailView(drinkID: drink.objectID)
            .environment(\.managedObjectContext, context)
    }
}
