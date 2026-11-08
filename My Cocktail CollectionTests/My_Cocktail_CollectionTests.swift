//
//  My_Cocktail_CollectionTests.swift
//  My Cocktail CollectionTests
//
//  Created by William Faucett on 2/24/24.
//

import XCTest
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
    private typealias V1 = CocktailSchemaV1
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

    func testSchemaHasSevenModelsAtVersionOne() {
        XCTAssertEqual(V1.models.count, 7)
        XCTAssertEqual(V1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(CocktailMigrationPlan.schemas.count, 1)
    }

    // MARK: Defaults and enums

    func testDefaultsAndEnumsRoundTrip() throws {
        let style = V1.SpiritStyle(name: "Bourbon", family: .whiskey, isBuiltIn: true)
        let bottle = V1.Bottle(brand: "Buffalo Trace")
        let cocktail = V1.Cocktail(name: "Old Fashioned", source: .classic)
        let ingredient = V1.RecipeIngredient(position: 0, name: "Bourbon", amount: 2, unit: .part)
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
        let style = V1.SpiritStyle(name: "Mystery", family: .other)
        style.familyRaw = "notAFamily"
        XCTAssertEqual(style.family, .other)
        let cocktail = V1.Cocktail(name: "Mystery")
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
        let bottle = V1.Bottle(brand: "Buffalo Trace")
        context.insert(bottle)
        bottle.style = bourbon
        let cocktail = V1.Cocktail(name: "Old Fashioned")
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
        let ingredient = V1.RecipeIngredient(parsed: parsed, position: 4)
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
        XCTAssertEqual(try count(V1.RecipeIngredient.self), 3)
        XCTAssertEqual(try count(V1.MenuEntry.self), 1)

        context.delete(cocktail)
        try context.save()

        XCTAssertEqual(try count(V1.RecipeIngredient.self), 0)
        XCTAssertEqual(try count(V1.MenuEntry.self), 0, "No orphaned menu entries")
        XCTAssertEqual(try count(V1.Menu.self), 1, "The menu itself stays")
        XCTAssertEqual(menu.entries?.count ?? 0, 0)
    }

    func testDeletingAMenuRemovesItsEntriesButKeepsCocktails() throws {
        let negroni = insertCocktail("Negroni", ingredients: ["Gin"])
        let martini = insertCocktail("Martini", ingredients: ["Gin"])
        let menu = insertMenu("Friday Night", cocktails: [negroni, martini])
        try context.save()

        context.delete(menu)
        try context.save()

        XCTAssertEqual(try count(V1.MenuEntry.self), 0)
        XCTAssertEqual(try count(V1.Cocktail.self), 2)
        XCTAssertEqual(negroni.menuEntries?.count ?? 0, 0)
    }

    func testDeletingAStyleKeepsWhatUsedIt() throws {
        let gin = insertStyle("London Dry", .gin)
        let bottle = V1.Bottle(brand: "Tanqueray")
        context.insert(bottle)
        bottle.style = gin
        let cocktail = insertCocktail("Martini", ingredients: ["Gin"])
        cocktail.baseStyle = gin
        cocktail.orderedIngredients.first?.style = gin
        try context.save()

        context.delete(gin)
        try context.save()

        XCTAssertEqual(try count(V1.Bottle.self), 1)
        XCTAssertNil(bottle.style)
        XCTAssertEqual(try count(V1.Cocktail.self), 1)
        XCTAssertNil(cocktail.baseStyle)
        XCTAssertEqual(try count(V1.RecipeIngredient.self), 1)
        XCTAssertNil(cocktail.orderedIngredients.first?.style)
    }

    func testDeletingABottleChangesNothingElse() throws {
        let gin = insertStyle("London Dry", .gin)
        let bottle = V1.Bottle(brand: "Tanqueray")
        context.insert(bottle)
        bottle.style = gin
        try context.save()

        context.delete(bottle)
        try context.save()

        XCTAssertEqual(try count(V1.SpiritStyle.self), 1)
        XCTAssertEqual(gin.bottles?.count ?? 0, 0)
    }

    // MARK: Fetching

    func testFetchFavorites() throws {
        let negroni = insertCocktail("Negroni", ingredients: [])
        _ = insertCocktail("Martini", ingredients: [])
        negroni.isFavorite = true
        try context.save()

        let favorites = try context.fetch(FetchDescriptor<V1.Cocktail>(predicate: #Predicate { $0.isFavorite }))
        XCTAssertEqual(favorites.map(\.name), ["Negroni"])
    }

    // MARK: Helpers

    private func insertStyle(_ name: String, _ family: SpiritFamily) -> V1.SpiritStyle {
        let style = V1.SpiritStyle(name: name, family: family)
        context.insert(style)
        return style
    }

    private func insertCocktail(_ name: String, ingredients names: [String]) -> V1.Cocktail {
        let cocktail = V1.Cocktail(name: name)
        context.insert(cocktail)
        for (position, ingredientName) in names.enumerated() {
            let ingredient = V1.RecipeIngredient(position: position, name: ingredientName, amount: 1, unit: .part)
            context.insert(ingredient)
            ingredient.cocktail = cocktail
        }
        return cocktail
    }

    @discardableResult
    private func insertMenu(_ name: String, cocktails: [V1.Cocktail]) -> V1.Menu {
        let menu = V1.Menu(name: name)
        context.insert(menu)
        for (position, cocktail) in cocktails.enumerated() {
            let entry = V1.MenuEntry(position: position)
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

    func style(_ name: String) throws -> V1.SpiritStyle {
        try XCTUnwrap(try StyleStore(context: context).style(named: name), "No style named \(name)")
    }

    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}

final class StyleStoreTests: StoreTestCase {
    private var styles: StyleStore { StyleStore(context: context) }

    func testBuiltInStylesAreThereInOrder() throws {
        XCTAssertEqual(try count(V1.SpiritStyle.self), SpiritTaxonomy.builtInStyles.count)
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
        XCTAssertEqual(try count(V1.Bottle.self), 1)
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
        XCTAssertEqual(try count(V1.Bottle.self), 0)
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
        XCTAssertEqual(try count(V1.RecipeIngredient.self), 2, "Old rows are deleted, not left behind")
    }

    func testCocktailNeedsANameAndValidRating() throws {
        XCTAssertThrowsError(try cocktails.addCocktail(name: "  "))
        XCTAssertThrowsError(try cocktails.addCocktail(name: "Too Good", rating: 11))
        XCTAssertEqual(try count(V1.Cocktail.self), 0)
        XCTAssertEqual(try count(V1.RecipeIngredient.self), 0)
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

        XCTAssertEqual(try count(V1.RecipeIngredient.self), 0)
        XCTAssertEqual(try count(V1.MenuEntry.self), 0)
        XCTAssertEqual(try count(V1.Menu.self), 1)
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
        XCTAssertTrue(rows[0].style === (try style("Bourbon")))
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
        XCTAssertEqual(try count(V1.RecipeIngredient.self), 3, "Old rows are deleted, not left behind")
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

    private func cocktail(_ name: String) throws -> V1.Cocktail {
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
        XCTAssertEqual(try count(V1.Cocktail.self), 3, "Removing from a menu keeps the cocktail")
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
        XCTAssertEqual(try count(V1.Menu.self), 0)
        XCTAssertEqual(try count(V1.MenuEntry.self), 0)
        XCTAssertEqual(try count(V1.Cocktail.self), 1)
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

    private func cocktails() throws -> [V1.Cocktail] {
        try context.fetch(FetchDescriptor<V1.Cocktail>())
    }

    func testFreshSeedAddsStylesAndClassicsInParts() throws {
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count)
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
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count)
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

        let bottles = try context.fetch(FetchDescriptor<V1.Bottle>())
        let buffalo = try XCTUnwrap(bottles.first { $0.brand == "Buffalo Trace" })
        XCTAssertEqual(buffalo.style?.name, "Bourbon")
        XCTAssertEqual(buffalo.stock, .low)
        XCTAssertEqual(buffalo.bottleCount, 2)
        XCTAssertTrue(buffalo.isFavorite)
        XCTAssertEqual(buffalo.rating, 8)
        XCTAssertEqual(buffalo.notes, "Go-to")
        XCTAssertEqual(bottles.first { $0.brand == "Aperol" }?.style?.name, "Aperitivo")

        let menu = try XCTUnwrap(try context.fetch(FetchDescriptor<V1.Menu>()).first)
        XCTAssertEqual(menu.orderedEntries.compactMap { $0.cocktail?.name }, ["Manhattan", "Old Fashioned"])

        let styles = StyleStore(context: context)
        XCTAssertEqual(try styles.style(named: "Japanese Whiskey Blend")?.family, .whiskey)
        XCTAssertEqual(try styles.style(named: "Amaro")?.isBuiltIn, true, "Amaro matches the built-in style")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count + 1)
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
        XCTAssertNil(try context.fetch(FetchDescriptor<V1.Cocktail>()).first { $0.name == "Daquiri" }, "Renamed during import")
        XCTAssertEqual(daquiri.baseStyle?.name, "Rum", "Rum maps to the general style")
        XCTAssertEqual(daquiri.orderedIngredients.first?.style?.name, "White Rum")
        XCTAssertEqual(try context.fetch(FetchDescriptor<V1.Bottle>()).first?.style?.name, "Rum")
    }

    // MARK: Safety

    func testImportRunsOnlyOnce() throws {
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            _ = self.drink("Negroni", base: nil, ingredients: "1 oz Gin\n1 oz Campari\n1 oz Sweet Vermouth", in: old)
        }

        XCTAssertNotNil(try importer().importIfNeeded())
        XCTAssertNil(try importer().importIfNeeded(), "Second launch does nothing")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.Cocktail>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.ImportRecord>()), 1)
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

        let bottle = try XCTUnwrap(try context.fetch(FetchDescriptor<V1.Bottle>()).first)
        XCTAssertEqual(bottle.photo?.count, largePhoto.count)
        XCTAssertEqual(bottle.photo, largePhoto)
    }

    func testFailedImportLeavesNothingBehind() throws {
        try Data("not a database".utf8).write(to: storeURL)

        XCTAssertThrowsError(try importer().runImport())

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.Cocktail>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.ImportRecord>()), 0, "No marker, so it can try again")
    }

    func testEmptyNamesGetFallbacks() throws {
        try makeLegacyStore(version: "CocktailRecipe 3") { old in
            _ = self.drink("   ", base: nil, ingredients: "", in: old)
            _ = self.menu("", in: old)
        }

        try importer().runImport()

        XCTAssertEqual(try context.fetch(FetchDescriptor<V1.Cocktail>()).first?.name, "Untitled Cocktail")
        XCTAssertEqual(try context.fetch(FetchDescriptor<V1.Menu>()).first?.name, "Untitled Menu")
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

        let names = Set(try context.fetch(FetchDescriptor<V1.Cocktail>()).map(\.name))
        XCTAssertFalse(names.contains("Negroni"), "Deleted in the old app, so not added back")
        XCTAssertTrue(names.contains("Gimlet"), "Never offered by the old app, so added")
        XCTAssertEqual(names.filter { $0 == "Martini" }.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count)
    }

    // MARK: Helpers

    private func importer(defaults: UserDefaults? = nil) -> LegacyImporter {
        LegacyImporter(context: context, legacyStoreURL: storeURL, defaults: defaults)
    }

    private func cocktail(_ name: String) throws -> V1.Cocktail {
        try XCTUnwrap(try context.fetch(FetchDescriptor<V1.Cocktail>()).first { $0.name == name }, "No cocktail named \(name)")
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

    func cocktail(_ name: String) throws -> V1.Cocktail {
        try XCTUnwrap(try context.fetch(FetchDescriptor<V1.Cocktail>()).first { $0.name == name }, "No cocktail named \(name)")
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
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count + 2)
    }

    func testMenus() throws {
        try importer(defaults: defaults).runImport()
        let menus = try context.fetch(FetchDescriptor<V1.Menu>())

        let friday = try XCTUnwrap(menus.first { $0.name == "Friday Night" })
        XCTAssertEqual(friday.orderedEntries.compactMap { $0.cocktail?.name }, ["Daiquiri", "Garden Gimlet", "Old Fashioned"])
        XCTAssertEqual(menus.first { $0.name == "Holiday Party" }?.entries?.count ?? -1, 0)
        XCTAssertEqual(menus.first { $0.name == "Untitled Menu" }?.orderedEntries.compactMap { $0.cocktail?.name }, ["Martini"])
    }

    // MARK: After the import, the first launch seeds

    func testSeedingAfterImportAddsOnlyTheNewClassics() throws {
        try importer(defaults: defaults).runImport()
        try ModelSeeder.seedBuiltIns(context: context, defaults: defaults)

        let names = try context.fetch(FetchDescriptor<V1.Cocktail>()).map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "No duplicates")
        XCTAssertFalse(names.contains("Cosmopolitan"), "Deleted in the old app, so it stays deleted")
        XCTAssertFalse(names.contains("Daquiri"))
        XCTAssertTrue(names.contains("Negroni"), "New classics arrive")
        XCTAssertEqual(names.count, 15 + 31, "15 imported + 31 new classics (36 minus the original five)")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<V1.SpiritStyle>()), SpiritTaxonomy.builtInStyles.count + 2)
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

