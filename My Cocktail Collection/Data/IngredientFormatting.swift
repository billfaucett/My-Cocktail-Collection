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
