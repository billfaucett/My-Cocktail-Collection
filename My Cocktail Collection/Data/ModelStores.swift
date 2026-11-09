//
//  ModelStores.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 3: add, find, change and delete for the new SwiftData models.
//  One store per area (styles, bottles, cocktails, menus). Every change is validated and saved
//  immediately; a change that fails is undone and throws a StoreError with a message for the user.
//  Not used by the app yet.
//

import Foundation
import SwiftData
import UIKit

/// Short name for the new schema while the refactor is in progress. Phase 5 replaces it with plain names.
typealias V1 = CocktailSchemaV1

// MARK: - Errors

enum StoreError: LocalizedError, Equatable {
    /// `what` names the missing field, e.g. "cocktail name".
    case missingName(String)
    case duplicateName(String)
    case invalidBottleCount
    case invalidRating

    var errorDescription: String? {
        switch self {
        case .missingName(let what): return "Please enter a \(what)."
        case .duplicateName(let name): return "You already have one named \(name)."
        case .invalidBottleCount: return "The number of bottles can't be negative."
        case .invalidRating: return "Ratings go from 0 to 10."
        }
    }
}

extension ModelContext {
    /// Saves. If saving fails, unsaved changes are undone and the error is passed on.
    func saveOrUndo() throws {
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}

private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func byName(_ first: String, _ second: String) -> Bool {
    first.localizedCaseInsensitiveCompare(second) == .orderedAscending
}

// MARK: - Styles

struct StyleStore {
    let context: ModelContext

    /// Every style, grouped by family in display order: built-in styles in catalog order, then yours A–Z.
    func allStyles() throws -> [V1.SpiritStyle] {
        try context.fetch(FetchDescriptor<V1.SpiritStyle>()).sorted(by: Self.displayOrder)
    }

    func styles(in family: SpiritFamily) throws -> [V1.SpiritStyle] {
        try allStyles().filter { $0.family == family }
    }

    /// Finds a style by name, ignoring case and surrounding spaces.
    func style(named name: String) throws -> V1.SpiritStyle? {
        let key = trimmed(name).lowercased()
        return try context.fetch(FetchDescriptor<V1.SpiritStyle>()).first { $0.name.lowercased() == key }
    }

    @discardableResult
    func addStyle(name: String, family: SpiritFamily, isBuiltIn: Bool = false) throws -> V1.SpiritStyle {
        let clean = trimmed(name)
        guard !clean.isEmpty else { throw StoreError.missingName("style name") }
        if try self.style(named: clean) != nil {
            throw StoreError.duplicateName(clean)
        }
        let newStyle = V1.SpiritStyle(name: clean, family: family, isBuiltIn: isBuiltIn)
        context.insert(newStyle)
        try context.saveOrUndo()
        return newStyle
    }

    func update(_ style: V1.SpiritStyle, name: String, family: SpiritFamily) throws {
        let clean = trimmed(name)
        guard !clean.isEmpty else { throw StoreError.missingName("style name") }
        if let existing = try self.style(named: clean), existing !== style {
            throw StoreError.duplicateName(clean)
        }
        style.name = clean
        style.family = family
        try context.saveOrUndo()
    }

    /// Deletes a style. Bottles, cocktails and ingredients that used it stay, without a style.
    func delete(_ style: V1.SpiritStyle) throws {
        context.delete(style)
        try context.saveOrUndo()
    }

    static func displayOrder(_ first: V1.SpiritStyle, _ second: V1.SpiritStyle) -> Bool {
        if first.family != second.family {
            return first.family.sortOrder < second.family.sortOrder
        }
        let firstIndex = SpiritTaxonomy.builtInStyles.firstIndex { $0.name == first.name } ?? Int.max
        let secondIndex = SpiritTaxonomy.builtInStyles.firstIndex { $0.name == second.name } ?? Int.max
        if firstIndex != secondIndex {
            return firstIndex < secondIndex
        }
        return byName(first.name, second.name)
    }
}

// MARK: - Bottles

struct BottleStore {
    let context: ModelContext

    @discardableResult
    func addBottle(
        brand: String,
        style: V1.SpiritStyle?,
        stock: StockLevel = .full,
        bottleCount: Int = 1,
        notes: String = "",
        isFavorite: Bool = false,
        rating: Int = 0,
        photo: UIImage? = nil
    ) throws -> V1.Bottle {
        let bottle = V1.Bottle(brand: brand, stock: stock, bottleCount: bottleCount)
        context.insert(bottle)
        bottle.style = style
        bottle.notes = notes
        bottle.isFavorite = isFavorite
        bottle.rating = rating
        bottle.photo = photo?.cocktailPhotoData()
        try validateAndSave(bottle)
        return bottle
    }

    /// Bottles sorted by brand. Every filter is optional and they can be combined.
    func bottles(
        style: V1.SpiritStyle? = nil,
        family: SpiritFamily? = nil,
        stock: Set<StockLevel>? = nil,
        favoritesOnly: Bool = false
    ) throws -> [V1.Bottle] {
        try context.fetch(FetchDescriptor<V1.Bottle>())
            .filter { bottle in
                if let style, bottle.style !== style { return false }
                if let family, bottle.style?.family != family { return false }
                if let stock, !stock.contains(bottle.stock) { return false }
                if favoritesOnly && !bottle.isFavorite { return false }
                return true
            }
            .sorted { byName($0.brand, $1.brand) }
    }

    /// Bottles that are Full, Half or Low.
    func inStockBottles() throws -> [V1.Bottle] {
        try bottles(stock: Set(StockLevel.allCases.filter(\.isInStock)))
    }

    /// Bottles that are Low or Out.
    func shoppingList() throws -> [V1.Bottle] {
        try bottles(stock: Set(StockLevel.allCases.filter(\.needsRestock)))
    }

    /// Makes any changes to a bottle, then validates and saves them.
    func update(_ bottle: V1.Bottle, _ changes: (V1.Bottle) -> Void) throws {
        changes(bottle)
        try validateAndSave(bottle)
    }

    /// Sets the stock level. Marking an empty bottle (count 0) as in stock sets the count to 1.
    func setStock(_ level: StockLevel, for bottle: V1.Bottle) throws {
        try update(bottle) {
            $0.stock = level
            if level.isInStock && $0.bottleCount == 0 {
                $0.bottleCount = 1
            }
        }
    }

    /// Sets the number of bottles. Setting it to 0 marks the bottle Out.
    func setBottleCount(_ count: Int, for bottle: V1.Bottle) throws {
        try update(bottle) { $0.bottleCount = count }
    }

    func setFavorite(_ isFavorite: Bool, for bottle: V1.Bottle) throws {
        try update(bottle) { $0.isFavorite = isFavorite }
    }

    /// Replaces the label photo, or removes it when `photo` is nil.
    func setPhoto(_ photo: UIImage?, for bottle: V1.Bottle) throws {
        try update(bottle) { $0.photo = photo?.cocktailPhotoData() }
    }

    func delete(_ bottle: V1.Bottle) throws {
        context.delete(bottle)
        try context.saveOrUndo()
    }

    private func validateAndSave(_ bottle: V1.Bottle) throws {
        let brand = trimmed(bottle.brand)
        do {
            guard !brand.isEmpty else { throw StoreError.missingName("brand or name") }
            guard bottle.bottleCount >= 0 else { throw StoreError.invalidBottleCount }
            guard (0...10).contains(bottle.rating) else { throw StoreError.invalidRating }
            bottle.brand = brand
            if bottle.bottleCount == 0 {
                bottle.stock = .out
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

// MARK: - Ingredient rows

/// One ingredient row being edited, before it's saved. The style is set explicitly,
/// so a style picked by hand wins over the one the name suggests.
struct IngredientInput: Identifiable, Equatable {
    let id = UUID()
    var amount: Double?
    var amountMax: Double?
    var unit: IngredientUnit = .unspecified
    var name: String = ""
    var note: String?
    var isGarnish = false
    var isOptional = false
    var style: V1.SpiritStyle?
    /// True when the parser wasn't sure about this row. Editing it by hand clears this.
    var needsReview = false

    init(amount: Double? = nil, amountMax: Double? = nil, unit: IngredientUnit = .unspecified, name: String = "",
         note: String? = nil, isGarnish: Bool = false, isOptional: Bool = false,
         style: V1.SpiritStyle? = nil, needsReview: Bool = false) {
        self.amount = amount
        self.amountMax = amountMax
        self.unit = unit
        self.name = name
        self.note = note
        self.isGarnish = isGarnish
        self.isOptional = isOptional
        self.style = style
        self.needsReview = needsReview
    }

    /// A row read from text. Pass the style that matches its style name, if any.
    init(parsed: ParsedIngredient, style: V1.SpiritStyle?) {
        self.init(amount: parsed.amount, amountMax: parsed.amountMax, unit: parsed.unit, name: parsed.name,
                  note: parsed.note, isGarnish: parsed.isGarnish, isOptional: parsed.isOptional,
                  style: style, needsReview: parsed.needsReview)
    }

    /// A row copied from a saved ingredient.
    init(stored: V1.RecipeIngredient, needsReview: Bool = false) {
        self.init(amount: stored.amount, amountMax: stored.amountMax, unit: stored.unit, name: stored.name,
                  note: stored.note, isGarnish: stored.isGarnish, isOptional: stored.isOptional,
                  style: stored.style, needsReview: needsReview)
    }

    /// This row as it will read in the recipe, e.g. "1½ parts Bourbon".
    var displayText: String {
        IngredientFormatter.line(amount: amount, amountMax: amountMax, unit: unit, name: name,
                                 note: note, isGarnish: isGarnish, isOptional: isOptional)
    }

    /// Rows are equal when they'd save the same ingredient; the id is ignored.
    static func == (lhs: IngredientInput, rhs: IngredientInput) -> Bool {
        lhs.amount == rhs.amount && lhs.amountMax == rhs.amountMax && lhs.unit == rhs.unit
            && lhs.name == rhs.name && (lhs.note ?? "") == (rhs.note ?? "")
            && lhs.isGarnish == rhs.isGarnish && lhs.isOptional == rhs.isOptional
            && lhs.style === rhs.style && lhs.needsReview == rhs.needsReview
    }
}

// MARK: - Cocktails

enum CocktailSort {
    case name
    case rating
}

struct CocktailStore {
    let context: ModelContext

    @discardableResult
    func addCocktail(
        name: String,
        source: CocktailSource = .original,
        baseStyle: V1.SpiritStyle? = nil,
        ingredients: [ParsedIngredient] = [],
        rows: [IngredientInput] = [],
        method: String = "",
        rating: Int = 0,
        isFavorite: Bool = false,
        photo: UIImage? = nil
    ) throws -> V1.Cocktail {
        let cocktail = V1.Cocktail(name: name, source: source, method: method)
        context.insert(cocktail)
        cocktail.baseStyle = baseStyle
        cocktail.rating = rating
        cocktail.isFavorite = isFavorite
        cocktail.photo = photo?.cocktailPhotoData()
        insertRows(inputs(from: ingredients) + rows, into: cocktail)
        try validateAndSave(cocktail)
        return cocktail
    }

    /// Replaces a cocktail's ingredients. Each is linked to its style when one matches.
    func setIngredients(_ ingredients: [ParsedIngredient], for cocktail: V1.Cocktail) throws {
        try setIngredients(inputs(from: ingredients), for: cocktail)
    }

    /// Replaces a cocktail's ingredients with edited rows, in order, keeping each row's own style.
    func setIngredients(_ rows: [IngredientInput], for cocktail: V1.Cocktail) throws {
        for old in cocktail.ingredients ?? [] {
            context.delete(old)
        }
        cocktail.ingredients = []
        insertRows(rows, into: cocktail)
        try validateAndSave(cocktail)
    }

    /// Reads recipe text into rows, linking each to the stored style its name matches.
    func rows(fromText text: String) -> [IngredientInput] {
        inputs(from: IngredientParser.parse(text).ingredients)
    }

    /// Replaces a cocktail's ingredients by reading recipe text, one ingredient per line.
    func setIngredients(fromText text: String, for cocktail: V1.Cocktail) throws {
        try setIngredients(IngredientParser.parse(text).ingredients, for: cocktail)
    }

    /// Cocktails matching every filter given.
    /// - Parameters:
    ///   - search: Matches the cocktail's name or any ingredient's name.
    ///   - family: Base style in this family (Whiskey includes Bourbon, Rye, Scotch…).
    ///   - style: Exactly this base style.
    func cocktails(
        matching search: String = "",
        family: SpiritFamily? = nil,
        style: V1.SpiritStyle? = nil,
        favoritesOnly: Bool = false,
        sortedBy sort: CocktailSort = .name
    ) throws -> [V1.Cocktail] {
        let query = trimmed(search)
        return try context.fetch(FetchDescriptor<V1.Cocktail>())
            .filter { matches($0, query: query, family: family, style: style, favoritesOnly: favoritesOnly) }
            .sorted { first, second in
                if sort == .rating && first.rating != second.rating {
                    return first.rating > second.rating
                }
                return byName(first.name, second.name)
            }
    }

    /// Makes any changes to a cocktail, then validates and saves them.
    func update(_ cocktail: V1.Cocktail, _ changes: (V1.Cocktail) -> Void) throws {
        changes(cocktail)
        try validateAndSave(cocktail)
    }

    func setFavorite(_ isFavorite: Bool, for cocktail: V1.Cocktail) throws {
        try update(cocktail) { $0.isFavorite = isFavorite }
    }

    func toggleFavorite(_ cocktail: V1.Cocktail) throws {
        try setFavorite(!cocktail.isFavorite, for: cocktail)
    }

    func setPhoto(_ photo: UIImage?, for cocktail: V1.Cocktail) throws {
        try update(cocktail) { $0.photo = photo?.cocktailPhotoData() }
    }

    /// Deletes a cocktail, its ingredients and its menu entries.
    func delete(_ cocktail: V1.Cocktail) throws {
        context.delete(cocktail)
        try context.saveOrUndo()
    }

    private func matches(_ cocktail: V1.Cocktail, query: String, family: SpiritFamily?, style: V1.SpiritStyle?, favoritesOnly: Bool) -> Bool {
        if let family, cocktail.baseStyle?.family != family { return false }
        if let style, cocktail.baseStyle !== style { return false }
        if favoritesOnly && !cocktail.isFavorite { return false }
        if query.isEmpty { return true }
        if cocktail.name.localizedCaseInsensitiveContains(query) { return true }
        return (cocktail.ingredients ?? []).contains { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Parsed lines as rows, each linked to the stored style named by the parser.
    private func inputs(from parsed: [ParsedIngredient]) -> [IngredientInput] {
        guard !parsed.isEmpty else { return [] }
        let styles = (try? context.fetch(FetchDescriptor<V1.SpiritStyle>())) ?? []
        let stylesByName = Dictionary(styles.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return parsed.map { line in
            IngredientInput(parsed: line, style: line.styleName.flatMap { stylesByName[$0.lowercased()] })
        }
    }

    /// Inserts rows in order, each with its own style link.
    private func insertRows(_ rows: [IngredientInput], into cocktail: V1.Cocktail) {
        for (position, row) in rows.enumerated() {
            let ingredient = V1.RecipeIngredient(position: position, name: trimmed(row.name), amount: row.amount,
                                                 amountMax: row.amountMax, unit: row.unit,
                                                 note: row.note.map(trimmed).flatMap { $0.isEmpty ? nil : $0 },
                                                 isGarnish: row.isGarnish, isOptional: row.isOptional)
            context.insert(ingredient)
            ingredient.cocktail = cocktail
            ingredient.style = row.style
        }
        cocktail.needsIngredientReview = rows.contains(where: \.needsReview)
    }

    private func validateAndSave(_ cocktail: V1.Cocktail) throws {
        let name = trimmed(cocktail.name)
        do {
            guard !name.isEmpty else { throw StoreError.missingName("cocktail name") }
            guard (0...10).contains(cocktail.rating) else { throw StoreError.invalidRating }
            cocktail.name = name
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

// MARK: - Menus

struct MenuStore {
    let context: ModelContext

    @discardableResult
    func addMenu(name: String) throws -> V1.Menu {
        let clean = trimmed(name)
        guard !clean.isEmpty else { throw StoreError.missingName("menu name") }
        let menu = V1.Menu(name: clean)
        context.insert(menu)
        try context.saveOrUndo()
        return menu
    }

    /// Menus, newest first.
    func menus() throws -> [V1.Menu] {
        try context.fetch(FetchDescriptor<V1.Menu>(sortBy: [SortDescriptor(\.dateCreated, order: .reverse)]))
    }

    func rename(_ menu: V1.Menu, to name: String) throws {
        let clean = trimmed(name)
        guard !clean.isEmpty else { throw StoreError.missingName("menu name") }
        menu.name = clean
        try context.saveOrUndo()
    }

    /// Adds cocktails to the end of a menu, in the order given. Cocktails already on it are skipped.
    func add(_ cocktails: [V1.Cocktail], to menu: V1.Menu) throws {
        var onMenu = Set((menu.entries ?? []).compactMap { $0.cocktail?.id })
        var nextPosition = ((menu.entries ?? []).map(\.position).max() ?? -1) + 1
        for cocktail in cocktails where !onMenu.contains(cocktail.id) {
            let entry = V1.MenuEntry(position: nextPosition)
            context.insert(entry)
            entry.menu = menu
            entry.cocktail = cocktail
            onMenu.insert(cocktail.id)
            nextPosition += 1
        }
        try context.saveOrUndo()
    }

    /// Takes a cocktail off a menu (the cocktail stays in the collection) and closes the gap.
    func remove(_ entry: V1.MenuEntry, from menu: V1.Menu) throws {
        let remaining = menu.orderedEntries.filter { $0 !== entry }
        context.delete(entry)
        for (position, other) in remaining.enumerated() {
            other.position = position
        }
        try context.saveOrUndo()
    }

    /// Moves an entry to a new place in the menu (0 = first).
    func move(_ entry: V1.MenuEntry, to index: Int, in menu: V1.Menu) throws {
        var ordered = menu.orderedEntries
        guard let from = ordered.firstIndex(where: { $0 === entry }) else { return }
        ordered.remove(at: from)
        ordered.insert(entry, at: min(max(index, 0), ordered.count))
        for (position, item) in ordered.enumerated() {
            item.position = position
        }
        try context.saveOrUndo()
    }

    /// Deletes a menu and its entries. The cocktails stay in the collection.
    func delete(_ menu: V1.Menu) throws {
        context.delete(menu)
        try context.saveOrUndo()
    }

    /// Deletes every menu and its entries. The cocktails stay in the collection.
    func deleteAll() throws {
        for menu in try menus() {
            context.delete(menu)
        }
        try context.saveOrUndo()
    }
}
