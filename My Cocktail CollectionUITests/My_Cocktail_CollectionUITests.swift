//
//  My_Cocktail_CollectionUITests.swift
//  My Cocktail CollectionUITests
//
//  Created by William Faucett on 2/24/24.
//

import XCTest

final class My_Cocktail_CollectionUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // The app allows landscape, and a Simulator left sideways hides most of each form. Always test upright.
        XCUIDevice.shared.orientation = .portrait

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Swiping to delete a cocktail removes that cocktail and no other.
    /// Before the fix, every row shared one alert flag, so the wrong drink could be deleted.
    func testSwipeToDeleteRemovesTheSwipedCocktail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] // fresh in-memory database seeded with the classic cocktails
        app.launch()

        let aviation = app.staticTexts["Aviation"]
        XCTAssertTrue(aviation.waitForExistence(timeout: 5), "The seeded classics should be listed")
        // The first rows alphabetically, so they are on screen on every iPhone.
        let others = ["Aperol Spritz", "Bee's Knees", "Bloody Mary"]
        for name in others {
            XCTAssertTrue(app.staticTexts[name].exists, "\(name) should be listed before deleting")
        }

        revealSwipeAction("Delete", on: aviation, in: app).tap()

        let alert = app.alerts["Confirm Delete"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["Are you sure you want to delete Aviation?"].exists,
                      "The alert should name the drink that was swiped")
        alert.buttons["Delete"].tap()

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: aviation)
        wait(for: [gone], timeout: 3)
        for name in others {
            XCTAssertTrue(app.staticTexts[name].exists, "\(name) should not have been deleted")
        }
    }

    /// Cancelling the alert keeps the cocktail.
    func testCancellingSwipeDeleteKeepsTheCocktail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let aviation = app.staticTexts["Aviation"]
        XCTAssertTrue(aviation.waitForExistence(timeout: 5))

        revealSwipeAction("Delete", on: aviation, in: app).tap()
        let alert = app.alerts["Confirm Delete"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Cancel"].tap()

        XCTAssertTrue(aviation.waitForExistence(timeout: 2))
    }

    /// Swipe right to favorite a cocktail, then Show Favorites lists only favorites until turned off.
    func testShowFavoritesFiltersTheCocktailList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let aviation = app.staticTexts["Aviation"]
        let aperolSpritz = app.staticTexts["Aperol Spritz"]
        XCTAssertTrue(aviation.waitForExistence(timeout: 5))
        XCTAssertTrue(aperolSpritz.exists)

        // A full swipe favorites immediately; a shorter one reveals the Favorite button.
        aviation.swipeRight()
        let favoriteButton = app.buttons["Favorite"]
        if favoriteButton.waitForExistence(timeout: 1) {
            favoriteButton.tap()
        }

        app.buttons["Show Favorites"].tap()
        XCTAssertTrue(aviation.waitForExistence(timeout: 2), "The favorite should still be listed")
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: aperolSpritz)
        wait(for: [hidden], timeout: 3)

        app.buttons["Show All"].tap()
        XCTAssertTrue(aperolSpritz.waitForExistence(timeout: 2), "Show All should bring every cocktail back")
    }

    /// Tapping a row's heart favorites the cocktail without opening it; tapping again undoes it.
    func testTappingTheHeartFavoritesACocktail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let row = app.cells.containing(.staticText, identifier: "Aviation").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.buttons["Add to Favorites"].tap()
        XCTAssertTrue(row.buttons["Remove from Favorites"].waitForExistence(timeout: 2), "The heart fills in")
        XCTAssertTrue(app.navigationBars["My Cocktails"].exists, "Tapping the heart doesn't open the recipe")

        app.buttons["Show Favorites"].tap()
        XCTAssertTrue(app.staticTexts["Aviation"].waitForExistence(timeout: 2))
        let aperolGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Aperol Spritz"])
        wait(for: [aperolGone], timeout: 3)

        // Wait for the filtered list to finish animating before tapping, so the tap lands on the heart.
        let removeButton = app.cells.containing(.staticText, identifier: "Aviation").firstMatch.buttons["Remove from Favorites"]
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: removeButton)
        wait(for: [ready], timeout: 3)
        removeButton.tap()

        XCTAssertFalse(app.navigationBars["Aviation"].waitForExistence(timeout: 1),
                       "Tapping the heart opened the recipe instead of unfavoriting")
        XCTAssertTrue(app.staticTexts["No Favorites"].waitForExistence(timeout: 3),
                      "Unfavoriting the only favorite empties the Show Favorites list")
    }

    /// The Spirits tab lists built-in spirit types from the new database, and search narrows them.
    func testStylesTabListsStyles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.tabBars.buttons["Spirits"].tap()
        XCTAssertTrue(app.staticTexts["Bourbon"].waitForExistence(timeout: 5), "Whiskey styles come first")
        XCTAssertTrue(app.staticTexts["Rye"].exists)

        // The Styles search bar is always visible; some iOS versions show it as a Search button first.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) {
            let searchButton = app.buttons["Search"].firstMatch
            if searchButton.exists {
                searchButton.tap()
            }
        }
        XCTAssertTrue(search.waitForExistence(timeout: 3), "The search field is available")
        search.tap()
        search.typeText("Aperitivo")
        XCTAssertTrue(app.staticTexts["Aperitivo"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Bourbon"].exists, "Search hides other styles")
    }

    /// Adding a bottle on the My Bar tab lists it, and tapping it opens it for editing.
    func testAddingABottleListsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.tabBars.buttons["My Bar"].tap()
        let addButton = app.buttons["Add Bottle"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // The form opens with the Scan Label section first, so the brand field may be further down.
        XCTAssertTrue(app.navigationBars["Add Bottle"].waitForExistence(timeout: 5), "The Add Bottle form opens")
        let brand = scrollTo(app.textFields["Brand or name (e.g. Buffalo Trace)"], in: app)
        XCTAssertTrue(brand.exists, "The brand field is on the form")
        brand.tap()
        brand.typeText("Test Bottle")
        app.navigationBars["Add Bottle"].buttons["Save"].tap()

        let row = app.staticTexts["Test Bottle"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The new bottle should be listed")
        XCTAssertTrue(app.staticTexts["No Type"].exists, "A bottle with no type is listed under No Type")

        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Bottle"].waitForExistence(timeout: 3))
        app.navigationBars["Edit Bottle"].buttons["Cancel"].tap()
    }

    /// Creating a menu opens it, and cocktails picked from the collection are added to it.
    func testCreatingAMenuAndAddingCocktails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.tabBars.buttons["Menus"].tap()
        let newMenu = app.buttons["New Menu"].firstMatch
        XCTAssertTrue(newMenu.waitForExistence(timeout: 5))
        newMenu.tap()

        let name = app.textFields["Menu name (e.g. Friday Night)"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Test Night")
        app.navigationBars["New Menu"].buttons["Create"].tap()

        XCTAssertTrue(app.navigationBars["Test Night"].waitForExistence(timeout: 3), "A new menu opens straight away")
        app.buttons["Add Cocktails"].firstMatch.tap()

        let aviation = app.buttons.containing(.staticText, identifier: "Aviation").firstMatch
        XCTAssertTrue(aviation.waitForExistence(timeout: 3))
        aviation.tap()
        app.navigationBars["Add Cocktails"].buttons["Add (1)"].tap()

        XCTAssertTrue(app.staticTexts["Aviation"].waitForExistence(timeout: 3), "The picked cocktail is on the menu")
    }

    /// A whole recipe entered by tapping: Bourbon → 2, Angostura Bitters → 4, Simple Syrup → 1, Orange Peel (one tap).
    func testAddingIngredientsByTapping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let addCocktail = app.buttons["Add Cocktail"].firstMatch
        XCTAssertTrue(addCocktail.waitForExistence(timeout: 5))
        addCocktail.tap()
        let name = app.textFields["Name (e.g. Old Fashioned)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Tapped Old Fashioned\n") // Return closes the keyboard

        scrollTo(app.buttons["Add Ingredient"].firstMatch, in: app).tap()
        XCTAssertTrue(app.navigationBars["Add Ingredients"].waitForExistence(timeout: 5))
        let search = app.searchFields["Search or add an ingredient"]

        /// Finds the ingredient, opens its row, and taps the amount (or nothing, for one-tap garnishes).
        func pick(search text: String, item: String, amount: String?) {
            search.tap()
            search.typeText(text)
            let row = app.buttons["catalog.\(item)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 3), "\(item) is in the list")
            row.tap()
            if let amount {
                let button = app.buttons["amount.\(amount)"].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 3), "\(item) opens with amount \(amount)")
                button.tap()
            }
        }
        pick(search: "bourbon", item: "Bourbon", amount: "2")
        pick(search: "ango", item: "Angostura Bitters", amount: "4")
        pick(search: "simple", item: "Simple Syrup", amount: "1")
        pick(search: "orange peel", item: "Orange Peel", amount: nil)

        for line in ["2 parts Bourbon", "4 dashes Angostura Bitters", "1 part Simple Syrup", "Orange Peel, to garnish"] {
            XCTAssertTrue(app.staticTexts[line].waitForExistence(timeout: 3), "\(line) is in the recipe")
        }
        app.navigationBars["Add Ingredients"].buttons["Done"].tap()
        // On the form each row is a button, so its text is part of the button's label.
        XCTAssertTrue(app.navigationBars["Add Cocktail"].waitForExistence(timeout: 3), "Back on the cocktail form")
        let formRow = scrollTo(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "4 dashes Angostura Bitters")).firstMatch, in: app)
        XCTAssertTrue(formRow.exists, "The rows are on the cocktail form")
        app.navigationBars["Add Cocktail"].buttons["Save"].tap()
        let formClosed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Add Cocktail"])
        wait(for: [formClosed], timeout: 5)
        XCTAssertTrue(scrollTo(app.staticTexts["Tapped Old Fashioned"], in: app, maxSwipes: 10).exists, "The cocktail is saved and listed")
    }

    /// An ingredient that isn't in the list can be added from the search field, then given an amount.
    func testAddingANewIngredientFromSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let addCocktail = app.buttons["Add Cocktail"].firstMatch
        XCTAssertTrue(addCocktail.waitForExistence(timeout: 5))
        addCocktail.tap()
        XCTAssertTrue(app.navigationBars["Add Cocktail"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Add Ingredient"].firstMatch, in: app).tap()
        let search = app.searchFields["Search or add an ingredient"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Smoked Maple Syrup")
        app.buttons["catalog.addNew"].tap()
        let half = app.buttons["amount.½"].firstMatch
        XCTAssertTrue(half.waitForExistence(timeout: 3), "A new syrup opens with amounts in parts")
        half.tap()
        XCTAssertTrue(app.staticTexts["½ part Smoked Maple Syrup"].waitForExistence(timeout: 3))
    }

    /// The row editor suggests ingredient names while typing; tapping one fills in the exact name.
    func testEditorSuggestsIngredientNames() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let addCocktail = app.buttons["Add Cocktail"].firstMatch
        XCTAssertTrue(addCocktail.waitForExistence(timeout: 5))
        addCocktail.tap()
        XCTAssertTrue(app.navigationBars["Add Cocktail"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Add Ingredient"].firstMatch, in: app).tap()

        // Add 2 parts Bourbon with quick add, then open that row in the editor.
        let search = app.searchFields["Search or add an ingredient"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("bourbon")
        app.buttons["catalog.Bourbon"].firstMatch.tap()
        app.buttons["amount.2"].firstMatch.tap()
        app.navigationBars["Add Ingredients"].buttons["Done"].tap()
        let row = scrollTo(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2 parts Bourbon")).firstMatch, in: app)
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Ingredient"].waitForExistence(timeout: 3))

        // Replace the name by typing a few letters and tapping a suggestion.
        let name = scrollTo(app.textFields["Name (e.g. Bourbon, Lime Juice)"], in: app)
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "ango")
        let suggestion = app.buttons["suggestion.Angostura Bitters"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3), "Angostura Bitters is suggested")
        suggestion.tap()
        XCTAssertEqual(name.value as? String, "Angostura Bitters", "The exact name is filled in")
    }

    /// Settings opens an About screen with the version, build and data model.
    func testAboutScreenShowsVersions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let more = app.navigationBars["My Cocktails"].buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Settings…"].tap()
        let about = scrollTo(app.buttons["About My Cocktail Collection"], in: app)
        XCTAssertTrue(about.exists)
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 3))
        for label in ["Version", "Build", "Data Model"] {
            XCTAssertTrue(app.staticTexts[label].exists, "\(label) is shown")
        }
        XCTAssertTrue(app.staticTexts["1.0.0"].exists, "The data model version is shown")
    }

    /// Scrolls up until the element is on screen. Forms and lists only create the rows that are visible,
    /// so something further down doesn't exist until it's scrolled to.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> XCUIElement {
        _ = element.waitForExistence(timeout: 1)
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element
    }

    /// Swipes a row left to reveal one of its trailing swipe actions, such as Delete.
    /// It drags the whole row slowly rather than flicking the label, which the Simulator sometimes
    /// reads as a scroll while the list is settling after launch. It tries up to three times, and
    /// never swipes again once the button is showing (a second swipe would close it).
    private func revealSwipeAction(_ title: String, on row: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[title].firstMatch
        let cell = app.cells.containing(.staticText, identifier: row.label).firstMatch
        let target = cell.waitForExistence(timeout: 2) ? cell : row
        for _ in 0..<3 {
            if button.exists { return button }
            let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: target)
            _ = XCTWaiter.wait(for: [hittable], timeout: 2)
            let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
            if button.waitForExistence(timeout: 3) {
                return button
            }
        }
        XCTFail("Swiping didn't reveal \(title)")
        return button
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
