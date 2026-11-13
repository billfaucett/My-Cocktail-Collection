//
//  CocktailSchemaV3.swift
//  My Cocktail Collection
//
//  Data model version 3: prepares for iCloud sync and sharing. Adds libraries (yours, and ones shared
//  with you) and the bookkeeping iCloud sync needs. Cocktails, menus and spirit types can belong to a
//  library; with none they're in My Library, so existing data comes through unchanged. Bottles (My Bar)
//  stay private and never belong to a library. Versions 1 and 2 are kept so older databases can be migrated.
//

import Foundation
import SwiftData

/// The app's current models. Use `DB.Cocktail`, `DB.Bottle`… so a new schema version only changes this line.
typealias DB = CocktailSchemaV3

enum CocktailSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SpiritStyle.self, Bottle.self, Cocktail.self, RecipeIngredient.self, Menu.self, MenuEntry.self, ImportRecord.self,
         Library.self, SyncRecord.self]
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
        /// The library it belongs to. Nil means My Library; a library shared with you sets it. (New in version 3.)
        var library: Library?

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
        /// 0 (not rated) to 10. Kept, but no longer shown or edited.
        var rating: Int = 0
        var isFavorite: Bool = false
        @Attribute(.externalStorage)
        var photo: Data?
        var dateAdded: Date = Date()
        /// Which of the six Cocktail Codex templates the recipe follows. Nil until it's set. (Added in version 2.)
        var templateRaw: String?
        /// The library it belongs to. Nil means My Library; a library shared with you sets it. (New in version 3.)
        var library: Library?

        var template: CocktailTemplate? {
            get { templateRaw.flatMap(CocktailTemplate.init(rawValue:)) }
            set { templateRaw = newValue?.rawValue }
        }

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
        /// The library it belongs to. Nil means My Library; a library shared with you sets it. (New in version 3.)
        var library: Library?

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

    // MARK: Import record

    /// Written once, in the same save as the imported data, when the old database has been copied in.
    /// Its presence means the import never runs again.
    @Model
    final class ImportRecord {
        var completedAt: Date = Date()
        var cocktailCount: Int = 0
        var bottleCount: Int = 0
        var menuCount: Int = 0

        init(cocktailCount: Int, bottleCount: Int, menuCount: Int) {
            self.cocktailCount = cocktailCount
            self.bottleCount = bottleCount
            self.menuCount = menuCount
        }
    }

    // MARK: Library (new in version 3)

    /// A collection of cocktails, menus and spirit types that syncs as one unit in iCloud.
    /// Everything with no library is in My Library, so existing data needs no changes. A library someone
    /// shares with you gets a row here; removing it removes everything in it. My Bar is never in a library.
    @Model
    final class Library {
        var id: UUID = UUID()
        /// Shown in the app, e.g. "Bill's Library".
        var name: String = ""
        /// The person who owns it.
        var ownerName: String = ""
        /// True for your own library (used once it's shared), false for one shared with you.
        var isOwned: Bool = false
        /// Whether you can change it. Always true for your own.
        var canEdit: Bool = false
        /// Where it lives in iCloud (the record zone and its owner).
        var zoneName: String = ""
        var zoneOwnerName: String = ""
        var dateAdded: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Cocktail.library)
        var cocktails: [Cocktail]? = []
        @Relationship(deleteRule: .cascade, inverse: \Menu.library)
        var menus: [Menu]? = []
        @Relationship(deleteRule: .cascade, inverse: \SpiritStyle.library)
        var styles: [SpiritStyle]? = []

        init(name: String, ownerName: String, zoneName: String, zoneOwnerName: String,
             isOwned: Bool = false, canEdit: Bool = false) {
            self.name = name
            self.ownerName = ownerName
            self.zoneName = zoneName
            self.zoneOwnerName = zoneOwnerName
            self.isOwned = isOwned
            self.canEdit = canEdit || isOwned
        }
    }

    // MARK: Sync record (new in version 3)

    /// Bookkeeping for iCloud: one per item that has been sent to or received from iCloud.
    /// It keeps the record's iCloud details so later changes update the same record. Never shown in the app.
    @Model
    final class SyncRecord {
        /// The kind of item, e.g. "Cocktail".
        var recordType: String = ""
        /// The item's `id`, which is also its record name in iCloud.
        var recordName: String = ""
        var zoneName: String = ""
        var zoneOwnerName: String = ""
        /// iCloud's system fields for the record (encoded), needed to save changes to it.
        var systemFields: Data?
        /// True when the item changed here and iCloud hasn't been told yet.
        var needsUpload: Bool = false
        var dateModified: Date = Date()

        init(recordType: String, recordName: String, zoneName: String, zoneOwnerName: String) {
            self.recordType = recordType
            self.recordName = recordName
            self.zoneName = zoneName
            self.zoneOwnerName = zoneOwnerName
        }
    }
}

// MARK: - Migration plan

/// Lists every schema version in order. New versions and their migration stages are added here.
enum CocktailMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CocktailSchemaV1.self, CocktailSchemaV2.self, CocktailSchemaV3.self] }

    /// Version 2 adds an optional field (Cocktail.templateRaw). Version 3 adds two models (Library, SyncRecord)
    /// and optional library links. SwiftData migrates both on its own.
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CocktailSchemaV1.self, toVersion: CocktailSchemaV2.self),
            .lightweight(fromVersion: CocktailSchemaV2.self, toVersion: CocktailSchemaV3.self),
        ]
    }
}

// MARK: - Container

/// Creates the new database. It lives in its own file ("Cocktails.store"),
/// separate from today's Core Data file, which the importer will read from.
enum CocktailModelContainer {
    static let storeName = "Cocktails"

    /// - Parameters:
    ///   - inMemory: Keeps everything in memory (tests and previews); nothing touches disk.
    ///   - url: A specific file to open instead of the app's store (used by migration tests).
    static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: DB.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(storeName, schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: CocktailMigrationPlan.self, configurations: configuration)
    }
}
