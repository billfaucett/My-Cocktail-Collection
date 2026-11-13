//
//  AppStartup.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 5: prepares the new SwiftData database when the app launches.
//  On first launch it copies the old data in (LegacyImporter), then adds any missing built-ins.
//  This runs before any screen appears, so nothing is writing to the old database while it's copied.
//  Then iCloud sync starts (not in tests).
//

import Foundation
import SwiftData

@MainActor
enum AppStartup {
    /// Set when preparing the database failed, so the main screen can tell the user. The old data is untouched.
    static var lastErrorMessage: String?

    /// Creates the new database and prepares it. UI tests get a fresh in-memory database with no import.
    static func makeModelContainer(isUITesting: Bool) -> ModelContainer {
        let container: ModelContainer
        do {
            container = try CocktailModelContainer.make(inMemory: isUITesting)
        } catch {
            fatalError("The cocktail database couldn't be created: \(error)")
        }
        prepare(container.mainContext, isUITesting: isUITesting)
        if !isUITesting && !isRunningTests {
            CloudSync.start(container: container)
            SettingsSync.start {
                // Another device deleted a built-in: remove it here too.
                try? ModelSeeder.removeDeletedBuiltIns(context: container.mainContext,
                                                       deleted: BuiltInDeletions.ids(in: .standard))
            }
        }
        return container
    }

    /// True when unit tests host the app. They use their own in-memory databases and never touch iCloud.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Imports the old database once, then adds missing built-in styles and classics.
    static func prepare(_ context: ModelContext, isUITesting: Bool) {
        do {
            if !isUITesting {
                try LegacyImporter(context: context).importIfNeeded()
            }
            try ModelSeeder.seedBuiltIns(context: context, defaults: isUITesting ? nil : .standard)
            if isUITesting && ProcessInfo.processInfo.arguments.contains("-uiTestingSharedLibrary") {
                addSampleSharedLibrary(to: context)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            print("Preparing the database failed: \(error)")
        }
    }

    /// A small library "shared by Bill" (view only), for previews and UI tests of shared libraries.
    @discardableResult
    static func addSampleSharedLibrary(to context: ModelContext) -> DB.Library {
        let library = DB.Library(name: "Bill's Library", ownerName: "Bill", zoneName: CloudSchema.libraryZoneName,
                                 zoneOwnerName: "_sampleOwner")
        context.insert(library)
        let gin = DB.SpiritStyle(name: "London Dry", family: .gin, isBuiltIn: true)
        context.insert(gin)
        gin.library = library
        let sour = DB.Cocktail(name: "Shared Sour", source: .original, method: "Shake with ice\nStrain into a coupe")
        context.insert(sour)
        sour.library = library
        sour.baseStyle = gin
        sour.template = .daiquiri
        let rows = [
            DB.RecipeIngredient(position: 0, name: "Gin", amount: 2, unit: .part),
            DB.RecipeIngredient(position: 1, name: "Lemon Juice", amount: 0.75, unit: .part),
            DB.RecipeIngredient(position: 2, name: "Simple Syrup", amount: 0.5, unit: .part),
        ]
        for row in rows {
            context.insert(row)
            row.cocktail = sour
        }
        rows[0].style = gin
        let menu = DB.Menu(name: "Bill's Party")
        context.insert(menu)
        menu.library = library
        let entry = DB.MenuEntry(position: 0)
        context.insert(entry)
        entry.menu = menu
        entry.cocktail = sour
        try? context.save()
        return library
    }

    #if DEBUG
    /// Development only: empties the new database and copies the old one in again, so screens that have
    /// moved to the new database can be tested against the latest old data during the refactor.
    static func resetAndReimport(_ context: ModelContext) throws {
        try context.delete(model: DB.MenuEntry.self)
        try context.delete(model: DB.Menu.self)
        try context.delete(model: DB.RecipeIngredient.self)
        try context.delete(model: DB.Cocktail.self)
        try context.delete(model: DB.Bottle.self)
        try context.delete(model: DB.SpiritStyle.self)
        try context.delete(model: DB.ImportRecord.self)
        try context.delete(model: DB.Library.self)
        try context.delete(model: DB.SyncRecord.self)
        try context.save()
        try LegacyImporter(context: context).importIfNeeded()
        try ModelSeeder.seedBuiltIns(context: context, defaults: .standard)
    }
    #endif
}

// MARK: - Version

/// The app's version, build number and data model version, for the splash screen and Settings.
/// Version and build come from the project's build settings (MARKETING_VERSION, CURRENT_PROJECT_VERSION).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// The SwiftData schema version, e.g. "3.0.0". Changes when the database's design changes.
    static var dataModelVersion: String {
        let version = DB.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    /// "Version 2.0 (3)"
    static func versionLine(version: String = AppInfo.version, build: String = AppInfo.build) -> String {
        "Version \(version) (\(build))"
    }

    /// "Data model 1.0.0"
    static func dataModelLine(_ dataModel: String = AppInfo.dataModelVersion) -> String {
        "Data model \(dataModel)"
    }
}
