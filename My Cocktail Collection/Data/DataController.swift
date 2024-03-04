//
//  DataController.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import CoreData
import Foundation
import SwiftUI

class DataController: ObservableObject {
    let container = NSPersistentContainer(name: "CocktailRecipe")
    
    init() {
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data faled to load: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteStuff(context: NSManagedObjectContext) {
        DeleteHelper().deleteAllRowsFromEntity(entity: MenuItem.self, context: context)
        DeleteHelper().deleteAllRowsFromEntity(entity: Menu.self, context: context)
    }
    
    func seedCocktails(context: NSManagedObjectContext, spirits: FetchedResults<Spirit>) {
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
        
        //@FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
        
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
    
    func seedSpirits(context: NSManagedObjectContext) {
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
    
    func addBillsFaves(context: NSManagedObjectContext, spirits: FetchedResults<Spirit>, loadedDrinks: FetchedResults<Drink>) {
        struct ClassicCocktail {
            var name: String
            var ingredients: String
            var method: String
            var liquor: String
        }
        
        let billsFaves = [
            ClassicCocktail(name: "Blood Orange Margarita", ingredients: "3 parts Tequila, 2 parts Blood Orange Juice, 1 part Triple Sec, .5 parts Lime Juice, Optional .5 parts Agave Nectar", method: "Use a lime wedge to lightly salt the rim of a chilled glass, Mix ingredients into a cocktail shker filled with ice, Shake until chilled, Strain into your glass over ice, garnish with a slice of blood orange", liquor: "Tequila"),
            ClassicCocktail(name: "Irish Whiskey Sour", ingredients: "2 parts Irish Whiskey, 1 part Lemon Juice, .5-1 part Simple Syrup, Egg White", method: "Add all ingredients to a shaker without ice, Dry Shake 10-15 seconds to Froth the egg white, Add ice and shake again until chilled, Strain into a chilled low ball glass, Garnish with a twist of lemon and a Luxardo Cherry", liquor: "Whiskey"),
            ClassicCocktail(name: "Ranch Water", ingredients: "2 parts Tequila, 1 part Lime Juice, Topo Chico", method: "Add Tequila and Lime Juice to a shaker, Fill with ice and shake until chilled, strain into a chilled glass or over ice, Fill the rest of the glass with Topo Chico, Garnish with a wedge of lime", liquor: "Tequila"),
            ClassicCocktail(name: "Bourbon Renewal", ingredients: "2 parts Bourbon, 1 part Lemon Juice, .5 parts Creme de Cassis, .5 parts Simple Syrup", method: "Add igredients to a cocktail shaker, fill with ice and shake until chilled, strain into a low ball glass over a large ice cube, garnish with a slice of lemon", liquor: "Bourbon"),
            ClassicCocktail(name: "Chocolate Peanutbutter Sundae", ingredients: "2 parts Vodka, 1 part Creme de Cacao, .5 parts Peanut butter Whiskey, .5 parts Heavy Cream", method: "Add ingredients to a shaker, cover with ice and shake until chilled, strain ingredients into a chilled martini glass lined with a swirl of chocolate sauce, garnish with a luxardo cherry, and for an extra flourish float a touch of Luxardo Liqueur or Kirschwasser on top", liquor: "Vodka"),
            ClassicCocktail(name: "Cherry Bourbon Sour", ingredients: "2 parts bourbon, 1 part lemon juice, 3-4 Luxardo or bourbon soaked cherries, .5 parts simple syrup (if desired)", method: "To and old fashioned glass add the cherries and simple syrup, mull the cherries to a pulp, add a cube of lce to the glass and pour in the bourbon and lemon juice, stir with a bar spoon until combined and chilled, garnish with a cherry and lemon twist", liquor: "Bourbon")
        ]
        
        for cocktail in billsFaves {
            let isloaded = loadedDrinks.contains { $0.drinkName == cocktail.name }
            
            if !isloaded {
                let drink = Drink(context: context)
                drink.id = UUID()
                drink.source = 3
                drink.drinkName = cocktail.name
                drink.ingredients = cocktail.ingredients
                drink.method = cocktail.method
                if let spirit = spirits.first(where: { $0.spiritName == cocktail.liquor }) {
                    drink.baseSpirit = spirit.id
                }
            }
        }
        
        do {
            try context.save()
        } catch {
            print("error saving classics: \(error)")
        }
    }
}
