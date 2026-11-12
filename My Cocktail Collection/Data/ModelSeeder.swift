//
//  ModelSeeder.swift
//  My Cocktail Collection
//
//  Built-in styles and recipes for the database. Classics are read by the ingredient parser,
//  so they arrive as ingredient rows in parts, each with its Cocktail Codex template.
//

import Foundation
import SwiftData

enum ModelSeeder {
    /// Remember which built-ins have been added to the new database, so ones you delete stay deleted.
    static let seededStylesKey = "SeededStyleNamesV1"
    static let seededClassicsKey = "SeededClassicNamesV1"

    /// Adds any missing built-in styles, then any missing classic cocktails.
    ///
    /// With `defaults`, each built-in is added once: if you delete it later it stays deleted, unless that
    /// list is completely empty. Pass nil (previews, tests) to add everything that's missing.
    static func seedBuiltIns(context: ModelContext, defaults: UserDefaults? = .standard) throws {
        try addMissingStyles(context: context, defaults: defaults)
        try addMissingClassics(context: context, defaults: defaults)
        try fillInTemplates(context: context)
    }

    /// Gives built-in recipes their template when they don't have one yet, e.g. classics added or imported
    /// before templates existed. A template that's already set, including one you chose, is never changed.
    static func fillInTemplates(context: ModelContext) throws {
        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>())
        var changed = false
        for cocktail in cocktails where cocktail.template == nil {
            if let template = SeedData.templates[cocktail.name] {
                cocktail.template = template
                changed = true
            }
        }
        if changed {
            try context.saveOrUndo()
        }
    }

    static func addMissingStyles(context: ModelContext, defaults: UserDefaults?) throws {
        let existing = try context.fetch(FetchDescriptor<DB.SpiritStyle>())
        let existingNames = Set(existing.map { $0.name.lowercased() })
        let alreadyAdded = Set(defaults?.stringArray(forKey: seededStylesKey) ?? [])

        for builtIn in SpiritTaxonomy.builtInStyles where !existingNames.contains(builtIn.name.lowercased()) {
            guard defaults == nil || existing.isEmpty || !alreadyAdded.contains(builtIn.name) else { continue }
            context.insert(DB.SpiritStyle(name: builtIn.name, family: builtIn.family, isBuiltIn: true))
        }
        try context.saveOrUndo()
        defaults?.set(alreadyAdded.union(SpiritTaxonomy.builtInStyles.map(\.name)).sorted(), forKey: seededStylesKey)
    }

    static func addMissingClassics(context: ModelContext, defaults: UserDefaults?) throws {
        let existing = try context.fetch(FetchDescriptor<DB.Cocktail>())
        let existingNames = Set(existing.map { $0.name.lowercased() })
        let alreadyAdded = Set(defaults?.stringArray(forKey: seededClassicsKey) ?? [])

        for seed in SeedData.classics where !existingNames.contains(seed.name.lowercased()) {
            guard defaults == nil || existing.isEmpty || !alreadyAdded.contains(seed.name) else { continue }
            try add(seed, source: .classic, isFavorite: false, context: context)
        }
        defaults?.set(alreadyAdded.union(SeedData.classics.map(\.name)).sorted(), forKey: seededClassicsKey)
    }

    /// Adds the house favorites that aren't already in the collection, marked as favorites.
    static func addHouseFavorites(context: ModelContext) throws {
        let existingNames = Set(try context.fetch(FetchDescriptor<DB.Cocktail>()).map { $0.name.lowercased() })
        for seed in SeedData.favorites where !existingNames.contains(seed.name.lowercased()) {
            try add(seed, source: .original, isFavorite: true, context: context)
        }
    }

    /// The style a built-in recipe's base spirit becomes (Gin → London Dry, Rum → Rum, Aperol → Aperitivo).
    static func baseStyleName(for seed: SeedCocktail) -> String {
        SpiritTaxonomy.placement(forLegacySpirit: seed.spirit, type: .liquor).styleName
    }

    private static func add(_ seed: SeedCocktail, source: CocktailSource, isFavorite: Bool, context: ModelContext) throws {
        let baseStyle = try StyleStore(context: context).style(named: baseStyleName(for: seed))
        let cocktail = try CocktailStore(context: context).addCocktail(
            name: seed.name,
            source: source,
            baseStyle: baseStyle,
            ingredients: IngredientParser.parse(seed.ingredientsText).ingredients,
            method: seed.methodText,
            isFavorite: isFavorite
        )
        if let template = SeedData.templates[seed.name] {
            try CocktailStore(context: context).update(cocktail) { $0.template = template }
        }
    }
}
