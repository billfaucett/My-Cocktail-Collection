//
//  LabelMatcher.swift
//  My Cocktail Collection
//
//  Label scanning, step 1: turns the text read from a bottle's label into a suggested brand,
//  type and notes, and finds a bottle already in My Bar with the same brand.
//  Plain Swift with no camera or Vision code, so every rule can be unit tested.
//

import Foundation

/// One line of text read from a label, with where it sat on the photo.
struct LabelLine: Equatable {
    var text: String
    /// Height of the text as a fraction of the photo's height (bigger text = bigger number).
    var height: Double
    /// Distance from the top of the photo, 0 (top) to 1 (bottom).
    var top: Double

    init(_ text: String, height: Double, top: Double = 0.5) {
        self.text = text
        self.height = height
        self.top = top
    }
}

/// What the label suggests for a new bottle. Every field can be wrong, so the form shows them for checking.
struct LabelSuggestion: Equatable {
    /// The most likely brand, tidied up (e.g. "Buffalo Trace").
    var brand: String?
    /// Other lines that could be the brand, for one-tap correction.
    var brandAlternatives: [String] = []
    /// A built-in type name (e.g. "Bourbon"), or nil when the label didn't say.
    var styleName: String?
    /// The family the label points to, even when the exact type is unclear (e.g. Whiskey).
    var family: SpiritFamily?
    var proof: String?
    var abv: String?
    var age: String?
    var size: String?

    /// Proof, ABV, age and size for the Notes field, e.g. "90 proof · 45% ABV · 8 years old · 750 ml".
    var notes: String {
        [proof.map { "\($0) proof" }, abv.map { "\($0)% ABV" }, age.map { "\($0) years old" }, size]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// True when nothing useful could be read.
    var isEmpty: Bool { brand == nil && styleName == nil && family == nil && notes.isEmpty }
}

enum LabelMatcher {
    /// Reads label lines into a suggestion for a new bottle.
    static func suggest(from lines: [LabelLine]) -> LabelSuggestion {
        let ordered = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.top < $1.top }
        var suggestion = LabelSuggestion()
        let type = matchType(ordered)
        suggestion.family = type.family
        suggestion.styleName = type.style
        let brands = brandCandidates(ordered)
        suggestion.brand = brands.first
        suggestion.brandAlternatives = Array(brands.dropFirst().prefix(2))
        readDetails(ordered.map(\.text).joined(separator: "\n"), into: &suggestion)
        return suggestion
    }

    // MARK: - Type

    private enum Scope { case window, label }

    /// One way of recognising a type. Matches when any phrase appears as whole words, the required words
    /// appear (on the same or next line, or anywhere for `.label`), and no excluded word is on the label.
    private struct Rule {
        let phrases: [[String]]
        let style: String?
        let requires: [[String]]
        let scope: Scope
        let excludes: [[String]]

        init(_ phrases: [String], _ style: String?, requires: [String] = [], scope: Scope = .window, excludes: [String] = []) {
            self.phrases = phrases.map(LabelMatcher.words)
            self.style = style
            self.requires = requires.map(LabelMatcher.words)
            self.scope = scope
            self.excludes = excludes.map(LabelMatcher.words)
        }
    }

    /// Rules per family, most specific first. Brands whose labels don't name a type come first.
    private static let rules: [(family: SpiritFamily, rules: [Rule])] = [
        (.liqueursAndAmari, [
            Rule(["campari", "aperol", "aperitivo", "aperitif"], "Aperitivo"),
            Rule(["cointreau", "grand marnier", "triple sec", "curacao", "orange liqueur"], "Orange Liqueur"),
            Rule(["kahlua", "tia maria", "coffee liqueur", "espresso liqueur"], "Coffee Liqueur"),
            Rule(["baileys", "cream liqueur"], "Cream Liqueur"),
            Rule(["chartreuse", "benedictine", "drambuie", "galliano", "strega", "jagermeister", "herbal liqueur"], "Herbal Liqueur"),
            Rule(["fernet", "cynar", "montenegro", "averna", "nonino", "amaro", "amari"], "Amaro"),
            Rule(["st germain", "luxardo", "maraschino", "disaronno", "amaretto", "frangelico", "chambord",
                  "cherry heering", "creme de"], "Fruit & Nut Liqueur"),
            Rule(["liqueur", "liquore", "liqueure"], nil),
        ]),
        (.bitters, [
            Rule(["orange bitters"], "Orange Bitters"),
            Rule(["angostura", "peychaud", "peychauds", "aromatic bitters"], "Aromatic Bitters"),
            Rule(["bitters"], "Other Bitters"),
        ]),
        (.vermouthAndFortified, [
            Rule(["dry vermouth", "extra dry", "dry"], "Dry Vermouth", requires: ["vermouth", "vermut"]),
            Rule(["vermouth", "vermut"], "Sweet Vermouth"),
            Rule(["sherry", "jerez", "fino", "manzanilla", "amontillado", "oloroso", "pedro ximenez"], "Sherry"),
            Rule(["port", "porto", "tawny"], "Port"),
        ]),
        (.mixersAndSyrups, [
            Rule(["ginger beer", "ginger ale"], "Ginger Beer & Ale"),
            Rule(["tonic", "club soda", "soda water", "sparkling water", "seltzer", "mineral water"], "Tonic & Soda"),
            Rule(["cream of coconut", "coco lopez"], "Cream of Coconut"),
            Rule(["syrup", "grenadine", "orgeat", "falernum"], "Syrup"),
            Rule(["juice"], "Bottled Juice"),
        ]),
        (.agave, [
            Rule(["mezcal", "mescal"], "Mezcal"),
            Rule(["reposado"], "Tequila Reposado", requires: ["tequila", "agave"]),
            Rule(["extra anejo", "anejo"], "Tequila Añejo", requires: ["tequila", "agave"]),
            Rule(["tequila"], "Tequila Blanco"),
        ]),
        (.rum, [
            Rule(["rhum agricole", "agricole"], "Rhum Agricole"),
            Rule(["white", "silver", "light", "blanco", "blanca", "platinum", "plata"], "White Rum", requires: ["rum", "ron", "rhum"]),
            Rule(["dark", "black", "navy", "negra"], "Dark Rum", requires: ["rum", "ron", "rhum"]),
            Rule(["aged", "anejo", "reserva", "gold", "oro", "dorado", "years", "anos", "xo", "solera"], "Aged Rum",
                 requires: ["rum", "ron", "rhum"]),
            Rule(["rum", "ron", "rhum"], "Rum"),
        ]),
        (.whiskey, [
            Rule(["japanese whisky", "whisky", "whiskey", "single malt"], "Japanese Whisky",
                 requires: ["japan", "japanese"], scope: .label),
            Rule(["irish whiskey", "whiskey"], "Irish Whiskey", requires: ["irish", "ireland"], scope: .label),
            Rule(["scotch", "single malt", "blended malt", "highland", "islay", "speyside"], "Scotch"),
            Rule(["rye whiskey", "rye whisky", "straight rye"], "Rye"),
            Rule(["bourbon", "tennessee whiskey"], "Bourbon"),
            Rule(["rye"], "Rye", requires: ["whiskey", "whisky"]),
            Rule(["whiskey", "whisky"], nil),
        ]),
        (.gin, [
            Rule(["old tom"], "Old Tom"),
            Rule(["london dry", "gin", "genever", "jenever"], "London Dry"),
        ]),
        (.brandy, [
            Rule(["cognac", "fine champagne", "grande champagne"], "Cognac"),
            Rule(["armagnac"], "Armagnac"),
            Rule(["calvados"], "Calvados"),
            Rule(["pisco"], "Pisco"),
            Rule(["brandy"], "Brandy"),
        ]),
        (.vodka, [
            Rule(["citron", "citrus", "vanilla", "raspberry", "peach", "flavored", "flavoured", "infused"], "Flavored Vodka",
                 requires: ["vodka"]),
            Rule(["vodka"], "Vodka"),
        ]),
        (.wine, [
            Rule(["champagne", "prosecco", "cava", "cremant", "brut", "sparkling wine"], "Sparkling Wine", excludes: ["cognac"]),
            Rule(["sauternes", "late harvest", "ice wine", "icewine", "tokaji", "moscato"], "Dessert Wine"),
            Rule(["rose"], "Rosé", requires: ["wine", "vin", "vino"], scope: .label),
            Rule(["red wine", "vin rouge", "vino rosso", "cabernet", "merlot", "pinot noir", "malbec", "zinfandel",
                  "syrah", "shiraz", "rioja", "chianti", "sangiovese", "tempranillo", "grenache", "bordeaux"], "Red Wine"),
            Rule(["white wine", "vin blanc", "vino bianco", "chardonnay", "sauvignon blanc", "pinot grigio", "pinot gris",
                  "riesling", "chenin blanc", "albarino", "gruner"], "White Wine"),
            Rule(["wine", "vino"], nil),
        ]),
        (.beerAndCider, [
            Rule(["india pale ale", "ipa", "pale ale"], "Pale Ale & IPA"),
            Rule(["stout", "porter"], "Stout & Porter"),
            Rule(["sour ale", "gose", "lambic", "berliner weisse"], "Sour Beer"),
            Rule(["hefeweizen", "witbier", "wheat beer", "weissbier", "weizen"], "Wheat Beer"),
            Rule(["lager", "pilsner", "pils", "helles"], "Lager"),
            Rule(["hard cider", "cider", "cidre"], "Cider"),
            Rule(["beer", "ale"], nil),
        ]),
        (.other, [
            Rule(["absinthe", "absinth"], "Absinthe"),
            Rule(["aquavit", "akvavit"], "Aquavit"),
            Rule(["sake", "junmai", "ginjo", "daiginjo"], "Sake"),
        ]),
    ]

    /// Picks the family whose words are printed biggest (cask notes and small print lose to the main
    /// designation), with the order above breaking ties. Within that family the first matching rule wins.
    private static func matchType(_ lines: [LabelLine]) -> (family: SpiritFamily?, style: String?) {
        let lineWords = lines.map { words($0.text) }
        let labelWords = lineWords.flatMap { $0 }
        // Each line on its own, and each line joined to the next, for phrases that wrap.
        var windows: [(words: [String], weight: Double)] = lineWords.indices.map {
            (words: lineWords[$0], weight: lines[$0].height)
        }
        for index in lineWords.indices.dropLast() {
            windows.append((words: lineWords[index] + lineWords[index + 1],
                            weight: max(lines[index].height, lines[index + 1].height)))
        }

        func weight(of rule: Rule) -> Double? {
            if rule.excludes.contains(where: { hasPhrase(labelWords, $0) }) { return nil }
            var best: Double?
            for window in windows where rule.phrases.contains(where: { hasPhrase(window.words, $0) }) {
                let context = rule.scope == .label ? labelWords : window.words
                if !rule.requires.isEmpty && !rule.requires.contains(where: { hasPhrase(context, $0) }) { continue }
                best = max(best ?? 0, window.weight)
            }
            return best
        }

        var chosen: (family: SpiritFamily, weight: Double)?
        for (family, familyRules) in rules {
            guard let familyWeight = familyRules.compactMap(weight(of:)).max() else { continue }
            if familyWeight > (chosen?.weight ?? 0) + 0.000_1 {
                chosen = (family, familyWeight)
            }
        }
        guard let family = chosen?.family,
              let familyRules = rules.first(where: { $0.family == family })?.rules,
              let rule = familyRules.first(where: { weight(of: $0) != nil }) else {
            return (nil, nil)
        }
        return (family, rule.style)
    }

    // MARK: - Brand

    /// Words that describe the bottle rather than name it. A line made only of these isn't the brand.
    private static let descriptiveWords: Set<String> = {
        var set: Set<String> = [
            "kentucky", "tennessee", "straight", "small", "batch", "single", "barrel", "cask", "casks", "strength",
            "distilled", "distillery", "distillers", "distilling", "bottled", "by", "in", "est", "established", "since",
            "proof", "alc", "vol", "abv", "alcohol", "ml", "cl", "l", "liter", "litre", "product", "of", "imported",
            "import", "aged", "years", "year", "old", "yo", "the", "and", "a", "with", "from", "made", "handcrafted",
            "premium", "original", "reserve", "reserva", "finest", "fine", "extra", "dry", "sweet", "100", "de",
            "usa", "france", "italy", "mexico", "scotland", "ireland", "japan", "england", "jalisco", "naturally",
            "flavored", "flavoured", "natural", "flavors", "botanicals", "malt", "blended", "pure", "pot", "still",
            "white", "silver", "gold", "dark", "black", "aromatic", "orange", "red", "rouge", "blanco", "bianco",
            "rosso", "agave", "azul", "mash", "grain", "corn", "wheat", "rye", "spirit", "spirits", "drink",
            "responsibly", "contains", "sulfites", "government", "warning", "finished", "matured", "handmade",
            "doc", "docg", "aoc", "do", "most", "unusual", "bond"
        ]
        for (_, familyRules) in rules {
            for rule in familyRules {
                for phrase in rule.phrases { set.formUnion(phrase) }
            }
        }
        // Brand names that are also rules stay usable as brands.
        set.subtract(["campari", "aperol", "cointreau", "grand", "marnier", "kahlua", "tia", "maria", "baileys",
                      "chartreuse", "benedictine", "drambuie", "galliano", "strega", "jagermeister", "fernet", "cynar",
                      "montenegro", "averna", "nonino", "st", "germain", "luxardo", "disaronno", "frangelico", "chambord",
                      "heering", "angostura", "peychaud", "peychauds", "coco", "lopez"])
        return set
    }()

    /// Lines that could be the brand, biggest text first, tidied and with type words trimmed off the end
    /// ("BULLEIT BOURBON" → "Bulleit"). Words at the start are kept, so "Old Forester" stays whole.
    private static func brandCandidates(_ lines: [LabelLine]) -> [String] {
        var seen = Set<String>()
        return lines
            .sorted { $0.height != $1.height ? $0.height > $1.height : $0.top < $1.top }
            .compactMap { line -> String? in
                let tokens = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
                guard tokens.count <= 4 else { return nil } // a sentence of small print, not a name
                var kept = tokens
                while let last = kept.last, isDescriptive(last) { kept.removeLast() }
                guard !kept.isEmpty, !kept.allSatisfy(isDescriptive) else { return nil }
                let text = kept.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,-·•*"))
                let letters = text.filter(\.isLetter).count
                guard letters >= 3, letters * 2 >= text.count else { return nil }
                let key = words(text).joined()
                guard seen.insert(key).inserted else { return nil }
                return tidy(text)
            }
    }

    private static func isDescriptive(_ token: String) -> Bool {
        let tokenWords = words(token)
        return tokenWords.isEmpty || tokenWords.allSatisfy { descriptiveWords.contains($0) || $0.allSatisfy(\.isNumber) }
    }

    /// ALL CAPS becomes Title Case ("HENDRICK'S" → "Hendrick's", "ST-GERMAIN" → "St-Germain"). Mixed case is kept.
    private static func tidy(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased() else { return text }
        let lowerWords: Set<String> = ["of", "and", "de", "del", "la", "le", "du", "the"]
        var result = ""
        var startOfWord = true
        var wordIndex = 0
        var current = ""
        func flush() {
            if !current.isEmpty {
                let lower = current.lowercased()
                result += (wordIndex > 0 && lowerWords.contains(lower)) ? lower : current
                wordIndex += 1
                current = ""
            }
        }
        for character in text {
            if character == " " {
                flush()
                result.append(character)
                startOfWord = true
            } else if character == "-" {
                current.append(character)
                startOfWord = true
            } else if character.isLetter {
                current += startOfWord ? character.uppercased() : character.lowercased()
                startOfWord = false
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }

    // MARK: - Proof, ABV, age, size

    private static func readDetails(_ text: String, into suggestion: inout LabelSuggestion) {
        let lower = text.lowercased()
        suggestion.proof = firstMatch(#"(?<!\d)(\d{2,3}(?:\.\d)?)\s*(?:°\s*)?proof"#, in: lower)
        suggestion.abv = firstMatch(#"(?<!\d)(\d{1,2}(?:[.,]\d{1,2})?)\s*%"#, in: lower)?.replacingOccurrences(of: ",", with: ".")
        if let age = firstMatch(#"(?:aged\s+)?(?<!\d)(\d{1,2})\s*(?:years?|yrs?|y\.?o\.?|años|anos)(?![a-z])"#, in: lower),
           let years = Int(age), (1...50).contains(years) {
            suggestion.age = age
        }
        if let millilitres = firstMatch(#"(?<!\d)(\d{2,4})\s*ml(?![a-z])"#, in: lower) {
            suggestion.size = "\(millilitres) ml"
        } else if let centilitres = firstMatch(#"(?<!\d)(\d{2,3})\s*cl(?![a-z])"#, in: lower), let value = Int(centilitres) {
            suggestion.size = "\(value * 10) ml"
        } else if let litres = firstMatch(#"(?<![\d.,])(\d(?:[.,]\d{1,2})?)\s*(?:l|liters?|litres?)(?![a-z])"#, in: lower) {
            suggestion.size = "\(litres.replacingOccurrences(of: ",", with: ".")) L"
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Filling the form

    /// Adds the label's notes to what's already written, unless they're already there.
    static func mergedNotes(_ existing: String, adding labelNotes: String) -> String {
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !labelNotes.isEmpty, !current.contains(labelNotes) else { return current }
        return current.isEmpty ? labelNotes : current + "\n" + labelNotes
    }

    // MARK: - Existing bottles

    /// The index of the brand that's the same as `brand`, ignoring case, accents and punctuation, and allowing
    /// one letter's difference or a longer name ("Hendricks" = "Hendrick's", "Buffalo Trace Bourbon" = "Buffalo Trace").
    static func matchingBrandIndex(_ brand: String, in brands: [String]) -> Int? {
        let key = words(brand).joined()
        guard key.count >= 3 else { return nil }
        let keys = brands.map { words($0).joined() }
        if let exact = keys.firstIndex(of: key) { return exact }
        return keys.firstIndex { other in
            guard other.count >= 3 else { return false }
            if min(key.count, other.count) >= 5 && (key.hasPrefix(other) || other.hasPrefix(key)) { return true }
            return min(key.count, other.count) >= 5 && editDistance(key, other) <= 1
        }
    }

    /// A bottle in My Bar with the same brand, if there is one.
    static func existingBottle(matching brand: String, in bottles: [V1.Bottle]) -> V1.Bottle? {
        matchingBrandIndex(brand, in: bottles.map(\.brand)).map { bottles[$0] }
    }

    /// How many single-letter changes turn one word into the other ("hendriks" → "hendricks" = 1).
    static func editDistance(_ first: String, _ second: String) -> Int {
        let a = Array(first), b = Array(second)
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Words

    /// Lowercase words without accents or apostrophes: "Hendrick's AÑEJO" → ["hendricks", "anejo"].
    static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// True when `phrase` appears in `words` as consecutive whole words.
    private static func hasPhrase(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= words.count else { return false }
        return (0...(words.count - phrase.count)).contains { start in
            Array(words[start..<(start + phrase.count)]) == phrase
        }
    }
}
