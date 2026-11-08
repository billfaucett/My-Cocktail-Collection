//
//  AppStartup.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 5: prepares the new SwiftData database when the app launches.
//  On first launch it copies the old data in (LegacyImporter), then adds any missing built-ins.
//  This runs before any screen appears, so nothing is writing to the old database while it's copied.
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
        return container
    }

    /// Imports the old database once, then adds missing built-in styles and classics.
    static func prepare(_ context: ModelContext, isUITesting: Bool) {
        do {
            if !isUITesting {
                try LegacyImporter(context: context).importIfNeeded()
            }
            try ModelSeeder.seedBuiltIns(context: context, defaults: isUITesting ? nil : .standard)
        } catch {
            lastErrorMessage = error.localizedDescription
            print("Preparing the database failed: \(error)")
        }
    }

    #if DEBUG
    /// Development only: empties the new database and copies the old one in again, so screens that have
    /// moved to the new database can be tested against the latest old data during the refactor.
    static func resetAndReimport(_ context: ModelContext) throws {
        try context.delete(model: V1.MenuEntry.self)
        try context.delete(model: V1.Menu.self)
        try context.delete(model: V1.RecipeIngredient.self)
        try context.delete(model: V1.Cocktail.self)
        try context.delete(model: V1.Bottle.self)
        try context.delete(model: V1.SpiritStyle.self)
        try context.delete(model: V1.ImportRecord.self)
        try context.save()
        try LegacyImporter(context: context).importIfNeeded()
        try ModelSeeder.seedBuiltIns(context: context, defaults: .standard)
    }
    #endif
}
