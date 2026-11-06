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
    /// The data model is loaded once and shared. If the app and its tests each loaded their own copy,
    /// Core Data could get confused about which entity a class like `Drink` belongs to.
    static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: DataController.self).url(forResource: "CocktailRecipe", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Could not load the CocktailRecipe data model")
        }
        return model
    }()
    
    let container: NSPersistentContainer
    
    /// - Parameter inMemory: When true, data lives only in memory and nothing is written to disk.
    ///   Used by tests so they never touch your real recipes.
    init(inMemory: Bool = false) {
        // Keeping the name "CocktailRecipe" keeps the same database file, so existing data is untouched.
        container = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: DataController.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data faled to load: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Deleting

    /// Deletes a cocktail and removes it from any menus, so no empty menu entries are left behind.
    static func delete(_ drink: Drink, context: NSManagedObjectContext) {
        let request = NSFetchRequest<MenuItem>(entityName: "MenuItem")
        request.predicate = NSPredicate(format: "drink == %@", drink)
        let items = (try? context.fetch(request)) ?? []
        items.forEach { context.delete($0) }
        context.delete(drink)
        context.saveOrRollback()
    }
    
    static func deleteStuff(context: NSManagedObjectContext) {
        DeleteHelper().deleteAllRowsFromEntity(entity: MenuItem.self, context: context)
        DeleteHelper().deleteAllRowsFromEntity(entity: Menu.self, context: context)
    }
    
    // MARK: - Built-in spirits and cocktails
    
    /// The house favorites added by "Add Our Favorite Cocktails".
    static let favoriteCocktailNames: Set<String> = Set(SeedData.favorites.map(\.name))
    
    /// Remembers which built-in spirits and cocktails have been added, so ones you delete stay deleted.
    static let seededSpiritsKey = "SeededSpiritNames"
    static let seededCocktailsKey = "SeededClassicCocktailNames"
    
    /// Runs at every launch:
    /// 1. Adds any built-in spirits and classic cocktails that are missing (see `SeedData`).
    /// 2. Fixes typos and outdated text from earlier versions of the built-in recipes.
    /// 3. Links built-in cocktails to their base spirit.
    ///
    /// Each built-in spirit and cocktail is added once. If you delete one later it stays deleted,
    /// unless that list is completely empty, in which case everything is added again.
    /// - Parameter defaults: Where the record of what's been added is kept. Tests pass their own.
    static func seedIfNeeded(context: NSManagedObjectContext, defaults: UserDefaults = .standard) {
        addMissingSpirits(context: context, defaults: defaults)
        applySeedCorrections(context: context)
        addMissingClassics(context: context, defaults: defaults)
        linkMissingBaseSpirits(context: context)
    }
    
    /// Adds every built-in spirit that isn't already in the list. Used by previews; the app uses `seedIfNeeded`.
    static func seedSpirits(context: NSManagedObjectContext) {
        addMissingSpirits(context: context, defaults: nil)
    }
    
    /// Adds every classic cocktail that isn't already in the collection. Used by previews; the app uses `seedIfNeeded`.
    static func seedCocktails(context: NSManagedObjectContext) {
        addMissingClassics(context: context, defaults: nil)
        linkMissingBaseSpirits(context: context)
    }
    
    /// Adds the house favorites that aren't already in the collection.
    static func addBillsFaves(context: NSManagedObjectContext) {
        let existing = Set(fetchAll(Drink.self, context: context).compactMap { $0.drinkName?.lowercased() })
        let spirits = fetchAll(Spirit.self, context: context)
        for cocktail in SeedData.favorites where !existing.contains(cocktail.name.lowercased()) {
            insert(cocktail, source: .original, spirits: spirits, context: context)
        }
        context.saveOrRollback()
    }
    
    /// Fixes earlier versions of the built-in recipes:
    /// - renames cocktails listed in `SeedData.renamedCocktails` (e.g. "Daquiri")
    /// - replaces the original five classics with the updated recipes, if they were never edited
    /// - corrects known typos in built-in recipes, even edited ones
    static func applySeedCorrections(context: NSManagedObjectContext) {
        let drinks = fetchAll(Drink.self, context: context)
        let existingNames = Set(drinks.compactMap(\.drinkName))
        for drink in drinks {
            if let oldName = drink.drinkName, let newName = SeedData.renamedCocktails[oldName], !existingNames.contains(newName) {
                drink.drinkName = newName
            }
        }
        
        let builtIn = Dictionary((SeedData.classics + SeedData.favorites).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for drink in drinks {
            guard let name = drink.drinkName, let seed = builtIn[name] else { continue }
            if let original = SeedData.originalClassicRecipes[name],
               drink.ingredients == original.ingredients,
               drink.method == original.method {
                drink.ingredients = seed.ingredientsText
                drink.method = seed.methodText
                continue
            }
            for fix in SeedData.typoFixes {
                if let text = drink.ingredients, text.contains(fix.typo) {
                    drink.ingredients = text.replacingOccurrences(of: fix.typo, with: fix.correction)
                }
                if let text = drink.method, text.contains(fix.typo) {
                    drink.method = text.replacingOccurrences(of: fix.typo, with: fix.correction)
                }
            }
        }
        context.saveOrRollback()
    }
    
    /// Links built-in cocktails that have no base spirit to the right one. Drinks you created are not touched.
    static func linkMissingBaseSpirits(context: NSManagedObjectContext) {
        let request = NSFetchRequest<Drink>(entityName: "Drink")
        request.predicate = NSPredicate(format: "baseSpirit == nil")
        guard let drinks = try? context.fetch(request), !drinks.isEmpty else { return }
        let spirits = fetchAll(Spirit.self, context: context)
        let spiritForCocktail = Dictionary(
            (SeedData.classics + SeedData.favorites).map { ($0.name.lowercased(), $0.spirit) },
            uniquingKeysWith: { first, _ in first }
        )
        
        for drink in drinks {
            guard let spiritName = spiritForCocktail[(drink.drinkName ?? "").lowercased()],
                  let spirit = findSpirit(named: spiritName, in: spirits) else { continue }
            drink.baseSpirit = spirit.id
        }
        context.saveOrRollback()
    }
    
    // MARK: Seeding helpers
    
    /// Adds missing built-in spirits. With `defaults`, each one is only ever added once.
    private static func addMissingSpirits(context: NSManagedObjectContext, defaults: UserDefaults?) {
        let spirits = fetchAll(Spirit.self, context: context)
        let existing = Set(spirits.compactMap { $0.spiritName?.lowercased() })
        let alreadyAdded = Set(defaults?.stringArray(forKey: seededSpiritsKey) ?? [])
        let listIsEmpty = spirits.isEmpty
        
        for seed in SeedData.spirits where !existing.contains(seed.name.lowercased()) {
            guard defaults == nil || listIsEmpty || !alreadyAdded.contains(seed.name) else { continue }
            let spirit = Spirit(context: context)
            spirit.id = UUID()
            spirit.spiritName = seed.name
            spirit.type = seed.type.rawValue
        }
        if context.saveOrRollback() {
            defaults?.set(alreadyAdded.union(SeedData.spirits.map(\.name)).sorted(), forKey: seededSpiritsKey)
        }
    }
    
    /// Adds missing classic cocktails. With `defaults`, each one is only ever added once.
    private static func addMissingClassics(context: NSManagedObjectContext, defaults: UserDefaults?) {
        let drinks = fetchAll(Drink.self, context: context)
        let existing = Set(drinks.compactMap { $0.drinkName?.lowercased() })
        let alreadyAdded = Set(defaults?.stringArray(forKey: seededCocktailsKey) ?? [])
        let collectionIsEmpty = drinks.isEmpty
        let spirits = fetchAll(Spirit.self, context: context)
        
        for cocktail in SeedData.classics where !existing.contains(cocktail.name.lowercased()) {
            guard defaults == nil || collectionIsEmpty || !alreadyAdded.contains(cocktail.name) else { continue }
            insert(cocktail, source: .classic, spirits: spirits, context: context)
        }
        if context.saveOrRollback() {
            defaults?.set(alreadyAdded.union(SeedData.classics.map(\.name)).sorted(), forKey: seededCocktailsKey)
        }
    }
    
    private static func insert(_ cocktail: SeedCocktail, source: SourceType, spirits: [Spirit], context: NSManagedObjectContext) {
        let drink = Drink(context: context)
        drink.id = UUID()
        drink.source = source.rawValue
        drink.drinkName = cocktail.name
        drink.ingredients = cocktail.ingredientsText
        drink.method = cocktail.methodText
        drink.baseSpirit = findSpirit(named: cocktail.spirit, in: spirits)?.id
    }
    
    private static func findSpirit(named name: String, in spirits: [Spirit]) -> Spirit? {
        spirits.first { ($0.spiritName ?? "").caseInsensitiveCompare(name) == .orderedSame }
    }
    
    private static func fetchAll<T: NSManagedObject>(_ type: T.Type, context: NSManagedObjectContext) -> [T] {
        (try? context.fetch(NSFetchRequest<T>(entityName: String(describing: type)))) ?? []
    }
}

extension NSManagedObjectContext {
    /// Saves any changes. If saving fails, the changes are undone and the error is logged.
    @discardableResult
    func saveOrRollback() -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            rollback()
            print("Failed to save changes: \(error)")
            return false
        }
    }
}
