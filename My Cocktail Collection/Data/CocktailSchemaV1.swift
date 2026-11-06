//
//  CocktailSchemaV1.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 3: the new SwiftData models.
//
//  The models live inside a versioned schema. That's how SwiftData expects models to be organised
//  for future migrations, and for now it also keeps them apart from today's Core Data classes,
//  which use some of the same names (Bottle, Menu). Not used by the app yet.
//
//  iCloud-ready: every attribute has a default or is optional, every relationship is optional,
//  and there are no unique constraints (uniqueness is enforced by the stores).
//

import Foundation
import SwiftData

// MARK: - Cocktail source

/// Where a recipe came from. Stored as text.
enum CocktailSource: String, CaseIterable, Codable {
    case classic
    case website
    case menu
    case original

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .website: return "Website"
        case .menu: return "Menu"
        case .original: return "Original"
        }
    }

    /// The matching source from today's database.
    init(legacy: SourceType) {
        switch legacy {
        case .classic: self = .classic
        case .website: self = .website
        case .menu: self = .menu
        case .original: self = .original
        }
    }
}

// MARK: - Schema version 1

enum CocktailSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SpiritStyle.self, Bottle.self, Cocktail.self, RecipeIngredient.self, Menu.self, MenuEntry.self]
    }

    // MARK: Spirit style

    /// A style within a family, e.g. Bourbon (Whiskey) or Aperitivo (Liqueurs & Amari).
    @Model
    final class SpiritStyle {
        var id: UUID = UUID()
        var name: String = ""
        var familyRaw: String = SpiritFamily.other.rawValue
        var isBuiltIn: Bool = false
        var dateAdded: Date = Date()

        /// Deleting a style keeps its bottles, cocktails and ingredients; they just lose the link.
        @Relationship(deleteRule: .nullify, inverse: \Bottle.style)
        var bottles: [Bottle]? = []
        @Relationship(deleteRule: .nullify, inverse: \Cocktail.baseStyle)
        var cocktails: [Cocktail]? = []
        @Relationship(deleteRule: .nullify, inverse: \RecipeIngredient.style)
        var ingredients: [RecipeIngredient]? = []

        var family: SpiritFamily {
            get { SpiritFamily(rawValue: familyRaw) ?? .other }
            set { familyRaw = newValue.rawValue }
        }

        init(name: String, family: SpiritFamily, isBuiltIn: Bool = false) {
            self.name = name
            self.familyRaw = family.rawValue
            self.isBuiltIn = isBuiltIn
        }
    }

    // MARK: Bottle

    /// A bottle on the shelf, linked to its style.
    @Model
    final class Bottle {
        var id: UUID = UUID()
        var brand: String = ""
        var style: SpiritStyle?
        var stockLevelRaw: Int = Int(StockLevel.full.rawValue)
        var bottleCount: Int = 1
        var notes: String = ""
        var isFavorite: Bool = false
        /// 0 (not rated) to 10, shown as up to five stars.
        var rating: Int = 0
        @Attribute(.externalStorage)
        var photo: Data?
        var dateAdded: Date = Date()

        var stock: StockLevel {
            get { StockLevel(rawValue: Int16(clamping: stockLevelRaw)) ?? .full }
            set { stockLevelRaw = Int(newValue.rawValue) }
        }

        init(brand: String, stock: StockLevel = .full, bottleCount: Int = 1) {
            self.brand = brand
            self.stockLevelRaw = Int(stock.rawValue)
            self.bottleCount = bottleCount
        }
    }

    // MARK: Cocktail

    /// A recipe. Owns its ingredients and its places on menus.
    @Model
    final class Cocktail {
        var id: UUID = UUID()
        var name: String = ""
        var sourceRaw: String = CocktailSource.original.rawValue
        var baseStyle: SpiritStyle?

        /// Deleting a cocktail deletes its ingredients and removes it from menus.
        @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.cocktail)
        var ingredients: [RecipeIngredient]? = []
        @Relationship(deleteRule: .cascade, inverse: \MenuEntry.cocktail)
        var menuEntries: [MenuEntry]? = []

        /// Steps, one per line.
        var method: String = ""
        /// The ingredient text as it was before structured ingredients, kept for reference.
        var originalIngredientsText: String?
        /// True when the import wasn't sure about some ingredients.
        var needsIngredientReview: Bool = false
        /// 0 (not rated) to 10, shown as up to five stars.
        var rating: Int = 0
        var isFavorite: Bool = false
        @Attribute(.externalStorage)
        var photo: Data?
        var dateAdded: Date = Date()

        var source: CocktailSource {
            get { CocktailSource(rawValue: sourceRaw) ?? .original }
            set { sourceRaw = newValue.rawValue }
        }

        /// Ingredients in recipe order.
        var orderedIngredients: [RecipeIngredient] {
            (ingredients ?? []).sorted { $0.position < $1.position }
        }

        init(name: String, source: CocktailSource = .original, method: String = "") {
            self.name = name
            self.sourceRaw = source.rawValue
            self.method = method
        }
    }

    // MARK: Recipe ingredient

    /// One line of a recipe: an amount in parts (or a count), a name, and an optional style link.
    @Model
    final class RecipeIngredient {
        var id: UUID = UUID()
        /// Order within the recipe, starting at 0.
        var position: Int = 0
        var amount: Double?
        var amountMax: Double?
        var unitRaw: String = IngredientUnit.unspecified.rawValue
        var name: String = ""
        var note: String?
        var isGarnish: Bool = false
        var isOptional: Bool = false
        var cocktail: Cocktail?
        var style: SpiritStyle?

        var unit: IngredientUnit {
            get { IngredientUnit(rawValue: unitRaw) ?? .unspecified }
            set { unitRaw = newValue.rawValue }
        }

        init(position: Int, name: String, amount: Double? = nil, amountMax: Double? = nil,
             unit: IngredientUnit = .unspecified, note: String? = nil, isGarnish: Bool = false, isOptional: Bool = false) {
            self.position = position
            self.name = name
            self.amount = amount
            self.amountMax = amountMax
            self.unitRaw = unit.rawValue
            self.note = note
            self.isGarnish = isGarnish
            self.isOptional = isOptional
        }

        /// Copies a parsed line. The style link is set separately, since it needs the stored styles.
        convenience init(parsed: ParsedIngredient, position: Int) {
            self.init(position: position, name: parsed.name, amount: parsed.amount, amountMax: parsed.amountMax,
                      unit: parsed.unit, note: parsed.note, isGarnish: parsed.isGarnish, isOptional: parsed.isOptional)
        }
    }

    // MARK: Menu

    /// A named, dated list of cocktails, e.g. for a party.
    @Model
    final class Menu {
        var id: UUID = UUID()
        var name: String = ""
        var dateCreated: Date = Date()
        var notes: String = ""

        /// Deleting a menu deletes its entries; the cocktails stay in the collection.
        @Relationship(deleteRule: .cascade, inverse: \MenuEntry.menu)
        var entries: [MenuEntry]? = []

        /// Entries in menu order.
        var orderedEntries: [MenuEntry] {
            (entries ?? []).sorted { $0.position < $1.position }
        }

        init(name: String, dateCreated: Date = Date()) {
            self.name = name
            self.dateCreated = dateCreated
        }
    }

    // MARK: Menu entry

    /// A cocktail's place on a menu.
    @Model
    final class MenuEntry {
        var id: UUID = UUID()
        /// Order within the menu, starting at 0.
        var position: Int = 0
        var menu: Menu?
        var cocktail: Cocktail?

        init(position: Int) {
            self.position = position
        }
    }
}

// MARK: - Migration plan

/// Lists every schema version in order. New versions and their migration stages are added here.
enum CocktailMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CocktailSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Container

/// Creates the new database. It lives in its own file ("Cocktails.store"),
/// separate from today's Core Data file, which the importer will read from.
enum CocktailModelContainer {
    static let storeName = "Cocktails"

    /// - Parameter inMemory: Keeps everything in memory (tests and previews); nothing touches disk.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CocktailSchemaV1.self)
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: CocktailMigrationPlan.self, configurations: configuration)
    }
}
