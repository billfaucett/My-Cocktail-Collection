//
//  CloudRecords.swift
//  My Cocktail Collection
//
//  Sync and sharing, step 2a: turns spirit types, cocktails, menus and bottles into iCloud records and
//  back. Nothing here talks to iCloud; the sync engine (step 2b) sends and receives what this builds.
//
//  - My Library (types, cocktails, menus) lives in the "Library" zone, so it can later be shared as one.
//    My Bar (bottles) lives in its own "MyBar" zone and is never shared.
//  - A record's name is the item's `id`, so built-ins (fixed IDs) are the same record on every device.
//  - A recipe's ingredients and a menu's entries travel inside their record, so a recipe is always sent
//    and received whole and two devices can't end up with doubled ingredient lists.
//  - Links to other items (a cocktail's base spirit, a menu's cocktails) are stored as record names and
//    looked up when a record arrives. A link that isn't here yet is reported, so it can be retried.
//

import CloudKit
import Foundation
import SwiftData

// MARK: - Zones and record types

enum CloudSchema {
    static let containerIdentifier = "iCloud.Lemursoft.My-Cocktail-Collection"
    static let libraryZoneName = "Library"
    static let myBarZoneName = "MyBar"

    /// My Library's zone, or the zone of a library someone shared with you (their `ownerName`).
    static func libraryZoneID(ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: libraryZoneName, ownerName: ownerName)
    }

    static var myBarZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: myBarZoneName, ownerName: CKCurrentUserDefaultName)
    }
}

enum CloudRecordType: String, CaseIterable {
    case style = "SpiritStyle"
    case cocktail = "Cocktail"
    case menu = "Menu"
    case bottle = "Bottle"

    /// Records arriving together are applied in this order: types first, so cocktails and bottles can link
    /// to them, then cocktails, then the menus that list them.
    var applyOrder: Int {
        switch self {
        case .style: return 0
        case .cocktail: return 1
        case .bottle: return 2
        case .menu: return 3
        }
    }
}

/// Field names, kept in one place so sending and receiving always agree.
private enum Field {
    static let name = "name"
    static let family = "family"
    static let isBuiltIn = "isBuiltIn"
    static let dateAdded = "dateAdded"
    static let source = "source"
    static let baseStyle = "baseStyle"
    static let method = "method"
    static let originalIngredientsText = "originalIngredientsText"
    static let needsIngredientReview = "needsIngredientReview"
    static let rating = "rating"
    static let isFavorite = "isFavorite"
    static let template = "template"
    static let ingredients = "ingredients"
    static let photo = "photo"
    static let dateCreated = "dateCreated"
    static let notes = "notes"
    static let entries = "entries"
    static let brand = "brand"
    static let style = "style"
    static let stockLevel = "stockLevel"
    static let bottleCount = "bottleCount"
}

// MARK: - Embedded rows

/// One ingredient row inside a cocktail's record.
struct CloudIngredient: Codable, Equatable {
    var id: UUID
    var position: Int
    var amount: Double?
    var amountMax: Double?
    var unit: String
    var name: String
    var note: String?
    var isGarnish: Bool
    var isOptional: Bool
    /// The linked spirit type's record name.
    var style: String?

    init(_ ingredient: DB.RecipeIngredient) {
        id = ingredient.id
        position = ingredient.position
        amount = ingredient.amount
        amountMax = ingredient.amountMax
        unit = ingredient.unitRaw
        name = ingredient.name
        note = ingredient.note
        isGarnish = ingredient.isGarnish
        isOptional = ingredient.isOptional
        style = ingredient.style?.id.uuidString
    }
}

/// One cocktail's place inside a menu's record.
struct CloudMenuEntry: Codable, Equatable {
    var id: UUID
    var position: Int
    /// The cocktail's record name.
    var cocktail: String?

    init(_ entry: DB.MenuEntry) {
        id = entry.id
        position = entry.position
        cocktail = entry.cocktail?.id.uuidString
    }
}

// MARK: - System fields

/// iCloud's bookkeeping for a record (its ID, type and version), saved in `SyncRecord.systemFields`
/// so the next change is sent as an update to the same record.
enum CloudSystemFields {
    static func encode(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func decode(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}

// MARK: - Records

enum CloudRecords {
    // MARK: Record IDs

    /// Bottles go in My Bar's zone; everything else in the library's zone.
    static func recordID(for id: UUID, type: CloudRecordType,
                         libraryOwner: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        let zone = type == .bottle ? CloudSchema.myBarZoneID : CloudSchema.libraryZoneID(ownerName: libraryOwner)
        return CKRecord.ID(recordName: id.uuidString, zoneID: zone)
    }

    /// The record to fill in: the saved one when there is one, so iCloud knows which version is being
    /// changed, otherwise a new record.
    static func blankRecord(type: CloudRecordType, id: CKRecord.ID, systemFields: Data?) -> CKRecord {
        if let systemFields, let saved = CloudSystemFields.decode(systemFields),
           saved.recordID == id, saved.recordType == type.rawValue {
            return saved
        }
        return CKRecord(recordType: type.rawValue, recordID: id)
    }

    // MARK: Items to records

    static func record(for style: DB.SpiritStyle, systemFields: Data?,
                       libraryOwner: String = CKCurrentUserDefaultName) -> CKRecord {
        let record = blankRecord(type: .style, id: recordID(for: style.id, type: .style, libraryOwner: libraryOwner),
                                 systemFields: systemFields)
        record[Field.name] = style.name
        record[Field.family] = style.familyRaw
        record[Field.isBuiltIn] = style.isBuiltIn
        record[Field.dateAdded] = style.dateAdded
        return record
    }

    static func record(for cocktail: DB.Cocktail, systemFields: Data?,
                       libraryOwner: String = CKCurrentUserDefaultName) -> CKRecord {
        let record = blankRecord(type: .cocktail, id: recordID(for: cocktail.id, type: .cocktail, libraryOwner: libraryOwner),
                                 systemFields: systemFields)
        record[Field.name] = cocktail.name
        record[Field.source] = cocktail.sourceRaw
        record[Field.baseStyle] = cocktail.baseStyle?.id.uuidString
        record[Field.method] = cocktail.method
        record[Field.originalIngredientsText] = cocktail.originalIngredientsText
        record[Field.needsIngredientReview] = cocktail.needsIngredientReview
        record[Field.rating] = cocktail.rating
        record[Field.isFavorite] = cocktail.isFavorite
        record[Field.dateAdded] = cocktail.dateAdded
        record[Field.template] = cocktail.templateRaw
        record[Field.ingredients] = encode(cocktail.orderedIngredients.map(CloudIngredient.init))
        record[Field.photo] = asset(for: cocktail.photo, name: "\(cocktail.id.uuidString)-cocktail")
        return record
    }

    static func record(for menu: DB.Menu, systemFields: Data?,
                       libraryOwner: String = CKCurrentUserDefaultName) -> CKRecord {
        let record = blankRecord(type: .menu, id: recordID(for: menu.id, type: .menu, libraryOwner: libraryOwner),
                                 systemFields: systemFields)
        record[Field.name] = menu.name
        record[Field.dateCreated] = menu.dateCreated
        record[Field.notes] = menu.notes
        record[Field.entries] = encode(menu.orderedEntries.map(CloudMenuEntry.init))
        return record
    }

    static func record(for bottle: DB.Bottle, systemFields: Data?) -> CKRecord {
        let record = blankRecord(type: .bottle, id: recordID(for: bottle.id, type: .bottle), systemFields: systemFields)
        record[Field.brand] = bottle.brand
        record[Field.style] = bottle.style?.id.uuidString
        record[Field.stockLevel] = bottle.stockLevelRaw
        record[Field.bottleCount] = bottle.bottleCount
        record[Field.notes] = bottle.notes
        record[Field.isFavorite] = bottle.isFavorite
        record[Field.rating] = bottle.rating
        record[Field.dateAdded] = bottle.dateAdded
        record[Field.photo] = asset(for: bottle.photo, name: "\(bottle.id.uuidString)-bottle")
        return record
    }

    // MARK: Records to items

    /// Creates or updates the item a record describes. `library` is nil for My Library and My Bar.
    /// Doesn't save. Returns false if a linked item isn't here yet; apply the record again once it is.
    @discardableResult
    static func apply(_ record: CKRecord, in context: ModelContext, library: DB.Library? = nil) throws -> Bool {
        guard let type = CloudRecordType(rawValue: record.recordType),
              let id = UUID(uuidString: record.recordID.recordName) else { return true }
        switch type {
        case .style: return try applyStyle(record, id: id, in: context, library: library)
        case .cocktail: return try applyCocktail(record, id: id, in: context, library: library)
        case .menu: return try applyMenu(record, id: id, in: context, library: library)
        case .bottle: return try applyBottle(record, id: id, in: context)
        }
    }

    /// Removes the item a deleted record described, with its ingredients or menu entries. Doesn't save.
    static func deleteItem(type: CloudRecordType, id: UUID, in context: ModelContext, library: DB.Library? = nil) throws {
        switch type {
        case .style:
            if let style = try findStyle(id, library: library, in: context) { context.delete(style) }
        case .cocktail:
            if let cocktail = try findCocktail(id, library: library, in: context) { context.delete(cocktail) }
        case .menu:
            if let menu = try findMenu(id, library: library, in: context) { context.delete(menu) }
        case .bottle:
            if let bottle = try findBottle(id, in: context) { context.delete(bottle) }
        }
    }

    private static func applyStyle(_ record: CKRecord, id: UUID, in context: ModelContext, library: DB.Library?) throws -> Bool {
        let style: DB.SpiritStyle
        if let existing = try findStyle(id, library: library, in: context) {
            style = existing
        } else {
            style = DB.SpiritStyle(name: "", family: .other)
            style.id = id
            context.insert(style)
            style.library = library
        }
        style.name = record[Field.name] as? String ?? ""
        style.familyRaw = record[Field.family] as? String ?? SpiritFamily.other.rawValue
        style.isBuiltIn = record[Field.isBuiltIn] as? Bool ?? false
        style.dateAdded = record[Field.dateAdded] as? Date ?? style.dateAdded
        return true
    }

    private static func applyCocktail(_ record: CKRecord, id: UUID, in context: ModelContext, library: DB.Library?) throws -> Bool {
        let cocktail: DB.Cocktail
        if let existing = try findCocktail(id, library: library, in: context) {
            cocktail = existing
        } else {
            cocktail = DB.Cocktail(name: "")
            cocktail.id = id
            context.insert(cocktail)
            cocktail.library = library
        }
        var allLinksFound = true
        cocktail.name = record[Field.name] as? String ?? ""
        cocktail.sourceRaw = record[Field.source] as? String ?? CocktailSource.original.rawValue
        cocktail.method = record[Field.method] as? String ?? ""
        cocktail.originalIngredientsText = record[Field.originalIngredientsText] as? String
        cocktail.needsIngredientReview = record[Field.needsIngredientReview] as? Bool ?? false
        cocktail.rating = record[Field.rating] as? Int ?? 0
        cocktail.isFavorite = record[Field.isFavorite] as? Bool ?? false
        cocktail.dateAdded = record[Field.dateAdded] as? Date ?? cocktail.dateAdded
        cocktail.templateRaw = record[Field.template] as? String
        cocktail.photo = photo(in: record)

        if let styleID = (record[Field.baseStyle] as? String).flatMap(UUID.init(uuidString:)) {
            cocktail.baseStyle = try findStyle(styleID, library: library, in: context)
            if cocktail.baseStyle == nil { allLinksFound = false }
        } else {
            cocktail.baseStyle = nil
        }

        // The record has the whole ingredient list: replace the rows rather than merging them.
        let oldRows = cocktail.ingredients ?? []
        cocktail.ingredients = []
        for row in oldRows { context.delete(row) }
        for row in decode([CloudIngredient].self, from: record[Field.ingredients] as? Data) ?? [] {
            let ingredient = DB.RecipeIngredient(position: row.position, name: row.name, amount: row.amount,
                                                 amountMax: row.amountMax, note: row.note,
                                                 isGarnish: row.isGarnish, isOptional: row.isOptional)
            ingredient.id = row.id
            ingredient.unitRaw = row.unit
            context.insert(ingredient)
            ingredient.cocktail = cocktail
            if let styleID = row.style.flatMap(UUID.init(uuidString:)) {
                ingredient.style = try findStyle(styleID, library: library, in: context)
                if ingredient.style == nil { allLinksFound = false }
            }
        }
        return allLinksFound
    }

    private static func applyMenu(_ record: CKRecord, id: UUID, in context: ModelContext, library: DB.Library?) throws -> Bool {
        let menu: DB.Menu
        if let existing = try findMenu(id, library: library, in: context) {
            menu = existing
        } else {
            menu = DB.Menu(name: "")
            menu.id = id
            context.insert(menu)
            menu.library = library
        }
        var allLinksFound = true
        menu.name = record[Field.name] as? String ?? ""
        menu.dateCreated = record[Field.dateCreated] as? Date ?? menu.dateCreated
        menu.notes = record[Field.notes] as? String ?? ""

        let oldEntries = menu.entries ?? []
        menu.entries = []
        for entry in oldEntries { context.delete(entry) }
        for row in decode([CloudMenuEntry].self, from: record[Field.entries] as? Data) ?? [] {
            guard let cocktailID = row.cocktail.flatMap(UUID.init(uuidString:)) else { continue }
            guard let cocktail = try findCocktail(cocktailID, library: library, in: context) else {
                allLinksFound = false
                continue
            }
            let entry = DB.MenuEntry(position: row.position)
            entry.id = row.id
            context.insert(entry)
            entry.menu = menu
            entry.cocktail = cocktail
        }
        return allLinksFound
    }

    private static func applyBottle(_ record: CKRecord, id: UUID, in context: ModelContext) throws -> Bool {
        let bottle: DB.Bottle
        if let existing = try findBottle(id, in: context) {
            bottle = existing
        } else {
            bottle = DB.Bottle(brand: "")
            bottle.id = id
            context.insert(bottle)
        }
        var allLinksFound = true
        bottle.brand = record[Field.brand] as? String ?? ""
        bottle.stockLevelRaw = record[Field.stockLevel] as? Int ?? Int(StockLevel.full.rawValue)
        bottle.bottleCount = record[Field.bottleCount] as? Int ?? 1
        bottle.notes = record[Field.notes] as? String ?? ""
        bottle.isFavorite = record[Field.isFavorite] as? Bool ?? false
        bottle.rating = record[Field.rating] as? Int ?? 0
        bottle.dateAdded = record[Field.dateAdded] as? Date ?? bottle.dateAdded
        bottle.photo = photo(in: record)
        // My Bar links to types in My Library.
        if let styleID = (record[Field.style] as? String).flatMap(UUID.init(uuidString:)) {
            bottle.style = try findStyle(styleID, library: nil, in: context)
            if bottle.style == nil { allLinksFound = false }
        } else {
            bottle.style = nil
        }
        return allLinksFound
    }

    // MARK: Finding items
    // Built-ins have the same ID in every library, so lookups also match the library (nil = My Library).

    static func findStyle(_ id: UUID, library: DB.Library?, in context: ModelContext) throws -> DB.SpiritStyle? {
        try context.fetch(FetchDescriptor<DB.SpiritStyle>(predicate: #Predicate { $0.id == id }))
            .first { $0.library?.id == library?.id }
    }

    static func findCocktail(_ id: UUID, library: DB.Library?, in context: ModelContext) throws -> DB.Cocktail? {
        try context.fetch(FetchDescriptor<DB.Cocktail>(predicate: #Predicate { $0.id == id }))
            .first { $0.library?.id == library?.id }
    }

    static func findMenu(_ id: UUID, library: DB.Library?, in context: ModelContext) throws -> DB.Menu? {
        try context.fetch(FetchDescriptor<DB.Menu>(predicate: #Predicate { $0.id == id }))
            .first { $0.library?.id == library?.id }
    }

    static func findBottle(_ id: UUID, in context: ModelContext) throws -> DB.Bottle? {
        var descriptor = FetchDescriptor<DB.Bottle>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Helpers

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Photos travel as iCloud assets, which are files. Writes the photo to a temporary file for sending.
    private static func asset(for data: Data?, name: String) -> CKAsset? {
        guard let data else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloudAssets", isDirectory: true)
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return CKAsset(fileURL: url)
    }

    private static func photo(in record: CKRecord) -> Data? {
        guard let url = (record[Field.photo] as? CKAsset)?.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
