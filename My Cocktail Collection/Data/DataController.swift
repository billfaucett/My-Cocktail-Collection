//
//  DataController.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import CoreData
import Foundation

class DataController: ObservableObject {
    let container = NSPersistentContainer(name: "CocktailRecipe")
    
    init() {
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data faled to load: \(error.localizedDescription)")
            }
        }
    }
}
