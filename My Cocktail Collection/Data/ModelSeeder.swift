//
//  ModelSeeder.swift
//  My Cocktail Collection
//
//  Built-in styles and recipes for the database. Classics are read by the ingredient parser,
//  so they arrive as ingredient rows in parts, each with its Cocktail Codex template.
//  Built-ins get fixed IDs worked out from their names, so every device gives the same recipe the
//  same ID and iCloud keeps one copy of it.
//

import CryptoKit
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
        try assignBuiltInIDs(context: context)
    }

    /// Gives built-in spirit types and recipes in My Library their fixed IDs (see `BuiltInID`), for databases
    /// made before IDs were fixed, or built-ins copied in by the old-database import. Matching is by name.
    /// If two items share a built-in's name, the oldest gets the ID. Safe to run at every launch.
    static func assignBuiltInIDs(context: ModelContext) throws {
        let builtInStyles = Set(SpiritTaxonomy.builtInStyles.map { BuiltInID.key($0.name) })
        let styles = try context.fetch(FetchDescriptor<DB.SpiritStyle>(sortBy: [SortDescriptor(\.dateAdded)]))
            .filter { $0.library == nil }
        let changedStyles = assignFixedIDs(to: styles, id: \.id) { style in
            builtInStyles.contains(BuiltInID.key(style.name)) ? BuiltInID.style(named: style.name) : nil
        }

        let builtInCocktails = Set((SeedData.classics + SeedData.favorites).map { BuiltInID.key($0.name) })
        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>(sortBy: [SortDescriptor(\.dateAdded)]))
            .filter { $0.library == nil }
        let changedCocktails = assignFixedIDs(to: cocktails, id: \.id) { cocktail in
            builtInCocktails.contains(BuiltInID.key(cocktail.name)) ? BuiltInID.cocktail(named: cocktail.name) : nil
        }

        if changedStyles || changedCocktails {
            try context.saveOrUndo()
        }
    }

    /// Sets each item's fixed ID unless another item already has it. Items should be oldest first.
    /// Returns true if anything changed.
    private static func assignFixedIDs<Item>(to items: [Item], id: ReferenceWritableKeyPath<Item, UUID>,
                                             fixedID: (Item) -> UUID?) -> Bool {
        var taken = Set(items.map { $0[keyPath: id] })
        var changed = false
        for item in items {
            guard let fixed = fixedID(item), item[keyPath: id] != fixed, !taken.contains(fixed) else { continue }
            taken.remove(item[keyPath: id])
            item[keyPath: id] = fixed
            taken.insert(fixed)
            changed = true
        }
        return changed
    }

    /// Gives built-in recipes their template when they don't have one yet, e.g. classics added or imported
    /// before templates existed. A template that's already set, including one you chose, is never changed.
    static func fillInTemplates(context: ModelContext) throws {
        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>()).filter { $0.library == nil }
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
        let existing = try context.fetch(FetchDescriptor<DB.SpiritStyle>()).filter { $0.library == nil }
        let existingNames = Set(existing.map { $0.name.lowercased() })
        let alreadyAdded = Set(defaults?.stringArray(forKey: seededStylesKey) ?? [])

        for builtIn in SpiritTaxonomy.builtInStyles where !existingNames.contains(builtIn.name.lowercased()) {
            guard defaults == nil || existing.isEmpty || !alreadyAdded.contains(builtIn.name) else { continue }
            let style = DB.SpiritStyle(name: builtIn.name, family: builtIn.family, isBuiltIn: true)
            style.id = BuiltInID.style(named: builtIn.name)
            context.insert(style)
        }
        try context.saveOrUndo()
        defaults?.set(alreadyAdded.union(SpiritTaxonomy.builtInStyles.map(\.name)).sorted(), forKey: seededStylesKey)
    }

    static func addMissingClassics(context: ModelContext, defaults: UserDefaults?) throws {
        let existing = try context.fetch(FetchDescriptor<DB.Cocktail>()).filter { $0.library == nil }
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
        let existingNames = Set(try context.fetch(FetchDescriptor<DB.Cocktail>()).filter { $0.library == nil }.map { $0.name.lowercased() })
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
        try CocktailStore(context: context).update(cocktail) {
            $0.id = BuiltInID.cocktail(named: seed.name)
            if let template = SeedData.templates[seed.name] {
                $0.template = template
            }
        }
    }
}

// MARK: - Fixed IDs for built-ins

/// IDs for built-in spirit types and recipes, worked out from their names. Every device gets the same ID
/// for the same built-in, so when iCloud sync arrives it recognises them as one item instead of two.
/// The formula must never change: IDs already in iCloud would stop matching.
enum BuiltInID {
    static func style(named name: String) -> UUID {
        make(kind: "style", name: name)
    }

    static func cocktail(named name: String) -> UUID {
        make(kind: "cocktail", name: name)
    }

    /// Names match ignoring case and surrounding spaces.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The first 16 bytes of a SHA-256 hash of "My Cocktail Collection/<kind>/<name>", marked as a
    /// name-based UUID (version 5 layout).
    private static func make(kind: String, name: String) -> UUID {
        let digest = SHA256.hash(data: Data("My Cocktail Collection/\(kind)/\(key(name))".utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
