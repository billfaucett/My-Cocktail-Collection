//
//  LegacyImporter.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 4: copies everything from the current Core Data database
//  into the new SwiftData database, once.
//
//  The old database file is never opened or changed. The importer copies it to a temporary
//  folder, upgrades and reads the copy, then deletes the copy. Everything is saved in one go:
//  if anything fails, nothing is kept and the import can simply run again.
//

import Foundation
import CoreData
import SwiftData

/// What an import copied across.
struct ImportSummary: Equatable {
    var cocktails = 0
    var bottles = 0
    var menus = 0
    var menuEntries = 0
    /// Your own spirits that didn't match a built-in style and became new styles.
    var customStyles = 0
    /// Cocktails whose ingredients the parser wasn't sure about.
    var cocktailsNeedingReview = 0
}

enum ImportError: LocalizedError {
    case couldNotOpenOldDatabase(String)

    var errorDescription: String? {
        switch self {
        case .couldNotOpenOldDatabase(let reason):
            return "Your recipes couldn't be read from the old database: \(reason)"
        }
    }
}

struct LegacyImporter {
    let context: ModelContext
    /// The old Core Data database. Tests point this at their own files.
    var legacyStoreURL: URL = LegacyImporter.defaultLegacyStoreURL
    /// Where the seeding records live. Pass nil to leave them alone (tests).
    var defaults: UserDefaults? = .standard

    /// Where today's app keeps its database ("CocktailRecipe.sqlite").
    static var defaultLegacyStoreURL: URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("CocktailRecipe.sqlite")
    }

    /// True once an import has completed into this database.
    var hasImported: Bool {
        ((try? context.fetchCount(FetchDescriptor<DB.ImportRecord>())) ?? 0) > 0
    }

    /// Imports if there's an old database and it hasn't been imported yet. Returns nil when there was nothing to do.
    @discardableResult
    func importIfNeeded() throws -> ImportSummary? {
        guard !hasImported, FileManager.default.fileExists(atPath: legacyStoreURL.path) else { return nil }
        return try runImport()
    }

    /// Copies everything across in one save. On any error nothing is kept and the error is passed on.
    @discardableResult
    func runImport() throws -> ImportSummary {
        let workFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        let legacy = try openCopy(of: legacyStoreURL, in: workFolder)
        defer {
            for store in legacy.persistentStoreCoordinator.persistentStores {
                try? legacy.persistentStoreCoordinator.remove(store)
            }
        }

        do {
            let (summary, offeredClassics) = try copyEverything(from: legacy.viewContext)
            try context.save()
            if let defaults {
                defaults.set(offeredClassics.sorted(), forKey: ModelSeeder.seededClassicsKey)
                defaults.set(SpiritTaxonomy.builtInStyles.map(\.name).sorted(), forKey: ModelSeeder.seededStylesKey)
            }
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Opening the old database

    /// Copies the database files to `folder` and opens the copy, upgrading it to the current model if needed.
    private func openCopy(of storeURL: URL, in folder: URL) throws -> NSPersistentContainer {
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            }
        }
        // Large photos live outside the database file, in a hidden folder beside it
        // (".CocktailRecipe_SUPPORT"). Without it, those photos would be missing from the copy.
        let supportFolder = storeURL.deletingLastPathComponent()
            .appendingPathComponent(Self.supportFolderName(for: storeURL), isDirectory: true)
        if FileManager.default.fileExists(atPath: supportFolder.path) {
            try FileManager.default.copyItem(at: supportFolder, to: folder.appendingPathComponent(supportFolder.lastPathComponent, isDirectory: true))
        }

        let container = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: DataController.model)
        let description = NSPersistentStoreDescription(url: folder.appendingPathComponent(storeURL.lastPathComponent))
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw ImportError.couldNotOpenOldDatabase(loadError.localizedDescription)
        }
        return container
    }

    // MARK: Copying

    /// Inserts everything into the new database without saving. Returns the summary and the
    /// classic cocktail names to record as already offered.
    private func copyEverything(from old: NSManagedObjectContext) throws -> (ImportSummary, Set<String>) {
        var summary = ImportSummary()

        // 1. Built-in styles, then a style for each old spirit (see the mapping in SpiritTaxonomy).
        var stylesByName: [String: DB.SpiritStyle] = [:]
        for style in try context.fetch(FetchDescriptor<DB.SpiritStyle>()) {
            stylesByName[style.name.lowercased()] = style
        }
        for builtIn in SpiritTaxonomy.builtInStyles where stylesByName[builtIn.name.lowercased()] == nil {
            let style = DB.SpiritStyle(name: builtIn.name, family: builtIn.family, isBuiltIn: true)
            context.insert(style)
            stylesByName[builtIn.name.lowercased()] = style
        }

        var styleForSpiritID: [UUID: DB.SpiritStyle] = [:]
        var styleForSpiritObject: [NSManagedObjectID: DB.SpiritStyle] = [:]
        for spirit in try old.fetch(NSFetchRequest<Spirit>(entityName: "Spirit")) {
            let name = (spirit.spiritName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let placement = SpiritTaxonomy.placement(forLegacySpirit: name, type: SpiritType(rawValue: spirit.type) ?? .liquor)
            let style: DB.SpiritStyle
            if let existing = stylesByName[placement.styleName.lowercased()] {
                style = existing
            } else {
                style = DB.SpiritStyle(name: placement.styleName, family: placement.family)
                context.insert(style)
                stylesByName[placement.styleName.lowercased()] = style
                summary.customStyles += 1
            }
            if let id = spirit.id {
                styleForSpiritID[id] = style
            }
            styleForSpiritObject[spirit.objectID] = style
        }

        // 2. Cocktails, with ingredients read into rows. Older databases never received the built-in
        //    recipe corrections, so they're applied here. The original ingredient text is kept as it was.
        let classicsByName = Dictionary(SeedData.classics.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let drinks = try old.fetch(NSFetchRequest<Drink>(entityName: "Drink"))
        let takenNames = Set(drinks.map { Self.clean($0.drinkName, fallback: "") })
        var cocktailForDrink: [NSManagedObjectID: DB.Cocktail] = [:]
        for drink in drinks {
            let recipe = SeedData.corrected(
                name: Self.clean(drink.drinkName, fallback: "Untitled Cocktail"),
                ingredients: drink.ingredients,
                method: drink.method,
                takenNames: takenNames
            )
            let cocktail = DB.Cocktail(
                name: recipe.name,
                source: CocktailSource(legacy: SourceType(rawValue: drink.source) ?? .original),
                method: recipe.method ?? ""
            )
            context.insert(cocktail)
            cocktail.rating = Int(min(max(drink.rating, 0), 10))
            cocktail.isFavorite = drink.isFavorite
            cocktail.photo = drink.image
            cocktail.originalIngredientsText = drink.ingredients

            // Base style: the old spirit link; for a built-in classic with no link, its seed data.
            if let spiritID = drink.baseSpirit, let style = styleForSpiritID[spiritID] {
                cocktail.baseStyle = style
            } else if let seed = classicsByName[cocktail.name.lowercased()] {
                cocktail.baseStyle = stylesByName[ModelSeeder.baseStyleName(for: seed).lowercased()]
            }

            let parsed = IngredientParser.parse(recipe.ingredients ?? "").ingredients
            for (position, line) in parsed.enumerated() {
                let ingredient = DB.RecipeIngredient(parsed: line, position: position)
                context.insert(ingredient)
                ingredient.cocktail = cocktail
                ingredient.style = line.styleName.flatMap { stylesByName[$0.lowercased()] }
            }
            cocktail.needsIngredientReview = parsed.contains(where: \.needsReview)
            if cocktail.needsIngredientReview {
                summary.cocktailsNeedingReview += 1
            }

            cocktailForDrink[drink.objectID] = cocktail
            summary.cocktails += 1
        }

        // 3. Bottles (version 2 and later databases).
        for bottle in try old.fetch(NSFetchRequest<Bottle>(entityName: "Bottle")) {
            let newBottle = DB.Bottle(
                brand: Self.clean(bottle.brand, fallback: "Unnamed Bottle"),
                stock: StockLevel(rawValue: bottle.stockLevel) ?? .full,
                bottleCount: max(Int(bottle.bottleCount), 0)
            )
            context.insert(newBottle)
            newBottle.style = bottle.spirit.flatMap { styleForSpiritObject[$0.objectID] }
            newBottle.notes = bottle.notes ?? ""
            newBottle.isFavorite = bottle.isFavorite
            newBottle.rating = Int(min(max(bottle.rating, 0), 10))
            newBottle.photo = bottle.image
            newBottle.dateAdded = bottle.dateAdded ?? Date()
            summary.bottles += 1
        }

        // 4. Menus. Entries in cocktail name order; each cocktail once; entries whose cocktail is gone are skipped.
        let oldItems = try old.fetch(NSFetchRequest<MenuItem>(entityName: "MenuItem"))
        for menu in try old.fetch(NSFetchRequest<Menu>(entityName: "Menu")) {
            let newMenu = DB.Menu(name: Self.clean(menu.menuName, fallback: "Untitled Menu"), dateCreated: menu.dateCreated ?? Date())
            context.insert(newMenu)
            summary.menus += 1

            var seen = Set<UUID>()
            let cocktails = oldItems
                .filter { $0.menu == menu }
                .compactMap { item in item.drink.flatMap { cocktailForDrink[$0.objectID] } }
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for (position, cocktail) in cocktails.enumerated() {
                let entry = DB.MenuEntry(position: position)
                context.insert(entry)
                entry.menu = newMenu
                entry.cocktail = cocktail
                summary.menuEntries += 1
            }
        }

        // 5. Mark the import complete, in the same save as the data.
        context.insert(DB.ImportRecord(cocktailCount: summary.cocktails, bottleCount: summary.bottles, menuCount: summary.menus))

        // Classics already offered by the old app, so ones you deleted there stay deleted.
        // Older installs have no record: every version seeded the original five classics, so those
        // count as offered (a missing one was deleted), plus whatever was actually imported.
        let legacyRecord = defaults?.stringArray(forKey: DataController.seededCocktailsKey)
        let offered = legacyRecord.map { Set($0) }
            ?? Set(cocktailForDrink.values.map(\.name)).union(SeedData.originalClassicRecipes.keys)
        return (summary, offered)
    }

    /// Core Data's folder for large binary data: ".CocktailRecipe_SUPPORT" for "CocktailRecipe.sqlite".
    static func supportFolderName(for storeURL: URL) -> String {
        "." + storeURL.deletingPathExtension().lastPathComponent + "_SUPPORT"
    }

    private static func clean(_ text: String?, fallback: String) -> String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
