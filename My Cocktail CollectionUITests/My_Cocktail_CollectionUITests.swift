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
        let others = ["Aperol Spritz", "Bee's Knees", "Bloody Mary", "Boulevardier"]
        for name in others {
            XCTAssertTrue(app.staticTexts[name].exists, "\(name) should be listed before deleting")
        }

        aviation.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()

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

        aviation.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
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

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
