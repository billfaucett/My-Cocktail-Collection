//
//  My_Cocktail_CollectionTests.swift
//  My Cocktail CollectionTests
//
//  Created by William Faucett on 2/24/24.
//

import XCTest
import CoreData
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

    private func load(_ container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }
}
