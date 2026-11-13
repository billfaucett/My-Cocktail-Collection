//
//  FormFields.swift
//  My Cocktail Collection
//
//  Form building blocks shared by every add/edit screen.
//

import SwiftUI
import CoreData
import SwiftData
import PhotosUI

// MARK: - Photo section

/// A form section with a thumbnail and Add/Change/Remove Photo buttons.
/// Uses the system photo picker, so the app doesn't need photo library permission.
struct PhotoSection: View {
    @Binding private var photo: UIImage?
    @Binding private var photoChanged: Bool
    @State private var pickerItem: PhotosPickerItem?

    private let placeholder: Thumbnail.Placeholder
    private let addTitle: String

    /// - Parameters:
    ///   - photo: The current photo.
    ///   - photoChanged: Set to true whenever a photo is picked or removed, so saving knows to update it.
    init(photo: Binding<UIImage?>, photoChanged: Binding<Bool>, placeholder: Thumbnail.Placeholder = .photo, addTitle: String = "Add Photo") {
        _photo = photo
        _photoChanged = photoChanged
        self.placeholder = placeholder
        self.addTitle = addTitle
    }

    var body: some View {
        Section {
            HStack(spacing: 16) {
                Thumbnail(image: photo, placeholder: placeholder, size: Theme.ImageSize.form, cornerRadius: Theme.Radius.form)

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text(photo == nil ? addTitle : "Change Photo")
                    }
                    if photo != nil {
                        Button("Remove Photo", role: .destructive) {
                            photo = nil
                            pickerItem = nil
                            photoChanged = true
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    photo = image
                    photoChanged = true
                }
            }
        }
    }
}

// MARK: - Rating picker

/// A 0–10 rating picker that shows the rating as stars once one is chosen.
struct RatingPicker: View {
    @Binding private var rating: Int
    private let title: String

    init(rating: Binding<Int>, title: String = "Rating") {
        _rating = rating
        self.title = title
    }

    var body: some View {
        Picker(selection: $rating) {
            Text("Not Rated").tag(0)
            ForEach(1...10, id: \.self) { value in
                Text("\(value)").tag(value)
            }
        } label: {
            HStack {
                Text(title)
                if rating > 0 {
                    StarRatingView(rating: Double(rating) / 2.0)
                        .font(.caption2)
                }
            }
        }
    }
}

// MARK: - Template picker

/// A template's name with its icon, for the Template picker and filter menu.
struct TemplateLabel: View {
    let template: CocktailTemplate

    var body: some View {
        Label(template.displayName, systemImage: template.symbolName)
    }
}

/// A template on one line, icon then name, for a row's value (the recipe screen's Details).
/// The icon takes its size from the text, slightly smaller and dimmer, and only its width is fixed,
/// so names line up and no icon (the Sidecar's car especially) can make the row taller.
struct TemplateInline: View {
    let template: CocktailTemplate

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: template.symbolName)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(template.displayName)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(template.displayName)
    }
}

#Preview("Template rows") {
    // Every template as it appears on the recipe screen, to check they're all the same height.
    List {
        Section("Details") {
            LabeledContent("Base Spirit", value: "Bourbon · Whiskey")
            ForEach(CocktailTemplate.allCases) { template in
                LabeledContent {
                    TemplateInline(template: template)
                } label: {
                    Text("Template")
                }
            }
            LabeledContent("Source", value: "Classic")
        }
    }
}

/// Picks a cocktail's Cocktail Codex template. When none is chosen and the ingredients point to one,
/// offers it as a suggestion to tap; nothing is set until you do.
struct TemplatePicker: View {
    @Binding private var selection: CocktailTemplate?
    private let suggestion: CocktailTemplate?

    init(selection: Binding<CocktailTemplate?>, suggestion: CocktailTemplate?) {
        _selection = selection
        self.suggestion = suggestion
    }

    var body: some View {
        Picker(selection: $selection) {
            Text("Not Set").tag(nil as CocktailTemplate?)
            ForEach(CocktailTemplate.allCases) { template in
                TemplateLabel(template: template)
                    .tag(template as CocktailTemplate?)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Template")
                if let selection {
                    Text(selection.formula)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if selection == nil, let suggestion {
            Button {
                selection = suggestion
            } label: {
                HStack {
                    Label("Suggested: \(suggestion.displayName)", systemImage: "sparkles")
                    Spacer()
                    Text("Use")
                        .fontWeight(.semibold)
                }
            }
            .accessibilityLabel("Use suggested template, \(suggestion.displayName)")
            .accessibilityIdentifier("suggestedTemplate")
        }
    }
}

// MARK: - Favorites toggle

/// A "Favorites Only" switch for filtering a list inside a form.
struct FavoritesToggle: View {
    @Binding private var isOn: Bool

    init(isOn: Binding<Bool>) {
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label("Favorites Only", systemImage: isOn ? "heart.fill" : "heart")
        }
        .tint(Theme.favorite)
    }
}

// MARK: - Spirit picker

/// Picks a spirit category, with a button to add a new one. New spirits appear in the picker right away.
struct SpiritPicker: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)])
    private var spirits: FetchedResults<Spirit>
    @Binding private var selection: Spirit?
    @State private var showAddSpirit = false

    private let title: String
    private let addTitle: String

    init(selection: Binding<Spirit?>, title: String = "Base Spirit", addTitle: String = "Add a New Spirit") {
        _selection = selection
        self.title = title
        self.addTitle = addTitle
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag(nil as Spirit?)
            ForEach(spirits) { spirit in
                Text(spirit.spiritName ?? "").tag(spirit as Spirit?)
            }
        }
        Button(addTitle) {
            showAddSpirit = true
        }
        .sheet(isPresented: $showAddSpirit) {
            AddEditSpirit()
        }
    }
}

// MARK: - Style picker (new database)

/// Picks a style from the new database, grouped by family, with a button to add a new one.
/// New styles appear in the picker right away.
struct StylePicker: View {
    @Query private var allStyles: [DB.SpiritStyle]
    /// Only My Library; libraries shared with you are shown separately.
    private var styles: [DB.SpiritStyle] { allStyles.filter { $0.library == nil } }
    @Binding private var selection: DB.SpiritStyle?
    @State private var showAddStyle = false

    private let title: String
    private let addTitle: String

    init(selection: Binding<DB.SpiritStyle?>, title: String = "Base Spirit", addTitle: String = "Add a New Type") {
        _selection = selection
        self.title = title
        self.addTitle = addTitle
    }

    var body: some View {
        let ordered = styles.sorted(by: StyleStore.displayOrder)
        Picker(title, selection: $selection) {
            Text("None").tag(nil as DB.SpiritStyle?)
            ForEach(SpiritFamily.allCases) { family in
                let familyStyles = ordered.filter { $0.family == family }
                if !familyStyles.isEmpty {
                    Section(family.displayName) {
                        ForEach(familyStyles) { style in
                            Text(style.name).tag(style as DB.SpiritStyle?)
                        }
                    }
                }
            }
        }
        Button(addTitle) {
            showAddStyle = true
        }
        .sheet(isPresented: $showAddStyle) {
            AddEditStyleView(family: selection?.family ?? .other)
        }
    }
}

