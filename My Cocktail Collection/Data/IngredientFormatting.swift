//
//  IngredientFormatting.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 5: shows ingredient rows as text, in parts, with fractions.
//  "2 parts Gin", "¾ part Lime Juice", "2–3 dashes Angostura Bitters", "Club soda, to top".
//  The text reads back through IngredientParser to the same row, so it can be edited as text.
//

import Foundation

enum IngredientFormatter {
    private static let fractions: [(value: Double, glyph: String)] = [
        (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")
    ]

    /// An amount with fraction glyphs: 2 → "2", 2.5 → "2½", 0.75 → "¾". Other values get up to two decimals.
    static func amount(_ value: Double) -> String {
        var whole = value.rounded(.down)
        var remainder = value - whole
        if remainder > 0.99 {
            whole += 1
            remainder = 0
        }
        let wholeText = whole > 0 ? String(Int(whole)) : ""
        if remainder < 0.01 {
            return whole > 0 ? wholeText : "0"
        }
        if let match = fractions.first(where: { abs($0.value - remainder) < 0.01 }) {
            return wholeText + match.glyph
        }
        var decimal = String(format: "%.2f", value)
        while decimal.hasSuffix("0") { decimal.removeLast() }
        if decimal.hasSuffix(".") { decimal.removeLast() }
        return decimal
    }

    /// One ingredient as a line of text, e.g. "1½ parts Bourbon" or "Orange peel, to garnish".
    static func line(amount: Double?, amountMax: Double?, unit: IngredientUnit, name: String,
                     note: String?, isGarnish: Bool, isOptional: Bool) -> String {
        var text: String
        if unit == .topUp {
            text = name + ", to top"
        } else {
            var parts: [String] = []
            if let amount {
                parts.append(amountMax.map { "\(Self.amount(amount))–\(Self.amount($0))" } ?? Self.amount(amount))
            }
            if let word = unitWord(unit, for: amountMax ?? amount ?? 1) {
                parts.append(word)
            }
            parts.append(name)
            text = parts.joined(separator: " ")
        }
        if let note, !note.isEmpty {
            text += ", " + note
        }
        if isGarnish {
            text += ", to garnish"
        }
        if isOptional {
            text += " (optional)"
        }
        return text
    }

    /// Several rows as text, one per line, in recipe order.
    static func text(for ingredients: [V1.RecipeIngredient]) -> String {
        ingredients.map(\.displayText).joined(separator: "\n")
    }

    private static func unitWord(_ unit: IngredientUnit, for value: Double) -> String? {
        let plural = value > 1
        switch unit {
        case .part: return plural ? "parts" : "part"
        case .dash: return plural ? "dashes" : "dash"
        case .drop: return plural ? "drops" : "drop"
        case .barspoon: return plural ? "barspoons" : "barspoon"
        case .slice: return plural ? "slices" : "slice"
        case .sprig: return plural ? "sprigs" : "sprig"
        case .piece, .topUp, .unspecified: return nil
        }
    }
}

extension CocktailSchemaV1.RecipeIngredient {
    /// This ingredient as a line of text, in parts.
    var displayText: String {
        IngredientFormatter.line(amount: amount, amountMax: amountMax, unit: unit, name: name,
                                 note: note, isGarnish: isGarnish, isOptional: isOptional)
    }
}

extension ParsedIngredient {
    /// This ingredient as a line of text, in parts.
    var displayText: String {
        IngredientFormatter.line(amount: amount, amountMax: amountMax, unit: unit, name: name,
                                 note: note, isGarnish: isGarnish, isOptional: isOptional)
    }
}

// MARK: - Part size

/// How big a part is, for showing recipes converted to ounces or millilitres (data model refactor, phase 6).
/// Recipes are always stored in parts; this only changes what the recipe screen shows beside them.
enum PartSize: String, CaseIterable, Identifiable {
    case off
    case oneOunce = "1oz"
    case oneAndAHalfOunces = "1.5oz"
    case twoOunces = "2oz"
    case twentyFiveMillilitres = "25ml"
    case thirtyMillilitres = "30ml"
    case fortyFiveMillilitres = "45ml"
    case fiftyMillilitres = "50ml"

    /// Where the setting is saved, for `@AppStorage`.
    static let storageKey = "PartSize"

    var id: Self { self }

    /// Ounces or millilitres in one part, or nil when converting is off.
    var size: (amount: Double, unit: String)? {
        switch self {
        case .off: return nil
        case .oneOunce: return (1, "oz")
        case .oneAndAHalfOunces: return (1.5, "oz")
        case .twoOunces: return (2, "oz")
        case .twentyFiveMillilitres: return (25, "ml")
        case .thirtyMillilitres: return (30, "ml")
        case .fortyFiveMillilitres: return (45, "ml")
        case .fiftyMillilitres: return (50, "ml")
        }
    }

    /// "1 part = 1½ oz", or "Parts only" when off.
    var displayName: String {
        guard let size else { return "Parts only" }
        return "1 part = \(Self.format(size.amount, unit: size.unit))"
    }

    /// An amount in parts, converted: 2 parts at 1½ oz → "3 oz"; a range → "1–1½ oz".
    /// Nil when converting is off or there's no amount.
    func converted(amount: Double?, amountMax: Double? = nil) -> String? {
        guard let size, let amount else { return nil }
        let low = Self.rounded(amount * size.amount, unit: size.unit)
        guard let amountMax else { return Self.format(low, unit: size.unit) }
        let high = Self.rounded(amountMax * size.amount, unit: size.unit)
        return "\(Self.number(low, unit: size.unit))–\(Self.format(high, unit: size.unit))"
    }

    /// The converted amount for an ingredient measured in parts. Dashes, garnishes and the like stay as they are.
    func converted(_ ingredient: V1.RecipeIngredient) -> String? {
        guard ingredient.unit == .part else { return nil }
        return converted(amount: ingredient.amount, amountMax: ingredient.amountMax)
    }

    /// Ounces to the nearest eighth (thirds are kept, so ⅓ part of 1 oz shows as ⅓ oz);
    /// millilitres to the nearest 5 from 20 ml up, otherwise to the nearest whole.
    private static func rounded(_ value: Double, unit: String) -> Double {
        if unit == "ml" {
            return value >= 20 ? (value / 5).rounded() * 5 : value.rounded()
        }
        let thirds = value * 3
        if abs(thirds - thirds.rounded()) < 0.01 { return thirds.rounded() / 3 }
        return (value * 8).rounded() / 8
    }

    private static func number(_ value: Double, unit: String) -> String {
        unit == "ml" ? String(Int(value.rounded())) : IngredientFormatter.amount(value)
    }

    private static func format(_ value: Double, unit: String) -> String {
        "\(number(value, unit: unit)) \(unit)"
    }
}
