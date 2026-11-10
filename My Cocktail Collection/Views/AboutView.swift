//
//  AboutView.swift
//  My Cocktail Collection
//
//  About the app: version, build and data model version, what's in your collection, and when your
//  data was brought over from the previous version. Opened from Settings.
//

import SwiftUI
import SwiftData

struct AboutView: View {
    @Query private var cocktails: [V1.Cocktail]
    @Query private var bottles: [V1.Bottle]
    @Query private var menus: [V1.Menu]
    @Query private var styles: [V1.SpiritStyle]
    @Query private var imports: [V1.ImportRecord]

    var body: some View {
        Form {
            Section {
                header
                    .listRowInsets(EdgeInsets())
            }

            Section("App") {
                LabeledContent("Version", value: AppInfo.version)
                LabeledContent("Build", value: AppInfo.build)
                LabeledContent("Data Model", value: AppInfo.dataModelVersion)
            }

            Section("Your Collection") {
                LabeledContent("Cocktails", value: "\(cocktails.count)")
                LabeledContent("Favorite Cocktails", value: "\(cocktails.filter(\.isFavorite).count)")
                LabeledContent("Bottles in My Bar", value: "\(bottles.count)")
                LabeledContent("Menus", value: "\(menus.count)")
                LabeledContent("Spirit Types You Added", value: "\(styles.filter { !$0.isBuiltIn }.count)")
            }

            if let record = imports.first {
                Section {
                    LabeledContent("Brought Over", value: record.completedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("From Before", value: AboutView.importSummary(record))
                } header: {
                    Text("Earlier Version")
                } footer: {
                    Text("Your recipes, bottles and menus were copied from the previous version of the app the first time this version opened.")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The launch artwork on its background, as a banner.
    private var header: some View {
        ZStack {
            Image("LaunchBackground")
                .resizable()
                .scaledToFill()
            Image("LaunchArtwork")
                .resizable()
                .scaledToFit()
                .padding(.vertical, 12)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("My Cocktail Collection")
    }

    /// "31 cocktails · 12 bottles · 2 menus"
    static func importSummary(_ record: V1.ImportRecord) -> String {
        func count(_ number: Int, _ word: String) -> String { number == 1 ? "1 \(word)" : "\(number) \(word)s" }
        return [count(record.cocktailCount, "cocktail"), count(record.bottleCount, "bottle"), count(record.menuCount, "menu")]
            .joined(separator: " · ")
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    return NavigationStack { AboutView() }
        .modelContainer(container)
}
