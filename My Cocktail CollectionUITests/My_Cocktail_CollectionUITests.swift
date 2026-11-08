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

    /// The Styles tab lists built-in styles from the new database, and search narrows them.
    func testStylesTabListsStyles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.tabBars.buttons["Styles"].tap()
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

    /// Adding a bottle on the Inventory tab lists it, and tapping it opens it for editing.
    func testAddingABottleListsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.tabBars.buttons["Inventory"].tap()
        let addButton = app.buttons["Add Bottle"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let brand = app.textFields["Brand or name (e.g. Buffalo Trace)"]
        XCTAssertTrue(brand.waitForExistence(timeout: 3))
        brand.tap()
        brand.typeText("Test Bottle")
        app.navigationBars["Add Bottle"].buttons["Save"].tap()

        let row = app.staticTexts["Test Bottle"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The new bottle should be listed")
        XCTAssertTrue(app.staticTexts["No Style"].exists, "A bottle with no style is listed under No Style")

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
