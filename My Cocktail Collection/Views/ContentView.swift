//
//  ContentView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var drinks: FetchedResults<Drink>
    @State var isPreview = false
    
    var body: some View {
        NavigationView{
            VStack{
                HStack{
                    Spacer()
                    NavigationLink(destination: AddEditCocktailRecipeView()){
                        Text("Add Cocktail")
                            .padding()
                    }
                }
                CocktailListView()
            }
            .onAppear {
                if drinks.isEmpty && !isPreview {
                    seedDatabase()
                }
            }
        }
        /*NavigationView{
            VStack {
                NavigationLink(destination: CocktailListView()){
                    Text("View Cocktails")
                        .padding()
                        .background(Color.mint)
                        .foregroundColor(.indigo)
                        .cornerRadius(15)
                        .foregroundColor(.white)
                }
                NavigationLink(destination: AddEditCocktailRecipeView()){
                    Text("Add a New Cocktail")
                        .padding()
                        .background(Color.mint)
                        .foregroundColor(.indigo)
                        .cornerRadius(15)
                        .foregroundColor(.white)
                }
                .padding()
            }
            .padding()
        }*/
    }
    
    func seedDatabase() {
        struct ClassicCocktail {
            var name: String
            var ingredients: String
            var method: String
        }
        
        let classicCocktails = [
            ClassicCocktail(name: "Margarita", ingredients: "2pt Tequila /n1pt Tripe Sec /n1pt Lime Juice", method: "Combine ingredients in a shaker /nAdd Ice and shake until chilled /nStrain into a chilled glass or over ice"),
            ClassicCocktail(name: "Old Fashioned", ingredients: "2pt Bourbon /n1pt Simple Syrup /n2-4 dashes Angostura Bitters /nOrange Peel", method: "Combine ingredients in a mixing glass /nAdd Ice and stir until chilled /nStrain into a chilled glass or over ice /Express oil from orange peel over drink and use peel to garnish"),
            ClassicCocktail(name: "Martini", ingredients: "1pt Gin /n1pt Dry Vermouth /nOlive", method: "Combine ingredients in a mixing glass /nAdd Ice and stir until chilled /nStrain into a chilled martini glass /nGarnish with olive"),
            ClassicCocktail(name: "Daquiri", ingredients: "2pt Light Rum /n1pt Lime Juice /n.5pt Simple Syrup", method: "Combine ingredients in a shaker /nAdd Ice and shake until chilled /nStrain into a chilled coupe glass"),
        ]
        
        for cocktail in classicCocktails {
            let drink = Drink(context: context)
            drink.id = UUID()
            drink.source = 1
            drink.drinkName = cocktail.name
            drink.ingredients = cocktail.ingredients
            drink.method = cocktail.method
        }
        
        do {
            try context.save()
        } catch {
            print("error saving classics: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(isPreview: true)
    }
}
