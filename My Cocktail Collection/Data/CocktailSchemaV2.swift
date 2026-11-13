//
//  CocktailSchemaV2.swift
//  My Cocktail Collection
//
//  Data model version 2: adds each cocktail's template, one of the six root cocktails from
//  Cocktail Codex (Death & Co). Everything else is the same as version 1, which is kept so
//  existing databases can be migrated. Version 3 (CocktailSchemaV3.swift) is now current; this file keeps
//  version 2 for upgrades, along with the `CocktailTemplate` enum used by every version.
//

import Foundation
import SwiftData

// MARK: - Cocktail templates

/// The six root cocktails from Cocktail Codex. Every cocktail is a variation on one of them.
enum CocktailTemplate: String, CaseIterable, Identifiable, Codable {
    case oldFashioned
    case martini
    case daiquiri
    case sidecar
    case highball
    case flip

    var id: Self { self }

    var displayName: String {
        switch self {
        case .oldFashioned: return "Old Fashioned"
        case .martini: return "Martini"
        case .daiquiri: return "Daiquiri"
        case .sidecar: return "Sidecar"
        case .highball: return "Highball"
        case .flip: return "Flip"
        }
    }

    /// What the template is made of, e.g. "Spirit, sugar and bitters".
    var formula: String {
        switch self {
        case .oldFashioned: return "Spirit, sugar and bitters"
        case .martini: return "Spirit and aromatized wine"
        case .daiquiri: return "Spirit, citrus and sugar"
        case .sidecar: return "Spirit, citrus and liqueur"
        case .highball: return "Spirit and a sparkling mixer"
        case .flip: return "Spirit, egg or cream, and sugar"
        }
    }

    var symbolName: String {
        switch self {
        case .oldFashioned: return "cube"
        case .martini: return "wineglass"
        case .daiquiri: return "drop"
        case .sidecar: return "car.side"
        case .highball: return "bubbles.and.sparkles"
        case .flip: return "oval.portrait"
        }
    }
}

// MARK: - Schema version 2

enum CocktailSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SpiritStyle.self, Bottle.self, Cocktail.self, RecipeIngredient.self, Menu.self, MenuEntry.self, ImportRecord.self]
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
        /// 0 (not rated) to 10. Kept, but no longer shown or edited.
        var rating: Int = 0
        var isFavorite: Bool = false
        @Attribute(.externalStorage)
        var photo: Data?
        var dateAdded: Date = Date()
        /// Which of the six Cocktail Codex templates the recipe follows. Nil until it's set. (New in version 2.)
        var templateRaw: String?

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
}
