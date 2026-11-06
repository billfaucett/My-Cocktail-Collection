//
//  Inventory.swift
//  My Cocktail Collection
//
//  The spirit inventory: the bottles you have on hand, each linked to a base spirit
//  category from the Spirits list (e.g. "Buffalo Trace" under Bourbon).
//

import CoreData
import UIKit

// MARK: - Stock level

/// How much is left in the bottle you're using.
enum StockLevel: Int16, CaseIterable, CustomStringConvertible {
    case full = 0
    case half = 1
    case low = 2
    case out = 3

    var description: String {
        switch self {
        case .full: return "Full"
        case .half: return "Half"
        case .low: return "Low"
        case .out: return "Out"
        }
    }

    /// Anything except Out counts as in stock.
    var isInStock: Bool { self != .out }

    /// Low and Out bottles belong on the shopping list.
    var needsRestock: Bool { self == .low || self == .out }
}

// MARK: - Errors

enum InventoryError: LocalizedError, Equatable {
    case missingBrand
    case invalidBottleCount
    case invalidRating

    var errorDescription: String? {
        switch self {
        case .missingBrand: return "Please enter a brand or name for the bottle."
        case .invalidBottleCount: return "The number of bottles can't be negative."
        case .invalidRating: return "Ratings go from 0 to 10."
        }
    }
}

// MARK: - Bottle conveniences

extension Bottle {
    /// The stock level as a `StockLevel` rather than the raw number stored in the database.
    var stock: StockLevel {
        get { StockLevel(rawValue: stockLevel) ?? .full }
        set { stockLevel = newValue.rawValue }
    }

    /// Stores a label photo, shrunk and compressed the same way as cocktail photos.
    func setPhoto(_ photo: UIImage?) {
        image = photo?.cocktailPhotoData()
    }
}

// MARK: - Inventory (create, read, update, delete)

/// Adds, finds, changes and removes bottles. Every change is validated and saved immediately.
///
/// Usage:
///
///     let inventory = Inventory(context: context)
///     let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)
///     try inventory.setStock(.low, for: bottle)
///     let toBuy = try inventory.shoppingList()
///
/// If a change fails validation, all unsaved changes in the context are undone and an
/// `InventoryError` is thrown, so a half-finished edit is never left behind.
struct Inventory {
    let context: NSManagedObjectContext

    /// Brand A–Z, ignoring upper/lower case. Also usable in a SwiftUI `@FetchRequest`.
    static let sortByBrand = [
        NSSortDescriptor(key: "brand", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ]

    // MARK: Create

    @discardableResult
    func addBottle(
        brand: String,
        spirit: Spirit?,
        stock: StockLevel = .full,
        bottleCount: Int16 = 1,
        notes: String = "",
        isFavorite: Bool = false,
        rating: Int16 = 0,
        photo: UIImage? = nil
    ) throws -> Bottle {
        let bottle = Bottle(context: context)
        bottle.id = UUID()
        bottle.dateAdded = Date()
        bottle.brand = brand
        bottle.spirit = spirit
        bottle.stock = stock
        bottle.bottleCount = bottleCount
        bottle.notes = notes
        bottle.isFavorite = isFavorite
        bottle.rating = rating
        bottle.setPhoto(photo)
        try validateAndSave(bottle)
        return bottle
    }

    // MARK: Read

    /// Bottles sorted by brand. Every filter is optional and they can be combined.
    /// - Parameters:
    ///   - spirit: Only bottles in this base spirit category.
    ///   - stock: Only bottles at one of these stock levels.
    ///   - favoritesOnly: Only bottles marked as favorites.
    func bottles(in spirit: Spirit? = nil, stock: Set<StockLevel>? = nil, favoritesOnly: Bool = false) throws -> [Bottle] {
        let request = NSFetchRequest<Bottle>(entityName: "Bottle")
        var predicates: [NSPredicate] = []
        if let spirit {
            predicates.append(NSPredicate(format: "spirit == %@", spirit))
        }
        if let stock {
            predicates.append(NSPredicate(format: "stockLevel IN %@", stock.map { NSNumber(value: $0.rawValue) }))
        }
        if favoritesOnly {
            predicates.append(NSPredicate(format: "isFavorite == YES"))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = Inventory.sortByBrand
        return try context.fetch(request)
    }

    /// Bottles that are Full, Half or Low.
    func inStockBottles() throws -> [Bottle] {
        try bottles(stock: Set(StockLevel.allCases.filter(\.isInStock)))
    }

    /// Bottles that are Low or Out.
    func shoppingList() throws -> [Bottle] {
        try bottles(stock: Set(StockLevel.allCases.filter(\.needsRestock)))
    }

    func bottle(withID id: UUID) throws -> Bottle? {
        let request = NSFetchRequest<Bottle>(entityName: "Bottle")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: Update

    /// Makes any changes to a bottle, then validates and saves them.
    ///
    ///     try inventory.update(bottle) {
    ///         $0.brand = "Buffalo Trace Kosher Wheat"
    ///         $0.notes = "Softer than the original"
    ///     }
    func update(_ bottle: Bottle, _ changes: (Bottle) -> Void) throws {
        changes(bottle)
        try validateAndSave(bottle)
    }

    /// Sets the stock level. Marking an empty bottle (count 0) as in stock sets the count to 1.
    func setStock(_ level: StockLevel, for bottle: Bottle) throws {
        try update(bottle) {
            $0.stock = level
            if level.isInStock && $0.bottleCount == 0 {
                $0.bottleCount = 1
            }
        }
    }

    /// Sets the number of bottles. Setting it to 0 marks the bottle Out.
    func setBottleCount(_ count: Int16, for bottle: Bottle) throws {
        try update(bottle) { $0.bottleCount = count }
    }

    func setFavorite(_ isFavorite: Bool, for bottle: Bottle) throws {
        try update(bottle) { $0.isFavorite = isFavorite }
    }

    /// Replaces the label photo, or removes it when `photo` is nil.
    func setPhoto(_ photo: UIImage?, for bottle: Bottle) throws {
        try update(bottle) { $0.setPhoto(photo) }
    }

    // MARK: Delete

    func delete(_ bottle: Bottle) throws {
        context.delete(bottle)
        try context.save()
    }

    // MARK: Validation

    private func validateAndSave(_ bottle: Bottle) throws {
        let brand = (bottle.brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            guard !brand.isEmpty else { throw InventoryError.missingBrand }
            guard bottle.bottleCount >= 0 else { throw InventoryError.invalidBottleCount }
            guard (0...10).contains(bottle.rating) else { throw InventoryError.invalidRating }

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
