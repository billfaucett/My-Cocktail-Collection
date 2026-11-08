//
//  IngredientParser.swift
//  My Cocktail Collection
//
//  Data model refactor, step 2: turns recipe ingredient text into structured rows.
//  Volumes become parts ("2 oz" and "2pt" are both 2 parts); dashes, drops, barspoons
//  and garnishes stay as counts. Not used by the app yet; the importer will use it.
//

import Foundation

// MARK: - Results

/// How an ingredient is measured. Volumes are always parts.
/// The raw value is what gets stored, so never rename a raw value.
enum IngredientUnit: String, CaseIterable, Codable {
    case part
    case dash
    case drop
    case barspoon
    case piece
    case slice
    case sprig
    case topUp
    case unspecified = "none"
}

/// One ingredient line, read into its parts.
struct ParsedIngredient: Equatable {
    var amount: Double?
    /// The top of a range, e.g. 3 in "2–3 dashes".
    var amountMax: Double?
    var unit: IngredientUnit
    var name: String
    /// Anything else the line said, e.g. "for the rim" or "equal parts honey and warm water".
    var note: String?
    var isGarnish = false
    var isOptional = false
    /// The built-in style this ingredient matches, e.g. "Sweet Vermouth". Nil when there's no match.
    var styleName: String?
    /// True when the parser wasn't sure, so the recipe should be checked by a person.
    var needsReview = false
    /// The line exactly as written.
    var original: String
}

/// A recipe's ingredients, read into rows.
struct ParsedRecipe {
    let ingredients: [ParsedIngredient]

    /// True when any line should be checked by a person.
    var needsReview: Bool { ingredients.contains(where: \.needsReview) }
}

// MARK: - Parser

enum IngredientParser {

    /// Reads a recipe's ingredient text. One ingredient per line, or older comma-separated recipes.
    static func parse(_ text: String) -> ParsedRecipe {
        let isOnePerLine = text.contains("\n")
        var pieces = (isOnePerLine ? text.components(separatedBy: .newlines) : text.components(separatedBy: ","))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // In comma-separated text, "…, to garnish" or "…, for the rim" belongs to the line before it.
        if !isOnePerLine {
            var merged: [String] = []
            for piece in pieces {
                let lower = piece.lowercased()
                if let last = merged.last, lower.hasPrefix("to ") || lower.hasPrefix("for ") {
                    merged[merged.count - 1] = last + ", " + piece
                } else {
                    merged.append(piece)
                }
            }
            pieces = merged
        }
        return ParsedRecipe(ingredients: pieces.map(parseLine))
    }

    /// Reads one ingredient line, such as "2½ oz Gin", "2–3 dashes Angostura Bitters" or "Club soda, to top".
    static func parseLine(_ line: String) -> ParsedIngredient {
        let original = line.trimmingCharacters(in: .whitespaces)
        var working = original
        var isOptional = false
        var notes: [String] = []

        // "(optional)", "(if desired)" or a leading "Optional"
        for marker in ["(optional)", "(if desired)"] {
            if let range = working.range(of: marker, options: .caseInsensitive) {
                working.removeSubrange(range)
                isOptional = true
            }
        }
        if working.lowercased().hasPrefix("optional ") {
            working = String(working.dropFirst("optional ".count))
            isOptional = true
        }

        // Everything after the first comma is a note: "Orange peel, to garnish"
        var head = working
        if let comma = working.firstIndex(of: ",") {
            head = String(working[..<comma])
            let note = working[working.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            if !note.isEmpty {
                notes.append(note)
            }
        }

        // A bracketed remark is a note too: "Honey Syrup (equal parts honey and warm water)"
        if let open = head.firstIndex(of: "("), let close = head[open...].firstIndex(of: ")") {
            let inside = head[head.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !inside.isEmpty {
                notes.append(inside)
            }
            head.removeSubrange(open...close)
        }
        head = head.trimmingCharacters(in: .whitespaces)

        // "Top with ginger beer" or "Top up with soda" is a top-up
        var isTopUp = false
        for prefix in ["top up with ", "top with "] where head.lowercased().hasPrefix(prefix) {
            head = String(head.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            isTopUp = true
            break
        }

        var ingredient = ParsedIngredient(unit: isTopUp ? .topUp : .unspecified, name: head, isOptional: isOptional, original: original)

        // Amount, range and unit at the start of the line
        let chars = Array(head)
        var i = 0
        if var value = readNumber(chars, &i) {
            var maxValue: Double?
            skipSpaces(chars, &i)
            if i < chars.count, "-–—".contains(chars[i]) {
                var j = i + 1
                skipSpaces(chars, &j)
                if let upper = readNumber(chars, &j) {
                    maxValue = upper
                    i = j
                    skipSpaces(chars, &i)
                }
            }

            var j = i
            var word = ""
            while j < chars.count, chars[j].isLetter {
                word.append(chars[j])
                j += 1
            }
            if !word.isEmpty, j < chars.count, chars[j] == "." {
                j += 1 // "oz."
            }

            if let measure = unitWords[word.lowercased()] {
                ingredient.unit = measure.unit
                value *= measure.factor
                maxValue = maxValue.map { $0 * measure.factor }
                if measure.isMetric {
                    ingredient.needsReview = true // converted from ml or cl; worth a look
                }
                i = j
                skipSpaces(chars, &i)
                if startsWithWord(chars, at: i, "of") {
                    i += 2
                    skipSpaces(chars, &i)
                }
            } else {
                ingredient.unit = .piece // a count, e.g. "1 Egg White" or "8–10 Mint Leaves"
            }
            ingredient.amount = value
            ingredient.amountMax = maxValue
            ingredient.name = String(chars[i...]).trimmingCharacters(in: .whitespaces)
        } else if let first = chars.first, isDigit(first) || first == "." {
            ingredient.needsReview = true // looks like an amount, but couldn't be read
        }

        // Notes that set a flag rather than staying as text
        var remaining: [String] = []
        for note in notes {
            let lower = note.lowercased()
            if lower.contains("garnish") {
                ingredient.isGarnish = true
            } else if lower.hasPrefix("to top") {
                if ingredient.amount == nil {
                    ingredient.unit = .topUp
                }
            } else {
                remaining.append(note)
            }
        }
        ingredient.note = remaining.isEmpty ? nil : remaining.joined(separator: "; ")

        // Older recipes list garnishes without saying so: "Orange Peel", "Olive"
        if ingredient.amount == nil, notes.isEmpty, !Set(words(ingredient.name)).isDisjoint(with: garnishWords) {
            ingredient.isGarnish = true
        }
        if ingredient.isGarnish, ingredient.unit == .unspecified {
            ingredient.unit = .piece
        }

        ingredient.name = ingredient.name.trimmingCharacters(in: CharacterSet(charactersIn: " .;:"))
        if ingredient.name.isEmpty || ingredient.name.contains(where: isDigit) || original.count > 80 {
            ingredient.needsReview = true
        }

        // Link spirits, liqueurs, bitters and mixers to a style. Garnishes and counted items stay unlinked,
        // so "3–4 bourbon soaked cherries" isn't mistaken for bourbon.
        if !ingredient.isGarnish, ingredient.unit != .piece {
            ingredient.styleName = styleName(forIngredient: ingredient.name)
        }
        return ingredient
    }

    // MARK: Styles

    /// Ingredient names that point to a built-in style, most specific first. Matched as whole words,
    /// so "gin" never matches "ginger".
    static let styleAliases: [(alias: String, style: String)] = [
        ("sweet vermouth", "Sweet Vermouth"), ("dry vermouth", "Dry Vermouth"),
        ("rye", "Rye"), ("bourbon", "Bourbon"), ("irish whiskey", "Irish Whiskey"),
        ("japanese whisky", "Japanese Whisky"), ("scotch", "Scotch"),
        ("london dry", "London Dry"), ("old tom", "Old Tom"), ("gin", "London Dry"),
        ("white rum", "White Rum"), ("light rum", "White Rum"), ("aged rum", "Aged Rum"),
        ("dark rum", "Dark Rum"), ("rhum agricole", "Rhum Agricole"), ("rum", "Rum"),
        ("tequila reposado", "Tequila Reposado"), ("tequila añejo", "Tequila Añejo"),
        ("tequila anejo", "Tequila Añejo"), ("tequila", "Tequila Blanco"), ("mezcal", "Mezcal"),
        ("cognac", "Cognac"), ("armagnac", "Armagnac"), ("pisco", "Pisco"),
        ("calvados", "Calvados"), ("brandy", "Brandy"),
        ("citrus vodka", "Flavored Vodka"), ("flavored vodka", "Flavored Vodka"), ("vodka", "Vodka"),
        ("triple sec", "Orange Liqueur"), ("cointreau", "Orange Liqueur"), ("curaçao", "Orange Liqueur"),
        ("curacao", "Orange Liqueur"), ("grand marnier", "Orange Liqueur"),
        ("coffee liqueur", "Coffee Liqueur"), ("kahlúa", "Coffee Liqueur"), ("kahlua", "Coffee Liqueur"),
        ("chartreuse", "Herbal Liqueur"), ("bénédictine", "Herbal Liqueur"), ("benedictine", "Herbal Liqueur"),
        ("crème de violette", "Herbal Liqueur"), ("creme de violette", "Herbal Liqueur"),
        ("maraschino", "Fruit & Nut Liqueur"), ("crème de cassis", "Fruit & Nut Liqueur"),
        ("creme de cassis", "Fruit & Nut Liqueur"), ("crème de cacao", "Fruit & Nut Liqueur"),
        ("creme de cacao", "Fruit & Nut Liqueur"),
        ("campari", "Aperitivo"), ("aperol", "Aperitivo"), ("amaro", "Amaro"),
        ("orange bitters", "Orange Bitters"), ("angostura", "Aromatic Bitters"), ("peychaud", "Aromatic Bitters"),
        ("champagne", "Sparkling Wine"), ("prosecco", "Sparkling Wine"), ("sparkling wine", "Sparkling Wine"),
        ("ginger beer", "Ginger Beer & Ale"), ("ginger ale", "Ginger Beer & Ale"),
        ("club soda", "Tonic & Soda"), ("soda water", "Tonic & Soda"), ("tonic", "Tonic & Soda"),
        ("grapefruit soda", "Tonic & Soda"), ("topo chico", "Tonic & Soda"),
        ("cranberry juice", "Bottled Juice"), ("pineapple juice", "Bottled Juice"), ("tomato juice", "Bottled Juice"),
        ("cream of coconut", "Cream of Coconut"),
        ("syrup", "Syrup"), ("orgeat", "Syrup"), ("grenadine", "Syrup"), ("agave nectar", "Syrup"),
        ("absinthe", "Absinthe"), ("aquavit", "Aquavit")
    ]

    /// The built-in style an ingredient name points to, if any.
    static func styleName(forIngredient name: String) -> String? {
        let nameWords = words(name)
        return styleAliases.first { containsPhrase(nameWords, words($0.alias)) }?.style
    }

    // MARK: Helpers

    private static let unitWords: [String: (unit: IngredientUnit, factor: Double, isMetric: Bool)] = [
        "oz": (.part, 1, false), "ounce": (.part, 1, false), "ounces": (.part, 1, false),
        "pt": (.part, 1, false), "pts": (.part, 1, false), "part": (.part, 1, false), "parts": (.part, 1, false),
        "ml": (.part, 1.0 / 30, true), "cl": (.part, 1.0 / 3, true),
        "tbsp": (.part, 0.5, false), "tablespoon": (.part, 0.5, false), "tablespoons": (.part, 0.5, false),
        "tsp": (.barspoon, 1, false), "teaspoon": (.barspoon, 1, false), "teaspoons": (.barspoon, 1, false),
        "barspoon": (.barspoon, 1, false), "barspoons": (.barspoon, 1, false), "bsp": (.barspoon, 1, false),
        "dash": (.dash, 1, false), "dashes": (.dash, 1, false),
        "drop": (.drop, 1, false), "drops": (.drop, 1, false),
        "sprig": (.sprig, 1, false), "sprigs": (.sprig, 1, false),
        "slice": (.slice, 1, false), "slices": (.slice, 1, false)
    ]

    private static let garnishWords: Set<String> = ["peel", "twist", "wheel", "wedge", "olive", "olives", "cherry", "cherries", "sprig"]

    private static let unicodeFractions: [Character: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125
    ]

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    private static func containsPhrase(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= words.count else { return false }
        for start in 0...(words.count - phrase.count) where Array(words[start..<start + phrase.count]) == phrase {
            return true
        }
        return false
    }

    private static func skipSpaces(_ chars: [Character], _ i: inout Int) {
        while i < chars.count, chars[i] == " " {
            i += 1
        }
    }

    private static func startsWithWord(_ chars: [Character], at i: Int, _ word: String) -> Bool {
        let letters = Array(word)
        guard i + letters.count <= chars.count else { return false }
        let candidate = String(chars[i..<i + letters.count]).lowercased()
        let endsThere = i + letters.count == chars.count || chars[i + letters.count] == " "
        return candidate == word && endsThere
    }

    private static func readInteger(_ chars: [Character], _ i: inout Int) -> Int? {
        var j = i
        var digits = ""
        while j < chars.count, isDigit(chars[j]) {
            digits.append(chars[j])
            j += 1
        }
        guard let value = Int(digits) else { return nil }
        i = j
        return value
    }

    /// Reads "2", "2.5", ".5", "½", "2½", "2 ½", "1/2" or "1 1/2" starting at `i`.
    private static func readNumber(_ chars: [Character], _ i: inout Int) -> Double? {
        var j = i
        var text = ""
        while j < chars.count, isDigit(chars[j]) || chars[j] == "." {
            text.append(chars[j])
            j += 1
        }
        var value: Double?
        if !text.isEmpty {
            guard let number = Double(text.hasPrefix(".") ? "0" + text : text) else { return nil }
            value = number
        }

        if j < chars.count, let fraction = unicodeFractions[chars[j]] {
            value = (value ?? 0) + fraction
            j += 1
        } else if let whole = value, !text.contains(".") {
            if j < chars.count, chars[j] == "/" {
                var k = j + 1
                if let denominator = readInteger(chars, &k), denominator > 0 {
                    value = whole / Double(denominator)
                    j = k
                }
            } else if j + 1 < chars.count, chars[j] == " " {
                if let fraction = unicodeFractions[chars[j + 1]] {
                    value = whole + fraction
                    j += 2
                } else {
                    var k = j + 1
                    if let numerator = readInteger(chars, &k), k < chars.count, chars[k] == "/" {
                        var m = k + 1
                        if let denominator = readInteger(chars, &m), denominator > 0 {
                            value = whole + Double(numerator) / Double(denominator)
                            j = m
                        }
                    }
                }
            }
        }

        guard let result = value else { return nil }
        i = j
        return result
    }
}
