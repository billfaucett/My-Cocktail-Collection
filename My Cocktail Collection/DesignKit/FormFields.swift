//
//  FormFields.swift
//  My Cocktail Collection
//
//  Form building blocks shared by every add/edit screen.
//

import SwiftUI
import CoreData
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
