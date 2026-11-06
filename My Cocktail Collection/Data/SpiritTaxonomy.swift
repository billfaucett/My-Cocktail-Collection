//
//  SpiritTaxonomy.swift
//  My Cocktail Collection
//
//  The spirit taxonomy for the data model refactor: Family → Style → Bottle.
//  Families are fixed; styles belong to one family and can be added to. Bottles and
//  cocktails will link to a style. Not used by the app yet; see the refactor plan.
//

import Foundation

// MARK: - Families

/// The top level of the taxonomy. A fixed list, so filters, grouping and seed data stay consistent.
/// The raw value is what gets stored, so never rename a case's raw value.
enum SpiritFamily: String, CaseIterable, Identifiable, Codable {
    case whiskey
    case gin
    case rum
    case agave
    case brandy
    case vodka
    case liqueursAndAmari
    case vermouthAndFortified
    case bitters
    case wine
    case beerAndCider
    case mixersAndSyrups
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whiskey: return "Whiskey"
        case .gin: return "Gin"
        case .rum: return "Rum"
        case .agave: return "Agave"
        case .brandy: return "Brandy"
        case .vodka: return "Vodka"
        case .liqueursAndAmari: return "Liqueurs & Amari"
        case .vermouthAndFortified: return "Vermouth & Fortified"
        case .bitters: return "Bitters"
        case .wine: return "Wine"
        case .beerAndCider: return "Beer & Cider"
        case .mixersAndSyrups: return "Mixers & Syrups"
        case .other: return "Other"
        }
    }

    /// SF Symbol shown next to the family in lists and filters.
    var symbolName: String {
        switch self {
        case .whiskey: return "flame"
        case .gin: return "leaf"
        case .rum: return "sailboat"
        case .agave: return "sun.max"
        case .brandy: return "drop.halffull"
        case .vodka: return "snowflake"
        case .liqueursAndAmari: return "sparkles"
        case .vermouthAndFortified: return "seal"
        case .bitters: return "eyedropper"
        case .wine: return "wineglass"
        case .beerAndCider: return "mug"
        case .mixersAndSyrups: return "bubbles.and.sparkles"
        case .other: return "square.grid.2x2"
        }
    }

    /// Order in lists: spirits first, then modifiers, then wine, beer and mixers, with Other last.
    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

// MARK: - Built-in styles

/// A style that ships with the app. You can add your own styles alongside these.
struct BuiltInStyle: Hashable {
    let name: String
    let family: SpiritFamily
}

enum SpiritTaxonomy {
    /// Styles added to every collection, grouped by family in display order.
    static let builtInStyles: [BuiltInStyle] = [
        // Whiskey
        BuiltInStyle(name: "Bourbon", family: .whiskey),
        BuiltInStyle(name: "Rye", family: .whiskey),
        BuiltInStyle(name: "Scotch", family: .whiskey),
        BuiltInStyle(name: "Irish Whiskey", family: .whiskey),
        BuiltInStyle(name: "Japanese Whisky", family: .whiskey),
        // Gin
        BuiltInStyle(name: "London Dry", family: .gin),
        BuiltInStyle(name: "Old Tom", family: .gin),
        BuiltInStyle(name: "Contemporary Gin", family: .gin),
        // Rum: cocktails use the general style; the rest are for bottles
        BuiltInStyle(name: "Rum", family: .rum),
        BuiltInStyle(name: "White Rum", family: .rum),
        BuiltInStyle(name: "Aged Rum", family: .rum),
        BuiltInStyle(name: "Dark Rum", family: .rum),
        BuiltInStyle(name: "Rhum Agricole", family: .rum),
        // Agave
        BuiltInStyle(name: "Tequila Blanco", family: .agave),
        BuiltInStyle(name: "Tequila Reposado", family: .agave),
        BuiltInStyle(name: "Tequila Añejo", family: .agave),
        BuiltInStyle(name: "Mezcal", family: .agave),
        // Brandy: cocktails use the general style; the rest are for bottles
        BuiltInStyle(name: "Brandy", family: .brandy),
        BuiltInStyle(name: "Cognac", family: .brandy),
        BuiltInStyle(name: "Armagnac", family: .brandy),
        BuiltInStyle(name: "Pisco", family: .brandy),
        BuiltInStyle(name: "Calvados", family: .brandy),
        // Vodka
        BuiltInStyle(name: "Vodka", family: .vodka),
        BuiltInStyle(name: "Flavored Vodka", family: .vodka),
        // Liqueurs & Amari
        BuiltInStyle(name: "Orange Liqueur", family: .liqueursAndAmari),
        BuiltInStyle(name: "Coffee Liqueur", family: .liqueursAndAmari),
        BuiltInStyle(name: "Herbal Liqueur", family: .liqueursAndAmari),
        BuiltInStyle(name: "Aperitivo", family: .liqueursAndAmari),
        BuiltInStyle(name: "Amaro", family: .liqueursAndAmari),
        BuiltInStyle(name: "Cream Liqueur", family: .liqueursAndAmari),
        BuiltInStyle(name: "Fruit & Nut Liqueur", family: .liqueursAndAmari),
        // Vermouth & Fortified
        BuiltInStyle(name: "Sweet Vermouth", family: .vermouthAndFortified),
        BuiltInStyle(name: "Dry Vermouth", family: .vermouthAndFortified),
        BuiltInStyle(name: "Sherry", family: .vermouthAndFortified),
        BuiltInStyle(name: "Port", family: .vermouthAndFortified),
        // Bitters
        BuiltInStyle(name: "Aromatic Bitters", family: .bitters),
        BuiltInStyle(name: "Orange Bitters", family: .bitters),
        BuiltInStyle(name: "Other Bitters", family: .bitters),
        // Wine
        BuiltInStyle(name: "Red Wine", family: .wine),
        BuiltInStyle(name: "White Wine", family: .wine),
        BuiltInStyle(name: "Rosé", family: .wine),
        BuiltInStyle(name: "Sparkling Wine", family: .wine),
        BuiltInStyle(name: "Dessert Wine", family: .wine),
        // Beer & Cider
        BuiltInStyle(name: "Lager", family: .beerAndCider),
        BuiltInStyle(name: "Pale Ale & IPA", family: .beerAndCider),
        BuiltInStyle(name: "Stout & Porter", family: .beerAndCider),
        BuiltInStyle(name: "Wheat Beer", family: .beerAndCider),
        BuiltInStyle(name: "Sour Beer", family: .beerAndCider),
        BuiltInStyle(name: "Cider", family: .beerAndCider),
        // Mixers & Syrups
        BuiltInStyle(name: "Tonic & Soda", family: .mixersAndSyrups),
        BuiltInStyle(name: "Ginger Beer & Ale", family: .mixersAndSyrups),
        BuiltInStyle(name: "Bottled Juice", family: .mixersAndSyrups),
        BuiltInStyle(name: "Syrup", family: .mixersAndSyrups),
        BuiltInStyle(name: "Cream of Coconut", family: .mixersAndSyrups),
        // Other
        BuiltInStyle(name: "Aquavit", family: .other),
        BuiltInStyle(name: "Absinthe", family: .other),
        BuiltInStyle(name: "Sake", family: .other)
    ]

    /// The built-in styles in one family, in display order.
    static func builtInStyles(in family: SpiritFamily) -> [BuiltInStyle] {
        builtInStyles.filter { $0.family == family }
    }

    /// Finds a built-in style by name, ignoring case and surrounding spaces.
    static func builtInStyle(named name: String) -> BuiltInStyle? {
        let key = normalized(name)
        return builtInStyles.first { normalized($0.name) == key }
    }

    // MARK: - Mapping today's spirits

    /// Where a spirit from the current database belongs in the new taxonomy.
    struct Placement: Equatable {
        let family: SpiritFamily
        /// The style's name: a built-in style's name, or the spirit's own name for a new style.
        let styleName: String
        /// True when the spirit maps to a built-in style rather than becoming a new one.
        let isBuiltIn: Bool
    }

    /// The built-in spirits from earlier versions and the style each one becomes.
    static let legacySpiritStyles: [String: String] = [
        "bourbon": "Bourbon",
        "rye": "Rye",
        "scotch": "Scotch",
        "whiskey": "Irish Whiskey",
        "gin": "London Dry",
        "rum": "Rum",
        "tequila": "Tequila Blanco",
        "mezcal": "Mezcal",
        "brandy": "Brandy",
        "pisco": "Pisco",
        "vodka": "Vodka",
        "aperol": "Aperitivo",
        "aquavit": "Aquavit"
    ]

    /// Places a spirit from the current database, in this order:
    /// 1. A built-in spirit from earlier versions → its style (`legacySpiritStyles`).
    /// 2. A name that matches a built-in style → that style.
    /// 3. A name containing a telling word ("Japanese Whisky", "Ginger Liqueur") → that family, as a new style.
    /// 4. Otherwise its old type (Liqueur, Wine…) picks the family, as a new style; plain Liquor → Other.
    static func placement(forLegacySpirit name: String, type: SpiritType) -> Placement {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalized(trimmed)

        if let styleName = legacySpiritStyles[key], let style = builtInStyle(named: styleName) {
            return Placement(family: style.family, styleName: style.name, isBuiltIn: true)
        }
        if let style = builtInStyle(named: trimmed) {
            return Placement(family: style.family, styleName: style.name, isBuiltIn: true)
        }
        let matchedFamily = family(forName: key) ?? family(forLegacyType: type)
        return Placement(family: matchedFamily, styleName: trimmed, isBuiltIn: false)
    }

    /// Phrases checked before single words, so "Ginger Beer" is a mixer rather than a beer.
    private static let familyPhrases: [(phrase: String, family: SpiritFamily)] = [
        ("ginger beer", .mixersAndSyrups),
        ("ginger ale", .mixersAndSyrups),
        ("club soda", .mixersAndSyrups),
        ("cream of coconut", .mixersAndSyrups),
        ("simple syrup", .mixersAndSyrups)
    ]

    /// Whole words that point to a family. Matched as words, so "gin" doesn't match "ginger".
    private static let familyWords: [(family: SpiritFamily, words: Set<String>)] = [
        (.mixersAndSyrups, ["tonic", "soda", "syrup", "juice", "mixer", "grenadine", "orgeat"]),
        (.bitters, ["bitters"]),
        (.vermouthAndFortified, ["vermouth", "sherry", "port", "madeira", "lillet", "fortified"]),
        (.liqueursAndAmari, ["liqueur", "amaro", "amari", "aperitivo", "triple", "curaçao", "curacao", "chartreuse",
                             "campari", "aperol", "schnapps", "cordial", "crème", "creme", "maraschino"]),
        (.whiskey, ["whiskey", "whisky", "bourbon", "rye", "scotch"]),
        (.gin, ["gin", "genever"]),
        (.rum, ["rum", "rhum", "cachaça", "cachaca"]),
        (.agave, ["tequila", "mezcal", "sotol", "raicilla"]),
        (.brandy, ["brandy", "cognac", "armagnac", "pisco", "calvados", "grappa"]),
        (.vodka, ["vodka"]),
        (.wine, ["wine", "champagne", "prosecco", "cava"]),
        (.beerAndCider, ["beer", "ale", "lager", "ipa", "stout", "porter", "cider"]),
        (.other, ["aquavit", "akvavit", "absinthe", "sake"])
    ]

    private static func family(forName key: String) -> SpiritFamily? {
        if let match = familyPhrases.first(where: { key.contains($0.phrase) }) {
            return match.family
        }
        let words = Set(key.split { !$0.isLetter }.map(String.init))
        return familyWords.first { !$0.words.isDisjoint(with: words) }?.family
    }

    private static func family(forLegacyType type: SpiritType) -> SpiritFamily {
        switch type {
        case .liqueur: return .liqueursAndAmari
        case .wine: return .wine
        case .fortifiedWine: return .vermouthAndFortified
        case .beer, .cider: return .beerAndCider
        case .liquor, .sake, .mead: return .other
        }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
