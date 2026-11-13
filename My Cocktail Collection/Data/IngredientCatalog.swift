//
//  IngredientCatalog.swift
//  My Cocktail Collection
//
//  Pick-from-list ingredient entry, step 1: the list of ingredients to pick from.
//  A built-in list of common ingredients (each with its type and usual measure), merged with every
//  ingredient already in your recipes and the types of the bottles in My Bar. Plain Swift, so it's
//  fully testable; `load(context:)` reads the database.
//

import Foundation
import SwiftData

/// The sections of the ingredient list.
enum CatalogGroup: String, CaseIterable, Identifiable {
    case spirits, liqueursAndVermouth, bitters, juices, syrups, mixers, other, garnishes

    var id: Self { self }

    var displayName: String {
        switch self {
        case .spirits: return "Spirits"
        case .liqueursAndVermouth: return "Liqueurs & Vermouth"
        case .bitters: return "Bitters"
        case .juices: return "Juices"
        case .syrups: return "Syrups"
        case .mixers: return "Mixers & Wine"
        case .other: return "Other"
        case .garnishes: return "Garnishes"
        }
    }

    /// The measure an ingredient in this group usually takes.
    var usualUnit: IngredientUnit {
        switch self {
        case .spirits, .liqueursAndVermouth, .juices, .syrups, .other: return .part
        case .bitters: return .dash
        case .mixers: return .topUp
        case .garnishes: return .unspecified
        }
    }

    /// Where a type's ingredients belong, e.g. Bourbon → Spirits, Syrup → Syrups.
    static func group(forStyle styleName: String?, family: SpiritFamily?) -> CatalogGroup {
        switch styleName {
        case "Syrup": return .syrups
        case "Bottled Juice": return .juices
        case "Cream of Coconut": return .other
        default: break
        }
        switch family {
        case .whiskey, .gin, .rum, .agave, .brandy, .vodka, .other: return .spirits
        case .liqueursAndAmari, .vermouthAndFortified: return .liqueursAndVermouth
        case .bitters: return .bitters
        case .wine, .beerAndCider, .mixersAndSyrups: return .mixers
        case nil: return .other
        }
    }
}

/// One ingredient you can pick.
struct CatalogItem: Identifiable, Hashable {
    var name: String
    /// The type it links to (a built-in or your own), e.g. "Bourbon" or "Aperitivo".
    var styleName: String?
    var group: CatalogGroup
    /// How it's usually measured, e.g. dashes for bitters.
    var usualUnit: IngredientUnit
    /// The amount usually used in that measure, e.g. 2 (parts of bourbon). Nil for garnishes and top-ups.
    var usualAmount: Double?
    var isGarnish = false
    /// How many recipe rows use it.
    var useCount = 0
    /// Bottles in My Bar of this type, e.g. ["Buffalo Trace"] for Bourbon.
    var bottleBrands: [String] = []
    /// False for items that came from your recipes or bottles rather than the built-in list.
    var isBuiltIn = true

    var id: String { IngredientCatalog.key(name) }
}

/// An ingredient as used in a recipe, for building the catalog.
struct UsedIngredient {
    var name: String
    var styleName: String?
    var family: SpiritFamily?
    var unit: IngredientUnit
    var isGarnish = false
    var amount: Double?
    /// Which recipe it's in, so ingredients used together can be suggested together.
    var recipe: String?
}

/// A bottle in My Bar, for building the catalog.
struct OwnedBottle {
    var brand: String
    var styleName: String?
    var family: SpiritFamily?
}

struct IngredientCatalog {
    /// Every item: built-in, then from your recipes and bottles. Each name appears once.
    private(set) var items: [CatalogItem]
    /// How many recipes use each pair of ingredients, by key: pairs["bourbon"]["simple syrup"] = 2.
    private var pairs: [String: [String: Int]] = [:]

    init(used: [UsedIngredient] = [], bottles: [OwnedBottle] = []) {
        var items = Self.builtIn
        var index = Dictionary(items.enumerated().map { (Self.key($0.element.name), $0.offset) }, uniquingKeysWith: { first, _ in first })

        // Your recipes: count uses of known items, and add the rest.
        var unitsByKey: [String: [IngredientUnit: Int]] = [:]
        var garnishVotes: [String: Int] = [:]
        var amountsByKey: [String: [(unit: IngredientUnit, amount: Double)]] = [:]
        var keysByRecipe: [String: Set<String>] = [:]
        for ingredient in used {
            let name = ingredient.name.trimmingCharacters(in: .whitespaces)
            let key = Self.key(name)
            guard !key.isEmpty else { continue }
            if index[key] == nil {
                let group = ingredient.isGarnish ? .garnishes : CatalogGroup.group(forStyle: ingredient.styleName, family: ingredient.family)
                items.append(CatalogItem(name: name, styleName: ingredient.styleName, group: group, usualUnit: group.usualUnit,
                                         isGarnish: ingredient.isGarnish, isBuiltIn: false))
                index[key] = items.count - 1
            }
            items[index[key]!].useCount += 1
            unitsByKey[key, default: [:]][ingredient.unit, default: 0] += 1
            garnishVotes[key, default: 0] += ingredient.isGarnish ? 1 : -1
            if let amount = ingredient.amount {
                amountsByKey[key, default: []].append((ingredient.unit, amount))
            }
            if let recipe = ingredient.recipe {
                keysByRecipe[recipe, default: []].insert(key)
            }
        }
        // Items you added use the measure you use most.
        for (key, units) in unitsByKey {
            guard let position = index[key], !items[position].isBuiltIn,
                  let usual = units.max(by: { $0.value < $1.value })?.key else { continue }
            items[position].usualUnit = usual
            items[position].isGarnish = (garnishVotes[key] ?? 0) > 0
            if items[position].isGarnish { items[position].group = .garnishes }
        }

        // The amount you use most in each item's usual measure (ties go to the larger amount);
        // items you haven't measured yet get a sensible default for their group.
        for position in items.indices {
            let item = items[position]
            let amounts = (amountsByKey[item.id] ?? []).filter { $0.unit == item.usualUnit }.map(\.amount)
            let counts = Dictionary(amounts.map { ($0, 1) }, uniquingKeysWith: +)
            items[position].usualAmount = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }?.key
                ?? Self.defaultAmount(group: item.group, unit: item.usualUnit)
        }

        // Ingredients used together in the same recipe, for Goes With.
        var pairs: [String: [String: Int]] = [:]
        for keys in keysByRecipe.values {
            for first in keys {
                for second in keys where second != first {
                    pairs[first, default: [:]][second, default: 0] += 1
                }
            }
        }
        self.pairs = pairs

        // My Bar: show the bottles beside their type ("Bourbon: Buffalo Trace"), or beside the brand's own item
        // (a Campari bottle beside Campari). A type with no item yet gets one.
        for bottle in bottles {
            let brandKey = Self.key(bottle.brand)
            if let position = index[brandKey] {
                items[position].bottleBrands.append(bottle.brand)
                continue
            }
            guard let styleName = bottle.styleName else { continue }
            let styleKey = Self.key(styleName)
            if index[styleKey] == nil {
                let group = CatalogGroup.group(forStyle: styleName, family: bottle.family)
                items.append(CatalogItem(name: styleName, styleName: styleName, group: group, usualUnit: group.usualUnit, isBuiltIn: false))
                index[styleKey] = items.count - 1
            }
            items[index[styleKey]!].bottleBrands.append(bottle.brand)
        }
        // Types added from My Bar start with the default amount for their group.
        for position in items.indices where items[position].usualAmount == nil {
            items[position].usualAmount = Self.defaultAmount(group: items[position].group, unit: items[position].usualUnit)
        }
        self.items = items
    }

    /// Reads your recipes and My Bar from the database.
    static func load(context: ModelContext) throws -> IngredientCatalog {
        let used = try context.fetch(FetchDescriptor<DB.RecipeIngredient>()).filter { $0.cocktail?.library == nil }.map {
            UsedIngredient(name: $0.name, styleName: $0.style?.name, family: $0.style?.family, unit: $0.unit, isGarnish: $0.isGarnish,
                           amount: $0.amount, recipe: $0.cocktail?.id.uuidString)
        }
        let bottles = try context.fetch(FetchDescriptor<DB.Bottle>()).map {
            OwnedBottle(brand: $0.brand, styleName: $0.style?.name, family: $0.style?.family)
        }
        return IngredientCatalog(used: used, bottles: bottles)
    }

    // MARK: Sections

    /// The ingredients you use most, most used first.
    func mostUsed(limit: Int = 8) -> [CatalogItem] {
        items.filter { $0.useCount > 0 }
            .sorted { $0.useCount != $1.useCount ? $0.useCount > $1.useCount : Self.byName($0, $1) }
            .prefix(limit)
            .map { $0 }
    }

    /// Ingredients you have a bottle of, by name.
    var inMyBar: [CatalogItem] {
        items.filter { !$0.bottleBrands.isEmpty }.sorted(by: Self.byName)
    }

    /// One group's ingredients, by name.
    func items(in group: CatalogGroup) -> [CatalogItem] {
        items.filter { $0.group == group }.sorted(by: Self.byName)
    }

    func item(named name: String) -> CatalogItem? {
        let key = Self.key(name)
        return items.first { $0.id == key }
    }

    /// Ingredients your recipes use alongside the ones already picked, most often paired first.
    /// "Bourbon" → Simple Syrup, Angostura Bitters, Lemon Juice… Ingredients already picked are left out.
    func goesWith(_ picked: [String], limit: Int = 6) -> [CatalogItem] {
        let pickedKeys = Set(picked.map(Self.key))
        guard !pickedKeys.isEmpty else { return [] }
        var scores: [String: Int] = [:]
        for key in pickedKeys {
            for (other, count) in pairs[key] ?? [:] where !pickedKeys.contains(other) {
                scores[other, default: 0] += count
            }
        }
        return items
            .compactMap { item in scores[item.id].map { (item: item, score: $0) } }
            .sorted { first, second in
                if first.score != second.score { return first.score > second.score }
                if first.item.useCount != second.item.useCount { return first.item.useCount > second.item.useCount }
                return Self.byName(first.item, second.item)
            }
            .prefix(limit)
            .map(\.item)
    }

    /// A starting amount for an ingredient you haven't measured yet: 2 parts of a spirit, ¾ of a liqueur or juice,
    /// ½ of a syrup, 2 dashes of bitters. Garnishes and top-ups have no amount.
    static func defaultAmount(group: CatalogGroup, unit: IngredientUnit) -> Double? {
        switch unit {
        case .topUp, .unspecified: return nil
        case .dash: return 2
        case .drop: return 3
        case .barspoon, .piece, .slice, .sprig: return 1
        case .part:
            switch group {
            case .spirits: return 2
            case .liqueursAndVermouth, .juices: return 0.75
            case .syrups: return 0.5
            case .bitters, .mixers, .other, .garnishes: return 1
            }
        }
    }

    // MARK: Search

    /// Items matching what's typed, best first: the whole name, then names starting with it, then a word
    /// starting with it, then anywhere in the name, then a one-letter typo ("angostra" finds Angostura).
    func search(_ query: String) -> [CatalogItem] {
        let typed = Self.key(query)
        guard !typed.isEmpty else { return [] }
        let typedWords = typed.split(separator: " ").map(String.init)
        return items
            .compactMap { item -> (item: CatalogItem, score: Int)? in
                let name = item.id
                let nameWords = name.split(separator: " ").map(String.init)
                if name == typed { return (item, 0) }
                if name.hasPrefix(typed) { return (item, 1) }
                if typedWords.allSatisfy({ word in nameWords.contains { $0.hasPrefix(word) } }) { return (item, 2) }
                if name.contains(typed) { return (item, 3) }
                let forgiving = typedWords.allSatisfy { word in
                    word.count >= 4 && nameWords.contains { other in
                        LabelMatcher.editDistance(word, String(other.prefix(word.count))) <= 1
                            || LabelMatcher.editDistance(word, other) <= 1
                    }
                }
                return forgiving ? (item, 4) : nil
            }
            .sorted { first, second in
                if first.score != second.score { return first.score < second.score }
                if first.item.useCount != second.item.useCount { return first.item.useCount > second.item.useCount }
                return Self.byName(first.item, second.item)
            }
            .map(\.item)
    }

    /// Names to offer while typing an ingredient's name: the best search matches, leaving out the name
    /// exactly as typed (there's nothing to complete).
    func suggestions(for typed: String, limit: Int = 6) -> [CatalogItem] {
        let typedKey = Self.key(typed)
        guard !typedKey.isEmpty else { return [] }
        return Array(search(typed).filter { $0.id != typedKey }.prefix(limit))
    }

    // MARK: New items

    /// An item for a name that isn't in the list yet ("Add “Falernum”"), with its type and usual measure guessed.
    static func newItem(named name: String) -> CatalogItem {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameWords = Set(LabelMatcher.words(clean))
        let looksLikeBitters = nameWords.contains("bitters")
        var styleName = IngredientParser.styleName(forIngredient: clean)
        if looksLikeBitters && styleName == nil { styleName = "Other Bitters" }
        let family = styleName.flatMap { SpiritTaxonomy.builtInStyle(named: $0)?.family }
        let looksLikeGarnish = !looksLikeBitters
            && !nameWords.isDisjoint(with: ["peel", "twist", "wheel", "wedge", "sprig", "slice", "zest", "cherries", "olives"])
        let looksLikeJuice = nameWords.contains("juice")
        let group: CatalogGroup = looksLikeGarnish ? .garnishes
            : (looksLikeJuice && styleName == nil ? .juices : CatalogGroup.group(forStyle: styleName, family: family))
        return CatalogItem(name: clean, styleName: styleName, group: group, usualUnit: group.usualUnit,
                           usualAmount: defaultAmount(group: group, unit: group.usualUnit),
                           isGarnish: looksLikeGarnish, isBuiltIn: false)
    }

    // MARK: Helpers

    /// The key two names share when they're the same ingredient: lowercase, no accents or punctuation,
    /// and without "fresh" ("Fresh Lime Juice" = "lime juice").
    static func key(_ name: String) -> String {
        LabelMatcher.words(name)
            .filter { !["fresh", "freshly", "squeezed"].contains($0) }
            .joined(separator: " ")
    }

    private static func byName(_ first: CatalogItem, _ second: CatalogItem) -> Bool {
        first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }

    // MARK: Built-in list

    private static func item(_ name: String, _ group: CatalogGroup, _ style: String? = nil, unit: IngredientUnit? = nil) -> CatalogItem {
        CatalogItem(name: name, styleName: style, group: group, usualUnit: unit ?? group.usualUnit, isGarnish: group == .garnishes)
    }

    /// Common cocktail ingredients, each linked to its type where it has one.
    static let builtIn: [CatalogItem] = [
        // Spirits
        item("Bourbon", .spirits, "Bourbon"), item("Rye Whiskey", .spirits, "Rye"), item("Scotch", .spirits, "Scotch"),
        item("Irish Whiskey", .spirits, "Irish Whiskey"), item("Japanese Whisky", .spirits, "Japanese Whisky"),
        item("Gin", .spirits, "London Dry"), item("Old Tom Gin", .spirits, "Old Tom"),
        item("Rum", .spirits, "Rum"), item("White Rum", .spirits, "White Rum"), item("Aged Rum", .spirits, "Aged Rum"),
        item("Dark Rum", .spirits, "Dark Rum"), item("Rhum Agricole", .spirits, "Rhum Agricole"),
        item("Tequila Blanco", .spirits, "Tequila Blanco"), item("Tequila Reposado", .spirits, "Tequila Reposado"),
        item("Tequila Añejo", .spirits, "Tequila Añejo"), item("Mezcal", .spirits, "Mezcal"),
        item("Brandy", .spirits, "Brandy"), item("Cognac", .spirits, "Cognac"), item("Pisco", .spirits, "Pisco"),
        item("Calvados", .spirits, "Calvados"), item("Vodka", .spirits, "Vodka"),
        item("Absinthe", .spirits, "Absinthe", unit: .barspoon),
        // Liqueurs & vermouth
        item("Sweet Vermouth", .liqueursAndVermouth, "Sweet Vermouth"), item("Dry Vermouth", .liqueursAndVermouth, "Dry Vermouth"),
        item("Campari", .liqueursAndVermouth, "Aperitivo"), item("Aperol", .liqueursAndVermouth, "Aperitivo"),
        item("Cointreau", .liqueursAndVermouth, "Orange Liqueur"), item("Triple Sec", .liqueursAndVermouth, "Orange Liqueur"),
        item("Grand Marnier", .liqueursAndVermouth, "Orange Liqueur"), item("Orange Curaçao", .liqueursAndVermouth, "Orange Liqueur"),
        item("Maraschino Liqueur", .liqueursAndVermouth, "Fruit & Nut Liqueur"),
        item("Green Chartreuse", .liqueursAndVermouth, "Herbal Liqueur"), item("Yellow Chartreuse", .liqueursAndVermouth, "Herbal Liqueur"),
        item("Bénédictine", .liqueursAndVermouth, "Herbal Liqueur"), item("Crème de Violette", .liqueursAndVermouth, "Herbal Liqueur"),
        item("Crème de Cassis", .liqueursAndVermouth, "Fruit & Nut Liqueur"),
        item("Crème de Cacao", .liqueursAndVermouth, "Fruit & Nut Liqueur"),
        item("Amaretto", .liqueursAndVermouth, "Fruit & Nut Liqueur"), item("St-Germain", .liqueursAndVermouth, "Fruit & Nut Liqueur"),
        item("Coffee Liqueur", .liqueursAndVermouth, "Coffee Liqueur"), item("Irish Cream", .liqueursAndVermouth, "Cream Liqueur"),
        item("Amaro", .liqueursAndVermouth, "Amaro"), item("Fernet-Branca", .liqueursAndVermouth, "Amaro"),
        item("Lillet Blanc", .liqueursAndVermouth), item("Sherry", .liqueursAndVermouth, "Sherry"),
        item("Port", .liqueursAndVermouth, "Port"),
        // Bitters
        item("Angostura Bitters", .bitters, "Aromatic Bitters"), item("Peychaud's Bitters", .bitters, "Aromatic Bitters"),
        item("Orange Bitters", .bitters, "Orange Bitters"), item("Chocolate Bitters", .bitters, "Other Bitters"),
        // Juices (fresh, so no bottle type)
        item("Lime Juice", .juices), item("Lemon Juice", .juices), item("Orange Juice", .juices),
        item("Grapefruit Juice", .juices), item("Pineapple Juice", .juices, "Bottled Juice"),
        item("Cranberry Juice", .juices, "Bottled Juice"), item("Tomato Juice", .juices, "Bottled Juice"),
        // Syrups
        item("Simple Syrup", .syrups, "Syrup"), item("Rich Simple Syrup", .syrups, "Syrup"),
        item("Demerara Syrup", .syrups, "Syrup"), item("Honey Syrup", .syrups, "Syrup"), item("Agave Syrup", .syrups, "Syrup"),
        item("Maple Syrup", .syrups, "Syrup"), item("Grenadine", .syrups, "Syrup"), item("Orgeat", .syrups, "Syrup"),
        item("Falernum", .syrups, "Syrup"), item("Ginger Syrup", .syrups, "Syrup"), item("Cinnamon Syrup", .syrups, "Syrup"),
        // Mixers & wine
        item("Club Soda", .mixers, "Tonic & Soda"), item("Tonic Water", .mixers, "Tonic & Soda"),
        item("Ginger Beer", .mixers, "Ginger Beer & Ale"), item("Ginger Ale", .mixers, "Ginger Beer & Ale"),
        item("Grapefruit Soda", .mixers, "Tonic & Soda"), item("Cola", .mixers),
        item("Champagne", .mixers, "Sparkling Wine"), item("Prosecco", .mixers, "Sparkling Wine"),
        item("Sparkling Wine", .mixers, "Sparkling Wine"),
        // Other
        item("Egg White", .other, unit: .piece), item("Heavy Cream", .other), item("Cream of Coconut", .other, "Cream of Coconut"),
        item("Espresso", .other), item("Mint Leaves", .other, unit: .piece), item("Sugar Cube", .other, unit: .piece),
        item("Salt", .other, unit: .unspecified), item("Hot Sauce", .other, unit: .dash),
        item("Worcestershire Sauce", .other, unit: .dash),
        // Garnishes
        item("Orange Peel", .garnishes), item("Lemon Peel", .garnishes), item("Lemon Twist", .garnishes),
        item("Orange Twist", .garnishes), item("Lime Wheel", .garnishes), item("Lime Wedge", .garnishes),
        item("Lemon Wheel", .garnishes), item("Orange Slice", .garnishes), item("Cocktail Cherry", .garnishes),
        item("Brandied Cherry", .garnishes), item("Olive", .garnishes), item("Mint Sprig", .garnishes),
        item("Grated Nutmeg", .garnishes), item("Cucumber Slice", .garnishes), item("Coffee Beans", .garnishes),
    ]
}
