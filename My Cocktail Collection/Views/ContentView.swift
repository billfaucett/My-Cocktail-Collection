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
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
    @State var isPreview = false
    @State var addNewCocktail = false
    @State var createMenu = false
    
    var body: some View {
        NavigationView{
            VStack{
                HStack{
                    /*Button("Delete Menu Data"){
                        deleteStuff()
                    }
                    .padding()*/
                    Spacer()
                    Button("Add Cocktail") {
                        addNewCocktail = true
                    }
                    .padding()
                }
                CocktailListView()
                HStack{
                    NavigationLink(destination: MenusListView()) {
                        Text("Menus")
                            .padding()
                    }
                    NavigationLink(destination: SpiritListView()){
                        Text("Spirit List")
                            .padding()
                    }
                    Button("Create a Menu") {
                        createMenu = true
                    }
                    .padding()
                    .sheet(isPresented: $createMenu) {
                        AddEditMenuView()
                    }
                }
            }
            .onAppear {
                if spirits.isEmpty && !isPreview {
                    seedSpirits()
                }
                if drinks.isEmpty && !isPreview {
                    seedCocktails()
                }
            }
        }
        .sheet(isPresented: $addNewCocktail) {
            AddEditCocktailRecipeView()
        }
    }
    
    func deleteStuff() {
        DeleteHelper().deleteAllRowsFromEntity(entity: MenuItem.self, context: context)
        DeleteHelper().deleteAllRowsFromEntity(entity: Menu.self, context: context)
    }
    
    func seedCocktails() {
        struct ClassicCocktail {
            var name: String
            var ingredients: String
            var method: String
            var liquor: String
        }
        
        let classicCocktails = [
            ClassicCocktail(name: "Margarita", ingredients: "2pt Tequila, 1pt Tripe Sec, 1pt Lime Juice", method: "Combine ingredients in a shaker, Add Ice and shake until chilled, Strain into a chilled glass or over ice", liquor: "Tequila"),
            ClassicCocktail(name: "Old Fashioned", ingredients: "2pt Bourbon, 1pt Simple Syrup, 2-4 dashes Angostura Bitters, Orange Peel", method: "Combine ingredients in a mixing glass, Add Ice and stir until chilled, Strain into a chilled glass or over ice, Express oil from orange peel over drink and use peel to garnish", liquor: "Bourbon"),
            ClassicCocktail(name: "Martini", ingredients: "1pt Gin, 1pt Dry Vermouth, Olive", method: "Combine ingredients in a mixing glass, Add Ice and stir until chilled, Strain into a chilled martini glass, Garnish with olive", liquor: "Gin"),
            ClassicCocktail(name: "Daquiri", ingredients: "2pt Light Rum, 1pt Lime Juice, .5pt Simple Syrup", method: "Combine ingredients in a shaker, Add Ice and shake until chilled, Strain into a chilled coupe glass", liquor: "Rum"),
            ClassicCocktail(name: "Cosmopolitan", ingredients: "2pt Vodka, 1pt Triple Sec, 1pt Cranberry Juice, .5pt Lime Juice, Orange Twist", method: "Combine ingredients in a shaker and top with ice, Shake for 10-15 seconds untile chilled, Strain into a chilled martini glass, garnisg with orange twist", liquor: "Vodka")
        ]
        
        for cocktail in classicCocktails {
            let drink = Drink(context: context)
            drink.id = UUID()
            drink.source = 0
            drink.drinkName = cocktail.name
            drink.ingredients = cocktail.ingredients
            drink.method = cocktail.method
            if let spirit = spirits.first(where: { $0.spiritName == cocktail.liquor }) {
                drink.baseSpirit = spirit.id
            }
        }
        
        do {
            try context.save()
        } catch {
            print("error saving classics: \(error)")
        }
    }
    
    func seedSpirits() {
        struct Liquor {
            var name: String
        }
        
        let liquors = [
            Liquor(name: "Vodka"),
            Liquor(name: "Bourbon"),
            Liquor(name: "Scotch"),
            Liquor(name: "Whiskey"),
            Liquor(name: "Rum"),
            Liquor(name: "Brandy"),
            Liquor(name: "Gin"),
            Liquor(name: "Tequila"),
            Liquor(name: "Aquavit")
        ]
        
        for liquor in liquors {
            let spirit = Spirit(context: context)
            spirit.id = UUID()
            spirit.spiritName = liquor.name
            spirit.type = 0
        }
        do {
            try context.save()
        } catch {
            print("error saving spirits: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(isPreview: true)
    }
}
