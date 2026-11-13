//
//  My_Cocktail_CollectionTests.swift
//  My Cocktail CollectionTests
//
//  Created by William Faucett on 2/24/24.
//

import XCTest
import CloudKit
import CoreData
import SwiftData
import UIKit
@testable import My_Cocktail_Collection

// MARK: - Delete Menu Data

final class DeleteMenuDataTests: XCTestCase {
    private var dataController: DataController!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        dataController = DataController(inMemory: true)
        context = dataController.container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        dataController = nil
    }

    /// "Delete Menu Data" removes every menu and menu item, and leaves drinks and spirits alone.
    func testDeleteMenuDataRemovesMenusButKeepsRecipes() throws {
        let martini = makeDrink("Martini")
        let margarita = makeDrink("Margarita")
        let spirit = Spirit(context: context)
        spirit.id = UUID()
        spirit.spiritName = "Gin"

        let party = makeMenu("Party")
        let brunch = makeMenu("Brunch")
        addItem(martini, to: party)
        addItem(margarita, to: party)
        addItem(margarita, to: brunch)
        try context.save()

        DataController.deleteStuff(context: context)

        XCTAssertEqual(try count(Menu.self), 0)
        XCTAssertEqual(try count(MenuItem.self), 0)
        XCTAssertEqual(try count(Drink.self), 2, "Deleting menus must not delete cocktail recipes")
        XCTAssertEqual(try count(Spirit.self), 1, "Deleting menus must not delete spirits")
    }

    /// Menus already loaded on screen must be marked deleted right away.
    /// The old batch delete skipped this, so deleted menus stayed visible until you relaunched.
    func testDeleteMenuDataUpdatesMenusAlreadyOnScreen() throws {
        let menu = makeMenu("Party")
        let item = addItem(makeDrink("Martini"), to: menu)
        try context.save()

        DataController.deleteStuff(context: context)

        XCTAssertNil(menu.managedObjectContext, "The on-screen menu should be removed from the context")
        XCTAssertNil(item.managedObjectContext, "The on-screen menu item should be removed from the context")
        XCTAssertFalse(context.hasChanges, "The delete should be saved")
    }

    func testDeleteMenuDataWithNoMenusDoesNothing() throws {
        makeDrink("Martini")
        try context.save()

        DataController.deleteStuff(context: context)

        XCTAssertEqual(try count(Drink.self), 1)
    }

    // MARK: Helpers

    @discardableResult
    private func makeDrink(_ name: String) -> Drink {
        let drink = Drink(context: context)
        drink.id = UUID()
        drink.drinkName = name
        return drink
    }

    private func makeMenu(_ name: String) -> Menu {
        let menu = Menu(context: context)
        menu.id = UUID()
        menu.menuName = name
        menu.dateCreated = Date()
        return menu
    }

    @discardableResult
    private func addItem(_ drink: Drink, to menu: Menu) -> MenuItem {
        let item = MenuItem(context: context)
        item.id = UUID()
        item.drink = drink
        item.menu = menu
        return item
    }

    private func count<T: NSManagedObject>(_ type: T.Type) throws -> Int {
        try context.count(for: NSFetchRequest<T>(entityName: String(describing: type)))
    }
}

// MARK: - Photo saving

final class PhotoSaveTests: XCTestCase {

    func testLandscapePhotoShrinksTo600WideAndKeepsShape() {
        let result = makeImage(width: 3000, height: 2000).scaledToFit(maxDimension: 600)
        XCTAssertEqual(result.size.width, 600, accuracy: 0.5)
        XCTAssertEqual(result.size.height, 400, accuracy: 0.5)
    }

    func testPortraitPhotoShrinksTo600TallAndKeepsShape() {
        let result = makeImage(width: 1500, height: 3000).scaledToFit(maxDimension: 600)
        XCTAssertEqual(result.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(result.size.height, 600, accuracy: 0.5)
    }

    func testSmallPhotoIsNotEnlarged() {
        let result = makeImage(width: 400, height: 300).scaledToFit(maxDimension: 600)
        XCTAssertEqual(result.size, CGSize(width: 400, height: 300))
    }

    /// iPhone photos are often stored sideways with a rotation flag. The saved photo should come out upright.
    func testRotatedCameraPhotoIsSavedUpright() throws {
        let sideways = try XCTUnwrap(makeImage(width: 2000, height: 1000).cgImage)
        let photo = UIImage(cgImage: sideways, scale: 1, orientation: .right) // displays as 1000 × 2000

        let data = try XCTUnwrap(photo.cocktailPhotoData())
        let saved = try XCTUnwrap(UIImage(data: data))

        XCTAssertEqual(saved.imageOrientation, .up)
        XCTAssertEqual(saved.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(saved.size.height, 600, accuracy: 0.5)
    }

    func testPhotoDataIsCompressedJPEG() throws {
        let data = try XCTUnwrap(makeImage(width: 4032, height: 3024).cocktailPhotoData())

        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "Photo should be saved as JPEG")
        XCTAssertLessThan(data.count, 200_000, "A 600px JPEG should be well under 200 KB")
    }

    /// The original bug: saving a new drink threw away the resized photo and stored the full-size one.
    /// This checks what actually ends up in the database.
    func testSavedDrinkStoresTheResizedPhoto() throws {
        let dataController = DataController(inMemory: true)
        let context = dataController.container.viewContext

        let drink = Drink(context: context)
        drink.id = UUID()
        drink.drinkName = "Martini"
        drink.setPhoto(makeImage(width: 4032, height: 3024))
        try context.save()

        let request = NSFetchRequest<Drink>(entityName: "Drink")
        let stored = try XCTUnwrap(try context.fetch(request).first?.image)
        let image = try XCTUnwrap(UIImage(data: stored))

        XCTAssertEqual(image.size.width, 600, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 450, accuracy: 0.5)
    }

    // MARK: Helpers

    /// Makes a test image of an exact pixel size, with some detail so compression is realistic.
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 3))
            UIColor.systemPurple.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: width / 3, y: height / 3, width: width / 2, height: height / 2))
        }
    }
}

// MARK: - Spirit inventory

final class InventoryTests: XCTestCase {
    private var dataController: DataController!
    private var context: NSManagedObjectContext!
    private var inventory: Inventory!
    private var bourbon: Spirit!
    private var gin: Spirit!

    override func setUpWithError() throws {
        dataController = DataController(inMemory: true)
        context = dataController.container.viewContext
        inventory = Inventory(context: context)
        bourbon = makeSpirit("Bourbon")
        gin = makeSpirit("Gin")
        try context.save()
    }

    override func tearDownWithError() throws {
        inventory = nil
        context = nil
        dataController = nil
    }

    // MARK: Create

    func testAddBottleSavesEveryField() throws {
        let bottle = try inventory.addBottle(
            brand: "Buffalo Trace", spirit: bourbon, stock: .half, bottleCount: 2,
            notes: "Great in Old Fashioneds", isFavorite: true, rating: 8
        )

        XCTAssertNotNil(bottle.id)
        XCTAssertNotNil(bottle.dateAdded)
        XCTAssertEqual(bottle.brand, "Buffalo Trace")
        XCTAssertEqual(bottle.spirit, bourbon)
        XCTAssertEqual(bottle.spirit?.spiritName, "Bourbon")
        XCTAssertEqual(bottle.stock, .half)
        XCTAssertEqual(bottle.bottleCount, 2)
        XCTAssertEqual(bottle.notes, "Great in Old Fashioneds")
        XCTAssertTrue(bottle.isFavorite)
        XCTAssertEqual(bottle.rating, 8)
        XCTAssertFalse(context.hasChanges, "Adding a bottle should save it")
    }

    func testNewBottleDefaultsToOneFullBottle() throws {
        let bottle = try inventory.addBottle(brand: "Hendrick's", spirit: gin)
        XCTAssertEqual(bottle.stock, .full)
        XCTAssertEqual(bottle.bottleCount, 1)
        XCTAssertFalse(bottle.isFavorite)
        XCTAssertEqual(bottle.rating, 0)
        XCTAssertNil(bottle.image)
    }

    func testBottleCanBeAddedWithoutACategory() throws {
        let bottle = try inventory.addBottle(brand: "Mystery Gift Bottle", spirit: nil)
        XCTAssertNil(bottle.spirit)
    }

    func testBrandIsTrimmed() throws {
        let bottle = try inventory.addBottle(brand: "  Buffalo Trace \n", spirit: bourbon)
        XCTAssertEqual(bottle.brand, "Buffalo Trace")
    }

    func testBlankBrandIsRejectedAndNothingIsSaved() throws {
        XCTAssertThrowsError(try inventory.addBottle(brand: "   ", spirit: bourbon)) { error in
            XCTAssertEqual(error as? InventoryError, .missingBrand)
        }
        XCTAssertEqual(try inventory.bottles().count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testNegativeBottleCountIsRejected() {
        XCTAssertThrowsError(try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, bottleCount: -1)) { error in
            XCTAssertEqual(error as? InventoryError, .invalidBottleCount)
        }
    }

    func testRatingOutsideZeroToTenIsRejected() {
        XCTAssertThrowsError(try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, rating: 11)) { error in
            XCTAssertEqual(error as? InventoryError, .invalidRating)
        }
    }

    func testLabelPhotoIsStoredResized() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, photo: makeImage(width: 3024, height: 4032))
        let image = try XCTUnwrap(bottle.image.flatMap(UIImage.init(data:)))
        XCTAssertEqual(image.size.height, 600, accuracy: 0.5)
        XCTAssertEqual(image.size.width, 450, accuracy: 0.5)
    }

    // MARK: Read

    func testBottlesAreSortedByBrandIgnoringCase() throws {
        try inventory.addBottle(brand: "maker's Mark", spirit: bourbon)
        try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)
        try inventory.addBottle(brand: "Woodford Reserve", spirit: bourbon)

        XCTAssertEqual(try inventory.bottles().map(\.brand), ["Buffalo Trace", "maker's Mark", "Woodford Reserve"])
    }

    func testFilterByCategory() throws {
        try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)
        try inventory.addBottle(brand: "Hendrick's", spirit: gin)
        try inventory.addBottle(brand: "Tanqueray", spirit: gin)

        XCTAssertEqual(try inventory.bottles(in: gin).map(\.brand), ["Hendrick's", "Tanqueray"])
        XCTAssertEqual(gin.bottles?.count, 2, "The category should list its bottles too")
    }

    func testShoppingListHasLowAndOutBottles() throws {
        try inventory.addBottle(brand: "Full Bottle", spirit: bourbon, stock: .full)
        try inventory.addBottle(brand: "Half Bottle", spirit: bourbon, stock: .half)
        try inventory.addBottle(brand: "Low Bottle", spirit: bourbon, stock: .low)
        try inventory.addBottle(brand: "Out Bottle", spirit: bourbon, stock: .out)

        XCTAssertEqual(try inventory.shoppingList().map(\.brand), ["Low Bottle", "Out Bottle"])
        XCTAssertEqual(try inventory.inStockBottles().map(\.brand), ["Full Bottle", "Half Bottle", "Low Bottle"])
    }

    func testFiltersCanBeCombined() throws {
        try inventory.addBottle(brand: "Favorite Low Gin", spirit: gin, stock: .low, isFavorite: true)
        try inventory.addBottle(brand: "Plain Low Gin", spirit: gin, stock: .low)
        try inventory.addBottle(brand: "Favorite Low Bourbon", spirit: bourbon, stock: .low, isFavorite: true)
        try inventory.addBottle(brand: "Favorite Full Gin", spirit: gin, stock: .full, isFavorite: true)

        let result = try inventory.bottles(in: gin, stock: [.low], favoritesOnly: true)
        XCTAssertEqual(result.map(\.brand), ["Favorite Low Gin"])
    }

    func testFindBottleByID() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)
        let id = try XCTUnwrap(bottle.id)
        XCTAssertEqual(try inventory.bottle(withID: id), bottle)
        XCTAssertNil(try inventory.bottle(withID: UUID()))
    }

    // MARK: Update

    func testUpdateSavesChanges() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)

        try inventory.update(bottle) {
            $0.brand = "Buffalo Trace Kosher Wheat"
            $0.notes = "Softer than the original"
            $0.rating = 7
        }

        XCTAssertEqual(bottle.brand, "Buffalo Trace Kosher Wheat")
        XCTAssertEqual(bottle.notes, "Softer than the original")
        XCTAssertEqual(bottle.rating, 7)
        XCTAssertFalse(context.hasChanges)
    }

    func testInvalidUpdateIsUndone() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, notes: "Original note")

        XCTAssertThrowsError(try inventory.update(bottle) {
            $0.notes = "Changed note"
            $0.brand = ""
        })

        XCTAssertEqual(bottle.brand, "Buffalo Trace", "A failed update should leave the bottle unchanged")
        XCTAssertEqual(bottle.notes, "Original note")
    }

    func testSettingCountToZeroMarksBottleOut() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, stock: .low, bottleCount: 1)
        try inventory.setBottleCount(0, for: bottle)
        XCTAssertEqual(bottle.stock, .out)
    }

    func testRestockingAnEmptyBottleSetsCountToOne() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, bottleCount: 0)
        XCTAssertEqual(bottle.stock, .out)

        try inventory.setStock(.full, for: bottle)

        XCTAssertEqual(bottle.stock, .full)
        XCTAssertEqual(bottle.bottleCount, 1)
    }

    func testMarkingOutKeepsBackupBottleCount() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon, bottleCount: 3)
        try inventory.setStock(.out, for: bottle)
        XCTAssertEqual(bottle.bottleCount, 3, "Stock level and bottle count are tracked separately")
    }

    func testToggleFavoriteAndPhoto() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)

        try inventory.setFavorite(true, for: bottle)
        try inventory.setPhoto(makeImage(width: 800, height: 800), for: bottle)
        XCTAssertTrue(bottle.isFavorite)
        XCTAssertNotNil(bottle.image)

        try inventory.setPhoto(nil, for: bottle)
        XCTAssertNil(bottle.image)
    }

    // MARK: Delete

    func testDeleteBottle() throws {
        let keep = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)
        let remove = try inventory.addBottle(brand: "Woodford Reserve", spirit: bourbon)

        try inventory.delete(remove)

        XCTAssertEqual(try inventory.bottles(), [keep])
        XCTAssertEqual(bourbon.bottles?.count, 1)
    }

    func testDeletingACategoryKeepsItsBottles() throws {
        let bottle = try inventory.addBottle(brand: "Buffalo Trace", spirit: bourbon)

        context.delete(bourbon)
        try context.save()

        XCTAssertEqual(try inventory.bottles(), [bottle])
        XCTAssertNil(bottle.spirit, "The bottle stays in the inventory without a category")
    }

    // MARK: Helpers

    private func makeSpirit(_ name: String) -> Spirit {
        let spirit = Spirit(context: context)
        spirit.id = UUID()
        spirit.spiritName = name
        spirit.type = SpiritType.liquor.rawValue
        return spirit
    }

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Database upgrade

final class ModelUpgradeTests: XCTestCase {

    /// Your phone's database was created with model version 1 (no inventory).
    /// This creates a version 1 database, opens it with the current model the way the
    /// updated app will, and checks the recipes survive and the inventory works.
    func testExistingRecipesSurviveUpgradeToInventoryModel() throws {
        let bundle = Bundle(for: DataController.self)
        let v1URL = try XCTUnwrap(
            bundle.url(forResource: "CocktailRecipe", withExtension: "mom", subdirectory: "CocktailRecipe.momd"),
            "Version 1 of the model should be in the app bundle"
        )
        let v1 = try XCTUnwrap(NSManagedObjectModel(contentsOf: v1URL))
        XCTAssertNil(v1.entitiesByName["Bottle"], "Version 1 is the model before the inventory")
        // Use plain NSManagedObject for the old model so it doesn't compete with the app's Drink/Spirit classes.
        v1.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upgrade-test-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // 1. A database as it exists on your phone today.
        let oldContainer = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: v1)
        oldContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        try load(oldContainer)

        let spiritID = UUID()
        let spirit = NSEntityDescription.insertNewObject(forEntityName: "Spirit", into: oldContainer.viewContext)
        spirit.setValue(spiritID, forKey: "id")
        spirit.setValue("Bourbon", forKey: "spiritName")
        let drink = NSEntityDescription.insertNewObject(forEntityName: "Drink", into: oldContainer.viewContext)
        drink.setValue(UUID(), forKey: "id")
        drink.setValue("Old Fashioned", forKey: "drinkName")
        drink.setValue(spiritID, forKey: "baseSpirit")
        drink.setValue(Int16(9), forKey: "rating")
        try oldContainer.viewContext.save()
        for store in oldContainer.persistentStoreCoordinator.persistentStores {
            try oldContainer.persistentStoreCoordinator.remove(store)
        }

        // 2. The updated app opens the same file with the current model.
        let newContainer = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: DataController.model)
        newContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        try load(newContainer)
        let context = newContainer.viewContext

        let drinks = try context.fetch(NSFetchRequest<Drink>(entityName: "Drink"))
        XCTAssertEqual(drinks.count, 1)
        XCTAssertEqual(drinks.first?.drinkName, "Old Fashioned")
        XCTAssertEqual(drinks.first?.rating, 9)
        XCTAssertEqual(drinks.first?.baseSpirit, spiritID)

        let bourbon = try XCTUnwrap(try context.fetch(NSFetchRequest<Spirit>(entityName: "Spirit")).first)
        try Inventory(context: context).addBottle(brand: "Buffalo Trace", spirit: bourbon)
        XCTAssertEqual(bourbon.bottles?.count, 1)
    }

    /// Version 2 added the inventory; version 3 adds cocktail favorites.
    /// Checks a version 2 database (with recipes and bottles) upgrades with nothing lost.
    func testVersion2DatabaseUpgradesToFavoritesModel() throws {
        let bundle = Bundle(for: DataController.self)
        let v2URL = try XCTUnwrap(
            bundle.url(forResource: "CocktailRecipe 2", withExtension: "mom", subdirectory: "CocktailRecipe.momd"),
            "Version 2 of the model should be in the app bundle"
        )
        let v2 = try XCTUnwrap(NSManagedObjectModel(contentsOf: v2URL))
        XCTAssertNil(v2.entitiesByName["Drink"]?.attributesByName["isFavorite"], "Version 2 has no cocktail favorites")
        v2.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upgrade-v2-test-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // 1. A version 2 database with a recipe, a spirit and a bottle.
        let oldContainer = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: v2)
        oldContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        try load(oldContainer)
        let oldContext = oldContainer.viewContext
        let spirit = NSEntityDescription.insertNewObject(forEntityName: "Spirit", into: oldContext)
        spirit.setValue(UUID(), forKey: "id")
        spirit.setValue("Bourbon", forKey: "spiritName")
        let bottle = NSEntityDescription.insertNewObject(forEntityName: "Bottle", into: oldContext)
        bottle.setValue(UUID(), forKey: "id")
        bottle.setValue("Buffalo Trace", forKey: "brand")
        bottle.setValue(spirit, forKey: "spirit")
        let drink = NSEntityDescription.insertNewObject(forEntityName: "Drink", into: oldContext)
        drink.setValue(UUID(), forKey: "id")
        drink.setValue("Old Fashioned", forKey: "drinkName")
        try oldContext.save()
        for store in oldContainer.persistentStoreCoordinator.persistentStores {
            try oldContainer.persistentStoreCoordinator.remove(store)
        }

        // 2. Open it with the current model.
        let newContainer = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: DataController.model)
        newContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        try load(newContainer)
        let context = newContainer.viewContext

        let upgradedDrink = try XCTUnwrap(try context.fetch(NSFetchRequest<Drink>(entityName: "Drink")).first)
        XCTAssertEqual(upgradedDrink.drinkName, "Old Fashioned")
        XCTAssertFalse(upgradedDrink.isFavorite, "Existing cocktails start as not favorite")
        let upgradedBottle = try XCTUnwrap(try context.fetch(NSFetchRequest<Bottle>(entityName: "Bottle")).first)
        XCTAssertEqual(upgradedBottle.brand, "Buffalo Trace")
        XCTAssertEqual(upgradedBottle.spirit?.spiritName, "Bourbon")

        upgradedDrink.isFavorite = true
        XCTAssertNoThrow(try context.save())
    }

    private func load(_ container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }
}

// MARK: - Built-in spirits and cocktails

final class SeedDataTests: XCTestCase {
    private var dataController: DataController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        dataController = DataController(inMemory: true)
        context = dataController.container.viewContext
        defaultsSuite = "SeedDataTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults = nil
        context = nil
        dataController = nil
    }

    // MARK: Seed data itself

    func testBuiltInNamesAreUniqueAndSpiritsExist() {
        let names = (SeedData.classics + SeedData.favorites).map { $0.name.lowercased() }
        XCTAssertEqual(names.count, Set(names).count, "Every built-in cocktail needs a unique name")

        let spiritNames = Set(SeedData.spirits.map(\.name))
        for cocktail in SeedData.classics + SeedData.favorites {
            XCTAssertTrue(spiritNames.contains(cocktail.spirit), "\(cocktail.name) uses unknown spirit \(cocktail.spirit)")
            XCTAssertFalse(cocktail.ingredients.isEmpty, "\(cocktail.name) has no ingredients")
            XCTAssertFalse(cocktail.method.isEmpty, "\(cocktail.name) has no method")
        }
    }

    func testSeedDataHasNoKnownTypos() {
        let allText = (SeedData.classics + SeedData.favorites)
            .flatMap { [$0.name, $0.ingredientsText, $0.methodText] }
            .joined(separator: "\n")
        for fix in SeedData.typoFixes {
            XCTAssertFalse(allText.contains(fix.typo), "Seed data still contains \"\(fix.typo)\"")
        }
        XCTAssertFalse(allText.contains("Daquiri"))
    }

    // MARK: Fresh install

    func testFreshInstallAddsEverythingWithBaseSpirits() throws {
        DataController.seedIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(try spirits().count, SeedData.spirits.count)
        let drinks = try self.drinks()
        XCTAssertEqual(drinks.count, SeedData.classics.count)

        let spiritNamesByID = Dictionary(uniqueKeysWithValues: try spirits().map { ($0.id!, $0.spiritName!) })
        for seed in SeedData.classics {
            let drink = try XCTUnwrap(drinks.first { $0.drinkName == seed.name }, "\(seed.name) missing")
            XCTAssertEqual(drink.baseSpirit.flatMap { spiritNamesByID[$0] }, seed.spirit, "\(seed.name) has the wrong base spirit")
            XCTAssertEqual(drink.ingredients, seed.ingredientsText)
            XCTAssertEqual(drink.source, SourceType.classic.rawValue)
        }
    }

    func testRunningAgainAddsNothing() throws {
        DataController.seedIfNeeded(context: context, defaults: defaults)
        DataController.seedIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(try spirits().count, SeedData.spirits.count)
        XCTAssertEqual(try drinks().count, SeedData.classics.count)
    }

    // MARK: Existing install (the database on your phone)

    func testExistingInstallGetsNewSpiritsAndClassics() throws {
        makeOriginalInstall()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        let spiritNames = Set(try spirits().compactMap(\.spiritName))
        for name in ["Rye", "Mezcal", "Pisco", "Aperol"] {
            XCTAssertTrue(spiritNames.contains(name), "\(name) should be added")
        }
        XCTAssertEqual(try spirits().count, SeedData.spirits.count)

        let drinkNames = try drinks().compactMap(\.drinkName)
        XCTAssertEqual(drinkNames.count, SeedData.classics.count, "Every classic exactly once")
        XCTAssertTrue(drinkNames.contains("Negroni"))
        XCTAssertTrue(drinkNames.contains("Daiquiri"))
        XCTAssertFalse(drinkNames.contains("Daquiri"), "Daquiri should be renamed, not duplicated")
    }

    func testUneditedOriginalClassicsGetTheUpdatedRecipe() throws {
        makeOriginalInstall()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        for name in ["Margarita", "Old Fashioned", "Martini", "Daiquiri", "Cosmopolitan"] {
            let drink = try XCTUnwrap(try drinks().first { $0.drinkName == name })
            let seed = try XCTUnwrap(SeedData.classics.first { $0.name == name })
            XCTAssertEqual(drink.ingredients, seed.ingredientsText, "\(name) ingredients should be updated")
            XCTAssertEqual(drink.method, seed.methodText, "\(name) method should be updated")
        }
    }

    func testEditedClassicKeepsYourEditsButGetsTypoFixed() throws {
        let original = try XCTUnwrap(SeedData.originalClassicRecipes["Margarita"])
        let margarita = makeDrink("Margarita", ingredients: original.ingredients + ", Splash of orange juice", method: original.method)
        try context.save()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        let ingredients = try XCTUnwrap(margarita.ingredients)
        XCTAssertTrue(ingredients.contains("Splash of orange juice"), "Your edit should be kept")
        XCTAssertTrue(ingredients.contains("Triple Sec"))
        XCTAssertFalse(ingredients.contains("Tripe Sec"))
    }

    func testFavoritesTyposAreFixed() throws {
        let renewal = makeDrink("Bourbon Renewal", ingredients: "2 parts Bourbon", method: "Add igredients to a cocktail shaker")
        let cherry = makeDrink("Cherry Bourbon Sour", ingredients: "2 parts bourbon",
                               method: "To and old fashioned glass add the cherries and simple syrup, mull the cherries to a pulp, add a cube of lce")
        try context.save()

        DataController.applySeedCorrections(context: context)

        XCTAssertEqual(renewal.method, "Add ingredients to a cocktail shaker")
        XCTAssertEqual(cherry.method, "To an old fashioned glass add the cherries and simple syrup, muddle the cherries to a pulp, add a cube of ice")
    }

    func testYourOwnDrinksAreNotChanged() throws {
        let mine = makeDrink("Tripe Sec Surprise", ingredients: "1pt Tripe Sec", method: "Shake untile chilled")
        try context.save()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(mine.drinkName, "Tripe Sec Surprise")
        XCTAssertEqual(mine.ingredients, "1pt Tripe Sec", "Only built-in recipes are corrected")
        XCTAssertNil(mine.baseSpirit)
    }

    // MARK: Deleting built-ins

    func testDeletedClassicIsNotAddedBack() throws {
        DataController.seedIfNeeded(context: context, defaults: defaults)
        let negroni = try XCTUnwrap(try drinks().first { $0.drinkName == "Negroni" })
        context.delete(negroni)
        try context.save()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        XCTAssertFalse(try drinks().contains { $0.drinkName == "Negroni" })
    }

    func testDeletedSpiritIsNotAddedBack() throws {
        DataController.seedIfNeeded(context: context, defaults: defaults)
        let aquavit = try XCTUnwrap(try spirits().first { $0.spiritName == "Aquavit" })
        context.delete(aquavit)
        try context.save()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        XCTAssertFalse(try spirits().contains { $0.spiritName == "Aquavit" })
    }

    func testEmptyCollectionIsFilledAgain() throws {
        DataController.seedIfNeeded(context: context, defaults: defaults)
        try drinks().forEach { context.delete($0) }
        try context.save()

        DataController.seedIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(try drinks().count, SeedData.classics.count)
    }

    // MARK: Favorites

    func testAddFavoritesAddsEachOnceWithBaseSpirit() throws {
        DataController.seedIfNeeded(context: context, defaults: defaults)

        DataController.addBillsFaves(context: context)
        DataController.addBillsFaves(context: context)

        let favorites = try drinks().filter { DataController.favoriteCocktailNames.contains($0.drinkName ?? "") }
        XCTAssertEqual(favorites.count, SeedData.favorites.count)
        XCTAssertTrue(favorites.allSatisfy { $0.source == SourceType.original.rawValue })
        XCTAssertTrue(favorites.allSatisfy(\.isFavorite), "House favorites should be marked as favorites")
        let whiskey = try XCTUnwrap(try spirits().first { $0.spiritName == "Whiskey" })
        XCTAssertEqual(favorites.first { $0.drinkName == "Irish Whiskey Sour" }?.baseSpirit, whiskey.id)
    }

    // MARK: Helpers

    /// A database as earlier versions created it: the original nine spirits and five classics, with old text.
    private func makeOriginalInstall() {
        for name in ["Vodka", "Bourbon", "Scotch", "Whiskey", "Rum", "Brandy", "Gin", "Tequila", "Aquavit"] {
            let spirit = Spirit(context: context)
            spirit.id = UUID()
            spirit.spiritName = name
            spirit.type = SpiritType.liquor.rawValue
        }
        for (name, recipe) in SeedData.originalClassicRecipes {
            makeDrink(name == "Daiquiri" ? "Daquiri" : name, ingredients: recipe.ingredients, method: recipe.method)
        }
        try? context.save()
    }

    @discardableResult
    private func makeDrink(_ name: String, ingredients: String, method: String) -> Drink {
        let drink = Drink(context: context)
        drink.id = UUID()
        drink.drinkName = name
        drink.ingredients = ingredients
        drink.method = method
        return drink
    }

    private func drinks() throws -> [Drink] {
        try context.fetch(NSFetchRequest<Drink>(entityName: "Drink"))
    }

    private func spirits() throws -> [Spirit] {
        try context.fetch(NSFetchRequest<Spirit>(entityName: "Spirit"))
    }
}

// MARK: - Cocktail favorites

final class CocktailFavoriteTests: XCTestCase {
    private var dataController: DataController!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        dataController = DataController(inMemory: true)
        context = dataController.container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        dataController = nil
    }

    func testNewCocktailIsNotAFavorite() throws {
        let drink = makeDrink("Martini")
        try context.save()
        XCTAssertFalse(drink.isFavorite)
    }

    func testToggleFavoriteSavesBothWays() throws {
        let drink = makeDrink("Martini")
        try context.save()

        DataController.toggleFavorite(drink, context: context)
        XCTAssertTrue(drink.isFavorite)
        XCTAssertFalse(context.hasChanges, "Toggling should save")

        DataController.toggleFavorite(drink, context: context)
        XCTAssertFalse(drink.isFavorite)
        XCTAssertFalse(context.hasChanges)
    }

    func testFavoritesCanBeFetched() throws {
        let martini = makeDrink("Martini")
        makeDrink("Negroni")
        DataController.toggleFavorite(martini, context: context)

        let request = NSFetchRequest<Drink>(entityName: "Drink")
        request.predicate = NSPredicate(format: "isFavorite == YES")
        XCTAssertEqual(try context.fetch(request), [martini])
    }

    func testSeedingDoesNotChangeFavorites() throws {
        DataController.seedIfNeeded(context: context, defaults: UserDefaults(suiteName: "CocktailFavoriteTests-\(UUID().uuidString)")!)
        let negroni = try XCTUnwrap(try context.fetch(NSFetchRequest<Drink>(entityName: "Drink")).first { $0.drinkName == "Negroni" })
        XCTAssertFalse(negroni.isFavorite, "Classics start as not favorite")

        DataController.toggleFavorite(negroni, context: context)
        DataController.applySeedCorrections(context: context)
        XCTAssertTrue(negroni.isFavorite, "Corrections must not reset favorites")
    }

    @discardableResult
    private func makeDrink(_ name: String) -> Drink {
        let drink = Drink(context: context)
        drink.id = UUID()
        drink.drinkName = name
        return drink
    }
}

// MARK: - Spirit taxonomy (data model refactor, step 1)

final class SpiritTaxonomyTests: XCTestCase {

    // MARK: Families

    func testThirteenFamiliesWithNames() {
        XCTAssertEqual(SpiritFamily.allCases.count, 13)
        XCTAssertEqual(Set(SpiritFamily.allCases.map(\.rawValue)).count, 13)
        for family in SpiritFamily.allCases {
            XCTAssertFalse(family.displayName.isEmpty)
            XCTAssertFalse(family.symbolName.isEmpty)
        }
        XCTAssertEqual(SpiritFamily.allCases.map(\.sortOrder), Array(0..<13))
        XCTAssertEqual(SpiritFamily.other.sortOrder, 12, "Other sorts last")
    }

    func testStoredValuesNeverChange() {
        // These strings are saved in the database. Changing one would orphan stored styles.
        XCTAssertEqual(SpiritFamily.liqueursAndAmari.rawValue, "liqueursAndAmari")
        XCTAssertEqual(SpiritFamily(rawValue: "whiskey"), .whiskey)
        XCTAssertEqual(SpiritFamily(rawValue: "mixersAndSyrups"), .mixersAndSyrups)
    }

    // MARK: Built-in styles

    func testBuiltInStyleNamesAreUnique() {
        let names = SpiritTaxonomy.builtInStyles.map { $0.name.lowercased() }
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testEveryFamilyHasAtLeastOneStyle() {
        for family in SpiritFamily.allCases {
            XCTAssertFalse(SpiritTaxonomy.builtInStyles(in: family).isEmpty, "\(family.displayName) has no styles")
        }
    }

    func testGeneralRumAndBrandyStylesExist() {
        XCTAssertEqual(SpiritTaxonomy.builtInStyle(named: "Rum")?.family, .rum)
        XCTAssertEqual(SpiritTaxonomy.builtInStyle(named: "Brandy")?.family, .brandy)
        XCTAssertEqual(SpiritTaxonomy.builtInStyles(in: .rum).first?.name, "Rum", "The general style is listed first")
        XCTAssertEqual(SpiritTaxonomy.builtInStyles(in: .brandy).first?.name, "Brandy")
    }

    func testFindStyleIgnoresCaseAndSpaces() {
        XCTAssertEqual(SpiritTaxonomy.builtInStyle(named: "  sweet vermouth ")?.name, "Sweet Vermouth")
        XCTAssertNil(SpiritTaxonomy.builtInStyle(named: "Moonshine"))
    }

    // MARK: Mapping today's spirits

    func testEveryCurrentBuiltInSpiritMapsAsPlanned() throws {
        let expected: [String: (SpiritFamily, String)] = [
            "Bourbon": (.whiskey, "Bourbon"),
            "Rye": (.whiskey, "Rye"),
            "Scotch": (.whiskey, "Scotch"),
            "Whiskey": (.whiskey, "Irish Whiskey"),
            "Gin": (.gin, "London Dry"),
            "Rum": (.rum, "Rum"),
            "Tequila": (.agave, "Tequila Blanco"),
            "Mezcal": (.agave, "Mezcal"),
            "Brandy": (.brandy, "Brandy"),
            "Pisco": (.brandy, "Pisco"),
            "Vodka": (.vodka, "Vodka"),
            "Aperol": (.liqueursAndAmari, "Aperitivo"),
            "Aquavit": (.other, "Aquavit")
        ]
        XCTAssertEqual(Set(expected.keys), Set(SeedData.spirits.map(\.name)), "Every current seed spirit is covered")

        for seed in SeedData.spirits {
            let placement = SpiritTaxonomy.placement(forLegacySpirit: seed.name, type: seed.type)
            let (family, style) = try XCTUnwrap(expected[seed.name])
            XCTAssertEqual(placement.family, family, seed.name)
            XCTAssertEqual(placement.styleName, style, seed.name)
            XCTAssertTrue(placement.isBuiltIn, seed.name)
        }
    }

    func testMappingIgnoresCaseAndSpaces() {
        let placement = SpiritTaxonomy.placement(forLegacySpirit: "  bourbon ", type: .liquor)
        XCTAssertEqual(placement, .init(family: .whiskey, styleName: "Bourbon", isBuiltIn: true))
    }

    func testYourSpiritMatchingABuiltInStyleUsesIt() {
        let placement = SpiritTaxonomy.placement(forLegacySpirit: "Amaro", type: .liqueur)
        XCTAssertEqual(placement, .init(family: .liqueursAndAmari, styleName: "Amaro", isBuiltIn: true))
    }

    func testYourSpiritIsPlacedByTellingWord() {
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Japanese Whiskey Blend", type: .liquor),
                       .init(family: .whiskey, styleName: "Japanese Whiskey Blend", isBuiltIn: false))
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Lillet Blanc", type: .liquor).family, .vermouthAndFortified)
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Cachaça", type: .liquor).family, .rum)
    }

    func testGingerIsNotGin() {
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Ginger Liqueur", type: .liquor).family, .liqueursAndAmari)
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Ginger Beer", type: .beer).family, .mixersAndSyrups,
                       "Ginger beer is a mixer, even if it was saved as Beer")
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Old Tom Gin", type: .liquor).family, .gin)
    }

    func testSpiritNamedLikeAnIngredientUsesItsStyle() {
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Campari", type: .liqueur),
                       .init(family: .liqueursAndAmari, styleName: "Aperitivo", isBuiltIn: true))
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Prosecco", type: .wine).styleName, "Sparkling Wine")
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Cointreau", type: .liqueur).styleName, "Orange Liqueur")
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Ginger Beer", type: .beer).styleName, "Ginger Beer & Ale")
    }

    func testExplicitTypeBeatsAWordInTheName() {
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Sloe Gin", type: .liqueur),
                       .init(family: .liqueursAndAmari, styleName: "Sloe Gin", isBuiltIn: false))
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Sloe Gin", type: .liquor).family, .gin,
                       "Saved as plain Liquor, the word decides")
    }

    func testOldTypeDecidesWhenTheNameDoesNot() {
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "House Red", type: .wine).family, .wine)
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Something Herbal", type: .liqueur).family, .liqueursAndAmari)
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Junmai", type: .sake).family, .other)
        XCTAssertEqual(SpiritTaxonomy.placement(forLegacySpirit: "Mystery Spirit", type: .liquor),
                       .init(family: .other, styleName: "Mystery Spirit", isBuiltIn: false))
    }
}

// MARK: - Ingredient parser (data model refactor, step 2)

final class IngredientParserTests: XCTestCase {

    private func line(_ text: String) -> ParsedIngredient {
        IngredientParser.parseLine(text)
    }

    // MARK: Lines from the plan

    func testPartsLine() {
        let gin = line("2 parts Gin")
        XCTAssertEqual(gin.amount, 2)
        XCTAssertEqual(gin.unit, .part)
        XCTAssertEqual(gin.name, "Gin")
        XCTAssertEqual(gin.styleName, "London Dry")
        XCTAssertFalse(gin.needsReview)
        XCTAssertEqual(gin.original, "2 parts Gin")
    }

    func testOlderPtLine() {
        let tequila = line("2pt Tequila")
        XCTAssertEqual(tequila.amount, 2)
        XCTAssertEqual(tequila.unit, .part)
        XCTAssertEqual(tequila.name, "Tequila")
        XCTAssertEqual(tequila.styleName, "Tequila Blanco")
    }

    func testOuncesBecomePartsOneToOne() {
        let gin = line("2½ oz Gin")
        XCTAssertEqual(gin.amount, 2.5)
        XCTAssertEqual(gin.unit, .part)
        XCTAssertFalse(gin.needsReview)
    }

    func testDashRange() {
        let bitters = line("2–3 dashes Angostura Bitters")
        XCTAssertEqual(bitters.amount, 2)
        XCTAssertEqual(bitters.amountMax, 3)
        XCTAssertEqual(bitters.unit, .dash)
        XCTAssertEqual(bitters.name, "Angostura Bitters")
        XCTAssertEqual(bitters.styleName, "Aromatic Bitters")
    }

    func testTeaspoonBecomesBarspoon() {
        let benedictine = line("1 tsp Bénédictine")
        XCTAssertEqual(benedictine.amount, 1)
        XCTAssertEqual(benedictine.unit, .barspoon)
        XCTAssertEqual(benedictine.styleName, "Herbal Liqueur")
    }

    func testTopUp() {
        let soda = line("Club soda, to top")
        XCTAssertNil(soda.amount)
        XCTAssertEqual(soda.unit, .topUp)
        XCTAssertEqual(soda.name, "Club soda")
        XCTAssertNil(soda.note)
        XCTAssertEqual(soda.styleName, "Tonic & Soda")
    }

    func testTopWithIsATopUp() {
        let ginger = line("Top with ginger beer")
        XCTAssertEqual(ginger.unit, .topUp)
        XCTAssertEqual(ginger.name, "ginger beer")
        XCTAssertEqual(ginger.styleName, "Ginger Beer & Ale")
        XCTAssertEqual(line("Top up with soda water").unit, .topUp)
    }

    func testGarnish() {
        let peel = line("Orange peel, to garnish")
        XCTAssertTrue(peel.isGarnish)
        XCTAssertEqual(peel.unit, .piece)
        XCTAssertEqual(peel.name, "Orange peel")
        XCTAssertNil(peel.styleName)
    }

    func testOptionalCount() {
        let egg = line("1 Egg White (optional)")
        XCTAssertEqual(egg.amount, 1)
        XCTAssertEqual(egg.unit, .piece)
        XCTAssertEqual(egg.name, "Egg White")
        XCTAssertTrue(egg.isOptional)
    }

    // MARK: Amounts

    func testFractions() {
        XCTAssertEqual(line("¾ oz Lime Juice").amount, 0.75)
        XCTAssertEqual(line("1/2 oz Lime Juice").amount, 0.5)
        XCTAssertEqual(line("1 1/2 oz Gin").amount, 1.5)
        XCTAssertEqual(line("1 ½ oz Gin").amount, 1.5)
        XCTAssertEqual(line(".5pt Simple Syrup").amount, 0.5)
        XCTAssertEqual(line("1¼ oz Bourbon").amount, 1.25)
    }

    func testRangeOfParts() {
        let syrup = line(".5-1 part Simple Syrup")
        XCTAssertEqual(syrup.amount, 0.5)
        XCTAssertEqual(syrup.amountMax, 1)
        XCTAssertEqual(syrup.unit, .part)
        XCTAssertEqual(syrup.styleName, "Syrup")
    }

    func testTablespoonIsHalfAPart() {
        XCTAssertEqual(line("1 tbsp Honey Syrup").amount, 0.5)
        XCTAssertEqual(line("1 tbsp Honey Syrup").unit, .part)
    }

    func testMetricIsConvertedAndFlagged() {
        let gin = line("45 ml Gin")
        XCTAssertEqual(gin.amount ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(gin.unit, .part)
        XCTAssertTrue(gin.needsReview, "Converted from ml, so worth a look")
        XCTAssertEqual(line("4.5 cl Gin").amount ?? 0, 1.5, accuracy: 0.001)
    }

    // MARK: Notes and flags

    func testNotesAreKept() {
        XCTAssertEqual(line("¼ oz Islay Scotch, to float").note, "to float")
        XCTAssertEqual(line("¼ oz Islay Scotch, to float").styleName, "Scotch")
        let honey = line("¾ oz Honey Syrup (equal parts honey and warm water)")
        XCTAssertEqual(honey.name, "Honey Syrup")
        XCTAssertEqual(honey.note, "equal parts honey and warm water")
        let salt = line("Salt, for the rim (optional)")
        XCTAssertEqual(salt.name, "Salt")
        XCTAssertEqual(salt.note, "for the rim")
        XCTAssertTrue(salt.isOptional)
    }

    func testOptionalWordings() {
        XCTAssertTrue(line("Optional .5 parts Agave Nectar").isOptional)
        XCTAssertEqual(line("Optional .5 parts Agave Nectar").amount, 0.5)
        XCTAssertTrue(line(".5 parts simple syrup (if desired)").isOptional)
    }

    func testOlderRecipesListGarnishesWithoutSayingSo() {
        XCTAssertTrue(line("Orange Peel").isGarnish)
        XCTAssertTrue(line("Olive").isGarnish)
        XCTAssertTrue(line("Orange Twist").isGarnish)
        XCTAssertFalse(line("Egg White").isGarnish)
        XCTAssertFalse(line("Topo Chico").isGarnish)
    }

    // MARK: Styles

    func testGingerIsNotGin() {
        XCTAssertEqual(line("4 oz Ginger Beer").styleName, "Ginger Beer & Ale")
        XCTAssertEqual(line("¾ oz Honey-Ginger Syrup").styleName, "Syrup")
    }

    func testCountedItemsAreNotLinkedToAStyle() {
        let cherries = line("3-4 Luxardo or bourbon soaked cherries")
        XCTAssertEqual(cherries.amount, 3)
        XCTAssertEqual(cherries.amountMax, 4)
        XCTAssertEqual(cherries.unit, .piece)
        XCTAssertNil(cherries.styleName, "Cherries aren't bourbon")
    }

    func testFreshIngredientsHaveNoStyle() {
        XCTAssertNil(line("1 oz Fresh Lime Juice").styleName)
        XCTAssertNil(line("1 oz Heavy Cream").styleName)
        XCTAssertNil(line(".5 parts Peanut butter Whiskey").styleName)
    }

    func testEveryAliasPointsToARealStyle() {
        for alias in IngredientParser.styleAliases {
            XCTAssertNotNil(SpiritTaxonomy.builtInStyle(named: alias.style), "\(alias.alias) → \(alias.style) is not a built-in style")
        }
    }

    // MARK: Things to flag

    func testUnclearLinesAreFlagged() {
        XCTAssertTrue(line("Bourbon 2 oz").needsReview, "Amount after the name")
        XCTAssertTrue(line("2/0 oz Gin").needsReview, "Unreadable amount")
        XCTAssertTrue(line(String(repeating: "Shake with ice ", count: 8)).needsReview, "A sentence, not an ingredient")
    }

    // MARK: Whole recipes

    func testAllBuiltInClassicsParseWithoutReview() {
        for cocktail in SeedData.classics {
            let recipe = IngredientParser.parse(cocktail.ingredientsText)
            XCTAssertEqual(recipe.ingredients.count, cocktail.ingredients.count, cocktail.name)
            XCTAssertFalse(recipe.needsReview, "\(cocktail.name): \(recipe.ingredients.filter(\.needsReview).map(\.original))")
            for ingredient in recipe.ingredients where ingredient.original.first?.isNumber == true {
                XCTAssertNotNil(ingredient.amount, "\(cocktail.name): \(ingredient.original)")
            }
        }
    }

    func testEveryClassicsBaseSpiritAppearsInItsIngredients() {
        // Each classic's base spirit should be recognised among its ingredients (same family at least).
        for cocktail in SeedData.classics {
            let recipe = IngredientParser.parse(cocktail.ingredientsText)
            let families = Set(recipe.ingredients.compactMap { $0.styleName.flatMap(SpiritTaxonomy.builtInStyle(named:))?.family })
            let baseFamily = SpiritTaxonomy.placement(forLegacySpirit: cocktail.spirit, type: .liquor).family
            XCTAssertTrue(families.contains(baseFamily), "\(cocktail.name): no \(baseFamily.displayName) ingredient found")
        }
    }

    func testHouseFavoritesParseWithoutReview() {
        for cocktail in SeedData.favorites {
            let recipe = IngredientParser.parse(cocktail.ingredientsText)
            XCTAssertFalse(recipe.ingredients.isEmpty, cocktail.name)
            XCTAssertFalse(recipe.needsReview, "\(cocktail.name): \(recipe.ingredients.filter(\.needsReview).map(\.original))")
        }
    }

    func testOriginalFiveClassicsParseWithoutReview() {
        for (name, recipe) in SeedData.originalClassicRecipes {
            XCTAssertFalse(IngredientParser.parse(recipe.ingredients).needsReview, name)
        }
    }

    func testCommaSeparatedRecipe() {
        let recipe = IngredientParser.parse("2pt Light Rum, 1pt Lime Juice, .5pt Simple Syrup")
        XCTAssertEqual(recipe.ingredients.map(\.name), ["Light Rum", "Lime Juice", "Simple Syrup"])
        XCTAssertEqual(recipe.ingredients.map(\.amount), [2, 1, 0.5])
        XCTAssertEqual(recipe.ingredients.map(\.styleName), ["White Rum", nil, "Syrup"])
    }

    func testCommaSeparatedRecipeKeepsNotesWithTheirLine() {
        let recipe = IngredientParser.parse("2 oz Gin, 1 oz Lemon Juice, Lemon twist, to garnish")
        XCTAssertEqual(recipe.ingredients.count, 3)
        XCTAssertTrue(recipe.ingredients[2].isGarnish)
    }

    func testEmptyTextHasNoIngredients() {
        XCTAssertTrue(IngredientParser.parse("").ingredients.isEmpty)
        XCTAssertFalse(IngredientParser.parse("  \n ").needsReview)
    }
}

// MARK: - SwiftData models (data model refactor, phase 3)

final class SwiftDataModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: Schema

    func testSchemaVersions() {
        XCTAssertEqual(DB.models.count, 9, "Version 3 adds Library and SyncRecord")
        XCTAssertEqual(DB.versionIdentifier, Schema.Version(3, 0, 0), "The app uses version 3")
        XCTAssertEqual(CocktailSchemaV1.versionIdentifier, Schema.Version(1, 0, 0), "Version 1 is kept for upgrades")
        XCTAssertEqual(CocktailSchemaV1.models.count, 7)
        XCTAssertEqual(CocktailSchemaV2.versionIdentifier, Schema.Version(2, 0, 0), "Version 2 is kept for upgrades")
        XCTAssertEqual(CocktailSchemaV2.models.count, 7)
        XCTAssertEqual(CocktailMigrationPlan.schemas.count, 3)
        XCTAssertEqual(CocktailMigrationPlan.stages.count, 2, "Two steps: version 1 to 2, then 2 to 3")
    }

    // MARK: Defaults and enums

    func testDefaultsAndEnumsRoundTrip() throws {
        let style = DB.SpiritStyle(name: "Bourbon", family: .whiskey, isBuiltIn: true)
        let bottle = DB.Bottle(brand: "Buffalo Trace")
        let cocktail = DB.Cocktail(name: "Old Fashioned", source: .classic)
        let ingredient = DB.RecipeIngredient(position: 0, name: "Bourbon", amount: 2, unit: .part)
        context.insert(style)
        context.insert(bottle)
        context.insert(cocktail)
        context.insert(ingredient)
        try context.save()

        XCTAssertEqual(style.family, .whiskey)
        XCTAssertEqual(bottle.stock, .full)
        XCTAssertEqual(bottle.bottleCount, 1)
        XCTAssertFalse(bottle.isFavorite)
        XCTAssertEqual(cocktail.source, .classic)
        XCTAssertFalse(cocktail.needsIngredientReview)
        XCTAssertEqual(ingredient.unit, .part)

        bottle.stock = .low
        style.family = .liqueursAndAmari
        cocktail.source = .website
        ingredient.unit = .dash
        XCTAssertEqual(bottle.stockLevelRaw, Int(StockLevel.low.rawValue))
        XCTAssertEqual(style.familyRaw, "liqueursAndAmari")
        XCTAssertEqual(cocktail.sourceRaw, "website")
        XCTAssertEqual(ingredient.unitRaw, "dash")
    }

    func testUnknownStoredValuesFallBackSafely() {
        let style = DB.SpiritStyle(name: "Mystery", family: .other)
        style.familyRaw = "notAFamily"
        XCTAssertEqual(style.family, .other)
        let cocktail = DB.Cocktail(name: "Mystery")
        cocktail.sourceRaw = "unknown"
        XCTAssertEqual(cocktail.source, .original)
    }

    func testLegacySourceMapping() {
        XCTAssertEqual(CocktailSource(legacy: .classic), .classic)
        XCTAssertEqual(CocktailSource(legacy: .website), .website)
        XCTAssertEqual(CocktailSource(legacy: .menu), .menu)
        XCTAssertEqual(CocktailSource(legacy: .original), .original)
    }

    // MARK: Relationships

    func testLinksWorkBothWays() throws {
        let bourbon = insertStyle("Bourbon", .whiskey)
        let bottle = DB.Bottle(brand: "Buffalo Trace")
        context.insert(bottle)
        bottle.style = bourbon
        let cocktail = DB.Cocktail(name: "Old Fashioned")
        context.insert(cocktail)
        cocktail.baseStyle = bourbon
        try context.save()

        XCTAssertEqual(bourbon.bottles?.map(\.brand), ["Buffalo Trace"])
        XCTAssertEqual(bourbon.cocktails?.map(\.name), ["Old Fashioned"])
        XCTAssertEqual(bottle.style?.family, .whiskey)
    }

    func testIngredientsKeepRecipeOrder() throws {
        let cocktail = insertCocktail("Negroni", ingredients: ["Gin", "Campari", "Sweet Vermouth"])
        try context.save()
        XCTAssertEqual(cocktail.orderedIngredients.map(\.name), ["Gin", "Campari", "Sweet Vermouth"])
    }

    func testIngredientFromParsedLine() {
        let parsed = IngredientParser.parseLine("2–3 dashes Angostura Bitters")
        let ingredient = DB.RecipeIngredient(parsed: parsed, position: 4)
        XCTAssertEqual(ingredient.position, 4)
        XCTAssertEqual(ingredient.name, "Angostura Bitters")
        XCTAssertEqual(ingredient.amount, 2)
        XCTAssertEqual(ingredient.amountMax, 3)
        XCTAssertEqual(ingredient.unit, .dash)
    }

    // MARK: Delete rules

    func testDeletingACocktailRemovesItsIngredientsAndMenuEntries() throws {
        let cocktail = insertCocktail("Negroni", ingredients: ["Gin", "Campari", "Sweet Vermouth"])
        let menu = insertMenu("Friday Night", cocktails: [cocktail])
        try context.save()
        XCTAssertEqual(try count(DB.RecipeIngredient.self), 3)
        XCTAssertEqual(try count(DB.MenuEntry.self), 1)

        context.delete(cocktail)
        try context.save()

        XCTAssertEqual(try count(DB.RecipeIngredient.self), 0)
        XCTAssertEqual(try count(DB.MenuEntry.self), 0, "No orphaned menu entries")
        XCTAssertEqual(try count(DB.Menu.self), 1, "The menu itself stays")
        XCTAssertEqual(menu.entries?.count ?? 0, 0)
    }

    func testDeletingAMenuRemovesItsEntriesButKeepsCocktails() throws {
        let negroni = insertCocktail("Negroni", ingredients: ["Gin"])
        let martini = insertCocktail("Martini", ingredients: ["Gin"])
        let menu = insertMenu("Friday Night", cocktails: [negroni, martini])
        try context.save()

        context.delete(menu)
        try context.save()

        XCTAssertEqual(try count(DB.MenuEntry.self), 0)
        XCTAssertEqual(try count(DB.Cocktail.self), 2)
        XCTAssertEqual(negroni.menuEntries?.count ?? 0, 0)
    }

    func testDeletingAStyleKeepsWhatUsedIt() throws {
        let gin = insertStyle("London Dry", .gin)
        let bottle = DB.Bottle(brand: "Tanqueray")
        context.insert(bottle)
        bottle.style = gin
        let cocktail = insertCocktail("Martini", ingredients: ["Gin"])
        cocktail.baseStyle = gin
        cocktail.orderedIngredients.first?.style = gin
        try context.save()

        context.delete(gin)
        try context.save()

        XCTAssertEqual(try count(DB.Bottle.self), 1)
        XCTAssertNil(bottle.style)
        XCTAssertEqual(try count(DB.Cocktail.self), 1)
        XCTAssertNil(cocktail.baseStyle)
        XCTAssertEqual(try count(DB.RecipeIngredient.self), 1)
        XCTAssertNil(cocktail.orderedIngredients.first?.style)
    }

    func testDeletingABottleChangesNothingElse() throws {
        let gin = insertStyle("London Dry", .gin)
        let bottle = DB.Bottle(brand: "Tanqueray")
        context.insert(bottle)
        bottle.style = gin
        try context.save()

        context.delete(bottle)
        try context.save()

        XCTAssertEqual(try count(DB.SpiritStyle.self), 1)
        XCTAssertEqual(gin.bottles?.count ?? 0, 0)
    }

    // MARK: Fetching

    func testFetchFavorites() throws {
        let negroni = insertCocktail("Negroni", ingredients: [])
        _ = insertCocktail("Martini", ingredients: [])
        negroni.isFavorite = true
        try context.save()

        let favorites = try context.fetch(FetchDescriptor<DB.Cocktail>(predicate: #Predicate { $0.isFavorite }))
        XCTAssertEqual(favorites.map(\.name), ["Negroni"])
    }

    // MARK: Helpers

    private func insertStyle(_ name: String, _ family: SpiritFamily) -> DB.SpiritStyle {
        let style = DB.SpiritStyle(name: name, family: family)
        context.insert(style)
        return style
    }

    private func insertCocktail(_ name: String, ingredients names: [String]) -> DB.Cocktail {
        let cocktail = DB.Cocktail(name: name)
        context.insert(cocktail)
        for (position, ingredientName) in names.enumerated() {
            let ingredient = DB.RecipeIngredient(position: position, name: ingredientName, amount: 1, unit: .part)
            context.insert(ingredient)
            ingredient.cocktail = cocktail
        }
        return cocktail
    }

    @discardableResult
    private func insertMenu(_ name: String, cocktails: [DB.Cocktail]) -> DB.Menu {
        let menu = DB.Menu(name: name)
        context.insert(menu)
        for (position, cocktail) in cocktails.enumerated() {
            let entry = DB.MenuEntry(position: position)
            context.insert(entry)
            entry.menu = menu
            entry.cocktail = cocktail
        }
        return menu
    }

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}

// MARK: - Stores (data model refactor, phase 3)

/// Shared setup: an in-memory database with the built-in styles.
class StoreTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
        try ModelSeeder.addMissingStyles(context: context, defaults: nil)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func style(_ name: String) throws -> DB.SpiritStyle {
        try XCTUnwrap(try StyleStore(context: context).style(named: name), "No style named \(name)")
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}

final class StyleStoreTests: StoreTestCase {
    private var styles: StyleStore { StyleStore(context: context) }

    func testBuiltInStylesAreThereInOrder() throws {
        XCTAssertEqual(try count(DB.SpiritStyle.self), SpiritTaxonomy.builtInStyles.count)
        XCTAssertEqual(try styles.styles(in: .rum).map(\.name), ["Rum", "White Rum", "Aged Rum", "Dark Rum", "Rhum Agricole"])
        XCTAssertEqual(try styles.allStyles().first?.name, "Bourbon", "Whiskey is the first family")
    }

    func testAddYourOwnStyle() throws {
        let style = try styles.addStyle(name: "  Overproof Rum ", family: .rum)
        XCTAssertEqual(style.name, "Overproof Rum")
        XCTAssertFalse(style.isBuiltIn)
        XCTAssertEqual(try styles.styles(in: .rum).last?.name, "Overproof Rum", "Your styles come after the built-ins")
    }

    func testStyleNamesMustBeUniqueAndPresent() throws {
        XCTAssertThrowsError(try styles.addStyle(name: "bourbon", family: .whiskey)) {
            XCTAssertEqual($0 as? StoreError, .duplicateName("bourbon"))
        }
        XCTAssertThrowsError(try styles.addStyle(name: "  ", family: .other)) {
            XCTAssertEqual($0 as? StoreError, .missingName("style name"))
        }
        let rye = try style("Rye")
        XCTAssertThrowsError(try styles.update(rye, name: "Bourbon", family: .whiskey))
        XCTAssertNoThrow(try styles.update(rye, name: "Rye Whiskey", family: .whiskey), "Renaming to a new name is fine")
    }

    func testDeletingAStyleKeepsItsBottles() throws {
        let bottle = try BottleStore(context: context).addBottle(brand: "Buffalo Trace", style: try style("Bourbon"))
        try styles.delete(try style("Bourbon"))
        XCTAssertEqual(try count(DB.Bottle.self), 1)
        XCTAssertNil(bottle.style)
    }
}

final class BottleStoreTests: StoreTestCase {
    private var bottles: BottleStore { BottleStore(context: context) }

    func testAddBottle() throws {
        let bottle = try bottles.addBottle(brand: " Buffalo Trace ", style: try style("Bourbon"), stock: .half, bottleCount: 2,
                                           notes: "Go-to", isFavorite: true, rating: 8)
        XCTAssertEqual(bottle.brand, "Buffalo Trace")
        XCTAssertEqual(bottle.style?.name, "Bourbon")
        XCTAssertEqual(bottle.stock, .half)
        XCTAssertEqual(bottle.bottleCount, 2)
        XCTAssertTrue(bottle.isFavorite)
        XCTAssertFalse(context.hasChanges)
    }

    func testInvalidBottlesAreRejectedAndNotSaved() throws {
        XCTAssertThrowsError(try bottles.addBottle(brand: " ", style: nil))
        XCTAssertThrowsError(try bottles.addBottle(brand: "Tito's", style: nil, bottleCount: -1)) {
            XCTAssertEqual($0 as? StoreError, .invalidBottleCount)
        }
        XCTAssertThrowsError(try bottles.addBottle(brand: "Tito's", style: nil, rating: 11)) {
            XCTAssertEqual($0 as? StoreError, .invalidRating)
        }
        XCTAssertEqual(try count(DB.Bottle.self), 0)
    }

    func testFilters() throws {
        try bottles.addBottle(brand: "Buffalo Trace", style: try style("Bourbon"), stock: .low, isFavorite: true)
        try bottles.addBottle(brand: "Rittenhouse", style: try style("Rye"), stock: .full)
        try bottles.addBottle(brand: "Tanqueray", style: try style("London Dry"), stock: .out)

        XCTAssertEqual(try bottles.bottles(family: .whiskey).map(\.brand), ["Buffalo Trace", "Rittenhouse"])
        XCTAssertEqual(try bottles.bottles(style: try style("Rye")).map(\.brand), ["Rittenhouse"])
        XCTAssertEqual(try bottles.bottles(favoritesOnly: true).map(\.brand), ["Buffalo Trace"])
        XCTAssertEqual(try bottles.shoppingList().map(\.brand), ["Buffalo Trace", "Tanqueray"])
        XCTAssertEqual(try bottles.inStockBottles().map(\.brand), ["Buffalo Trace", "Rittenhouse"])
    }

    func testStockAndCountRules() throws {
        let bottle = try bottles.addBottle(brand: "Buffalo Trace", style: nil, bottleCount: 1)
        try bottles.setBottleCount(0, for: bottle)
        XCTAssertEqual(bottle.stock, .out)
        try bottles.setStock(.full, for: bottle)
        XCTAssertEqual(bottle.bottleCount, 1)
    }

    func testFailedUpdateIsUndone() throws {
        let bottle = try bottles.addBottle(brand: "Buffalo Trace", style: nil, notes: "Original")
        XCTAssertThrowsError(try bottles.update(bottle) {
            $0.notes = "Changed"
            $0.brand = ""
        })
        XCTAssertEqual(bottle.brand, "Buffalo Trace")
        XCTAssertEqual(bottle.notes, "Original")
    }
}

final class CocktailStoreTests: StoreTestCase {
    private var cocktails: CocktailStore { CocktailStore(context: context) }

    func testAddCocktailWithIngredientsInParts() throws {
        let negroni = try cocktails.addCocktail(
            name: "Negroni", source: .classic, baseStyle: try style("London Dry"),
            ingredients: IngredientParser.parse("1 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth\nOrange peel, to garnish").ingredients
        )
        let rows = negroni.orderedIngredients
        XCTAssertEqual(rows.map(\.name), ["Gin", "Campari", "Sweet Vermouth", "Orange peel"])
        XCTAssertEqual(rows.map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(rows.prefix(3).map(\.unit), [.part, .part, .part])
        XCTAssertEqual(rows.map { $0.style?.name }, ["London Dry", "Aperitivo", "Sweet Vermouth", nil])
        XCTAssertTrue(rows[3].isGarnish)
        XCTAssertFalse(negroni.needsIngredientReview)
        XCTAssertEqual(negroni.baseStyle?.family, .gin)
    }

    func testUncertainIngredientsFlagTheCocktail() throws {
        let cocktail = try cocktails.addCocktail(name: "Metric Martini", ingredients: IngredientParser.parse("60 ml Gin\n10 ml Dry Vermouth").ingredients)
        XCTAssertTrue(cocktail.needsIngredientReview)
    }

    func testReplacingIngredientsRemovesTheOldOnes() throws {
        let cocktail = try cocktails.addCocktail(name: "Gimlet", ingredients: IngredientParser.parse("2 oz Gin\n¾ oz Lime\n¾ oz Simple Syrup").ingredients)
        try cocktails.setIngredients(fromText: "2 parts Gin\n1 part Lime Cordial", for: cocktail)
        XCTAssertEqual(cocktail.orderedIngredients.map(\.name), ["Gin", "Lime Cordial"])
        XCTAssertEqual(try count(DB.RecipeIngredient.self), 2, "Old rows are deleted, not left behind")
    }

    func testCocktailNeedsANameAndValidRating() throws {
        XCTAssertThrowsError(try cocktails.addCocktail(name: "  "))
        XCTAssertThrowsError(try cocktails.addCocktail(name: "Too Good", rating: 11))
        XCTAssertEqual(try count(DB.Cocktail.self), 0)
        XCTAssertEqual(try count(DB.RecipeIngredient.self), 0)
    }

    func testSearchAndFilters() throws {
        let oldFashioned = try cocktails.addCocktail(name: "Old Fashioned", baseStyle: try style("Bourbon"),
                                                     ingredients: IngredientParser.parse("2 oz Bourbon\n¼ oz Simple Syrup").ingredients, rating: 9)
        try cocktails.addCocktail(name: "Manhattan", baseStyle: try style("Rye"),
                                  ingredients: IngredientParser.parse("2 oz Rye Whiskey\n1 oz Sweet Vermouth").ingredients, rating: 9)
        try cocktails.addCocktail(name: "Negroni", baseStyle: try style("London Dry"),
                                  ingredients: IngredientParser.parse("1 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth").ingredients, rating: 7)
        try cocktails.setFavorite(true, for: oldFashioned)

        XCTAssertEqual(try cocktails.cocktails(family: .whiskey).map(\.name), ["Manhattan", "Old Fashioned"])
        XCTAssertEqual(try cocktails.cocktails(style: try style("Rye")).map(\.name), ["Manhattan"])
        XCTAssertEqual(try cocktails.cocktails(matching: "vermouth").map(\.name), ["Manhattan", "Negroni"], "Search covers ingredients")
        XCTAssertEqual(try cocktails.cocktails(matching: "old").map(\.name), ["Old Fashioned"])
        XCTAssertEqual(try cocktails.cocktails(favoritesOnly: true).map(\.name), ["Old Fashioned"])
        XCTAssertEqual(try cocktails.cocktails(sortedBy: .rating).map(\.name), ["Manhattan", "Old Fashioned", "Negroni"])
    }

    func testDeletingACocktailRemovesItEverywhere() throws {
        let negroni = try cocktails.addCocktail(name: "Negroni", ingredients: IngredientParser.parse("1 oz Gin\n1 oz Campari").ingredients)
        let menu = try MenuStore(context: context).addMenu(name: "Friday Night")
        try MenuStore(context: context).add([negroni], to: menu)

        try cocktails.delete(negroni)

        XCTAssertEqual(try count(DB.RecipeIngredient.self), 0)
        XCTAssertEqual(try count(DB.MenuEntry.self), 0)
        XCTAssertEqual(try count(DB.Menu.self), 1)
    }
}

/// The list of ingredients to pick from (pick-from-list entry, step 1).
final class IngredientCatalogTests: XCTestCase {
    private func names(_ items: [CatalogItem]) -> [String] { items.map(\.name) }

    func testBuiltInListIsConsistent() {
        let keys = IngredientCatalog.builtIn.map(\.id)
        XCTAssertEqual(Set(keys).count, keys.count, "Each built-in ingredient appears once")
        XCTAssertGreaterThanOrEqual(keys.count, 90)
        for item in IngredientCatalog.builtIn {
            if let type = item.styleName {
                XCTAssertNotNil(SpiritTaxonomy.builtInStyle(named: type), "\(item.name): \(type) should be a built-in type")
            }
        }
        let catalog = IngredientCatalog()
        XCTAssertEqual(catalog.item(named: "Angostura Bitters")?.usualUnit, .dash)
        XCTAssertEqual(catalog.item(named: "Club Soda")?.usualUnit, .topUp)
        XCTAssertEqual(catalog.item(named: "Orange Peel")?.isGarnish, true)
        XCTAssertEqual(catalog.item(named: "Bourbon")?.group, .spirits)
    }

    func testRecipesCountUsesAndFreshMatchesPlain() {
        let catalog = IngredientCatalog(used: [
            UsedIngredient(name: "Fresh Lime Juice", unit: .part),
            UsedIngredient(name: "Lime Juice", unit: .part),
            UsedIngredient(name: "Bourbon", styleName: "Bourbon", family: .whiskey, unit: .part),
            UsedIngredient(name: "Light Rum", styleName: "White Rum", family: .rum, unit: .part),
        ])
        XCTAssertEqual(catalog.item(named: "Lime Juice")?.useCount, 2, "\"Fresh Lime Juice\" counts as Lime Juice")
        XCTAssertNil(catalog.items.first { $0.name == "Fresh Lime Juice" }, "No duplicate for the fresh version")
        let lightRum = catalog.item(named: "Light Rum")
        XCTAssertEqual(lightRum?.isBuiltIn, false)
        XCTAssertEqual(lightRum?.group, .spirits)
        XCTAssertEqual(names(catalog.mostUsed()), ["Lime Juice", "Bourbon", "Light Rum"])
    }

    func testItemsYouAddUseYourUsualMeasure() {
        let catalog = IngredientCatalog(used: [
            UsedIngredient(name: "Velvet Falernum", unit: .part),
            UsedIngredient(name: "Velvet Falernum", unit: .part),
            UsedIngredient(name: "Velvet Falernum", unit: .barspoon),
            UsedIngredient(name: "Candied ginger", unit: .piece, isGarnish: true),
        ])
        XCTAssertEqual(catalog.item(named: "Velvet Falernum")?.usualUnit, .part)
        let ginger = catalog.item(named: "candied ginger")
        XCTAssertEqual(ginger?.group, .garnishes)
        XCTAssertEqual(ginger?.isGarnish, true)
    }

    func testMyBarBottlesShowBesideTheirType() {
        let catalog = IngredientCatalog(bottles: [
            OwnedBottle(brand: "Buffalo Trace", styleName: "Bourbon", family: .whiskey),
            OwnedBottle(brand: "Campari", styleName: "Aperitivo", family: .liqueursAndAmari),
            OwnedBottle(brand: "Smith & Cross", styleName: "Navy Rum", family: .rum),
        ])
        XCTAssertEqual(catalog.item(named: "Bourbon")?.bottleBrands, ["Buffalo Trace"])
        XCTAssertEqual(catalog.item(named: "Campari")?.bottleBrands, ["Campari"])
        XCTAssertEqual(catalog.item(named: "Aperol")?.bottleBrands, [], "Another aperitivo isn't marked as owned")
        XCTAssertEqual(catalog.item(named: "Navy Rum")?.group, .spirits, "A type of your own gets an item")
        XCTAssertEqual(names(catalog.inMyBar), ["Bourbon", "Campari", "Navy Rum"])
    }

    func testSearchRanksBestMatchesFirst() {
        let catalog = IngredientCatalog()
        XCTAssertEqual(catalog.search("bour").first?.name, "Bourbon")
        XCTAssertEqual(catalog.search("ang").first?.name, "Angostura Bitters")
        XCTAssertEqual(catalog.search("angostra").first?.name, "Angostura Bitters", "A one-letter typo still finds it")
        XCTAssertEqual(catalog.search("lime").prefix(3).map(\.name), ["Lime Juice", "Lime Wedge", "Lime Wheel"])
        let simple = names(catalog.search("simple"))
        XCTAssertEqual(simple.first, "Simple Syrup")
        XCTAssertTrue(simple.contains("Rich Simple Syrup"))
        XCTAssertEqual(catalog.search("creme de").first?.name.hasPrefix("Crème de"), true, "Accents don't matter")
        XCTAssertTrue(catalog.search("").isEmpty)
        XCTAssertTrue(catalog.search("xyzzy").isEmpty)
    }

    func testSearchPrefersWhatYouUseMost() {
        let catalog = IngredientCatalog(used: Array(repeating: UsedIngredient(name: "Lime Wheel", unit: .piece, isGarnish: true), count: 3))
        XCTAssertEqual(catalog.search("lime").first?.name, "Lime Wheel")
    }

    func testSuggestionsWhileTyping() {
        let catalog = IngredientCatalog()
        XCTAssertEqual(catalog.suggestions(for: "ang").first?.name, "Angostura Bitters")
        XCTAssertEqual(catalog.suggestions(for: "lime").map(\.name).prefix(3), ["Lime Juice", "Lime Wedge", "Lime Wheel"])
        XCTAssertFalse(catalog.suggestions(for: "Bourbon").contains { $0.name == "Bourbon" },
                       "A name typed in full isn't offered again")
        XCTAssertEqual(catalog.suggestions(for: "s", limit: 3).count, 3)
        XCTAssertTrue(catalog.suggestions(for: "  ").isEmpty)
    }

    func testNewItemsGuessTheirTypeAndMeasure() {
        let syrup = IngredientCatalog.newItem(named: " Smoked Maple Syrup ")
        XCTAssertEqual(syrup.name, "Smoked Maple Syrup")
        XCTAssertEqual(syrup.styleName, "Syrup")
        XCTAssertEqual(syrup.group, .syrups)
        XCTAssertEqual(syrup.usualUnit, .part)

        XCTAssertEqual(IngredientCatalog.newItem(named: "Blood Orange Juice").group, .juices)

        let bitters = IngredientCatalog.newItem(named: "Celery Bitters")
        XCTAssertEqual(bitters.group, .bitters)
        XCTAssertEqual(bitters.usualUnit, .dash)

        let twist = IngredientCatalog.newItem(named: "Grapefruit Twist")
        XCTAssertTrue(twist.isGarnish)
        XCTAssertEqual(twist.group, .garnishes)

        XCTAssertEqual(IngredientCatalog.newItem(named: "Plantation Pineapple Rum").group, .spirits)
    }
}

/// Turning a measure, an amount and a picked ingredient into a recipe row (pick-from-list entry, step 2).
final class QuickMeasureTests: XCTestCase {
    private func item(_ name: String) -> CatalogItem {
        IngredientCatalog().item(named: name) ?? IngredientCatalog.newItem(named: name)
    }

    func testTheOldFashionedByTaps() {
        let rows = [
            QuickMeasure.parts.row(for: item("Bourbon"), amount: 2, style: nil),
            QuickMeasure.dashes.row(for: item("Angostura Bitters"), amount: 4, style: nil),
            QuickMeasure.parts.row(for: item("Simple Syrup"), amount: 1, style: nil),
            QuickMeasure.garnish.row(for: item("Orange Peel"), amount: 2, style: nil),
        ]
        XCTAssertEqual(rows.map(\.displayText),
                       ["2 parts Bourbon", "4 dashes Angostura Bitters", "1 part Simple Syrup", "Orange Peel, to garnish"])
        XCTAssertTrue(rows[3].isGarnish)
        XCTAssertNil(rows[3].amount, "A garnish has no amount")
    }

    func testOtherMeasures() {
        XCTAssertEqual(QuickMeasure.topUp.row(for: item("Club Soda"), amount: nil, style: nil).displayText, "Club Soda, to top")
        XCTAssertEqual(QuickMeasure.count.row(for: item("Egg White"), amount: 1, style: nil).displayText, "1 Egg White")
        XCTAssertEqual(QuickMeasure.parts.row(for: item("Lime Juice"), amount: 0.75, style: nil).displayText, "¾ part Lime Juice")
        XCTAssertEqual(QuickMeasure.barspoons.row(for: item("Absinthe"), amount: nil, style: nil).displayText, "1 barspoon Absinthe",
                       "No amount picked uses the measure's default")
    }

    func testEveryAmountReadsBackThroughTheParser() {
        for measure in QuickMeasure.allCases {
            XCTAssertEqual(measure.defaultAmount == nil, measure.amounts.isEmpty, "\(measure.rawValue)")
            for amount in measure.amounts {
                let row = measure.row(for: item("Gin"), amount: amount, style: nil)
                let reread = IngredientParser.parseLine(row.displayText)
                XCTAssertEqual(reread.amount ?? -1, amount, accuracy: 0.001, "\(row.displayText)")
                XCTAssertEqual(reread.unit, row.unit, "\(row.displayText)")
            }
        }
    }
}

/// Opening an ingredient's row: its usual measure and the amount to highlight.
final class QuickMeasureSuggestionTests: XCTestCase {
    func testEachIngredientOpensInItsUsualMeasure() {
        let catalog = IngredientCatalog()
        func measure(_ name: String) -> QuickMeasure? { catalog.item(named: name).map(QuickMeasure.init(for:)) }
        XCTAssertEqual(measure("Bourbon"), .parts)
        XCTAssertEqual(measure("Angostura Bitters"), .dashes)
        XCTAssertEqual(measure("Absinthe"), .barspoons)
        XCTAssertEqual(measure("Egg White"), .count)
        XCTAssertEqual(measure("Club Soda"), .topUp)
        XCTAssertEqual(measure("Orange Peel"), .garnish)
        XCTAssertEqual(measure("Salt"), .noAmount)
        XCTAssertTrue(QuickMeasure.garnish.amounts.isEmpty && QuickMeasure.topUp.amounts.isEmpty,
                      "Garnishes and top-ups add with one tap")
    }

    func testYourUsualAmountIsHighlightedAndOffered() {
        let catalog = IngredientCatalog(used: [
            UsedIngredient(name: "Bourbon", unit: .part, amount: 1.75, recipe: "a"),
            UsedIngredient(name: "Simple Syrup", unit: .part, amount: 0.75, recipe: "a"),
        ])
        let bourbon = catalog.item(named: "Bourbon")!
        XCTAssertEqual(QuickMeasure.parts.highlightedAmount(for: bourbon), 1.75)
        XCTAssertEqual(QuickMeasure.parts.amounts(for: bourbon), [0.25, 0.5, 0.75, 1, 1.5, 1.75, 2, 2.5, 3],
                       "An unusual usual amount gets its own button")
        let syrup = catalog.item(named: "Simple Syrup")!
        XCTAssertEqual(QuickMeasure.parts.highlightedAmount(for: syrup), 0.75)
        XCTAssertEqual(QuickMeasure.parts.amounts(for: syrup), QuickMeasure.parts.amounts)
        XCTAssertEqual(QuickMeasure.barspoons.highlightedAmount(for: syrup), 1, "Another measure highlights its default")
        XCTAssertNil(QuickMeasure.garnish.highlightedAmount(for: syrup))
    }

    func testNoAmountRow() {
        let salt = IngredientCatalog().item(named: "Salt")!
        let row = QuickMeasure.noAmount.row(for: salt, amount: nil, style: nil)
        XCTAssertEqual(row.displayText, "Salt")
        XCTAssertFalse(row.isGarnish)
    }
}

/// Picked rows keep the type the picker linked.
final class QuickAddStoreTests: StoreTestCase {
    func testPickedRowsSaveWithTheirType() throws {
        let bourbon = try style("Bourbon")
        let catalog = IngredientCatalog()
        let rows = [
            QuickMeasure.parts.row(for: try XCTUnwrap(catalog.item(named: "Bourbon")), amount: 2, style: bourbon),
            QuickMeasure.dashes.row(for: try XCTUnwrap(catalog.item(named: "Angostura Bitters")), amount: 4, style: try style("Aromatic Bitters")),
        ]
        let cocktail = try CocktailStore(context: context).addCocktail(name: "Tapped Old Fashioned", baseStyle: bourbon, rows: rows)
        XCTAssertEqual(cocktail.orderedIngredients.map { $0.style?.name }, ["Bourbon", "Aromatic Bitters"])
        XCTAssertFalse(cocktail.needsIngredientReview)
    }
}

/// Usual amounts and Goes With suggestions (pick-from-list entry, option 2, step 1).
final class IngredientSuggestionTests: XCTestCase {
    private func used(_ name: String, _ amount: Double?, _ unit: IngredientUnit = .part, in recipe: String,
                      garnish: Bool = false) -> UsedIngredient {
        UsedIngredient(name: name, unit: unit, isGarnish: garnish, amount: amount, recipe: recipe)
    }

    /// Four small recipes: an Old Fashioned, a Manhattan, a Whiskey Sour and a Gimlet.
    private var catalog: IngredientCatalog {
        IngredientCatalog(used: [
            used("Bourbon", 2, in: "old fashioned"), used("Angostura Bitters", 2, .dash, in: "old fashioned"),
            used("Simple Syrup", 0.25, in: "old fashioned"), used("Orange Peel", nil, .unspecified, in: "old fashioned", garnish: true),
            used("Rye Whiskey", 2, in: "manhattan"), used("Sweet Vermouth", 1, in: "manhattan"),
            used("Angostura Bitters", 2, .dash, in: "manhattan"),
            used("Bourbon", 2, in: "whiskey sour"), used("Fresh Lemon Juice", 0.75, in: "whiskey sour"),
            used("Simple Syrup", 0.75, in: "whiskey sour"),
            used("Gin", 2, in: "gimlet"), used("Lime Juice", 0.75, in: "gimlet"), used("Simple Syrup", 0.75, in: "gimlet"),
        ])
    }

    func testUsualAmountFollowsYourRecipes() {
        let catalog = catalog
        XCTAssertEqual(catalog.item(named: "Bourbon")?.usualAmount, 2)
        XCTAssertEqual(catalog.item(named: "Simple Syrup")?.usualAmount, 0.75, "The amount used most wins")
        XCTAssertEqual(catalog.item(named: "Angostura Bitters")?.usualAmount, 2)
        XCTAssertNil(catalog.item(named: "Orange Peel")?.usualAmount, "Garnishes have no amount")
    }

    func testUsualAmountIgnoresOtherMeasuresAndTiesGoLarger() {
        let catalog = IngredientCatalog(used: [
            used("Bourbon", 1.5, in: "a"), used("Bourbon", 2, in: "b"), used("Bourbon", 1, .barspoon, in: "c"),
        ])
        XCTAssertEqual(catalog.item(named: "Bourbon")?.usualAmount, 2, "A tie goes to the larger amount; barspoons don't count")
    }

    func testDefaultsForIngredientsNotUsedYet() {
        let catalog = IngredientCatalog()
        XCTAssertEqual(catalog.item(named: "Mezcal")?.usualAmount, 2)
        XCTAssertEqual(catalog.item(named: "Campari")?.usualAmount, 0.75)
        XCTAssertEqual(catalog.item(named: "Grapefruit Juice")?.usualAmount, 0.75)
        XCTAssertEqual(catalog.item(named: "Orgeat")?.usualAmount, 0.5)
        XCTAssertEqual(catalog.item(named: "Peychaud's Bitters")?.usualAmount, 2)
        XCTAssertEqual(catalog.item(named: "Egg White")?.usualAmount, 1)
        XCTAssertNil(catalog.item(named: "Club Soda")?.usualAmount, "Top-ups have no amount")
        XCTAssertNil(catalog.item(named: "Lemon Twist")?.usualAmount)
        XCTAssertEqual(IngredientCatalog.newItem(named: "Smoked Maple Syrup").usualAmount, 0.5)
        let withBottle = IngredientCatalog(bottles: [OwnedBottle(brand: "Smith & Cross", styleName: "Navy Rum", family: .rum)])
        XCTAssertEqual(withBottle.item(named: "Navy Rum")?.usualAmount, 2)
    }

    func testGoesWithSuggestsWhatYourRecipesPair() {
        let catalog = catalog
        XCTAssertEqual(catalog.goesWith(["Bourbon"]).map(\.name),
                       ["Simple Syrup", "Angostura Bitters", "Lemon Juice", "Orange Peel"])
        XCTAssertEqual(catalog.goesWith(["Bourbon", "Simple Syrup"]).map(\.name),
                       ["Angostura Bitters", "Lemon Juice", "Orange Peel", "Gin", "Lime Juice"],
                       "Picked ingredients are left out, and suggestions for both are added together")
        XCTAssertEqual(catalog.goesWith(["Bourbon"], limit: 2).count, 2)
        XCTAssertTrue(catalog.goesWith([]).isEmpty)
        XCTAssertTrue(catalog.goesWith(["Absinthe"]).isEmpty, "Nothing to suggest for an ingredient no recipe uses")
    }
}

/// Building the ingredient list from the database.
final class IngredientCatalogLoadTests: StoreTestCase {
    func testLoadReadsRecipesAndMyBar() throws {
        try CocktailStore(context: context).addCocktail(
            name: "Old Fashioned", ingredients: IngredientParser.parse("2 oz Bourbon\n2 dashes Angostura Bitters\n¼ oz Simple Syrup").ingredients)
        try BottleStore(context: context).addBottle(brand: "Buffalo Trace", style: try style("Bourbon"))
        let catalog = try IngredientCatalog.load(context: context)
        XCTAssertEqual(catalog.item(named: "Bourbon")?.useCount, 1)
        XCTAssertEqual(catalog.item(named: "Bourbon")?.bottleBrands, ["Buffalo Trace"])
        XCTAssertEqual(catalog.item(named: "Angostura Bitters")?.useCount, 1)
        XCTAssertEqual(catalog.item(named: "Bourbon")?.usualAmount, 2)
        XCTAssertEqual(catalog.goesWith(["Bourbon"]).map(\.name), ["Angostura Bitters", "Simple Syrup"])
    }
}

/// Reading a bottle's label into a brand, type and notes (label scanning, step 1).
/// Each sample is a label typed out as Vision would read it: text, height and position on the photo.
final class LabelMatcherTests: XCTestCase {
    private func suggest(_ lines: [(String, Double, Double)]) -> LabelSuggestion {
        LabelMatcher.suggest(from: lines.map { LabelLine($0.0, height: $0.1, top: $0.2) })
    }

    private func assertLabel(_ lines: [(String, Double, Double)], brand: String, type: String?, family: SpiritFamily,
                             file: StaticString = #filePath, line: UInt = #line) {
        let suggestion = suggest(lines)
        XCTAssertEqual(suggestion.brand, brand, "brand", file: file, line: line)
        XCTAssertEqual(suggestion.styleName, type, "type", file: file, line: line)
        XCTAssertEqual(suggestion.family, family, "family", file: file, line: line)
        if let type {
            XCTAssertNotNil(SpiritTaxonomy.builtInStyle(named: type), "\(type) should be a built-in type", file: file, line: line)
        }
    }

    func testBourbonWithProofAbvAndSize() {
        let label = [("BUFFALO TRACE", 0.12, 0.2), ("KENTUCKY STRAIGHT", 0.05, 0.4), ("BOURBON WHISKEY", 0.07, 0.47),
                     ("Distilled and bottled by Buffalo Trace Distillery, Frankfort, KY", 0.015, 0.85),
                     ("90 PROOF", 0.03, 0.6), ("45% Alc./Vol.", 0.02, 0.65), ("750 ml", 0.02, 0.9)]
        assertLabel(label, brand: "Buffalo Trace", type: "Bourbon", family: .whiskey)
        let suggestion = suggest(label)
        XCTAssertEqual(suggestion.notes, "90 proof · 45% ABV · 750 ml")
        XCTAssertTrue(suggestion.brandAlternatives.isEmpty, "Small print sentences aren't offered as brands")
    }

    func testGinWithCentilitres() {
        let label = [("HENDRICK'S", 0.11, 0.25), ("GIN", 0.08, 0.4), ("DISTILLED IN SCOTLAND", 0.02, 0.55),
                     ("A MOST UNUSUAL GIN", 0.025, 0.6), ("44% vol", 0.02, 0.85), ("70cl", 0.02, 0.9)]
        assertLabel(label, brand: "Hendrick's", type: "London Dry", family: .gin)
        XCTAssertEqual(suggest(label).size, "700 ml")
    }

    func testBrandsWhoseLabelsDontNameAType() {
        assertLabel([("CAMPARI", 0.13, 0.3), ("MILANO", 0.03, 0.45), ("Bitter", 0.03, 0.5), ("24% vol", 0.02, 0.9)],
                    brand: "Campari", type: "Aperitivo", family: .liqueursAndAmari)
        assertLabel([("COINTREAU", 0.1, 0.2), ("L'UNIQUE", 0.04, 0.3), ("40% vol", 0.02, 0.9)],
                    brand: "Cointreau", type: "Orange Liqueur", family: .liqueursAndAmari)
        assertLabel([("ST-GERMAIN", 0.1, 0.2), ("Liqueur", 0.04, 0.3)],
                    brand: "St-Germain", type: "Fruit & Nut Liqueur", family: .liqueursAndAmari)
    }

    func testTequilaReposadoAcrossTwoLines() {
        let label = [("ESPOLÒN", 0.12, 0.2), ("TEQUILA", 0.06, 0.4), ("REPOSADO", 0.06, 0.47),
                     ("100% DE AGAVE", 0.03, 0.55), ("80 PROOF", 0.02, 0.8)]
        assertLabel(label, brand: "Espolòn", type: "Tequila Reposado", family: .agave)
        XCTAssertNil(suggest(label).abv, "\"100% de agave\" isn't an ABV")
    }

    func testCaskNotesInSmallPrintDontChangeTheType() {
        assertLabel([("LAPHROAIG", 0.12, 0.2), ("ISLAY SINGLE MALT", 0.05, 0.4), ("SCOTCH WHISKY", 0.05, 0.46),
                     ("AGED 10 YEARS", 0.04, 0.55), ("Finished in rum casks", 0.01, 0.8), ("43% vol", 0.02, 0.9)],
                    brand: "Laphroaig", type: "Scotch", family: .whiskey)
        assertLabel([("PLANTATION", 0.1, 0.2), ("XAYMACA", 0.05, 0.3), ("JAMAICA RUM", 0.05, 0.38),
                     ("Aged in ex-bourbon casks", 0.015, 0.7)],
                    brand: "Plantation", type: "Aged Rum", family: .rum)
    }

    func testAgeIsRead() {
        let label = [("THE YAMAZAKI", 0.1, 0.2), ("SINGLE MALT JAPANESE WHISKY", 0.05, 0.3),
                     ("AGED 12 YEARS", 0.04, 0.4), ("Product of Japan", 0.015, 0.9)]
        assertLabel(label, brand: "The Yamazaki", type: "Japanese Whisky", family: .whiskey)
        XCTAssertEqual(suggest(label).age, "12")
        XCTAssertEqual(suggest(label).notes, "12 years old")
    }

    func testRyeAndBrandWithTypeOnTheSameLine() {
        assertLabel([("RITTENHOUSE", 0.1, 0.2), ("STRAIGHT RYE WHISKY", 0.05, 0.3), ("100 PROOF", 0.03, 0.5)],
                    brand: "Rittenhouse", type: "Rye", family: .whiskey)
        assertLabel([("BULLEIT BOURBON", 0.1, 0.2), ("FRONTIER WHISKEY", 0.04, 0.3)],
                    brand: "Bulleit", type: "Bourbon", family: .whiskey)
        assertLabel([("OLD FORESTER", 0.1, 0.2), ("KENTUCKY STRAIGHT BOURBON WHISKY", 0.04, 0.3)],
                    brand: "Old Forester", type: "Bourbon", family: .whiskey)
    }

    func testLiqueurBeatsTheSpiritItIsMadeWith() {
        assertLabel([("Kahlúa", 0.12, 0.2), ("Rum & Coffee Liqueur", 0.04, 0.4), ("20% Alc./Vol. (40 Proof)", 0.02, 0.9)],
                    brand: "Kahlúa", type: "Coffee Liqueur", family: .liqueursAndAmari)
        assertLabel([("MAKER'S MARK", 0.1, 0.2), ("BOURBON CREAM LIQUEUR", 0.04, 0.3)],
                    brand: "Maker's Mark", type: "Cream Liqueur", family: .liqueursAndAmari)
    }

    func testVermouthBittersAndRum() {
        assertLabel([("CARPANO", 0.1, 0.2), ("ANTICA FORMULA", 0.06, 0.3), ("VERMOUTH", 0.05, 0.4)],
                    brand: "Carpano", type: "Sweet Vermouth", family: .vermouthAndFortified)
        assertLabel([("DOLIN", 0.1, 0.2), ("DRY", 0.07, 0.3), ("Vermouth de Chambéry", 0.04, 0.38)],
                    brand: "Dolin", type: "Dry Vermouth", family: .vermouthAndFortified)
        assertLabel([("ANGOSTURA", 0.08, 0.2), ("AROMATIC BITTERS", 0.05, 0.3), ("44.7% alc/vol", 0.015, 0.9)],
                    brand: "Angostura", type: "Aromatic Bitters", family: .bitters)
        assertLabel([("DIPLOMÁTICO", 0.1, 0.2), ("RESERVA EXCLUSIVA", 0.05, 0.3), ("RON DE VENEZUELA", 0.04, 0.38)],
                    brand: "Diplomático", type: "Aged Rum", family: .rum)
    }

    func testCognacIsNotSparklingWine() {
        assertLabel([("RÉMY MARTIN", 0.1, 0.2), ("V.S.O.P", 0.06, 0.25), ("FINE CHAMPAGNE COGNAC", 0.04, 0.3)],
                    brand: "Rémy Martin", type: "Cognac", family: .brandy)
        assertLabel([("LA MARCA", 0.1, 0.2), ("PROSECCO", 0.06, 0.3), ("11% alc. by vol.", 0.015, 0.9), ("750 ML", 0.015, 0.92)],
                    brand: "La Marca", type: "Sparkling Wine", family: .wine)
    }

    func testMixersAndVodka() {
        assertLabel([("FEVER-TREE", 0.08, 0.2), ("PREMIUM GINGER BEER", 0.05, 0.3)],
                    brand: "Fever-Tree", type: "Ginger Beer & Ale", family: .mixersAndSyrups)
        assertLabel([("TITO'S", 0.1, 0.2), ("HANDMADE VODKA", 0.05, 0.3)],
                    brand: "Tito's", type: "Vodka", family: .vodka)
    }

    func testNothingReadableGivesAnEmptySuggestion() {
        XCTAssertTrue(LabelMatcher.suggest(from: []).isEmpty)
        XCTAssertTrue(suggest([("   ", 0.1, 0.2)]).isEmpty)
    }

    func testMatchingBrandsIgnoresCaseAccentsAndSmallDifferences() {
        let brands = ["Buffalo Trace", "Hendrick's", "Espolòn", "Rye"]
        XCTAssertEqual(LabelMatcher.matchingBrandIndex("BUFFALO TRACE", in: brands), 0)
        XCTAssertEqual(LabelMatcher.matchingBrandIndex("Buffalo Trace Bourbon", in: brands), 0, "A longer name still matches")
        XCTAssertEqual(LabelMatcher.matchingBrandIndex("Hendricks", in: brands), 1)
        XCTAssertEqual(LabelMatcher.matchingBrandIndex("Espolon", in: brands), 2)
        XCTAssertEqual(LabelMatcher.matchingBrandIndex("Hendrik's", in: brands), 1, "One letter off still matches")
        XCTAssertNil(LabelMatcher.matchingBrandIndex("Bulleit", in: brands))
        XCTAssertNil(LabelMatcher.matchingBrandIndex("Ryes", in: brands), "Short names must match exactly")
    }
}

/// Filling in the bottle form from a scan (label scanning, step 2).
final class LabelScanFormTests: XCTestCase {
    func testLabelNotesAreAddedOnce() {
        XCTAssertEqual(LabelMatcher.mergedNotes("", adding: "90 proof · 750 ml"), "90 proof · 750 ml")
        XCTAssertEqual(LabelMatcher.mergedNotes("Gift from Dad", adding: "90 proof"), "Gift from Dad\n90 proof")
        XCTAssertEqual(LabelMatcher.mergedNotes("Gift from Dad\n90 proof", adding: "90 proof"), "Gift from Dad\n90 proof",
                       "Scanning twice doesn't repeat the notes")
        XCTAssertEqual(LabelMatcher.mergedNotes(" Gift ", adding: ""), "Gift")
    }

    func testEverySuggestedTypeExistsAsABuiltInType() {
        // The form looks the suggested type up by name, so every rule must name a real built-in type.
        let labels: [[LabelLine]] = [
            [LabelLine("BOURBON", height: 0.1)], [LabelLine("LONDON DRY GIN", height: 0.1)],
            [LabelLine("TEQUILA AÑEJO", height: 0.1)], [LabelLine("RHUM AGRICOLE", height: 0.1)],
            [LabelLine("ORANGE BITTERS", height: 0.1)], [LabelLine("PEDRO XIMENEZ SHERRY", height: 0.1)],
            [LabelLine("TAWNY PORT", height: 0.1)], [LabelLine("PINOT NOIR", height: 0.1)],
            [LabelLine("HAZY IPA", height: 0.1)], [LabelLine("HARD CIDER", height: 0.1)],
            [LabelLine("TONIC WATER", height: 0.1)], [LabelLine("GRENADINE", height: 0.1)],
            [LabelLine("JUNMAI SAKE", height: 0.1)], [LabelLine("ABSINTHE", height: 0.1)],
            [LabelLine("CITRON VODKA", height: 0.1)], [LabelLine("CALVADOS", height: 0.1)],
        ]
        for label in labels {
            let suggestion = LabelMatcher.suggest(from: label)
            let type = try? XCTUnwrap(suggestion.styleName, "\(label[0].text) should suggest a type")
            if let type {
                XCTAssertNotNil(SpiritTaxonomy.builtInStyle(named: type), "\(type) should be a built-in type")
            }
        }
    }
}

/// Finding a bottle already in My Bar for a scanned brand.
final class LabelMatcherBottleTests: StoreTestCase {
    func testAddingAnotherBottleBumpsTheCountAndRestocks() throws {
        let bottles = BottleStore(context: context)
        let trace = try bottles.addBottle(brand: "Buffalo Trace", style: try style("Bourbon"), stock: .out, bottleCount: 0)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }

        try bottles.addAnotherBottle(to: trace, photo: photo)
        XCTAssertEqual(trace.bottleCount, 1)
        XCTAssertEqual(trace.stock, .full, "An Out bottle becomes Full")
        XCTAssertNotNil(trace.photo, "The scan's photo fills in a missing label photo")

        let firstPhoto = trace.photo
        trace.stock = .low
        try bottles.addAnotherBottle(to: trace, photo: photo)
        XCTAssertEqual(trace.bottleCount, 2)
        XCTAssertEqual(trace.stock, .low, "The open bottle's level is kept")
        XCTAssertEqual(trace.photo, firstPhoto, "An existing photo isn't replaced")
        XCTAssertEqual(try count(DB.Bottle.self), 1, "No second bottle record is made")
    }

    func testFindsTheExistingBottle() throws {
        let bottles = BottleStore(context: context)
        let trace = try bottles.addBottle(brand: "Buffalo Trace", style: try style("Bourbon"))
        try bottles.addBottle(brand: "Campari", style: try style("Aperitivo"))
        let all = try bottles.bottles()
        XCTAssertTrue(LabelMatcher.existingBottle(matching: "BUFFALO TRACE", in: all) === trace)
        XCTAssertNil(LabelMatcher.existingBottle(matching: "Hendrick's", in: all))
    }
}

/// Cocktail Codex templates and data model version 2.
final class CocktailTemplateTests: StoreTestCase {
    func testTheSixTemplates() {
        XCTAssertEqual(CocktailTemplate.allCases.map(\.displayName),
                       ["Old Fashioned", "Martini", "Daiquiri", "Sidecar", "Highball", "Flip"])
        XCTAssertEqual(CocktailTemplate.daiquiri.formula, "Spirit, citrus and sugar")
        for template in CocktailTemplate.allCases {
            XCTAssertEqual(CocktailTemplate(rawValue: template.rawValue), template)
        }
    }

    func testEveryBuiltInRecipeHasATemplate() {
        for seed in SeedData.classics + SeedData.favorites {
            XCTAssertNotNil(SeedData.templates[seed.name], "\(seed.name) needs a template")
        }
        XCTAssertEqual(SeedData.templates.count, SeedData.classics.count + SeedData.favorites.count, "No templates for unknown recipes")
    }

    func testTemplateIsStoredAsText() throws {
        let cocktail = try CocktailStore(context: context).addCocktail(name: "House Sour")
        XCTAssertNil(cocktail.template, "New recipes start without a template")
        try CocktailStore(context: context).update(cocktail) { $0.template = .sidecar }
        XCTAssertEqual(cocktail.templateRaw, "sidecar")
        cocktail.templateRaw = "notATemplate"
        XCTAssertNil(cocktail.template, "Unknown text reads as no template")
    }

    func testAddingACocktailWithATemplate() throws {
        let cocktail = try CocktailStore(context: context).addCocktail(name: "House Highball", template: .highball)
        XCTAssertEqual(cocktail.template, .highball)
        XCTAssertEqual(try CocktailStore(context: context).cocktails().first?.templateRaw, "highball", "Saved with the cocktail")
    }

    func testSeedingGivesTheClassicsTheirTemplates() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)
        let cocktails = try CocktailStore(context: context).cocktails()
        XCTAssertFalse(cocktails.isEmpty)
        XCTAssertTrue(cocktails.allSatisfy { $0.template != nil }, "Every classic has a template")
        let byName = Dictionary(uniqueKeysWithValues: cocktails.map { ($0.name, $0.template) })
        XCTAssertEqual(byName["Negroni"], .martini)
        XCTAssertEqual(byName["Margarita"], .sidecar)
        XCTAssertEqual(byName["Moscow Mule"], .highball)
    }

    func testFillingInTemplatesNeverChangesOneAlreadySet() throws {
        let store = CocktailStore(context: context)
        let negroni = try store.addCocktail(name: "Negroni")
        let mine = try store.addCocktail(name: "Margarita")
        try store.update(mine) { $0.template = .daiquiri }
        let unknown = try store.addCocktail(name: "House Special")
        try ModelSeeder.fillInTemplates(context: context)
        XCTAssertEqual(negroni.template, .martini, "A classic without a template gets one")
        XCTAssertEqual(mine.template, .daiquiri, "A template you chose is kept")
        XCTAssertNil(unknown.template, "Your own recipes aren't given one automatically")
    }
}

/// Suggesting a recipe's template from its ingredients (cocktail templates, step 2).
final class TemplateSuggesterTests: XCTestCase {
    private func suggest(_ text: String) -> CocktailTemplate? {
        TemplateSuggester.suggest(parsed: IngredientParser.parse(text).ingredients)
    }

    func testEveryBuiltInRecipeGetsItsTemplate() {
        for seed in SeedData.classics + SeedData.favorites {
            XCTAssertEqual(suggest(seed.ingredientsText), SeedData.templates[seed.name], seed.name)
        }
    }

    func testEachRule() {
        XCTAssertEqual(suggest("2 oz Rye\n1 tsp Demerara Syrup\n2 dashes Angostura Bitters"), .oldFashioned)
        XCTAssertEqual(suggest("2 oz Gin\n1 oz Dry Vermouth"), .martini)
        XCTAssertEqual(suggest("2 oz Rum\n1 oz Lime Juice\n¾ oz Simple Syrup"), .daiquiri)
        XCTAssertEqual(suggest("2 oz Brandy\n¾ oz Cointreau\n¾ oz Lemon Juice"), .sidecar)
        XCTAssertEqual(suggest("2 oz Gin\nTonic water, to top"), .highball)
        XCTAssertEqual(suggest("1½ oz Brandy\n1 Whole Egg\n½ oz Simple Syrup"), .flip)
    }

    func testTrickyCases() {
        XCTAssertEqual(suggest("2 oz Pisco\n1 oz Lime Juice\n¾ oz Simple Syrup\n1 Egg White"), .daiquiri,
                       "An egg-white sour is still a Daiquiri, because citrus leads")
        XCTAssertEqual(suggest("1 oz Gin\n½ oz Lemon Juice\n½ oz Simple Syrup\n3 oz Champagne"), .daiquiri,
                       "Sparkling wine with citrus stays with the citrus")
        XCTAssertEqual(suggest("3 oz Prosecco\n2 oz Aperol\n1 oz Club Soda"), .highball)
        XCTAssertEqual(suggest("2 oz Bourbon\n¾ oz Lemon Juice\n¾ oz Simple Syrup\n1 Egg White (optional)"), .daiquiri,
                       "Optional ingredients don't count")
        XCTAssertEqual(suggest("2 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth"), .martini, "A liqueur without citrus doesn't make a Sidecar")
    }

    func testUnsureRecipesGetNoSuggestion() {
        XCTAssertNil(suggest("1 oz Lime Juice\n1 oz Simple Syrup\nClub soda, to top"), "No spirit: nothing to suggest")
        XCTAssertNil(suggest("2 oz Gin"), "A spirit on its own")
        XCTAssertNil(suggest(""))
    }

    func testRowsFromTheForm() {
        let rows = [
            IngredientInput(amount: 2, unit: .part, name: "Bourbon"),
            IngredientInput(amount: 4, unit: .dash, name: "Angostura Bitters"),
            IngredientInput(amount: 1, unit: .part, name: "Simple Syrup"),
            IngredientInput(unit: .unspecified, name: "Orange Peel", isGarnish: true),
        ]
        XCTAssertEqual(TemplateSuggester.suggest(rows: rows), .oldFashioned)
    }
}

/// Databases made with data model versions 1 and 2 upgrade to the current version with everything intact.
final class SchemaMigrationTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes a small version 1 database: a style, a cocktail with an ingredient, a bottle, a menu and the import record.
    private func makeVersion1Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CocktailSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let londonDry = CocktailSchemaV1.SpiritStyle(name: "London Dry", family: .gin, isBuiltIn: true)
        context.insert(londonDry)
        let negroni = CocktailSchemaV1.Cocktail(name: "Negroni", source: .classic, method: "Stir with ice")
        context.insert(negroni)
        negroni.baseStyle = londonDry
        negroni.isFavorite = true
        let gin = CocktailSchemaV1.RecipeIngredient(position: 0, name: "Gin", amount: 1, unit: .part)
        context.insert(gin)
        gin.cocktail = negroni
        gin.style = londonDry
        let bottle = CocktailSchemaV1.Bottle(brand: "Tanqueray", stock: .low, bottleCount: 2)
        context.insert(bottle)
        bottle.style = londonDry
        let menu = CocktailSchemaV1.Menu(name: "Friday Night")
        context.insert(menu)
        let entry = CocktailSchemaV1.MenuEntry(position: 0)
        context.insert(entry)
        entry.menu = menu
        entry.cocktail = negroni
        context.insert(CocktailSchemaV1.ImportRecord(cocktailCount: 1, bottleCount: 1, menuCount: 1))
        try context.save()
    }

    func testVersion1DatabaseUpgradesWithEverythingIntact() throws {
        let url = folder.appendingPathComponent("Cocktails.store")
        try makeVersion1Store(at: url)

        let container = try CocktailModelContainer.make(url: url)
        let context = ModelContext(container)
        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>())
        XCTAssertEqual(cocktails.count, 1)
        let negroni = try XCTUnwrap(cocktails.first)
        XCTAssertEqual(negroni.name, "Negroni")
        XCTAssertEqual(negroni.source, .classic)
        XCTAssertEqual(negroni.method, "Stir with ice")
        XCTAssertTrue(negroni.isFavorite)
        XCTAssertEqual(negroni.baseStyle?.name, "London Dry")
        XCTAssertEqual(negroni.orderedIngredients.map(\.displayText), ["1 part Gin"])
        XCTAssertEqual(negroni.orderedIngredients.first?.style?.name, "London Dry")
        XCTAssertNil(negroni.template, "The new field starts empty")
        XCTAssertNil(negroni.library, "Existing recipes are in My Library")

        let bottle = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Bottle>()).first)
        XCTAssertEqual(bottle.brand, "Tanqueray")
        XCTAssertEqual(bottle.stock, .low)
        XCTAssertEqual(bottle.bottleCount, 2)
        let menu = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Menu>()).first)
        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Negroni"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.ImportRecord>()), 1, "The import doesn't run again")

        // Starting up fills in templates for built-in recipes.
        try ModelSeeder.fillInTemplates(context: context)
        XCTAssertEqual(negroni.template, .martini)
    }

    /// Writes a small version 2 database: a style, a cocktail with a template and an ingredient, a bottle and a menu.
    private func makeVersion2Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CocktailSchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let bourbon = CocktailSchemaV2.SpiritStyle(name: "Bourbon", family: .whiskey, isBuiltIn: true)
        context.insert(bourbon)
        let renewal = CocktailSchemaV2.Cocktail(name: "Bourbon Renewal", source: .original, method: "Shake with ice")
        context.insert(renewal)
        renewal.baseStyle = bourbon
        renewal.template = .sidecar
        let whiskey = CocktailSchemaV2.RecipeIngredient(position: 0, name: "Bourbon", amount: 2, unit: .part)
        context.insert(whiskey)
        whiskey.cocktail = renewal
        whiskey.style = bourbon
        let bottle = CocktailSchemaV2.Bottle(brand: "Buffalo Trace", stock: .full, bottleCount: 1)
        context.insert(bottle)
        bottle.style = bourbon
        let menu = CocktailSchemaV2.Menu(name: "Saturday")
        context.insert(menu)
        let entry = CocktailSchemaV2.MenuEntry(position: 0)
        context.insert(entry)
        entry.menu = menu
        entry.cocktail = renewal
        try context.save()
    }

    func testVersion2DatabaseUpgradesIntoMyLibrary() throws {
        let url = folder.appendingPathComponent("Cocktails.store")
        try makeVersion2Store(at: url)

        let container = try CocktailModelContainer.make(url: url)
        let context = ModelContext(container)
        let renewal = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Cocktail>()).first)
        XCTAssertEqual(renewal.name, "Bourbon Renewal")
        XCTAssertEqual(renewal.template, .sidecar, "The template chosen in version 2 is kept")
        XCTAssertEqual(renewal.baseStyle?.name, "Bourbon")
        XCTAssertEqual(renewal.orderedIngredients.map(\.displayText), ["2 parts Bourbon"])
        XCTAssertNil(renewal.library, "Existing recipes are in My Library")

        let style = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.SpiritStyle>()).first)
        XCTAssertNil(style.library)
        let menu = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Menu>()).first)
        XCTAssertNil(menu.library)
        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Bourbon Renewal"])
        let bottle = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Bottle>()).first)
        XCTAssertEqual(bottle.brand, "Buffalo Trace")
        XCTAssertEqual(bottle.style?.name, "Bourbon")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.Library>()), 0, "No shared libraries yet")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SyncRecord>()), 0, "Nothing has synced yet")
    }
}

/// Built-in spirit types and recipes get the same ID on every device, so iCloud keeps one copy of each.
final class BuiltInIDTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testIDsNeverChange() {
        // These exact values may already be in iCloud; if this fails, the formula changed and must be put back.
        XCTAssertEqual(BuiltInID.cocktail(named: "Negroni").uuidString, "8242F0B7-90A7-552F-8D9C-48B256915DEE")
        XCTAssertEqual(BuiltInID.style(named: "London Dry").uuidString, "7785AE98-20F2-51BA-BDE0-F9BB927AA46C")
    }

    func testIDsIgnoreCaseAndSpacesAndDifferByKind() {
        XCTAssertEqual(BuiltInID.cocktail(named: " negroni "), BuiltInID.cocktail(named: "Negroni"))
        XCTAssertNotEqual(BuiltInID.cocktail(named: "Negroni"), BuiltInID.cocktail(named: "Boulevardier"))
        XCTAssertNotEqual(BuiltInID.cocktail(named: "Bourbon"), BuiltInID.style(named: "Bourbon"))
    }

    func testFreshSeedUsesFixedIDs() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)

        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>())
        XCTAssertEqual(cocktails.count, SeedData.classics.count)
        for cocktail in cocktails {
            XCTAssertEqual(cocktail.id, BuiltInID.cocktail(named: cocktail.name), cocktail.name)
        }
        let styles = try context.fetch(FetchDescriptor<DB.SpiritStyle>())
        XCTAssertEqual(styles.count, SpiritTaxonomy.builtInStyles.count)
        for style in styles {
            XCTAssertEqual(style.id, BuiltInID.style(named: style.name), style.name)
        }
        XCTAssertEqual(Set(cocktails.map(\.id)).count, cocktails.count, "No two recipes share an ID")
    }

    func testHouseFavoritesUseFixedIDs() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)
        try ModelSeeder.addHouseFavorites(context: context)
        let cocktails = try context.fetch(FetchDescriptor<DB.Cocktail>())
        for seed in SeedData.favorites {
            let cocktail = try XCTUnwrap(cocktails.first { $0.name == seed.name }, seed.name)
            XCTAssertEqual(cocktail.id, BuiltInID.cocktail(named: seed.name), seed.name)
        }
    }

    func testExistingBuiltInsGetFixedIDsAndYourOwnKeepTheirs() throws {
        // As in a database made before IDs were fixed: random IDs everywhere.
        let londonDry = DB.SpiritStyle(name: "London Dry", family: .gin, isBuiltIn: true)
        let negroni = DB.Cocktail(name: "Negroni", source: .classic)
        let mine = DB.Cocktail(name: "Bill's Sour", source: .original)
        let myStyle = DB.SpiritStyle(name: "Barrel-Aged Gin", family: .gin)
        [londonDry, myStyle].forEach { context.insert($0) }
        [negroni, mine].forEach { context.insert($0) }
        let mineID = mine.id
        let myStyleID = myStyle.id
        try context.save()

        try ModelSeeder.assignBuiltInIDs(context: context)
        XCTAssertEqual(negroni.id, BuiltInID.cocktail(named: "Negroni"))
        XCTAssertEqual(londonDry.id, BuiltInID.style(named: "London Dry"))
        XCTAssertEqual(mine.id, mineID, "Your own recipes keep their IDs")
        XCTAssertEqual(myStyle.id, myStyleID, "Your own types keep their IDs")

        // Running again changes nothing.
        try ModelSeeder.assignBuiltInIDs(context: context)
        XCTAssertEqual(negroni.id, BuiltInID.cocktail(named: "Negroni"))
        XCTAssertFalse(context.hasChanges)
    }

    func testUpgradedAndFreshDatabasesMatch() throws {
        // Upgraded: classics seeded with random IDs, then fixed at launch.
        for seed in SeedData.classics.prefix(5) {
            context.insert(DB.Cocktail(name: seed.name, source: .classic))
        }
        try context.save()
        try ModelSeeder.assignBuiltInIDs(context: context)
        let upgraded = Set(try context.fetch(FetchDescriptor<DB.Cocktail>()).map(\.id))

        // Fresh: a new database on another device.
        let otherContainer = try CocktailModelContainer.make(inMemory: true)
        let other = ModelContext(otherContainer)
        try ModelSeeder.seedBuiltIns(context: other, defaults: nil)
        let fresh = Set(try other.fetch(FetchDescriptor<DB.Cocktail>()).map(\.id))

        XCTAssertEqual(upgraded.count, 5)
        XCTAssertTrue(upgraded.isSubset(of: fresh), "The same recipes have the same IDs on both devices")
    }

    func testOnlyTheOldestDuplicateGetsTheFixedID() throws {
        let first = DB.Cocktail(name: "Negroni", source: .classic)
        first.dateAdded = Date(timeIntervalSince1970: 0)
        let second = DB.Cocktail(name: "negroni", source: .original)
        second.dateAdded = Date(timeIntervalSince1970: 100)
        context.insert(second)
        context.insert(first)
        let secondID = second.id
        try context.save()

        try ModelSeeder.assignBuiltInIDs(context: context)
        XCTAssertEqual(first.id, BuiltInID.cocktail(named: "Negroni"))
        XCTAssertEqual(second.id, secondID, "IDs stay unique")
    }

    func testItemsInASharedLibraryAreLeftAlone() throws {
        let library = DB.Library(name: "Shared Library", ownerName: "Friend", zoneName: "Library", zoneOwnerName: "_friend")
        context.insert(library)
        let negroni = DB.Cocktail(name: "Negroni", source: .classic)
        context.insert(negroni)
        negroni.library = library
        let sharedID = negroni.id
        try context.save()

        try ModelSeeder.assignBuiltInIDs(context: context)
        XCTAssertEqual(negroni.id, sharedID, "A shared library's IDs come from its owner")
    }
}

/// Libraries shared with you hold their own cocktails, menus and types; My Library is everything else.
final class LibraryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testNewItemsAreInMyLibrary() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)
        let cocktail = try CocktailStore(context: context).addCocktail(name: "Bill's Sour")
        XCTAssertNil(cocktail.library)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DB.Cocktail>()).allSatisfy { $0.library == nil })
        XCTAssertTrue(try context.fetch(FetchDescriptor<DB.SpiritStyle>()).allSatisfy { $0.library == nil })
    }

    func testYourOwnLibraryCanAlwaysBeEdited() {
        let mine = DB.Library(name: "My Library", ownerName: "Bill", zoneName: "Library", zoneOwnerName: "_me", isOwned: true)
        XCTAssertTrue(mine.canEdit)
        let shared = DB.Library(name: "Friend's Library", ownerName: "Friend", zoneName: "Library", zoneOwnerName: "_friend")
        XCTAssertFalse(shared.canEdit, "View only unless the owner allows editing")
    }

    func testRemovingASharedLibraryRemovesOnlyItsItems() throws {
        let gin = DB.SpiritStyle(name: "London Dry", family: .gin, isBuiltIn: true)
        let myNegroni = DB.Cocktail(name: "Negroni", source: .classic)
        let bottle = DB.Bottle(brand: "Tanqueray")
        context.insert(gin)
        context.insert(myNegroni)
        context.insert(bottle)
        bottle.style = gin
        myNegroni.baseStyle = gin

        let library = DB.Library(name: "Friend's Library", ownerName: "Friend", zoneName: "Library", zoneOwnerName: "_friend")
        context.insert(library)
        let theirGin = DB.SpiritStyle(name: "London Dry", family: .gin, isBuiltIn: true)
        let theirNegroni = DB.Cocktail(name: "Negroni", source: .classic)
        let theirIngredient = DB.RecipeIngredient(position: 0, name: "Gin", amount: 1, unit: .part)
        let theirMenu = DB.Menu(name: "Their Party")
        let theirEntry = DB.MenuEntry(position: 0)
        context.insert(theirGin)
        context.insert(theirNegroni)
        context.insert(theirIngredient)
        context.insert(theirMenu)
        context.insert(theirEntry)
        theirGin.library = library
        theirNegroni.library = library
        theirNegroni.baseStyle = theirGin
        theirIngredient.cocktail = theirNegroni
        theirMenu.library = library
        theirEntry.menu = theirMenu
        theirEntry.cocktail = theirNegroni
        try context.save()

        context.delete(library)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<DB.Cocktail>()).map(\.name), ["Negroni"])
        XCTAssertNil(try context.fetch(FetchDescriptor<DB.Cocktail>()).first?.library, "Your Negroni stays")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.Menu>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.MenuEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.RecipeIngredient>()), 0)
        XCTAssertEqual(bottle.style?.name, "London Dry", "My Bar keeps its links")
    }
}

/// Version, build and data model version for the splash screen and Settings.
final class AppInfoTests: XCTestCase {
    func testVersionLines() {
        XCTAssertEqual(AppInfo.versionLine(version: "2.0", build: "3"), "Version 2.0 (3)")
        XCTAssertEqual(AppInfo.dataModelLine("1.0.0"), "Data model 1.0.0")
        XCTAssertEqual(AppInfo.dataModelVersion, "3.0.0", "Matches the current schema (CocktailSchemaV3)")
    }

    func testImportSummaryOnTheAboutScreen() {
        XCTAssertEqual(AboutView.importSummary(DB.ImportRecord(cocktailCount: 31, bottleCount: 1, menuCount: 2)),
                       "31 cocktails · 1 bottle · 2 menus")
    }

    func testVersionComesFromTheBuildSettings() {
        XCTAssertNotEqual(AppInfo.version, "?")
        XCTAssertNotEqual(AppInfo.build, "?")
        XCTAssertNotNil(Int(AppInfo.build), "The build number is a whole number")
    }
}

/// Showing parts converted to ounces or millilitres (data model refactor, phase 6).
final class PartSizeTests: StoreTestCase {
    func testOffShowsNothing() {
        XCTAssertNil(PartSize.off.converted(amount: 2))
        XCTAssertEqual(PartSize.off.displayName, "Parts only")
    }

    func testOunces() {
        XCTAssertEqual(PartSize.oneOunce.converted(amount: 2), "2 oz")
        XCTAssertEqual(PartSize.oneOunce.converted(amount: 0.75), "¾ oz")
        XCTAssertEqual(PartSize.oneOunce.converted(amount: 1.0 / 3), "⅓ oz", "Thirds are kept")
        XCTAssertEqual(PartSize.oneAndAHalfOunces.converted(amount: 2), "3 oz")
        XCTAssertEqual(PartSize.oneAndAHalfOunces.converted(amount: 0.75), "1⅛ oz")
        XCTAssertEqual(PartSize.oneAndAHalfOunces.displayName, "1 part = 1½ oz")
        XCTAssertEqual(PartSize.twoOunces.converted(amount: 1, amountMax: 1.5), "2–3 oz")
    }

    func testMillilitres() {
        XCTAssertEqual(PartSize.thirtyMillilitres.converted(amount: 2), "60 ml")
        XCTAssertEqual(PartSize.thirtyMillilitres.converted(amount: 0.75), "25 ml", "22.5 ml rounds to the nearest 5")
        XCTAssertEqual(PartSize.thirtyMillilitres.converted(amount: 1.0 / 3), "10 ml")
        XCTAssertEqual(PartSize.twentyFiveMillilitres.converted(amount: 0.5), "13 ml", "Under 20 ml rounds to the nearest whole")
        XCTAssertEqual(PartSize.fiftyMillilitres.converted(amount: 1, amountMax: 2), "50–100 ml")
    }

    func testOnlyPartsAreConverted() throws {
        let cocktail = try CocktailStore(context: context).addCocktail(
            name: "Old Fashioned",
            ingredients: IngredientParser.parse("2 oz Bourbon\n2 dashes Angostura Bitters\nOrange peel, to garnish").ingredients
        )
        XCTAssertEqual(cocktail.orderedIngredients.map { PartSize.thirtyMillilitres.converted($0) }, ["60 ml", nil, nil])
    }
}

/// The Inventory tab's stock filter (data model refactor, phase 5).
final class StockFilterTests: XCTestCase {
    func testShoppingListShowsLowAndOutOnly() {
        XCTAssertEqual(StockLevel.allCases.filter(StockFilter.shoppingList.includes), [.low, .out])
        XCTAssertEqual(StockLevel.allCases.filter(StockFilter.inStock.includes), [.full, .half, .low])
        XCTAssertEqual(StockLevel.allCases.filter(StockFilter.all.includes), StockLevel.allCases)
    }
}

/// Ingredient rows as the ingredient editor makes them (data model refactor, phase 6).
final class IngredientRowTests: StoreTestCase {
    private var cocktails: CocktailStore { CocktailStore(context: context) }

    func testRowsKeepTheStylePickedByHand() throws {
        let rows = [
            IngredientInput(amount: 2, unit: .part, name: "House Rum Blend", style: try style("Rum")),
            IngredientInput(amount: 1, unit: .part, name: "Campari"),
        ]
        let cocktail = try cocktails.addCocktail(name: "Jungle-ish", rows: rows)
        let saved = cocktail.orderedIngredients
        XCTAssertEqual(saved.map(\.name), ["House Rum Blend", "Campari"])
        XCTAssertEqual(saved[0].style?.name, "Rum", "A style picked by hand is kept")
        XCTAssertNil(saved[1].style, "A row with no style isn't linked from its name behind the user's back")
    }

    func testRowsFromTextAreLinkedAndFlagged() throws {
        let rows = cocktails.rows(fromText: "2 oz Bourbon\n30 ml Sweet Vermouth\n2 dashes Angostura Bitters")
        XCTAssertEqual(rows.map(\.name), ["Bourbon", "Sweet Vermouth", "Angostura Bitters"])
        let bourbon = try style("Bourbon")
        XCTAssertTrue(rows[0].style === bourbon, "Bourbon is linked to the stored Bourbon style")
        XCTAssertEqual(rows.map(\.needsReview), [false, true, false], "Millilitres are converted and marked for checking")
        XCTAssertEqual(rows[1].amount, 1)
    }

    func testSettingRowsReplacesInOrderAndClearsReview() throws {
        let cocktail = try cocktails.addCocktail(name: "Martini", ingredients: IngredientParser.parse("60 ml Gin\n10 ml Dry Vermouth").ingredients)
        XCTAssertTrue(cocktail.needsIngredientReview)

        var rows = cocktail.orderedIngredients.map { IngredientInput(stored: $0, needsReview: true) }
        rows[0].needsReview = false
        rows[1].needsReview = false
        rows[1].amount = 0.5
        rows.append(IngredientInput(name: "Lemon twist", isGarnish: true))
        rows.swapAt(0, 1)
        try cocktails.setIngredients(rows, for: cocktail)

        XCTAssertEqual(cocktail.orderedIngredients.map(\.displayText), ["½ part Dry Vermouth", "2 parts Gin", "Lemon twist, to garnish"])
        XCTAssertEqual(cocktail.orderedIngredients.map(\.position), [0, 1, 2])
        XCTAssertFalse(cocktail.needsIngredientReview, "Checked rows clear the cocktail's flag")
        XCTAssertEqual(try count(DB.RecipeIngredient.self), 3, "Old rows are deleted, not left behind")
    }

    func testRowEqualityIgnoresIdButNotStyle() throws {
        let first = IngredientInput(amount: 2, unit: .part, name: "Gin", style: try style("London Dry"))
        var second = IngredientInput(amount: 2, unit: .part, name: "Gin", style: try style("London Dry"))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first, second)
        second.style = try style("Old Tom")
        XCTAssertNotEqual(first, second)
        second.style = first.style
        second.note = ""
        XCTAssertEqual(first, second, "An empty note is the same as no note")
    }

    func testStoredRowsRoundTripUnchanged() throws {
        let cocktail = try cocktails.addCocktail(name: "Bee's Knees", rows: cocktails.rows(fromText: "2 oz Gin\n¾ oz Honey Syrup\n¾ oz Lemon Juice\nLemon peel, to garnish (optional)"))
        let loaded = cocktail.orderedIngredients.map { IngredientInput(stored: $0) }
        let reloaded = cocktail.orderedIngredients.map { IngredientInput(stored: $0) }
        XCTAssertEqual(loaded, reloaded, "Untouched rows compare equal, so the form doesn't rewrite them")
        XCTAssertEqual(loaded.map(\.displayText), ["2 parts Gin", "¾ part Honey Syrup", "¾ part Lemon Juice", "Lemon peel, to garnish (optional)"])
        XCTAssertEqual(loaded[0].style?.name, "London Dry")
    }

    func testRangesAndTopUpRows() throws {
        let rows = [
            IngredientInput(amount: 2, amountMax: 3, unit: .dash, name: "Angostura Bitters"),
            IngredientInput(unit: .topUp, name: "Club Soda"),
            IngredientInput(amount: 1, unit: .piece, name: "Egg White", isOptional: true),
        ]
        XCTAssertEqual(rows.map(\.displayText), ["2–3 dashes Angostura Bitters", "Club Soda, to top", "1 Egg White (optional)"])
        for row in rows {
            let reread = IngredientParser.parseLine(row.displayText)
            XCTAssertEqual(reread.name, row.name)
            XCTAssertEqual(reread.unit, row.unit)
            XCTAssertEqual(reread.amountMax, row.amountMax)
        }
    }
}

final class MenuStoreTests: StoreTestCase {
    private var menus: MenuStore { MenuStore(context: context) }

    private func cocktail(_ name: String) throws -> DB.Cocktail {
        try CocktailStore(context: context).addCocktail(name: name)
    }

    func testMenuNeedsAName() {
        XCTAssertThrowsError(try menus.addMenu(name: " ")) {
            XCTAssertEqual($0 as? StoreError, .missingName("menu name"))
        }
    }

    func testAddKeepsOrderAndSkipsDuplicates() throws {
        let menu = try menus.addMenu(name: "Friday Night")
        let negroni = try cocktail("Negroni"), martini = try cocktail("Martini"), gimlet = try cocktail("Gimlet")
        try menus.add([negroni, martini], to: menu)
        try menus.add([martini, gimlet, gimlet], to: menu)

        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Negroni", "Martini", "Gimlet"])
        XCTAssertEqual(menu.orderedEntries.map(\.position), [0, 1, 2])
    }

    func testRemoveClosesTheGap() throws {
        let menu = try menus.addMenu(name: "Friday Night")
        try menus.add([try cocktail("Negroni"), try cocktail("Martini"), try cocktail("Gimlet")], to: menu)

        try menus.remove(menu.orderedEntries[1], from: menu)

        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Negroni", "Gimlet"])
        XCTAssertEqual(menu.orderedEntries.map(\.position), [0, 1])
        XCTAssertEqual(try count(DB.Cocktail.self), 3, "Removing from a menu keeps the cocktail")
    }

    func testMoveReorders() throws {
        let menu = try menus.addMenu(name: "Friday Night")
        try menus.add([try cocktail("Negroni"), try cocktail("Martini"), try cocktail("Gimlet")], to: menu)

        try menus.move(menu.orderedEntries[2], to: 0, in: menu)

        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Gimlet", "Negroni", "Martini"])
    }

    func testRenameAndDelete() throws {
        let menu = try menus.addMenu(name: "Friday Night")
        try menus.add([try cocktail("Negroni")], to: menu)
        try menus.rename(menu, to: " Saturday ")
        XCTAssertEqual(menu.name, "Saturday")

        try menus.delete(menu)
        XCTAssertEqual(try count(DB.Menu.self), 0)
        XCTAssertEqual(try count(DB.MenuEntry.self), 0)
        XCTAssertEqual(try count(DB.Cocktail.self), 1)
    }
}

/// Menus as shared and saved from the Menus tab (data model refactor, phase 5).
final class MenuExporterTests: StoreTestCase {
    private func makeMenu() throws -> DB.Menu {
        let cocktails = CocktailStore(context: context)
        let negroni = try cocktails.addCocktail(name: "Negroni", ingredients: IngredientParser.parse("1 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth").ingredients)
        let daiquiri = try cocktails.addCocktail(name: "Daiquiri", ingredients: IngredientParser.parse("2 oz Rum\n¾ oz Lime Juice\n¾ oz Simple Syrup").ingredients)
        let menus = MenuStore(context: context)
        let menu = try menus.addMenu(name: "Friday Night")
        try menus.add([negroni, daiquiri], to: menu)
        return menu
    }

    func testTextListsCocktailsInMenuOrderWithIngredientsInParts() throws {
        let menu = try makeMenu()
        XCTAssertEqual(MenuExporter.text(for: menu), """
            Friday Night

            Negroni
            1 part Gin · 1 part Campari · 1 part Sweet Vermouth

            Daiquiri
            2 parts Rum · ¾ part Lime Juice · ¾ part Simple Syrup

            """)

        let daiquiri = try XCTUnwrap(menu.orderedEntries.last)
        try MenuStore(context: context).move(daiquiri, to: 0, in: menu)
        XCTAssertTrue(MenuExporter.text(for: menu).hasPrefix("Friday Night\n\nDaiquiri"), "The text follows the menu's order")
    }

    func testSavingWritesATextFile() throws {
        let menu = try makeMenu()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try MenuExporter.saveToFiles(menu, folder: folder)
        XCTAssertEqual(file.lastPathComponent, "Friday Night.txt")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), MenuExporter.text(for: menu))
        XCTAssertEqual(MenuExporter.fileName(for: " 12/24: Party "), "1224 Party.txt")
        XCTAssertEqual(MenuExporter.fileName(for: "  "), "Menu.txt")
    }

    func testDeleteAllMenusKeepsTheCocktails() throws {
        _ = try makeMenu()
        _ = try MenuStore(context: context).addMenu(name: "Holiday Party")
        try MenuStore(context: context).deleteAll()
        XCTAssertEqual(try count(DB.Menu.self), 0)
        XCTAssertEqual(try count(DB.MenuEntry.self), 0)
        XCTAssertEqual(try count(DB.Cocktail.self), 2)
    }
}

final class ModelSeederTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
        suite = "ModelSeederTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        context = nil
        container = nil
    }

    private func cocktails() throws -> [DB.Cocktail] {
        try context.fetch(FetchDescriptor<DB.Cocktail>())
    }

    func testFreshSeedAddsStylesAndClassicsInParts() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count)
        let all = try cocktails()
        XCTAssertEqual(all.count, SeedData.classics.count)
        for seed in SeedData.classics {
            let cocktail = try XCTUnwrap(all.first { $0.name == seed.name }, seed.name)
            XCTAssertEqual(cocktail.baseStyle?.name, ModelSeeder.baseStyleName(for: seed), seed.name)
            XCTAssertEqual(cocktail.orderedIngredients.count, seed.ingredients.count, seed.name)
            XCTAssertFalse(cocktail.needsIngredientReview, seed.name)
            XCTAssertEqual(cocktail.source, .classic)
            XCTAssertEqual(cocktail.method, seed.methodText)
        }
    }

    func testRumAndBrandyCocktailsUseTheGeneralStyles() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        let all = try cocktails()
        XCTAssertEqual(all.first { $0.name == "Mai Tai" }?.baseStyle?.name, "Rum")
        XCTAssertEqual(all.first { $0.name == "Sidecar" }?.baseStyle?.name, "Brandy")
        XCTAssertEqual(all.first { $0.name == "Manhattan" }?.baseStyle?.name, "Rye")
        XCTAssertEqual(all.first { $0.name == "Aperol Spritz" }?.baseStyle?.name, "Aperitivo")
    }

    func testRunningAgainAddsNothing() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        XCTAssertEqual(try cocktails().count, SeedData.classics.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count)
    }

    func testDeletedBuiltInsStayDeleted() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        try CocktailStore(context: context).delete(try XCTUnwrap(try cocktails().first { $0.name == "Negroni" }))
        try StyleStore(context: context).delete(try XCTUnwrap(try StyleStore(context: context).style(named: "Sake")))

        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        XCTAssertFalse(try cocktails().contains { $0.name == "Negroni" })
        XCTAssertNil(try StyleStore(context: context).style(named: "Sake"))
    }

    func testEmptyCollectionIsFilledAgain() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        for cocktail in try cocktails() {
            context.delete(cocktail)
        }
        try context.save()

        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        XCTAssertEqual(try cocktails().count, SeedData.classics.count)
    }

    func testHouseFavorites() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        try ModelSeeder.addHouseFavorites(context: context)
        try ModelSeeder.addHouseFavorites(context: context)

        let favorites = try cocktails().filter { DataController.favoriteCocktailNames.contains($0.name) }
        XCTAssertEqual(favorites.count, SeedData.favorites.count)
        XCTAssertTrue(favorites.allSatisfy { $0.isFavorite && $0.source == .original })
        XCTAssertEqual(favorites.first { $0.name == "Irish Whiskey Sour" }?.baseStyle?.name, "Irish Whiskey")
        XCTAssertFalse(favorites.contains { $0.needsIngredientReview })
    }
}

// MARK: - Legacy importer (data model refactor, phase 4)

final class LegacyImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var folder: URL!
    private var storeURL: URL { folder.appendingPathComponent("CocktailRecipe.sqlite") }

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        context = nil
        container = nil
    }

    // MARK: Version 3 (today's database)

    func testVersion3DatabaseImportsEverything() throws {
        let photo = Data([1, 2, 3, 4])
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            let bourbon = self.spirit("Bourbon", in: old)
            let whiskey = self.spirit("Whiskey", in: old)
            let aperol = self.spirit("Aperol", type: .liqueur, in: old)
            _ = self.spirit("Amaro", type: .liqueur, in: old)
            _ = self.spirit("Japanese Whiskey Blend", in: old)

            let oldFashioned = self.drink("Old Fashioned", base: bourbon, ingredients: "2pt Bourbon, 1pt Simple Syrup, 2-4 dashes Angostura Bitters, Orange Peel", in: old)
            oldFashioned.setValue(Int16(9), forKey: "rating")
            oldFashioned.setValue(true, forKey: "isFavorite")
            oldFashioned.setValue(photo, forKey: "image")
            oldFashioned.setValue(Int16(SourceType.classic.rawValue), forKey: "source")
            _ = self.drink("Irish Whiskey Sour", base: whiskey, ingredients: "2 parts Irish Whiskey, 1 part Lemon Juice, Egg White", in: old)
            let manhattan = self.drink("Manhattan", base: nil, ingredients: "2 oz Rye Whiskey\n1 oz Sweet Vermouth", in: old)
            _ = self.drink("Metric Martini", base: nil, ingredients: "60 ml Gin\n10 ml Dry Vermouth", in: old)

            let buffalo = self.bottle("Buffalo Trace", spirit: bourbon, in: old)
            buffalo.setValue(StockLevel.low.rawValue, forKey: "stockLevel")
            buffalo.setValue(Int16(2), forKey: "bottleCount")
            buffalo.setValue(true, forKey: "isFavorite")
            buffalo.setValue(Int16(8), forKey: "rating")
            buffalo.setValue("Go-to", forKey: "notes")
            _ = self.bottle("Aperol", spirit: aperol, in: old)

            let friday = self.menu("Friday Night", in: old)
            self.menuItem(menu: friday, drink: oldFashioned, in: old)
            self.menuItem(menu: friday, drink: manhattan, in: old)
            self.menuItem(menu: friday, drink: oldFashioned, in: old) // duplicate
            self.menuItem(menu: friday, drink: nil, in: old)          // orphan
            self.menuItem(menu: nil, drink: manhattan, in: old)       // no menu
        }

        let summary = try importer().runImport()

        XCTAssertEqual(summary, ImportSummary(cocktails: 4, bottles: 2, menus: 1, menuEntries: 2, customStyles: 1, cocktailsNeedingReview: 1))

        let oldFashioned = try cocktail("Old Fashioned")
        XCTAssertEqual(oldFashioned.baseStyle?.name, "Bourbon")
        XCTAssertEqual(oldFashioned.rating, 9)
        XCTAssertTrue(oldFashioned.isFavorite)
        XCTAssertEqual(oldFashioned.photo, photo)
        XCTAssertEqual(oldFashioned.source, .classic)
        XCTAssertEqual(oldFashioned.originalIngredientsText, "2pt Bourbon, 1pt Simple Syrup, 2-4 dashes Angostura Bitters, Orange Peel")
        XCTAssertEqual(oldFashioned.orderedIngredients.map(\.name), ["Bourbon", "Simple Syrup", "Angostura Bitters", "Orange Peel"])
        XCTAssertEqual(oldFashioned.orderedIngredients.map(\.unit), [.part, .part, .dash, .piece])
        XCTAssertEqual(oldFashioned.orderedIngredients.first?.style?.name, "Bourbon")
        XCTAssertFalse(oldFashioned.needsIngredientReview)

        XCTAssertEqual(try cocktail("Irish Whiskey Sour").baseStyle?.name, "Irish Whiskey")
        XCTAssertEqual(try cocktail("Manhattan").baseStyle?.name, "Rye", "A built-in classic with no link takes its seed style")
        XCTAssertTrue(try cocktail("Metric Martini").needsIngredientReview)
        XCTAssertNil(try cocktail("Metric Martini").baseStyle)

        let bottles = try context.fetch(FetchDescriptor<DB.Bottle>())
        let buffalo = try XCTUnwrap(bottles.first { $0.brand == "Buffalo Trace" })
        XCTAssertEqual(buffalo.style?.name, "Bourbon")
        XCTAssertEqual(buffalo.stock, .low)
        XCTAssertEqual(buffalo.bottleCount, 2)
        XCTAssertTrue(buffalo.isFavorite)
        XCTAssertEqual(buffalo.rating, 8)
        XCTAssertEqual(buffalo.notes, "Go-to")
        XCTAssertEqual(bottles.first { $0.brand == "Aperol" }?.style?.name, "Aperitivo")

        let menu = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Menu>()).first)
        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Manhattan", "Old Fashioned"])

        let styles = StyleStore(context: context)
        XCTAssertEqual(try styles.style(named: "Japanese Whiskey Blend")?.family, .whiskey)
        XCTAssertEqual(try styles.style(named: "Amaro")?.isBuiltIn, true, "Amaro matches the built-in style")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count + 1)
        XCTAssertTrue(importer().hasImported)
    }

    // MARK: Older databases

    func testVersion1DatabaseImports() throws {
        try makeLegacyStore(version: "CocktailRecipe") { old in
            let gin = self.spirit("Gin", in: old)
            let martini = self.drink("Martini", base: gin, ingredients: "1pt Gin, 1pt Dry Vermouth, Olive", in: old)
            martini.setValue(Int16(7), forKey: "rating")
            let menu = self.menu("Date Night", in: old)
            self.menuItem(menu: menu, drink: martini, in: old)
        }

        let summary = try importer().runImport()

        XCTAssertEqual(summary.cocktails, 1)
        XCTAssertEqual(summary.bottles, 0)
        XCTAssertEqual(summary.menuEntries, 1)
        let martini = try cocktail("Martini")
        XCTAssertEqual(martini.baseStyle?.name, "London Dry")
        XCTAssertEqual(martini.rating, 7)
        XCTAssertFalse(martini.isFavorite, "Version 1 had no favorites")
        XCTAssertTrue(martini.orderedIngredients.last?.isGarnish ?? false)
    }

    func testVersion2DatabaseImports() throws {
        try makeLegacyStore(version: "CocktailRecipe 2") { old in
            let rum = self.spirit("Rum", in: old)
            _ = self.drink("Daquiri", base: rum, ingredients: "2pt Light Rum, 1pt Lime Juice, .5pt Simple Syrup", in: old)
            _ = self.bottle("Plantation 3 Stars", spirit: rum, in: old)
        }

        let summary = try importer().runImport()

        XCTAssertEqual(summary.cocktails, 1)
        XCTAssertEqual(summary.bottles, 1)
        let daquiri = try cocktail("Daiquiri")
        XCTAssertNil(try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Daquiri" }, "Renamed during import")
        XCTAssertEqual(daquiri.baseStyle?.name, "Rum", "Rum maps to the general style")
        XCTAssertEqual(daquiri.orderedIngredients.first?.style?.name, "White Rum")
        XCTAssertEqual(try context.fetch(FetchDescriptor<DB.Bottle>()).first?.style?.name, "Rum")
    }

    // MARK: Safety

    func testImportRunsOnlyOnce() throws {
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            _ = self.drink("Negroni", base: nil, ingredients: "1 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth", in: old)
        }

        XCTAssertNotNil(try importer().importIfNeeded())
        XCTAssertNil(try importer().importIfNeeded(), "Second launch does nothing")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.Cocktail>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.ImportRecord>()), 1)
    }

    func testNoOldDatabaseMeansNothingToImport() throws {
        XCTAssertNil(try importer().importIfNeeded())
        XCTAssertFalse(importer().hasImported)
    }

    func testOldDatabaseIsNeverModified() throws {
        try makeLegacyStore(version: "CocktailRecipe 2") { old in
            _ = self.drink("Gimlet", base: nil, ingredients: "2 oz Gin\n¾ oz Lime Juice", in: old)
        }
        let before = try storeFiles()

        try importer().runImport()

        XCTAssertEqual(try storeFiles(), before, "The old database files are byte-for-byte unchanged")
    }

    func testLargeBottlePhotosComeAcross() throws {
        // Big enough that Core Data stores it outside the database file, in the support folder.
        let largePhoto = Data((0..<400_000).map { UInt8($0 % 251) })
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            let bottle = self.bottle("Buffalo Trace", spirit: nil, in: old)
            bottle.setValue(largePhoto, forKey: "image")
        }

        try importer().runImport()

        let bottle = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Bottle>()).first)
        XCTAssertEqual(bottle.photo?.count, largePhoto.count)
        XCTAssertEqual(bottle.photo, largePhoto)
    }

    func testFailedImportLeavesNothingBehind() throws {
        try Data("not a database".utf8).write(to: storeURL)

        XCTAssertThrowsError(try importer().runImport())

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.Cocktail>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.ImportRecord>()), 0, "No marker, so it can try again")
    }

    func testEmptyNamesGetFallbacks() throws {
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            _ = self.drink("   ", base: nil, ingredients: "", in: old)
            _ = self.menu("", in: old)
        }

        try importer().runImport()

        XCTAssertEqual(try context.fetch(FetchDescriptor<DB.Cocktail>()).first?.name, "Untitled Cocktail")
        XCTAssertEqual(try context.fetch(FetchDescriptor<DB.Menu>()).first?.name, "Untitled Menu")
    }

    // MARK: Seeding record

    func testDeletedClassicsStayDeletedAfterImport() throws {
        let suite = "LegacyImporterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // The old app offered Negroni and Martini; the user then deleted Negroni.
        defaults.set(["Martini", "Negroni"], forKey: DataController.seededCocktailsKey)
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            _ = self.drink("Martini", base: nil, ingredients: "2½ oz Gin\n½ oz Dry Vermouth", in: old)
        }

        try importer(defaults: defaults).runImport()
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        let names = Set(try context.fetch(FetchDescriptor<DB.Cocktail>()).map(\.name))
        XCTAssertFalse(names.contains("Negroni"), "Deleted in the old app, so not added back")
        XCTAssertTrue(names.contains("Gimlet"), "Never offered by the old app, so added")
        XCTAssertEqual(names.filter { $0 == "Martini" }.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count)
    }

    // MARK: Helpers

    private func importer(defaults: UserDefaults? = nil) -> LegacyImporter {
        LegacyImporter(context: context, legacyStoreURL: storeURL, defaults: defaults)
    }

    private func cocktail(_ name: String) throws -> DB.Cocktail {
        try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == name }, "No cocktail named \(name)")
    }

    /// Every file in the old database's folder, including inside the hidden support folder, by relative path.
    private func storeFiles() throws -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files[String(url.path.dropFirst(folder.path.count))] = try Data(contentsOf: url)
        }
        return files
    }

    /// Creates an old database file with the given model version and fills it.
    private func makeLegacyStore(version: String, fill: (NSManagedObjectContext) throws -> Void) throws {
        let url = try XCTUnwrap(Bundle(for: DataController.self).url(forResource: version, withExtension: "mom", subdirectory: "CocktailRecipe.momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        model.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }
        let old = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: model)
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        var loadError: Error?
        old.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try fill(old.viewContext)
        try old.viewContext.save()
        for store in old.persistentStoreCoordinator.persistentStores {
            try old.persistentStoreCoordinator.remove(store)
        }
    }

    private func insert(_ entity: String, in context: NSManagedObjectContext) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        object.setValue(UUID(), forKey: "id")
        return object
    }

    private func spirit(_ name: String, type: SpiritType = .liquor, in context: NSManagedObjectContext) -> NSManagedObject {
        let spirit = insert("Spirit", in: context)
        spirit.setValue(name, forKey: "spiritName")
        spirit.setValue(type.rawValue, forKey: "type")
        return spirit
    }

    private func drink(_ name: String, base: NSManagedObject?, ingredients: String, in context: NSManagedObjectContext) -> NSManagedObject {
        let drink = insert("Drink", in: context)
        drink.setValue(name, forKey: "drinkName")
        drink.setValue(ingredients, forKey: "ingredients")
        drink.setValue("Shake or stir.", forKey: "method")
        drink.setValue(Int16(SourceType.original.rawValue), forKey: "source")
        drink.setValue(base?.value(forKey: "id"), forKey: "baseSpirit")
        return drink
    }

    private func bottle(_ brand: String, spirit: NSManagedObject?, in context: NSManagedObjectContext) -> NSManagedObject {
        let bottle = insert("Bottle", in: context)
        bottle.setValue(brand, forKey: "brand")
        bottle.setValue(spirit, forKey: "spirit")
        return bottle
    }

    private func menu(_ name: String, in context: NSManagedObjectContext) -> NSManagedObject {
        let menu = insert("Menu", in: context)
        menu.setValue(name, forKey: "menuName")
        menu.setValue(Date(), forKey: "dateCreated")
        return menu
    }

    private func menuItem(menu: NSManagedObject?, drink: NSManagedObject?, in context: NSManagedObjectContext) {
        let item = insert("MenuItem", in: context)
        item.setValue(menu, forKey: "menu")
        item.setValue(drink, forKey: "drink")
    }
}

// MARK: - Importing realistic and historical databases (data model refactor, phase 4)

/// Builds old Core Data databases with any historical model shape, for importer tests.
class LegacyStoreTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var folder: URL!
    var storeURL: URL { folder.appendingPathComponent("CocktailRecipe.sqlite") }

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        context = nil
        container = nil
    }

    /// An old model version from the app bundle, with plain classes so it doesn't clash with today's.
    func legacyModel(_ version: String) throws -> NSManagedObjectModel {
        let url = try XCTUnwrap(Bundle(for: DataController.self).url(forResource: version, withExtension: "mom", subdirectory: "CocktailRecipe.momd"),
                                "\(version) should be in the app bundle")
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        model.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }
        return model
    }

    func makeLegacyStore(version: String, fill: (NSManagedObjectContext) throws -> Void) throws {
        let old = NSPersistentContainer(name: "CocktailRecipe", managedObjectModel: try legacyModel(version))
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        var loadError: Error?
        old.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try fill(old.viewContext)
        try old.viewContext.save()
        for store in old.persistentStoreCoordinator.persistentStores {
            try old.persistentStoreCoordinator.remove(store)
        }
    }

    /// Inserts an object, setting only the values its model version actually has.
    @discardableResult
    func insert(_ entity: String, _ values: [String: Any?], in old: NSManagedObjectContext) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: old)
        let keys = Set(object.entity.propertiesByName.keys)
        if keys.contains("id") {
            object.setValue(UUID(), forKey: "id")
        }
        for (key, value) in values where keys.contains(key) {
            object.setValue(value, forKey: key)
        }
        return object
    }

    func importer(defaults: UserDefaults? = nil) -> LegacyImporter {
        LegacyImporter(context: context, legacyStoreURL: storeURL, defaults: defaults)
    }

    func cocktail(_ name: String) throws -> DB.Cocktail {
        try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == name }, "No cocktail named \(name)")
    }
}

final class HistoricalModelImportTests: LegacyStoreTestCase {

    /// Every shape the database has ever had, oldest first. The TestFlight build on a phone could be any of them.
    private let versions = [
        "CocktailRecipe 2024-02-24", "CocktailRecipe 2024-02-27", "CocktailRecipe 2024-02-29a",
        "CocktailRecipe 2024-02-29b", "CocktailRecipe 2024-03-01", "CocktailRecipe 2024-03-03",
        "CocktailRecipe", "CocktailRecipe 2", "CocktailRecipe 3"
    ]

    func testEveryHistoricalModelVersionIsInTheApp() throws {
        for version in versions {
            XCTAssertNoThrow(try legacyModel(version), version)
        }
    }

    func testEveryHistoricalDatabaseImports() throws {
        for version in versions {
            try setUpWithError()
            try makeLegacyStore(version: version) { old in
                let entities = old.persistentStoreCoordinator?.managedObjectModel.entitiesByName ?? [:]
                // The very first shape had no spirits or menus yet.
                let gin = entities["Spirit"] == nil ? nil : self.insert("Spirit", ["spiritName": "Gin", "type": Int16(0)], in: old)
                let martini = self.insert("Drink", [
                    "drinkName": "Martini",
                    "ingredients": "1pt Gin, 1pt Dry Vermouth, Olive",
                    "method": "Stir with ice.",
                    "baseSpirit": gin?.value(forKey: "id"),
                    "rating": Int16(8)
                ], in: old)
                if entities["Menu"] != nil {
                    let menu = self.insert("Menu", ["menuName": "Date Night", "dateCreated": Date()], in: old)
                    self.insert("MenuItem", ["menu": menu, "drink": martini], in: old)
                }
            }

            let summary = try importer().runImport()

            XCTAssertEqual(summary.cocktails, 1, version)
            let martini = try cocktail("Martini")
            XCTAssertEqual(martini.orderedIngredients.map(\.name), ["Gin", "Dry Vermouth", "Olive"], version)
            XCTAssertEqual(martini.method, "Stir with ice.", version)
            try tearDownWithError()
        }
    }
}

final class RealisticVersion1ImportTests: LegacyStoreTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let photo = Data((0..<20_000).map { UInt8($0 % 199) })

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "RealisticVersion1ImportTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        try makePhoneLikeDatabase()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try super.tearDownWithError()
    }

    /// A database like a phone that has had the app (model version 1) since spring 2024.
    private func makePhoneLikeDatabase() throws {
        func original(_ name: String) -> (ingredients: String, method: String) {
            SeedData.originalClassicRecipes[name]!
        }
        /// House favorites as the old app wrote them, typos included.
        func withOldTypos(_ text: String) -> String {
            SeedData.typoFixes.reduce(text) { $0.replacingOccurrences(of: $1.correction, with: $1.typo) }
        }
        let photo = self.photo

        try makeLegacyStore(version: "CocktailRecipe") { old in
            func spirit(_ name: String, _ type: SpiritType = .liquor) -> NSManagedObject {
                self.insert("Spirit", ["spiritName": name, "type": type.rawValue], in: old)
            }
            func drink(_ name: String, base: NSManagedObject?, ingredients: String, method: String = "Shake with ice and strain.",
                       source: SourceType = .original, rating: Int16 = 0) -> NSManagedObject {
                self.insert("Drink", ["drinkName": name, "ingredients": ingredients, "method": method,
                                      "baseSpirit": base?.value(forKey: "id"), "source": source.rawValue, "rating": rating], in: old)
            }

            // The nine original spirits, plus ones added by hand.
            let tequila = spirit("Tequila"), bourbon = spirit("Bourbon"), gin = spirit("Gin"), rum = spirit("Rum")
            let whiskey = spirit("Whiskey")
            for name in ["Vodka", "Scotch", "Brandy", "Aquavit"] { _ = spirit(name) }
            let amaretto = spirit("Amaretto", .liqueur)
            _ = spirit("Campari", .liqueur)
            _ = spirit("Sweet Vermouth", .fortifiedWine)
            _ = spirit("Prosecco", .wine)
            _ = spirit("Ginger Beer", .beer)
            _ = spirit("Mezcal")
            _ = spirit("Sloe Gin", .liqueur)

            // The original classics: one edited, three untouched, Cosmopolitan deleted.
            let margarita = original("Margarita")
            _ = drink("Margarita", base: tequila, ingredients: margarita.ingredients + ", splash of agave",
                      method: margarita.method, source: .classic, rating: 8)
            let oldFashioned = drink("Old Fashioned", base: bourbon, ingredients: original("Old Fashioned").ingredients,
                                     method: original("Old Fashioned").method, source: .classic, rating: 10)
            oldFashioned.setValue(photo, forKey: "image")
            let martini = drink("Martini", base: gin, ingredients: original("Martini").ingredients,
                                method: original("Martini").method, source: .classic)
            let daquiri = drink("Daquiri", base: rum, ingredients: original("Daiquiri").ingredients,
                                method: original("Daiquiri").method, source: .classic)

            // House favorites, added with the old button.
            for name in ["Blood Orange Margarita", "Irish Whiskey Sour", "Ranch Water"] {
                let seed = SeedData.favorites.first { $0.name == name }!
                let base = ["Tequila": tequila, "Whiskey": whiskey][seed.spirit]
                _ = drink(name, base: base, ingredients: withOldTypos(seed.ingredientsText), method: withOldTypos(seed.methodText))
            }

            // Recipes typed in by hand, the way people actually write them.
            _ = drink("Mom's Sangria", base: nil, ingredients: "1 bottle red wine\nJuice of 1 orange\nsplash of brandy\nTop with soda water")
            let gardenGimlet = drink("Garden Gimlet", base: gin, ingredients: "1 1/2 oz gin\n3/4 oz lime juice\n1/2 oz simple syrup\n2 cucumber slices",
                                     source: .website, rating: 12)
            _ = drink("Paloma (our way)", base: tequila, ingredients: "50ml tequila, 100ml grapefruit soda, pinch salt", source: .menu)
            _ = drink("Espresso Thing", base: nil, ingredients: "", method: "")
            _ = drink("Amaretto Sour", base: amaretto, ingredients: "Amaretto - 2oz\nLemon juice - 1oz\nEgg white")
            _ = drink("Dark & Stormy", base: rum, ingredients: "2 oz dark rum\nTop with ginger beer\nLime wedge")
            _ = drink("  ", base: nil, ingredients: "2 oz gin")
            let mystery = drink("Mystery Mix", base: nil, ingredients: "1 oz vodka\n1 oz something")
            mystery.setValue(UUID(), forKey: "baseSpirit") // its spirit was deleted long ago

            // Menus, with the leftovers old versions could leave behind.
            let friday = self.insert("Menu", ["menuName": "Friday Night", "dateCreated": Date()], in: old)
            for item in [oldFashioned, gardenGimlet, daquiri, oldFashioned] {
                self.insert("MenuItem", ["menu": friday, "drink": item], in: old)
            }
            self.insert("MenuItem", ["menu": friday], in: old)                      // its cocktail was deleted
            self.insert("Menu", ["menuName": "Holiday Party", "dateCreated": Date()], in: old) // empty
            let unnamed = self.insert("Menu", ["menuName": "", "dateCreated": Date()], in: old)
            self.insert("MenuItem", ["menu": unnamed, "drink": martini], in: old)
            self.insert("MenuItem", ["drink": martini], in: old)                    // no menu at all
        }
    }

    // MARK: The import

    func testSummary() throws {
        let summary = try importer(defaults: defaults).runImport()
        XCTAssertEqual(summary, ImportSummary(cocktails: 15, bottles: 0, menus: 3, menuEntries: 4, customStyles: 2, cocktailsNeedingReview: 3))
    }

    func testUneditedOriginalClassicsGetTheUpdatedRecipeInParts() throws {
        try importer(defaults: defaults).runImport()

        let daiquiri = try cocktail("Daiquiri")
        let seed = try XCTUnwrap(SeedData.classics.first { $0.name == "Daiquiri" })
        XCTAssertEqual(daiquiri.orderedIngredients.count, seed.ingredients.count)
        XCTAssertEqual(daiquiri.orderedIngredients.first?.amount, 2)
        XCTAssertEqual(daiquiri.orderedIngredients.first?.unit, .part)
        XCTAssertEqual(daiquiri.method, seed.methodText)
        XCTAssertEqual(daiquiri.originalIngredientsText, SeedData.originalClassicRecipes["Daiquiri"]?.ingredients, "Old text kept for reference")
        XCTAssertEqual(daiquiri.baseStyle?.name, "Rum")

        let oldFashioned = try cocktail("Old Fashioned")
        XCTAssertEqual(oldFashioned.orderedIngredients.count, SeedData.classics.first { $0.name == "Old Fashioned" }?.ingredients.count)
        XCTAssertEqual(oldFashioned.rating, 10)
        XCTAssertEqual(oldFashioned.photo, photo)
    }

    func testEditedClassicKeepsYourEditsWithTyposFixed() throws {
        try importer(defaults: defaults).runImport()

        let margarita = try cocktail("Margarita")
        let names = margarita.orderedIngredients.map(\.name)
        XCTAssertTrue(names.contains("splash of agave"), "Your edit is kept")
        XCTAssertTrue(names.contains("Triple Sec"))
        XCTAssertFalse(names.contains("Tripe Sec"))
        XCTAssertEqual(margarita.rating, 8)
        XCTAssertEqual(margarita.baseStyle?.name, "Tequila Blanco")
    }

    func testHouseFavoritesLoseTheirTypos() throws {
        try importer(defaults: defaults).runImport()
        let method = try cocktail("Blood Orange Margarita").method
        XCTAssertTrue(method.contains("cocktail shaker"))
        XCTAssertFalse(method.contains("shker"))
        XCTAssertEqual(try cocktail("Irish Whiskey Sour").baseStyle?.name, "Irish Whiskey")
    }

    func testHandTypedRecipes() throws {
        try importer(defaults: defaults).runImport()

        let gimlet = try cocktail("Garden Gimlet")
        XCTAssertEqual(gimlet.orderedIngredients.map(\.amount), [1.5, 0.75, 0.5, 2])
        XCTAssertEqual(gimlet.orderedIngredients.map(\.unit), [.part, .part, .part, .piece])
        XCTAssertEqual(gimlet.rating, 10, "Out-of-range ratings are capped")
        XCTAssertEqual(gimlet.source, .website)
        XCTAssertFalse(gimlet.needsIngredientReview)

        let stormy = try cocktail("Dark & Stormy").orderedIngredients
        XCTAssertEqual(stormy[1].unit, .topUp)
        XCTAssertEqual(stormy[1].style?.name, "Ginger Beer & Ale")
        XCTAssertTrue(stormy[2].isGarnish)

        XCTAssertTrue(try cocktail("Mom's Sangria").needsIngredientReview, "\"Juice of 1 orange\" needs a look")
        XCTAssertTrue(try cocktail("Paloma (our way)").needsIngredientReview, "Metric amounts need a look")
        XCTAssertTrue(try cocktail("Amaretto Sour").needsIngredientReview, "Amounts after the name need a look")
        XCTAssertEqual(try cocktail("Paloma (our way)").source, .menu)
        XCTAssertEqual(try cocktail("Amaretto Sour").baseStyle?.name, "Amaretto")

        XCTAssertTrue(try cocktail("Espresso Thing").orderedIngredients.isEmpty)
        XCTAssertFalse(try cocktail("Espresso Thing").needsIngredientReview)
        XCTAssertNoThrow(try cocktail("Untitled Cocktail"))
        XCTAssertNil(try cocktail("Mystery Mix").baseStyle, "Its spirit no longer exists")
    }

    func testSpiritsBecomeStyles() throws {
        try importer(defaults: defaults).runImport()
        let styles = StyleStore(context: context)

        XCTAssertEqual(try styles.style(named: "Aperitivo")?.isBuiltIn, true)
        XCTAssertNil(try styles.style(named: "Campari"), "Campari became Aperitivo, not its own style")
        XCTAssertNil(try styles.style(named: "Prosecco"))
        XCTAssertNil(try styles.style(named: "Ginger Beer"))
        XCTAssertEqual(try styles.style(named: "Amaretto")?.family, .liqueursAndAmari)
        XCTAssertEqual(try styles.style(named: "Sloe Gin")?.family, .liqueursAndAmari, "Saved as a liqueur, so it stays one")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count + 2)
    }

    func testMenus() throws {
        try importer(defaults: defaults).runImport()
        let menus = try context.fetch(FetchDescriptor<DB.Menu>())

        let friday = try XCTUnwrap(menus.first { $0.name == "Friday Night" })
        XCTAssertEqual(friday.orderedEntries.compactMap { $0.cocktail?.name }, ["Daiquiri", "Garden Gimlet", "Old Fashioned"])
        XCTAssertEqual(menus.first { $0.name == "Holiday Party" }?.entries?.count ?? -1, 0)
        XCTAssertEqual(menus.first { $0.name == "Untitled Menu" }?.orderedEntries.compactMap { $0.cocktail?.name }, ["Martini"])
    }

    // MARK: After the import, the first launch seeds

    func testSeedingAfterImportAddsOnlyTheNewClassics() throws {
        try importer(defaults: defaults).runImport()
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        let names = try context.fetch(FetchDescriptor<DB.Cocktail>()).map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "No duplicates")
        XCTAssertFalse(names.contains("Cosmopolitan"), "Deleted in the old app, so it stays deleted")
        XCTAssertFalse(names.contains("Daquiri"))
        XCTAssertTrue(names.contains("Negroni"), "New classics arrive")
        XCTAssertEqual(names.count, 15 + 31, "15 imported + 31 new classics (36 minus the original five)")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count + 2)
    }
}

// MARK: - Ingredient formatting (data model refactor, phase 5)

final class IngredientFormatterTests: XCTestCase {

    func testAmounts() {
        XCTAssertEqual(IngredientFormatter.amount(2), "2")
        XCTAssertEqual(IngredientFormatter.amount(2.5), "2½")
        XCTAssertEqual(IngredientFormatter.amount(0.75), "¾")
        XCTAssertEqual(IngredientFormatter.amount(1.25), "1¼")
        XCTAssertEqual(IngredientFormatter.amount(1.0 / 3), "⅓")
        XCTAssertEqual(IngredientFormatter.amount(0.125), "⅛")
        XCTAssertEqual(IngredientFormatter.amount(0.6), "0.6")
        XCTAssertEqual(IngredientFormatter.amount(1.999), "2")
    }

    func testLines() {
        func line(_ text: String) -> String { IngredientParser.parseLine(text).displayText }
        XCTAssertEqual(line("2 oz Gin"), "2 parts Gin")
        XCTAssertEqual(line("¾ oz Lime Juice"), "¾ part Lime Juice")
        XCTAssertEqual(line("1 oz Campari"), "1 part Campari")
        XCTAssertEqual(line("1½ oz Bourbon"), "1½ parts Bourbon")
        XCTAssertEqual(line("2–3 dashes Angostura Bitters"), "2–3 dashes Angostura Bitters")
        XCTAssertEqual(line("1 dash Orange Bitters"), "1 dash Orange Bitters")
        XCTAssertEqual(line("1 tsp Bénédictine"), "1 barspoon Bénédictine")
        XCTAssertEqual(line("Club soda, to top"), "Club soda, to top")
        XCTAssertEqual(line("Orange peel, to garnish"), "Orange peel, to garnish")
        XCTAssertEqual(line("1 Egg White (optional)"), "1 Egg White (optional)")
        XCTAssertEqual(line("Salt, for the rim (optional)"), "Salt, for the rim (optional)")
        XCTAssertEqual(line("¼ oz Islay Scotch, to float"), "¼ part Islay Scotch, to float")
        XCTAssertEqual(line("Pinch of salt"), "Pinch of salt")
    }

    /// Text shown in the form must read back to the same rows, or editing would quietly change recipes.
    func testEveryClassicSurvivesARoundTrip() {
        for recipe in SeedData.classics + SeedData.favorites {
            let first = IngredientParser.parse(recipe.ingredientsText).ingredients
            let text = first.map(\.displayText).joined(separator: "\n")
            let second = IngredientParser.parse(text).ingredients
            XCTAssertEqual(first.count, second.count, recipe.name)
            for (a, b) in zip(first, second) {
                XCTAssertEqual(a.amount, b.amount, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.amountMax, b.amountMax, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.unit, b.unit, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.name, b.name, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.note, b.note, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.isGarnish, b.isGarnish, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.isOptional, b.isOptional, "\(recipe.name): \(a.original)")
                XCTAssertEqual(a.styleName, b.styleName, "\(recipe.name): \(a.original)")
                XCTAssertFalse(b.needsReview, "\(recipe.name): \(b.original)")
            }
        }
    }

    func testStoredIngredientsFormatTheSameWay() throws {
        let container = try CocktailModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let cocktail = try CocktailStore(context: context).addCocktail(
            name: "Negroni", ingredients: IngredientParser.parse("1 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth\nOrange peel, to garnish").ingredients
        )
        XCTAssertEqual(IngredientFormatter.text(for: cocktail.orderedIngredients),
                       "1 part Gin\n1 part Campari\n1 part Sweet Vermouth\nOrange peel, to garnish")
    }
}

// MARK: - iCloud records

/// Items become iCloud records and come back unchanged on another device (sync and sharing, step 2a).
final class CloudRecordsTests: XCTestCase {
    /// Two databases, standing in for two devices. Both have the built-in types, with the same fixed IDs.
    private var containerA: ModelContainer!
    private var containerB: ModelContainer!
    private var a: ModelContext!
    private var b: ModelContext!

    override func setUpWithError() throws {
        containerA = try CocktailModelContainer.make(inMemory: true)
        containerB = try CocktailModelContainer.make(inMemory: true)
        a = ModelContext(containerA)
        b = ModelContext(containerB)
        try ModelSeeder.addMissingStyles(context: a, defaults: nil)
        try ModelSeeder.addMissingStyles(context: b, defaults: nil)
    }

    override func tearDownWithError() throws {
        a = nil
        b = nil
        containerA = nil
        containerB = nil
    }

    private func style(_ name: String, in context: ModelContext) throws -> DB.SpiritStyle {
        try XCTUnwrap(try StyleStore(context: context).style(named: name), "No style named \(name)")
    }

    private func cocktails(in context: ModelContext) throws -> [DB.Cocktail] {
        try context.fetch(FetchDescriptor<DB.Cocktail>(sortBy: [SortDescriptor(\.name)]))
    }

    /// A sour with every kind of ingredient row, a base spirit, a template and a photo.
    private func makeSour(in context: ModelContext) throws -> DB.Cocktail {
        let bourbon = try style("Bourbon", in: context)
        let cocktail = DB.Cocktail(name: "Test Sour", source: .website, method: "Dry shake\nShake with ice")
        context.insert(cocktail)
        cocktail.baseStyle = bourbon
        cocktail.isFavorite = true
        cocktail.template = .daiquiri
        cocktail.originalIngredientsText = "2 oz bourbon"
        cocktail.photo = Data([1, 2, 3, 4])
        let rows = [
            DB.RecipeIngredient(position: 0, name: "Bourbon", amount: 2, unit: .part),
            DB.RecipeIngredient(position: 1, name: "Lemon Juice", amount: 0.75, amountMax: 1, unit: .part, note: "fresh"),
            DB.RecipeIngredient(position: 2, name: "Egg White", amount: 1, isOptional: true),
            DB.RecipeIngredient(position: 3, name: "Lemon Peel", isGarnish: true),
        ]
        for row in rows {
            context.insert(row)
            row.cocktail = cocktail
        }
        rows[0].style = bourbon
        try context.save()
        return cocktail
    }

    func testRecordsLiveInTheRightZones() {
        let id = UUID()
        XCTAssertEqual(CloudRecords.recordID(for: id, type: .cocktail).recordName, id.uuidString, "The record name is the item's ID")
        XCTAssertEqual(CloudRecords.recordID(for: id, type: .cocktail).zoneID.zoneName, "Library")
        XCTAssertEqual(CloudRecords.recordID(for: id, type: .style).zoneID.zoneName, "Library")
        XCTAssertEqual(CloudRecords.recordID(for: id, type: .menu).zoneID.zoneName, "Library")
        XCTAssertEqual(CloudRecords.recordID(for: id, type: .bottle).zoneID.zoneName, "MyBar", "My Bar is kept apart, never shared")
        XCTAssertEqual(CloudRecords.recordID(for: id, type: .cocktail, libraryOwner: "_friend").zoneID.ownerName, "_friend")
    }

    func testCocktailComesBackUnchanged() throws {
        let sour = try makeSour(in: a)
        let record = CloudRecords.record(for: sour, systemFields: nil)
        XCTAssertEqual(record.recordType, "Cocktail")

        XCTAssertTrue(try CloudRecords.apply(record, in: b), "Every link was found")
        try b.save()

        let copy = try XCTUnwrap(try cocktails(in: b).first)
        XCTAssertEqual(copy.id, sour.id)
        XCTAssertEqual(copy.name, "Test Sour")
        XCTAssertEqual(copy.source, .website)
        XCTAssertEqual(copy.method, sour.method)
        XCTAssertTrue(copy.isFavorite)
        XCTAssertEqual(copy.template, .daiquiri)
        XCTAssertEqual(copy.originalIngredientsText, "2 oz bourbon")
        XCTAssertEqual(copy.photo, Data([1, 2, 3, 4]))
        XCTAssertEqual(copy.dateAdded, sour.dateAdded)
        XCTAssertEqual(copy.baseStyle?.name, "Bourbon")
        XCTAssertNil(copy.library)
        XCTAssertEqual(copy.orderedIngredients.map(\.displayText), sour.orderedIngredients.map(\.displayText))
        XCTAssertEqual(copy.orderedIngredients.map(\.id), sour.orderedIngredients.map(\.id))
        XCTAssertEqual(copy.orderedIngredients.map(\.isGarnish), [false, false, false, true])
        XCTAssertEqual(copy.orderedIngredients.map(\.isOptional), [false, false, true, false])
        XCTAssertEqual(copy.orderedIngredients.map(\.note), [nil, "fresh", nil, nil])
        XCTAssertEqual(copy.orderedIngredients.first?.style?.name, "Bourbon")
    }

    func testReceivingAChangeReplacesTheIngredientsInsteadOfAddingThem() throws {
        let sour = try makeSour(in: a)
        try CloudRecords.apply(CloudRecords.record(for: sour, systemFields: nil), in: b)
        try b.save()
        try CloudRecords.apply(CloudRecords.record(for: sour, systemFields: nil), in: b)
        try b.save()
        XCTAssertEqual(try cocktails(in: b).count, 1)
        XCTAssertEqual(try b.fetchCount(FetchDescriptor<DB.RecipeIngredient>()), 4, "Receiving the same recipe twice doesn't double it")

        // Remove the garnish on device A and send again.
        let garnish = try XCTUnwrap(sour.orderedIngredients.last)
        sour.ingredients?.removeAll { $0 === garnish }
        a.delete(garnish)
        sour.name = "Test Sour No. 2"
        try a.save()
        try CloudRecords.apply(CloudRecords.record(for: sour, systemFields: nil), in: b)
        try b.save()
        let copy = try XCTUnwrap(try cocktails(in: b).first)
        XCTAssertEqual(copy.name, "Test Sour No. 2")
        XCTAssertEqual(copy.orderedIngredients.map(\.name), ["Bourbon", "Lemon Juice", "Egg White"])
        XCTAssertEqual(try b.fetchCount(FetchDescriptor<DB.RecipeIngredient>()), 3)
    }

    func testALinkThatHasntArrivedIsReportedAndFixedLater() throws {
        let barrelGin = DB.SpiritStyle(name: "Barrel Gin", family: .gin)
        a.insert(barrelGin)
        let cocktail = DB.Cocktail(name: "Barrel Martini")
        a.insert(cocktail)
        cocktail.baseStyle = barrelGin
        try a.save()

        let record = CloudRecords.record(for: cocktail, systemFields: nil)
        XCTAssertFalse(try CloudRecords.apply(record, in: b), "Device B doesn't have Barrel Gin yet")
        try b.save()
        XCTAssertNil(try cocktails(in: b).first?.baseStyle)

        try CloudRecords.apply(CloudRecords.record(for: barrelGin, systemFields: nil), in: b)
        XCTAssertTrue(try CloudRecords.apply(record, in: b))
        try b.save()
        XCTAssertEqual(try cocktails(in: b).first?.baseStyle?.name, "Barrel Gin")
    }

    func testSpiritTypeComesBackUnchanged() throws {
        let barrelGin = DB.SpiritStyle(name: "Barrel Gin", family: .gin)
        a.insert(barrelGin)
        try a.save()
        try CloudRecords.apply(CloudRecords.record(for: barrelGin, systemFields: nil), in: b)
        try b.save()
        let copy = try XCTUnwrap(try CloudRecords.findStyle(barrelGin.id, library: nil, in: b))
        XCTAssertEqual(copy.name, "Barrel Gin")
        XCTAssertEqual(copy.family, .gin)
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertEqual(copy.dateAdded, barrelGin.dateAdded)

        // A built-in type is the same record on both devices: updating it doesn't add a second one.
        let londonDry = try style("London Dry", in: a)
        try CloudRecords.apply(CloudRecords.record(for: londonDry, systemFields: nil), in: b)
        try b.save()
        XCTAssertEqual(try b.fetch(FetchDescriptor<DB.SpiritStyle>()).filter { $0.name == "London Dry" }.count, 1)
    }

    func testMenuComesBackWithItsCocktailsInOrder() throws {
        let first = DB.Cocktail(name: "Aviation")
        let second = DB.Cocktail(name: "Negroni")
        a.insert(first)
        a.insert(second)
        let menu = DB.Menu(name: "Friday Night")
        menu.notes = "Bring ice"
        a.insert(menu)
        for (position, cocktail) in [second, first].enumerated() {
            let entry = DB.MenuEntry(position: position)
            a.insert(entry)
            entry.menu = menu
            entry.cocktail = cocktail
        }
        try a.save()

        let menuRecord = CloudRecords.record(for: menu, systemFields: nil)
        XCTAssertFalse(try CloudRecords.apply(menuRecord, in: b), "The cocktails haven't arrived yet")
        try CloudRecords.apply(CloudRecords.record(for: first, systemFields: nil), in: b)
        try CloudRecords.apply(CloudRecords.record(for: second, systemFields: nil), in: b)
        XCTAssertTrue(try CloudRecords.apply(menuRecord, in: b))
        try b.save()

        let copy = try XCTUnwrap(try b.fetch(FetchDescriptor<DB.Menu>()).first)
        XCTAssertEqual(copy.name, "Friday Night")
        XCTAssertEqual(copy.notes, "Bring ice")
        XCTAssertEqual(copy.dateCreated, menu.dateCreated)
        XCTAssertEqual(copy.orderedEntries.compactMap { $0.cocktail?.name }, ["Negroni", "Aviation"])
        XCTAssertEqual(try b.fetchCount(FetchDescriptor<DB.MenuEntry>()), 2)
    }

    func testBottleComesBackUnchanged() throws {
        let bottle = DB.Bottle(brand: "Tanqueray", stock: .low, bottleCount: 2)
        bottle.notes = "Gift"
        bottle.isFavorite = true
        bottle.photo = Data([9, 8, 7])
        a.insert(bottle)
        bottle.style = try style("London Dry", in: a)
        try a.save()

        let record = CloudRecords.record(for: bottle, systemFields: nil)
        XCTAssertEqual(record.recordID.zoneID.zoneName, "MyBar")
        XCTAssertTrue(try CloudRecords.apply(record, in: b))
        try b.save()

        let copy = try XCTUnwrap(try b.fetch(FetchDescriptor<DB.Bottle>()).first)
        XCTAssertEqual(copy.id, bottle.id)
        XCTAssertEqual(copy.brand, "Tanqueray")
        XCTAssertEqual(copy.stock, .low)
        XCTAssertEqual(copy.bottleCount, 2)
        XCTAssertEqual(copy.notes, "Gift")
        XCTAssertTrue(copy.isFavorite)
        XCTAssertEqual(copy.photo, Data([9, 8, 7]))
        XCTAssertEqual(copy.style?.name, "London Dry")
    }

    func testRemovingAPhotoIsSentToo() throws {
        let sour = try makeSour(in: a)
        try CloudRecords.apply(CloudRecords.record(for: sour, systemFields: nil), in: b)
        sour.photo = nil
        try a.save()
        try CloudRecords.apply(CloudRecords.record(for: sour, systemFields: nil), in: b)
        try b.save()
        XCTAssertNil(try cocktails(in: b).first?.photo)
    }

    func testDeletedRecordsRemoveTheItemAndItsRows() throws {
        let sour = try makeSour(in: a)
        try CloudRecords.apply(CloudRecords.record(for: sour, systemFields: nil), in: b)
        try b.save()

        try CloudRecords.deleteItem(type: .cocktail, id: sour.id, in: b)
        try b.save()
        XCTAssertEqual(try b.fetchCount(FetchDescriptor<DB.Cocktail>()), 0)
        XCTAssertEqual(try b.fetchCount(FetchDescriptor<DB.RecipeIngredient>()), 0)

        // Deleting something that isn't here does nothing.
        try CloudRecords.deleteItem(type: .menu, id: UUID(), in: b)
    }

    func testASharedLibrarysRecipesStaySeparateFromYourOwn() throws {
        try ModelSeeder.seedBuiltIns(context: a, defaults: nil)
        try ModelSeeder.seedBuiltIns(context: b, defaults: nil)
        let theirNegroni = try XCTUnwrap(try cocktails(in: a).first { $0.name == "Negroni" })
        theirNegroni.method = "Their way"
        try a.save()

        let library = DB.Library(name: "Friend's Library", ownerName: "Friend", zoneName: "Library", zoneOwnerName: "_friend")
        b.insert(library)
        let record = CloudRecords.record(for: theirNegroni, systemFields: nil, libraryOwner: "_friend")
        try CloudRecords.apply(record, in: b, library: library)
        try b.save()

        let negronis = try cocktails(in: b).filter { $0.name == "Negroni" }
        XCTAssertEqual(negronis.count, 2, "Same ID, but one is yours and one is theirs")
        let mine = try XCTUnwrap(negronis.first { $0.library == nil })
        let theirs = try XCTUnwrap(negronis.first { $0.library != nil })
        XCTAssertNotEqual(mine.method, "Their way", "Your recipe isn't changed by theirs")
        XCTAssertEqual(theirs.method, "Their way")
        XCTAssertNil(theirs.baseStyle, "Their types come with their library, not from yours")
    }

    func testSavedSystemFieldsAreReused() throws {
        let id = CloudRecords.recordID(for: UUID(), type: .cocktail)
        let original = CKRecord(recordType: "Cocktail", recordID: id)
        let data = CloudSystemFields.encode(original)

        let decoded = try XCTUnwrap(CloudSystemFields.decode(data))
        XCTAssertEqual(decoded.recordID, id)
        XCTAssertEqual(decoded.recordType, "Cocktail")
        XCTAssertEqual(CloudRecords.blankRecord(type: .cocktail, id: id, systemFields: data).recordID, id)

        // Saved fields for a different record are ignored.
        let otherID = CloudRecords.recordID(for: UUID(), type: .cocktail)
        XCTAssertEqual(CloudRecords.blankRecord(type: .cocktail, id: otherID, systemFields: data).recordID, otherID)
        XCTAssertNil(CloudSystemFields.decode(Data([0, 1, 2])), "Damaged data is ignored")
    }
}

/// What gets sent to iCloud, what arrives, and how disagreements settle (sync and sharing, step 2b).
/// Two in-memory databases stand in for two devices; records are passed between them by hand.
final class CloudSyncLedgerTests: XCTestCase {
    private var containerA: ModelContainer!
    private var containerB: ModelContainer!

    override func setUpWithError() throws {
        containerA = try CocktailModelContainer.make(inMemory: true)
        containerB = try CocktailModelContainer.make(inMemory: true)
    }

    override func tearDownWithError() throws {
        containerA = nil
        containerB = nil
    }

    // MARK: Helpers

    /// Sends everything waiting on a device, as iCloud would accept it, and returns what was sent.
    @MainActor
    @discardableResult
    private func sendAll(_ ledger: CloudSyncLedger) throws -> [CKRecord] {
        let changes = try ledger.localChanges()
        let records = try changes.saves.compactMap { try ledger.record(for: $0) }
        for record in records {
            try ledger.didSave(record)
        }
        for recordID in changes.deletes {
            try ledger.didDelete(recordID)
        }
        return records
    }

    /// A user recipe with a user type, so the test controls every ID.
    @MainActor
    private func addRecipe(_ name: String, in container: ModelContainer) throws -> (cocktail: UUID, style: UUID) {
        let context = ModelContext(container)
        let style = DB.SpiritStyle(name: "Barrel Gin", family: .gin)
        context.insert(style)
        let cocktail = DB.Cocktail(name: name, method: "Stir")
        context.insert(cocktail)
        cocktail.baseStyle = style
        let ingredient = DB.RecipeIngredient(position: 0, name: "Barrel Gin", amount: 2, unit: .part)
        context.insert(ingredient)
        ingredient.cocktail = cocktail
        try context.save()
        return (cocktail.id, style.id)
    }

    private func cocktail(_ id: UUID, in container: ModelContainer) throws -> DB.Cocktail? {
        try CloudRecords.findCocktail(id, library: nil, in: ModelContext(container))
    }

    private func recordID(_ id: UUID, _ type: CloudRecordType) -> CKRecord.ID {
        CloudRecords.recordID(for: id, type: type)
    }

    // MARK: Sending

    @MainActor
    func testFirstCheckQueuesEverythingUntilItIsSent() throws {
        let context = ModelContext(containerA)
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)
        context.insert(DB.Bottle(brand: "Tanqueray"))
        try context.save()
        let ledger = CloudSyncLedger(container: containerA)

        let first = try ledger.localChanges()
        XCTAssertEqual(first.saves.count, SpiritTaxonomy.builtInStyles.count + SeedData.classics.count + 1)
        XCTAssertEqual(first.deletes, [])
        XCTAssertEqual(try ledger.localChanges().saves.count, first.saves.count, "Still waiting until iCloud has it")
        XCTAssertEqual(Set(first.saves.map(\.zoneID.zoneName)), ["Library", "MyBar"])

        try sendAll(ledger)
        XCTAssertTrue(try ledger.localChanges().isEmpty, "Nothing left to send")
    }

    @MainActor
    func testChangesToARecipeOrItsIngredientsAreSent() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let ledger = CloudSyncLedger(container: containerA)
        try sendAll(ledger)

        let context = ModelContext(containerA)
        let cocktail = try XCTUnwrap(try CloudRecords.findCocktail(ids.cocktail, library: nil, in: context))
        cocktail.name = "Barrel Martini No. 2"
        try context.save()
        XCTAssertEqual(try ledger.localChanges(changed: [cocktail.persistentModelID]).saves, [recordID(ids.cocktail, .cocktail)])
        let record = try XCTUnwrap(try ledger.record(for: recordID(ids.cocktail, .cocktail)))
        XCTAssertEqual(record["name"] as? String, "Barrel Martini No. 2")
        try ledger.didSave(record)

        // Changing only an ingredient sends its recipe.
        let ingredient = try XCTUnwrap(cocktail.ingredients?.first)
        ingredient.amount = 3
        try context.save()
        XCTAssertEqual(try ledger.localChanges(changed: [ingredient.persistentModelID]).saves, [recordID(ids.cocktail, .cocktail)])
    }

    @MainActor
    func testDeletionsAreSentOnlyForItemsICloudHas() throws {
        let sent = try addRecipe("Sent Sour", in: containerA)
        let ledger = CloudSyncLedger(container: containerA)
        try sendAll(ledger)
        let unsent = try addRecipe("Unsent Sour", in: containerA)
        _ = try ledger.localChanges()

        let context = ModelContext(containerA)
        for id in [sent.cocktail, unsent.cocktail] {
            context.delete(try XCTUnwrap(try CloudRecords.findCocktail(id, library: nil, in: context)))
        }
        try context.save()

        let changes = try ledger.localChanges()
        XCTAssertEqual(changes.deletes, [recordID(sent.cocktail, .cocktail)], "The unsent recipe never reached iCloud")
        XCTAssertFalse(changes.saves.contains(recordID(unsent.cocktail, .cocktail)))
        try ledger.didDelete(recordID(sent.cocktail, .cocktail))
        XCTAssertEqual(try ledger.localChanges().deletes, [])
    }

    @MainActor
    func testSentRecordsKeepTheirICloudDetails() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let ledger = CloudSyncLedger(container: containerA)
        let id = recordID(ids.cocktail, .cocktail)
        _ = try ledger.localChanges()
        XCTAssertEqual(try ledger.bookkeeping(for: id), .init(needsUpload: true, hasSystemFields: false))
        try sendAll(ledger)
        XCTAssertEqual(try ledger.bookkeeping(for: id), .init(needsUpload: false, hasSystemFields: true))
        XCTAssertEqual(try ledger.record(for: id)?.recordID, id)
        XCTAssertNil(try ledger.record(for: recordID(UUID(), .cocktail)), "Nothing to send for an unknown item")
    }

    // MARK: Receiving

    @MainActor
    func testRecordsFromAnotherDeviceArriveAndArentSentBack() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let records = try sendAll(CloudSyncLedger(container: containerA))
        let ledgerB = CloudSyncLedger(container: containerB)

        // The cocktail comes before its type, as can happen; the type is put first.
        try ledgerB.applyFetched(modifications: records.reversed(), deletions: [])
        let copy = try XCTUnwrap(try cocktail(ids.cocktail, in: containerB))
        XCTAssertEqual(copy.name, "Barrel Martini")
        XCTAssertEqual(copy.baseStyle?.name, "Barrel Gin")
        XCTAssertEqual(copy.orderedIngredients.map(\.displayText), ["2 parts Barrel Gin"])
        XCTAssertTrue(try ledgerB.localChanges().isEmpty, "What arrived from iCloud isn't sent back")

        try ledgerB.applyFetched(modifications: [], deletions: [(recordID: recordID(ids.cocktail, .cocktail), recordType: "Cocktail")])
        XCTAssertNil(try cocktail(ids.cocktail, in: containerB), "Deleted on the other device")
        XCTAssertNil(try ledgerB.bookkeeping(for: recordID(ids.cocktail, .cocktail)))
    }

    @MainActor
    func testALinkThatArrivesLaterIsFilledIn() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let records = try sendAll(CloudSyncLedger(container: containerA))
        let cocktailRecord = try XCTUnwrap(records.first { $0.recordType == "Cocktail" })
        let styleRecord = try XCTUnwrap(records.first { $0.recordType == "SpiritStyle" })
        let ledgerB = CloudSyncLedger(container: containerB)

        try ledgerB.applyFetched(modifications: [cocktailRecord], deletions: [])
        XCTAssertNil(try cocktail(ids.cocktail, in: containerB)?.baseStyle)
        XCTAssertEqual(ledgerB.waiting.count, 1)

        try ledgerB.applyFetched(modifications: [styleRecord], deletions: [])
        XCTAssertEqual(try cocktail(ids.cocktail, in: containerB)?.baseStyle?.name, "Barrel Gin")
        XCTAssertTrue(ledgerB.waiting.isEmpty)
    }

    @MainActor
    func testAnIncomingChangeDoesntOverwriteOneWaitingToBeSent() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let ledgerA = CloudSyncLedger(container: containerA)
        let ledgerB = CloudSyncLedger(container: containerB)
        try ledgerB.applyFetched(modifications: try sendAll(ledgerA), deletions: [])

        // Device B renames it but hasn't sent yet; device A's rename arrives.
        let contextB = ModelContext(containerB)
        let copy = try XCTUnwrap(try CloudRecords.findCocktail(ids.cocktail, library: nil, in: contextB))
        copy.name = "B's Martini"
        try contextB.save()
        _ = try ledgerB.localChanges(changed: [copy.persistentModelID])

        let contextA = ModelContext(containerA)
        try XCTUnwrap(try CloudRecords.findCocktail(ids.cocktail, library: nil, in: contextA)).name = "A's Martini"
        try contextA.save()
        let fromA = try XCTUnwrap(try ledgerA.record(for: recordID(ids.cocktail, .cocktail)))
        try ledgerB.applyFetched(modifications: [fromA], deletions: [])

        XCTAssertEqual(try cocktail(ids.cocktail, in: containerB)?.name, "B's Martini")
        XCTAssertEqual(try ledgerB.localChanges().saves, [recordID(ids.cocktail, .cocktail)], "B's change is still sent")
    }

    @MainActor
    func testTheLibrarysShareRecordIsLeftAlone() throws {
        let ledger = CloudSyncLedger(container: containerA)
        let share = CKShare(recordZoneID: CloudSchema.libraryZoneID())
        try ledger.applyFetched(modifications: [share], deletions: [])
        XCTAssertNil(try ledger.bookkeeping(for: share.recordID), "The share isn't one of the app's items")
        XCTAssertTrue(try ledger.localChanges().isEmpty, "So it's never deleted as a missing item")
        try ledger.applyFetched(modifications: [], deletions: [(recordID: share.recordID, recordType: "cloudkit.share")])
    }

    // MARK: Disagreements

    @MainActor
    func testABuiltInNewHereTakesTheVersionAlreadyInICloud() throws {
        // Device A edited its Negroni and sent it; device B is new and has the original.
        let contextA = ModelContext(containerA)
        try ModelSeeder.seedBuiltIns(context: contextA, defaults: nil)
        let negroniA = try XCTUnwrap(try contextA.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Negroni" })
        negroniA.method = "Our house method"
        try contextA.save()
        let ledgerA = CloudSyncLedger(container: containerA)
        try sendAll(ledgerA)
        let inICloud = try XCTUnwrap(try ledgerA.record(for: recordID(negroniA.id, .cocktail)))

        try ModelSeeder.seedBuiltIns(context: ModelContext(containerB), defaults: nil)
        let ledgerB = CloudSyncLedger(container: containerB)
        _ = try ledgerB.localChanges()
        let fromB = try XCTUnwrap(try ledgerB.record(for: recordID(negroniA.id, .cocktail)))

        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: inICloud])
        XCTAssertEqual(try ledgerB.resolveFailedSave(fromB, error: error), .drop)
        XCTAssertEqual(try cocktail(negroniA.id, in: containerB)?.method, "Our house method")
        XCTAssertEqual(try ledgerB.bookkeeping(for: recordID(negroniA.id, .cocktail)), .init(needsUpload: false, hasSystemFields: true))
    }

    @MainActor
    func testAnEditOnBothDevicesSendsThisDevicesVersionAgain() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let ledger = CloudSyncLedger(container: containerA)
        let records = try sendAll(ledger)
        let id = recordID(ids.cocktail, .cocktail)
        let server = try XCTUnwrap(records.first { $0.recordID == id })

        let context = ModelContext(containerA)
        try XCTUnwrap(try CloudRecords.findCocktail(ids.cocktail, library: nil, in: context)).name = "Mine"
        try context.save()
        let mine = try XCTUnwrap(try ledger.record(for: id))
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        XCTAssertEqual(try ledger.resolveFailedSave(mine, error: error), .resend)
        XCTAssertEqual(try ledger.record(for: id)?["name"] as? String, "Mine", "This device's version goes again")
    }

    @MainActor
    func testOtherFailures() throws {
        let ids = try addRecipe("Barrel Martini", in: containerA)
        let ledger = CloudSyncLedger(container: containerA)
        let record = try XCTUnwrap(try sendAll(ledger).first { $0.recordType == "Cocktail" })
        let id = record.recordID

        XCTAssertEqual(try ledger.resolveFailedSave(record, error: CKError(.zoneNotFound)), .createZoneAndResend)
        XCTAssertEqual(try ledger.resolveFailedSave(record, error: CKError(.networkFailure)), .wait)
        XCTAssertEqual(try ledger.resolveFailedSave(record, error: CKError(.unknownItem)), .resend)
        XCTAssertEqual(try ledger.bookkeeping(for: id)?.hasSystemFields, false, "Sent again as a new record")
        XCTAssertNotNil(try cocktail(ids.cocktail, in: containerA))
    }

    // MARK: Resets

    @MainActor
    func testADeletedZoneAndSigningOutSendEverythingAgain() throws {
        _ = try addRecipe("Barrel Martini", in: containerA)
        let context = ModelContext(containerA)
        context.insert(DB.Bottle(brand: "Tanqueray"))
        try context.save()
        let ledger = CloudSyncLedger(container: containerA)
        try sendAll(ledger)

        try ledger.forgetZone("Library")
        let afterZone = try ledger.localChanges()
        XCTAssertEqual(afterZone.saves.count, 2, "The recipe and its type; My Bar's zone is fine")
        XCTAssertEqual(Set(afterZone.saves.map(\.zoneID.zoneName)), ["Library"])
        try sendAll(ledger)

        try ledger.resetAll()
        XCTAssertEqual(try ledger.localChanges().saves.count, 3, "Everything goes again after signing back in")
        XCTAssertEqual(try ModelContext(containerA).fetchCount(FetchDescriptor<DB.Cocktail>()), 1, "Signing out keeps your data")
    }
}

/// What Settings says about iCloud sync (sync and sharing, step 2c).
final class CloudSyncStatusTests: XCTestCase {
    func testTitlesAndDetails() {
        let now = Date()
        XCTAssertEqual(CloudSyncState.upToDate(now).title, "Up to date")
        XCTAssertEqual(CloudSyncState.upToDate(now.addingTimeInterval(-10)).detail(now: now), "Last synced just now")
        XCTAssertTrue(CloudSyncState.upToDate(now.addingTimeInterval(-7200)).detail(now: now)?.hasPrefix("Last synced 2 hours") ?? false)
        XCTAssertEqual(CloudSyncState.syncing.title, "Syncing…")
        XCTAssertNil(CloudSyncState.syncing.detail())
        XCTAssertEqual(CloudSyncState.notSignedIn.title, "Not signed in to iCloud")
        XCTAssertTrue(CloudSyncState.notSignedIn.detail()?.contains("stays on this device") ?? false)
        XCTAssertEqual(CloudSyncState.problem("No connection").detail(), "No connection")
        XCTAssertEqual(CloudSyncState.off.title, "Off")
    }

    func testSyncNowIsOfferedOnlyWhenItCanHelp() {
        XCTAssertTrue(CloudSyncState.upToDate(Date()).canSyncNow)
        XCTAssertTrue(CloudSyncState.problem("x").canSyncNow)
        XCTAssertFalse(CloudSyncState.syncing.canSyncNow)
        XCTAssertFalse(CloudSyncState.notSignedIn.canSyncNow)
        XCTAssertFalse(CloudSyncState.off.canSyncNow)
    }

    func testErrorMessages() {
        XCTAssertTrue(CloudSync.message(for: CKError(.networkUnavailable)).hasPrefix("No internet connection"))
        XCTAssertTrue(CloudSync.message(for: CKError(.quotaExceeded)).hasPrefix("Your iCloud storage is full"))
        XCTAssertTrue(CloudSync.message(for: CKError(.zoneBusy)).hasPrefix("iCloud is busy"))
    }
}

/// Part size follows you between devices through iCloud key-value storage (sync and sharing, step 2c).
/// Two UserDefaults suites stand in for this device and iCloud.
final class SettingsSyncTests: XCTestCase {
    private var local: UserDefaults!
    private var cloud: UserDefaults!
    private var suites: [String] = []

    override func setUpWithError() throws {
        suites = ["SettingsSyncLocal-\(UUID().uuidString)", "SettingsSyncCloud-\(UUID().uuidString)"]
        local = UserDefaults(suiteName: suites[0])
        cloud = UserDefaults(suiteName: suites[1])
    }

    override func tearDownWithError() throws {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        local = nil
        cloud = nil
    }

    @MainActor
    func testAtLaunchICloudsValueWins() {
        local.set(PartSize.oneOunce.rawValue, forKey: PartSize.storageKey)
        cloud.set(PartSize.thirtyMillilitres.rawValue, forKey: PartSize.storageKey)
        SettingsSync(local: local, cloud: cloud).mergeAtLaunch()
        XCTAssertEqual(local.string(forKey: PartSize.storageKey), "30ml", "Set on another device")
    }

    @MainActor
    func testAtLaunchThisDevicesValueGoesUpWhenICloudHasNone() {
        local.set(PartSize.twoOunces.rawValue, forKey: PartSize.storageKey)
        SettingsSync(local: local, cloud: cloud).mergeAtLaunch()
        XCTAssertEqual(cloud.string(forKey: PartSize.storageKey), "2oz")
    }

    @MainActor
    func testChangesGoBothWays() {
        let sync = SettingsSync(local: local, cloud: cloud)
        local.set(PartSize.oneAndAHalfOunces.rawValue, forKey: PartSize.storageKey)
        sync.localDidChange()
        XCTAssertEqual(cloud.string(forKey: PartSize.storageKey), "1.5oz")

        cloud.set(PartSize.fiftyMillilitres.rawValue, forKey: PartSize.storageKey)
        sync.cloudDidChange(keys: [PartSize.storageKey])
        XCTAssertEqual(local.string(forKey: PartSize.storageKey), "50ml")

        cloud.removeObject(forKey: PartSize.storageKey)
        sync.cloudDidChange(keys: nil)
        XCTAssertNil(local.string(forKey: PartSize.storageKey), "Cleared on another device")
    }

    @MainActor
    func testOnlyListedSettingsAreCopied() {
        let sync = SettingsSync(local: local, cloud: cloud)
        local.set("something", forKey: "SomeOtherSetting")
        sync.localDidChange()
        XCTAssertNil(cloud.object(forKey: "SomeOtherSetting"))
        cloud.set("else", forKey: "AnotherSetting")
        sync.cloudDidChange(keys: ["AnotherSetting"])
        XCTAssertNil(local.object(forKey: "AnotherSetting"))
    }
}

/// Sharing My Library as a whole (sync and sharing, step 3).
final class LibrarySharingTests: XCTestCase {
    func testTheWholeLibraryZoneIsShared() {
        XCTAssertEqual(LibrarySharing.shareRecordID.recordName, CKRecordNameZoneWideShare)
        XCTAssertEqual(LibrarySharing.shareRecordID.zoneID.zoneName, "Library", "My Bar's zone is never shared")
    }

    func testOnlyPeopleYouInviteCanOpenIt() {
        let share = CKShare(recordZoneID: CloudSchema.libraryZoneID())
        share.publicPermission = .readOnly
        LibrarySharing.configure(share)
        XCTAssertEqual(share.publicPermission, CKShare.ParticipantPermission.none, "No public link")
        XCTAssertEqual(share[CKShare.SystemFieldKey.title] as? String, "Cocktail Library")
        XCTAssertEqual(LibrarySharing.participantCount(of: share), 0, "You don't count")
    }

    func testSummary() {
        XCTAssertEqual(LibrarySharing.summary(participantCount: nil), "Not shared")
        XCTAssertEqual(LibrarySharing.summary(participantCount: 0), "No one invited yet")
        XCTAssertEqual(LibrarySharing.summary(participantCount: 1), "Shared with 1 person")
        XCTAssertEqual(LibrarySharing.summary(participantCount: 3), "Shared with 3 people")
    }

    func testSharingNeedsICloudSync() {
        XCTAssertTrue(CloudSyncState.upToDate(Date()).canShare)
        XCTAssertTrue(CloudSyncState.syncing.canShare)
        XCTAssertFalse(CloudSyncState.notSignedIn.canShare)
        XCTAssertFalse(CloudSyncState.off.canShare)
    }
}

/// Libraries other people share with you: kept apart from yours, edited only when allowed, and removed
/// when sharing stops (sync and sharing, step 4). Device A is the owner; device B was invited.
final class SharedLibrarySyncTests: XCTestCase {
    private var containerA: ModelContainer!
    private var containerB: ModelContainer!
    /// The owner's Library zone as device B sees it in its shared database.
    private let ownerZone = CKRecordZone.ID(zoneName: "Library", ownerName: "_owner")

    override func setUpWithError() throws {
        containerA = try CocktailModelContainer.make(inMemory: true)
        containerB = try CocktailModelContainer.make(inMemory: true)
    }

    override func tearDownWithError() throws {
        containerA = nil
        containerB = nil
    }

    // MARK: Helpers

    /// Device A's library as records in the owner's zone, as device B fetches them.
    @MainActor
    private func ownerRecords() throws -> [CKRecord] {
        let context = ModelContext(containerA)
        var records: [CKRecord] = []
        records += try context.fetch(FetchDescriptor<DB.SpiritStyle>()).map { CloudRecords.record(for: $0, systemFields: nil, libraryOwner: "_owner") }
        records += try context.fetch(FetchDescriptor<DB.Cocktail>()).map { CloudRecords.record(for: $0, systemFields: nil, libraryOwner: "_owner") }
        records += try context.fetch(FetchDescriptor<DB.Menu>()).map { CloudRecords.record(for: $0, systemFields: nil, libraryOwner: "_owner") }
        return records
    }

    /// Both devices have the built-ins; the owner changed their Negroni. Device B accepts and receives A's library.
    @MainActor
    private func shareAToB(canEdit: Bool) throws -> CloudSyncLedger {
        let contextA = ModelContext(containerA)
        try ModelSeeder.seedBuiltIns(context: contextA, defaults: nil)
        try XCTUnwrap(try contextA.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Negroni" }).method = "Owner's way"
        try contextA.save()
        try ModelSeeder.seedBuiltIns(context: ModelContext(containerB), defaults: nil)

        let ledgerB = CloudSyncLedger(container: containerB)
        try ledgerB.libraryAccepted(zoneID: ownerZone, ownerName: "Bill", canEdit: canEdit)
        try ledgerB.applyFetched(modifications: try ownerRecords(), deletions: [])
        return ledgerB
    }

    private func sharedLibrary(in container: ModelContainer) throws -> DB.Library? {
        try ModelContext(container).fetch(FetchDescriptor<DB.Library>()).first
    }

    private func negronis(in container: ModelContainer) throws -> [DB.Cocktail] {
        try ModelContext(container).fetch(FetchDescriptor<DB.Cocktail>()).filter { $0.name == "Negroni" }
    }

    private func sharedNegroniID() -> CKRecord.ID {
        CKRecord.ID(recordName: BuiltInID.cocktail(named: "Negroni").uuidString, zoneID: ownerZone)
    }

    // MARK: Arriving

    @MainActor
    func testASharedLibraryArrivesApartFromYours() throws {
        let ledgerB = try shareAToB(canEdit: false)

        let library = try XCTUnwrap(try sharedLibrary(in: containerB))
        XCTAssertEqual(library.name, "Bill's Library")
        XCTAssertFalse(library.canEdit)
        XCTAssertEqual(library.cocktails?.count, SeedData.classics.count)
        XCTAssertEqual(library.styles?.count, SpiritTaxonomy.builtInStyles.count)

        let both = try negronis(in: containerB)
        XCTAssertEqual(both.count, 2)
        XCTAssertNotEqual(both.first { $0.library == nil }?.method, "Owner's way", "Your Negroni is untouched")
        XCTAssertEqual(both.first { $0.library != nil }?.method, "Owner's way")
        XCTAssertEqual(both.first { $0.library != nil }?.baseStyle?.library?.name, "Bill's Library", "Linked to the owner's types")

        // Your lists and stores only show My Library.
        let contextB = ModelContext(containerB)
        XCTAssertEqual(try StyleStore(context: contextB).allStyles().count, SpiritTaxonomy.builtInStyles.count)
        XCTAssertEqual(try CocktailStore(context: contextB).cocktails().count, SeedData.classics.count)
        XCTAssertNil(try StyleStore(context: contextB).style(named: "London Dry")?.library)

        // Nothing of theirs is sent as yours, and nothing is sent back to them unchanged.
        let mine = try ledgerB.localChanges(scope: .private)
        XCTAssertEqual(mine.saves.count, SpiritTaxonomy.builtInStyles.count + SeedData.classics.count)
        XCTAssertTrue(mine.saves.allSatisfy { $0.zoneID.ownerName == CKCurrentUserDefaultName })
        XCTAssertTrue(try ledgerB.localChanges(scope: .shared).isEmpty)
    }

    @MainActor
    func testStartingUpDoesntTouchASharedLibrary() throws {
        _ = try shareAToB(canEdit: true)
        try ModelSeeder.seedBuiltIns(context: ModelContext(containerB), defaults: nil)
        XCTAssertEqual(try sharedLibrary(in: containerB)?.cocktails?.count, SeedData.classics.count)
        XCTAssertEqual(try negronis(in: containerB).count, 2, "No built-ins added to or removed from theirs")
    }

    // MARK: Editing

    @MainActor
    func testViewOnlyChangesAreNotSent() throws {
        let ledgerB = try shareAToB(canEdit: false)
        let context = ModelContext(containerB)
        let theirs = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Negroni" && $0.library != nil })
        theirs.method = "Changed"
        try context.save()
        XCTAssertTrue(try ledgerB.localChanges(changed: [theirs.persistentModelID], scope: .shared).isEmpty)
        XCTAssertNil(try ledgerB.record(for: sharedNegroniID()), "Nothing to send to a view-only library")
    }

    @MainActor
    func testEditsAreSentToTheOwnerWhenAllowed() throws {
        let ledgerB = try shareAToB(canEdit: true)
        let context = ModelContext(containerB)
        let theirs = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Negroni" && $0.library != nil })
        theirs.method = "Guest's way"
        try context.save()

        let changes = try ledgerB.localChanges(changed: [theirs.persistentModelID], scope: .shared)
        XCTAssertEqual(changes.saves, [sharedNegroniID()])
        let record = try XCTUnwrap(try ledgerB.record(for: sharedNegroniID()))
        XCTAssertEqual(record.recordID.zoneID.ownerName, "_owner", "Sent to the owner's library")
        XCTAssertEqual(record["method"] as? String, "Guest's way")
        XCTAssertFalse(try ledgerB.localChanges(scope: .private).saves.contains { $0.zoneID.ownerName == "_owner" })

        // A recipe added to their library goes there too.
        let library = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Library>()).first)
        let added = DB.Cocktail(name: "Guest Sour")
        context.insert(added)
        added.library = library
        try context.save()
        XCTAssertTrue(try ledgerB.localChanges(changed: [added.persistentModelID], scope: .shared).saves
            .contains(CKRecord.ID(recordName: added.id.uuidString, zoneID: ownerZone)))
    }

    @MainActor
    func testLosingEditPermissionMakesItViewOnly() throws {
        let ledgerB = try shareAToB(canEdit: true)
        let context = ModelContext(containerB)
        let theirs = try XCTUnwrap(try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Negroni" && $0.library != nil })
        theirs.method = "Guest's way"
        try context.save()
        _ = try ledgerB.localChanges(changed: [theirs.persistentModelID], scope: .shared)
        let record = try XCTUnwrap(try ledgerB.record(for: sharedNegroniID()))

        XCTAssertEqual(try ledgerB.resolveFailedSave(record, error: CKError(.permissionFailure)), .nowViewOnly)
        XCTAssertEqual(try sharedLibrary(in: containerB)?.canEdit, false)
        XCTAssertTrue(try ledgerB.localChanges(scope: .shared).isEmpty)
    }

    // MARK: Owner's changes and removal

    @MainActor
    func testTheOwnersDeletionsArrive() throws {
        let ledgerB = try shareAToB(canEdit: false)
        try ledgerB.applyFetched(modifications: [], deletions: [(recordID: sharedNegroniID(), recordType: "Cocktail")])
        let remaining = try negronis(in: containerB)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNil(remaining.first?.library, "Only theirs was deleted")
    }

    @MainActor
    func testStoppingSharingRemovesTheLibraryAndKeepsYours() throws {
        let ledgerB = try shareAToB(canEdit: false)
        try ledgerB.removeLibrary(zoneID: ownerZone)
        XCTAssertNil(try sharedLibrary(in: containerB))
        XCTAssertEqual(try ModelContext(containerB).fetchCount(FetchDescriptor<DB.Cocktail>()), SeedData.classics.count)
        XCTAssertNil(try ledgerB.bookkeeping(for: sharedNegroniID()))
    }

    @MainActor
    func testRemovingALibraryGivesItsNameForTheNotice() throws {
        let ledgerB = try shareAToB(canEdit: false)
        XCTAssertEqual(try ledgerB.removeLibrary(zoneID: ownerZone), "Bill's Library")
        XCTAssertNil(try ledgerB.removeLibrary(zoneID: ownerZone), "Already gone: nothing to tell")
    }

    @MainActor
    func testAMissingSharedZoneMeansTheLibraryIsGone() throws {
        let ledgerB = try shareAToB(canEdit: true)
        let record = CloudRecords.record(for: try XCTUnwrap(try negronis(in: containerB).first { $0.library != nil }),
                                         systemFields: nil, libraryOwner: "_owner")
        XCTAssertEqual(try ledgerB.resolveFailedSave(record, error: CKError(.zoneNotFound)), .libraryRemoved)
        XCTAssertNil(try sharedLibrary(in: containerB))
    }

    @MainActor
    func testSigningOutRemovesSharedLibrariesOnly() throws {
        let ledgerB = try shareAToB(canEdit: false)
        try ledgerB.resetAll(scope: .shared)
        XCTAssertNil(try sharedLibrary(in: containerB))
        XCTAssertEqual(try negronis(in: containerB).count, 1, "Your own collection stays")
    }

    @MainActor
    func testAShareRecordAloneCreatesTheLibrary() throws {
        let ledgerB = CloudSyncLedger(container: containerB)
        try ledgerB.applyFetched(modifications: [CKShare(recordZoneID: ownerZone)], deletions: [])
        let library = try XCTUnwrap(try sharedLibrary(in: containerB))
        XCTAssertEqual(library.zoneOwnerName, "_owner")
        XCTAssertEqual(library.zoneName, "Library")
        // Whether you can edit comes from your place in the share. A share made in a test has no invited
        // participant (its creator counts as you, with full access), so that part is checked on devices.
    }

    // MARK: Names

    func testLibraryNames() {
        XCTAssertEqual(CloudSyncLedger.libraryName(ownerName: "Bill"), "Bill's Library")
        XCTAssertEqual(CloudSyncLedger.libraryName(ownerName: "James"), "James' Library")
        XCTAssertEqual(CloudSyncLedger.libraryName(ownerName: nil), "Shared Library")
        XCTAssertEqual(CloudSyncLedger.libraryName(ownerName: "  "), "Shared Library")
        XCTAssertEqual(SharedLibraryRow.detail(canEdit: true, cocktailCount: 42), "Can edit · 42 cocktails")
        XCTAssertEqual(SharedLibraryRow.detail(canEdit: false, cocktailCount: 1), "View only · 1 cocktail")
    }
}

/// Copying a recipe from a library shared with you into My Library (sync and sharing, step 4b).
final class CopyToMyLibraryTests: StoreTestCase {
    @MainActor
    private func sharedSour() throws -> DB.Cocktail {
        let library = AppStartup.addSampleSharedLibrary(to: context)
        return try XCTUnwrap(library.cocktails?.first { $0.name == "Shared Sour" })
    }

    @MainActor
    func testACopyIsYoursAndUsesYourTypes() throws {
        let original = try sharedSour()
        let copy = try CocktailStore(context: context).copyToMyLibrary(original)

        XCTAssertNil(copy.library, "The copy is in My Library")
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, "Shared Sour")
        XCTAssertEqual(copy.method, original.method)
        XCTAssertEqual(copy.template, .daiquiri)
        XCTAssertFalse(copy.isFavorite)
        XCTAssertEqual(copy.orderedIngredients.map(\.displayText), original.orderedIngredients.map(\.displayText))
        XCTAssertNil(copy.baseStyle?.library, "Linked to your London Dry, not theirs")
        XCTAssertEqual(copy.baseStyle?.name, "London Dry")
        XCTAssertNil(copy.orderedIngredients.first?.style?.library)

        XCTAssertNotNil(original.library, "The original stays in their library")
        XCTAssertTrue(try CocktailStore(context: context).cocktails().contains { $0 === copy })
        XCTAssertFalse(try CocktailStore(context: context).cocktails().contains { $0 === original })
    }

    @MainActor
    func testACopyOfANameYouHaveIsNamedAfterTheOwner() throws {
        let original = try sharedSour()
        try CocktailStore(context: context).addCocktail(name: "Shared Sour")
        let store = CocktailStore(context: context)
        XCTAssertEqual(try store.copyToMyLibrary(original).name, "Shared Sour (Bill)")
        XCTAssertEqual(try store.copyToMyLibrary(original).name, "Shared Sour (Bill) 2")
    }

    @MainActor
    func testACopyWithNoOwnerNameSaysCopy() throws {
        let original = try sharedSour()
        original.library?.ownerName = ""
        try CocktailStore(context: context).addCocktail(name: "Shared Sour")
        XCTAssertEqual(try CocktailStore(context: context).copyName(for: original), "Shared Sour (Copy)")
    }

    func testMenuCocktailCount() {
        XCTAssertEqual(SharedLibraryView.cocktailCount(1), "1 cocktail")
        XCTAssertEqual(SharedLibraryView.cocktailCount(5), "5 cocktails")
    }
}

/// Step 5 polish: who you share with, offline status, and built-ins you delete staying deleted.
final class SyncPolishTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var cloud: UserDefaults!
    private var suites: [String] = []

    override func setUpWithError() throws {
        container = try CocktailModelContainer.make(inMemory: true)
        context = ModelContext(container)
        suites = ["SyncPolish-\(UUID().uuidString)", "SyncPolishCloud-\(UUID().uuidString)"]
        defaults = UserDefaults(suiteName: suites[0])
        cloud = UserDefaults(suiteName: suites[1])
    }

    override func tearDownWithError() throws {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        context = nil
        container = nil
    }

    private func cocktail(_ name: String) throws -> DB.Cocktail? {
        try context.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == name && $0.library == nil }
    }

    // MARK: Who you share with

    func testPeopleAreNamedAndDescribed() {
        var components = PersonNameComponents()
        components.givenName = "Jane"
        components.familyName = "Doe"
        XCTAssertEqual(LibrarySharing.displayName(nameComponents: components, email: "jane@example.com", phone: nil), "Jane Doe")
        XCTAssertEqual(LibrarySharing.displayName(nameComponents: nil, email: "jane@example.com", phone: nil), "jane@example.com")
        XCTAssertEqual(LibrarySharing.displayName(nameComponents: nil, email: nil, phone: "+1 555 0100"), "+1 555 0100")
        XCTAssertEqual(LibrarySharing.displayName(nameComponents: nil, email: nil, phone: nil), "Invited person")
        XCTAssertEqual(LibrarySharing.personDetail(canEdit: true, isPending: false), "Can edit")
        XCTAssertEqual(LibrarySharing.personDetail(canEdit: false, isPending: true), "View only · Invited")
    }

    func testANewShareHasNoOneInIt() {
        XCTAssertEqual(LibrarySharing.people(in: CKShare(recordZoneID: CloudSchema.libraryZoneID())), [])
    }

    // MARK: Offline

    func testGoingOfflineAndComingBack() {
        let offline = CloudSyncState.problem(CloudSyncState.offlineMessage)
        XCTAssertEqual(CloudSyncState.upToDate(Date()).afterNetworkChange(isOnline: false), offline)
        XCTAssertEqual(CloudSyncState.syncing.afterNetworkChange(isOnline: false), offline)
        XCTAssertNil(CloudSyncState.notSignedIn.afterNetworkChange(isOnline: false), "Not signed in says more")
        XCTAssertNil(CloudSyncState.off.afterNetworkChange(isOnline: false))
        XCTAssertEqual(offline.afterNetworkChange(isOnline: true), .syncing, "Back online: sync again")
        XCTAssertNil(CloudSyncState.problem("Storage full").afterNetworkChange(isOnline: true), "Other problems stay")
        XCTAssertNil(CloudSyncState.upToDate(Date()).afterNetworkChange(isOnline: true))
        XCTAssertEqual(CloudSync.message(for: CKError(.networkUnavailable)), CloudSyncState.offlineMessage)
    }

    // MARK: Deleted built-ins

    func testDeletingABuiltInIsRememberedButNotYourOwn() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)
        let negroni = try XCTUnwrap(try cocktail("Negroni"))
        negroni.name = "Our Negroni" // Renamed built-ins still count.
        BuiltInDeletions.noteDeleted(negroni, in: defaults)
        let mine = try CocktailStore(context: context).addCocktail(name: "Bill's Sour")
        BuiltInDeletions.noteDeleted(mine, in: defaults)
        let londonDry = try XCTUnwrap(try StyleStore(context: context).style(named: "London Dry"))
        BuiltInDeletions.noteDeleted(londonDry, in: defaults)

        XCTAssertEqual(BuiltInDeletions.ids(in: defaults),
                       [BuiltInID.cocktail(named: "Negroni"), BuiltInID.style(named: "London Dry")])
        XCTAssertEqual(BuiltInDeletions.ids(in: nil), [], "Nothing is remembered without a store")
    }

    func testDeletedBuiltInsArentAddedAgain() throws {
        BuiltInDeletions.record(BuiltInID.cocktail(named: "Negroni"), in: defaults)
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        XCTAssertNil(try cocktail("Negroni"), "Deleted on another device")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.Cocktail>()), SeedData.classics.count - 1)
    }

    func testBuiltInsDeletedElsewhereAreRemovedHereButYourOwnStay() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: nil)
        let mine = try CocktailStore(context: context).addCocktail(name: "Bill's Sour")
        try ModelSeeder.removeDeletedBuiltIns(context: context, deleted: [BuiltInID.cocktail(named: "Negroni"), mine.id])
        XCTAssertNil(try cocktail("Negroni"))
        XCTAssertNotNil(try cocktail("Bill's Sour"), "Only built-ins are removed")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DB.Cocktail>()), SeedData.classics.count)
    }

    func testAFavoriteAddedBackByHandStays() throws {
        let favorite = try XCTUnwrap(SeedData.favorites.first)
        let fixedID = BuiltInID.cocktail(named: favorite.name)
        BuiltInDeletions.record(fixedID, in: defaults)

        try ModelSeeder.addHouseFavorites(context: context, deletions: defaults)
        let added = try XCTUnwrap(try cocktail(favorite.name))
        XCTAssertNotEqual(added.id, fixedID, "A new ID, so it isn't removed as deleted")

        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)
        XCTAssertNotNil(try cocktail(favorite.name), "Starting up keeps it")
        XCTAssertNotEqual(try cocktail(favorite.name)?.id, fixedID)
    }

    @MainActor
    func testDeletedListsAreCombinedAcrossDevices() {
        defaults.set(["A"], forKey: BuiltInDeletions.key)
        cloud.set(["B"], forKey: BuiltInDeletions.key)
        let sync = SettingsSync(local: defaults, cloud: cloud)
        sync.mergeAtLaunch()
        XCTAssertEqual(defaults.stringArray(forKey: BuiltInDeletions.key), ["A", "B"])
        XCTAssertEqual(cloud.stringArray(forKey: BuiltInDeletions.key), ["A", "B"])

        cloud.set(["A", "B", "C"], forKey: BuiltInDeletions.key)
        XCTAssertTrue(sync.cloudDidChange(keys: [BuiltInDeletions.key]), "Another device deleted something")
        XCTAssertEqual(defaults.stringArray(forKey: BuiltInDeletions.key), ["A", "B", "C"])
        XCTAssertFalse(sync.cloudDidChange(keys: [BuiltInDeletions.key]), "Nothing new")

        defaults.set(["A", "B", "C", "D"], forKey: BuiltInDeletions.key)
        sync.localDidChange()
        XCTAssertEqual(cloud.stringArray(forKey: BuiltInDeletions.key), ["A", "B", "C", "D"])
    }
}

