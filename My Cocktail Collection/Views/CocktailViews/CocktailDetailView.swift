//
//  TestView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/28/24.
//

import SwiftUI
import SwiftData

/// A cocktail's recipe, in parts. Shown pushed from the cocktail list, or from a library shared with you.
/// For a shared recipe: no favorite (favorites are yours), editing only if its owner allows it, and
/// Copy to My Cocktails.
struct CocktailDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let cocktail: DB.Cocktail

    @AppStorage(PartSize.storageKey) private var partSize = PartSize.off
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    /// The name of the copy just made in My Cocktails, to confirm it.
    @State private var copiedName: String?

    init(cocktail: DB.Cocktail) {
        self.cocktail = cocktail
    }

    /// The library shared with you that this recipe is in, or nil for My Library.
    private var sharedLibrary: DB.Library? { cocktail.library }

    /// You can change your own recipes, and a shared library's when its owner allows it.
    private var canEdit: Bool { sharedLibrary?.canEdit ?? true }

    private var shareText: String {
        var lines = [cocktail.name, ""]
        lines += cocktail.orderedIngredients.map { ingredient in
            let converted = partSize.converted(ingredient).map { " (\($0))" } ?? ""
            return "• " + ingredient.displayText + converted
        }
        if !cocktail.method.isEmpty {
            lines += ["", cocktail.method]
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        // After a delete the object is gone; show nothing while the screen closes.
        if cocktail.modelContext == nil || cocktail.isDeleted {
            Color.clear
        } else {
            recipe
        }
    }

    private var recipe: some View {
        List {
            Section {
                Thumbnail(data: cocktail.photo, placeholder: .cocktail, size: Theme.ImageSize.detail, cornerRadius: Theme.Radius.detail)
                    .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                LabeledContent("Base Spirit", value: baseSpiritText)
                if let template = cocktail.template {
                    LabeledContent {
                        TemplateInline(template: template)
                    } label: {
                        Text("Template")
                    }
                    .accessibilityHint(template.formula)
                }
                LabeledContent("Source", value: cocktail.source.displayName)
                if let sharedLibrary {
                    LabeledContent("Library", value: sharedLibrary.name)
                }
            }

            Section {
                if cocktail.orderedIngredients.isEmpty {
                    Text("No ingredients added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cocktail.orderedIngredients) { ingredient in
                        ConvertedIngredientRow(text: ingredient.displayText,
                                               converted: partSize.converted(ingredient),
                                               isSecondary: ingredient.isGarnish)
                    }
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    // A quick way to switch the part size without leaving the recipe.
                    SwiftUI.Menu {
                        Picker("Part Size", selection: $partSize) {
                            ForEach(PartSize.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                    } label: {
                        Label(partSize == .off ? "Parts" : partSize.displayName,
                              systemImage: "ruler")
                            .font(.caption)
                            .textCase(nil)
                    }
                    .accessibilityLabel("Part Size")
                }
            } footer: {
                if cocktail.needsIngredientReview && canEdit {
                    Label("Some ingredients couldn't be read clearly. Tap Edit to check them.", systemImage: "exclamationmark.triangle")
                }
            }

            Section("How to Make") {
                if cocktail.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No directions added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(cocktail.method)
                }
            }
        }
        .navigationTitle(cocktail.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // "SwiftUI." is needed because the app's Core Data entity is also named Menu.
                SwiftUI.Menu {
                    ShareLink(item: shareText) {
                        Label("Share Recipe", systemImage: "square.and.arrow.up")
                    }
                    if sharedLibrary != nil {
                        Button {
                            run { copiedName = try CocktailStore(context: context).copyToMyLibrary(cocktail).name }
                        } label: {
                            Label("Copy to My Cocktails", systemImage: "doc.on.doc")
                        }
                    }
                    if canEdit {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete Cocktail", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                if sharedLibrary == nil {
                    Button {
                        run { try CocktailStore(context: context).toggleFavorite(cocktail) }
                    } label: {
                        Label(cocktail.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                              systemImage: cocktail.isFavorite ? "heart.fill" : "heart")
                    }
                    .tint(cocktail.isFavorite ? Theme.favorite : nil)
                }
                if canEdit {
                    Button("Edit") {
                        showEdit = true
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditCocktailRecipeView(cocktail: cocktail)
        }
        .alert("Delete \(cocktail.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                run {
                    try CocktailStore(context: context).delete(cocktail)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let sharedLibrary {
                Text("It will be removed from \(sharedLibrary.name) for everyone it's shared with.")
            } else {
                Text("It will be removed from your collection and from any menus.")
            }
        }
        .alert("Copied to My Cocktails", isPresented: Binding(
            get: { copiedName != nil },
            set: { if !$0 { copiedName = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\"\(copiedName ?? "")\" is now in your collection. Changes to it are yours alone.")
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var baseSpiritText: String {
        guard let style = cocktail.baseStyle else { return "None" }
        return style.name == style.family.displayName ? style.name : "\(style.name) · \(style.family.displayName)"
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    let negroni = try! container.mainContext.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Negroni" }!
    return NavigationStack {
        CocktailDetailView(cocktail: negroni)
    }
    .modelContainer(container)
}
