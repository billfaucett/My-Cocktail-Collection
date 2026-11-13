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
        let deleted = BuiltInDeletions.ids(in: defaults)
        try assignBuiltInIDs(context: context, skipping: deleted)
        try removeDeletedBuiltIns(context: context, deleted: deleted)
    }

    /// Removes built-ins from My Library that you deleted on any device (see `BuiltInDeletions`), e.g. after
    /// a new device added them before hearing about the deletion. Your own items are never touched.
    static func removeDeletedBuiltIns(context: ModelContext, deleted: Set<UUID>) throws {
        guard !deleted.isEmpty else { return }
        var changed = false
        for style in try context.fetch(FetchDescriptor<DB.SpiritStyle>()) where style.library == nil && deleted.contains(style.id) {
            context.delete(style)
            changed = true
        }
        for cocktail in try context.fetch(FetchDescriptor<DB.Cocktail>()) where cocktail.library == nil && deleted.contains(cocktail.id) {
            context.delete(cocktail)
            changed = true
        }
        if changed {
            try context.saveOrUndo()
        }
    }

    /// Gives built-in spirit types and recipes in My Library their fixed IDs (see `BuiltInID`), for databases
    /// made before IDs were fixed, or built-ins copied in by the old-database import. Matching is by name.
    /// If two items share a built-in's name, the oldest gets the ID. Safe to run at every launch.
    /// IDs in `deleted` aren't given out again, so a built-in you deleted and later added back by hand stays.
    static func assignBuiltInIDs(context: ModelContext, skipping deleted: Set<UUID> = []) throws {
        let builtInStyles = Set(SpiritTaxonomy.builtInStyles.map { BuiltInID.key($0.name) })
        let styles = try context.fetch(FetchDescriptor<DB.SpiritStyle>(sortBy: [SortDescriptor(\.dateAdded)]))
            .filter { $0.library == nil }
        let changedStyles = assignFixedIDs(to: styles, id: \.id) { style in
            let fixed = BuiltInID.style(named: style.name)
            return builtInStyles.contains(BuiltInID.key(style.name)) && !deleted.contains(fixed) ? fixed : nil
        }

        let builtInCocktails = Set((SeedData.classics + SeedData.favorites).map { BuiltInID.key($0.name) })
        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>(sortBy: [SortDescriptor(\.dateAdded)]))
            .filter { $0.library == nil }
        let changedCocktails = assignFixedIDs(to: cocktails, id: \.id) { cocktail in
            let fixed = BuiltInID.cocktail(named: cocktail.name)
            return builtInCocktails.contains(BuiltInID.key(cocktail.name)) && !deleted.contains(fixed) ? fixed : nil
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
        let deleted = BuiltInDeletions.ids(in: defaults)

        for builtIn in SpiritTaxonomy.builtInStyles where !existingNames.contains(builtIn.name.lowercased()) {
            guard defaults == nil || existing.isEmpty || !alreadyAdded.contains(builtIn.name) else { continue }
            guard !deleted.contains(BuiltInID.style(named: builtIn.name)) else { continue } // Deleted on some device.
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
        let deleted = BuiltInDeletions.ids(in: defaults)

        for seed in SeedData.classics where !existingNames.contains(seed.name.lowercased()) {
            guard defaults == nil || existing.isEmpty || !alreadyAdded.contains(seed.name) else { continue }
            guard !deleted.contains(BuiltInID.cocktail(named: seed.name)) else { continue } // Deleted on some device.
            try add(seed, source: .classic, isFavorite: false, context: context)
        }
        defaults?.set(alreadyAdded.union(SeedData.classics.map(\.name)).sorted(), forKey: seededClassicsKey)
    }

    /// Adds the house favorites that aren't already in the collection, marked as favorites. You asked for
    /// them, so ones you deleted before come back too (with new IDs, so they aren't removed again).
    static func addHouseFavorites(context: ModelContext, deletions: UserDefaults? = BuiltInDeletions.store) throws {
        let existingNames = Set(try context.fetch(FetchDescriptor<DB.Cocktail>()).filter { $0.library == nil }.map { $0.name.lowercased() })
        let deleted = BuiltInDeletions.ids(in: deletions)
        for seed in SeedData.favorites where !existingNames.contains(seed.name.lowercased()) {
            try add(seed, source: .original, isFavorite: true, context: context, deleted: deleted)
        }
    }

    /// The style a built-in recipe's base spirit becomes (Gin → London Dry, Rum → Rum, Aperol → Aperitivo).
    static func baseStyleName(for seed: SeedCocktail) -> String {
        SpiritTaxonomy.placement(forLegacySpirit: seed.spirit, type: .liquor).styleName
    }

    private static func add(_ seed: SeedCocktail, source: CocktailSource, isFavorite: Bool, context: ModelContext,
                            deleted: Set<UUID> = []) throws {
        let baseStyle = try StyleStore(context: context).style(named: baseStyleName(for: seed))
        let cocktail = try CocktailStore(context: context).addCocktail(
            name: seed.name,
            source: source,
            baseStyle: baseStyle,
            ingredients: IngredientParser.parse(seed.ingredientsText).ingredients,
            method: seed.methodText,
            isFavorite: isFavorite
        )
        let fixedID = BuiltInID.cocktail(named: seed.name)
        try CocktailStore(context: context).update(cocktail) {
            if !deleted.contains(fixedID) {
                $0.id = fixedID
            }
            if let template = SeedData.templates[seed.name] {
                $0.template = template
            }
        }
    }
}

// MARK: - Deleted built-ins

/// Built-ins you've deleted, by fixed ID. Kept in UserDefaults and copied to your other devices through
/// iCloud key-value storage (`SettingsSync`), so a new device doesn't add them back and send them to iCloud again.
enum BuiltInDeletions {
    static let key = "DeletedBuiltInIDs"

    /// Where deletions are remembered: UserDefaults in the app, nothing in tests (which use their own suites).
    static var store: UserDefaults? {
        let process = ProcessInfo.processInfo
        if process.environment["XCTestConfigurationFilePath"] != nil || process.arguments.contains("-uiTesting") {
            return nil
        }
        return .standard
    }

    static func ids(in defaults: UserDefaults?) -> Set<UUID> {
        Set((defaults?.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func record(_ id: UUID, in defaults: UserDefaults?) {
        guard let defaults else { return }
        var list = defaults.stringArray(forKey: key) ?? []
        guard !list.contains(id.uuidString) else { return }
        list.append(id.uuidString)
        defaults.set(list.sorted(), forKey: key)
    }

    /// Every built-in recipe's fixed ID (classics and house favorites).
    static let cocktailIDs = Set((SeedData.classics + SeedData.favorites).map { BuiltInID.cocktail(named: $0.name) })
    /// Every built-in spirit type's fixed ID.
    static let styleIDs = Set(SpiritTaxonomy.builtInStyles.map { BuiltInID.style(named: $0.name) })

    /// Remembers a deleted cocktail if it's one of My Library's built-ins (even if you renamed it).
    static func noteDeleted(_ cocktail: DB.Cocktail, in defaults: UserDefaults? = store) {
        if cocktail.library == nil && cocktailIDs.contains(cocktail.id) {
            record(cocktail.id, in: defaults)
        }
    }

    /// Remembers a deleted spirit type if it's one of My Library's built-ins.
    static func noteDeleted(_ style: DB.SpiritStyle, in defaults: UserDefaults? = store) {
        if style.library == nil && styleIDs.contains(style.id) {
            record(style.id, in: defaults)
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
