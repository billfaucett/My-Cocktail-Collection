//
//  TemplateSuggester.swift
//  My Cocktail Collection
//
//  Cocktail templates, step 2: suggests which of the six Cocktail Codex templates a recipe follows,
//  from its ingredients. It's a suggestion for you to confirm or change, and it says nothing when unsure.
//

import Foundation

/// What the suggester needs to know about one ingredient.
struct TemplateIngredient {
    var name: String
    var amount: Double?
    var unit: IngredientUnit
    /// The family of the ingredient's type, e.g. Liqueurs & Amari for Triple Sec.
    var family: SpiritFamily?
    var isGarnish = false
    var isOptional = false
}

enum TemplateSuggester {
    /// The template a recipe follows, or nil when its ingredients don't clearly point to one.
    ///
    /// In order:
    /// 1. A sparkling mixer (soda, tonic, ginger beer…) makes a Highball; so does sparkling wine without citrus.
    /// 2. A long, non-citrus juice (3 parts or more, like tomato juice) makes a Highball.
    /// 3. Egg, cream or espresso makes a Flip, unless citrus leads (an egg-white sour is still a Daiquiri).
    /// 4. Citrus makes a Sidecar when there's a liqueur, otherwise a Daiquiri.
    /// 5. Vermouth or another aromatized wine makes a Martini.
    /// 6. Sugar or bitters with a spirit makes an Old Fashioned.
    static func suggest(_ ingredients: [TemplateIngredient]) -> CocktailTemplate? {
        let used = ingredients.filter { !$0.isGarnish && !$0.isOptional }
        let parts = used.map(Facts.init)

        guard parts.contains(where: { $0.isSpirit || $0.isLiqueur || $0.isAromatizedWine }) else { return nil }

        let citrus = parts.filter(\.isCitrus)
        let citrusAmount = citrus.map(\.partsAmount).reduce(0, +)

        if parts.contains(where: { $0.isSparkling && !$0.isSparklingWine }) { return .highball }
        if parts.contains(where: \.isSparklingWine) && citrus.isEmpty { return .highball }
        if parts.contains(where: { $0.isLongJuice }) { return .highball }

        let rich = parts.filter(\.isRich)
        if !rich.isEmpty {
            let richAmount = rich.filter { !$0.isEgg }.map(\.partsAmount).reduce(0, +)
            if citrus.isEmpty || richAmount > citrusAmount { return .flip }
        }

        if !citrus.isEmpty {
            return parts.contains(where: \.isLiqueur) ? .sidecar : .daiquiri
        }
        if parts.contains(where: \.isAromatizedWine) { return .martini }
        if parts.contains(where: \.isSpirit) && parts.contains(where: { $0.isSweetener || $0.isBitters }) {
            return .oldFashioned
        }
        return nil
    }

    // MARK: Convenience

    /// From ingredients read from text (e.g. the built-in recipes).
    static func suggest(parsed: [ParsedIngredient]) -> CocktailTemplate? {
        suggest(parsed.map {
            TemplateIngredient(name: $0.name, amount: $0.amount, unit: $0.unit,
                               family: $0.styleName.flatMap { SpiritTaxonomy.builtInStyle(named: $0)?.family },
                               isGarnish: $0.isGarnish, isOptional: $0.isOptional)
        })
    }

    /// From rows being edited in the cocktail form.
    static func suggest(rows: [IngredientInput]) -> CocktailTemplate? {
        suggest(rows.map {
            TemplateIngredient(name: $0.name, amount: $0.amount, unit: $0.unit, family: $0.style?.family,
                               isGarnish: $0.isGarnish, isOptional: $0.isOptional)
        })
    }

    // MARK: Facts about one ingredient

    private struct Facts {
        let isSpirit, isLiqueur, isAromatizedWine, isBitters, isSweetener: Bool
        let isCitrus, isSparkling, isSparklingWine, isRich, isEgg, isLongJuice: Bool
        /// The amount in parts, or 0 for other measures.
        let partsAmount: Double

        init(_ ingredient: TemplateIngredient) {
            let words = Set(LabelMatcher.words(ingredient.name))
            let family = ingredient.family
            func has(_ any: String...) -> Bool { !words.isDisjoint(with: any) }

            partsAmount = ingredient.unit == .part ? (ingredient.amount ?? 0) : 0
            let spiritFamilies: Set<SpiritFamily> = [.whiskey, .gin, .rum, .agave, .brandy, .vodka]
            isSpirit = family.map(spiritFamilies.contains) ?? false
                || has("whiskey", "whisky", "bourbon", "rye", "scotch", "gin", "rum", "tequila", "mezcal", "vodka",
                       "brandy", "cognac", "pisco", "armagnac", "calvados")
            isLiqueur = family == .liqueursAndAmari || has("liqueur", "amaro", "curacao", "chartreuse")
            isAromatizedWine = family == .vermouthAndFortified || has("vermouth", "lillet", "quinquina", "sherry")
            isBitters = family == .bitters || has("bitters")
            isSweetener = has("syrup", "sugar", "honey", "agave", "nectar", "orgeat", "grenadine", "demerara", "falernum")
            isSparklingWine = has("champagne", "prosecco", "cava", "cremant") || (has("sparkling") && has("wine"))
            isSparkling = isSparklingWine || ingredient.unit == .topUp
                || has("soda", "tonic", "seltzer", "cola", "sparkling") || (has("ginger") && (has("beer") || has("ale")))
                || (has("topo") && has("chico"))
            let isJuice = has("juice")
            isCitrus = isJuice && has("lime", "lemon", "grapefruit", "orange", "yuzu")
            isLongJuice = isJuice && !isCitrus && partsAmount >= 3
            isEgg = has("egg", "yolk")
            isRich = isEgg || has("cream", "espresso", "milk")
        }
    }
}
