//
//  Rows.swift
//  My Cocktail Collection
//
//  Row building blocks shared by every list: thumbnails, badges and the standard row.
//

import SwiftUI

// MARK: - Thumbnail

/// A square photo with rounded corners, or a placeholder when there's no photo.
struct Thumbnail: View {
    enum Placeholder {
        case symbol(String)
        case asset(String)

        static let cocktail = Placeholder.asset("martini")
        static let bottle = Placeholder.symbol("wineglass")
        static let menu = Placeholder.symbol("menucard")
        static let photo = Placeholder.symbol("photo")
    }

    private let image: UIImage?
    private let placeholder: Placeholder
    private let size: CGFloat
    private let cornerRadius: CGFloat

    init(image: UIImage?, placeholder: Placeholder, size: CGFloat = Theme.ImageSize.row, cornerRadius: CGFloat = Theme.Radius.row) {
        self.image = image
        self.placeholder = placeholder
        self.size = size
        self.cornerRadius = cornerRadius
    }

    /// Builds the thumbnail from stored image data, such as `drink.image`.
    init(data: Data?, placeholder: Placeholder, size: CGFloat = Theme.ImageSize.row, cornerRadius: CGFloat = Theme.Radius.row) {
        self.init(image: data.flatMap(UIImage.init(data:)), placeholder: placeholder, size: size, cornerRadius: cornerRadius)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.placeholderBackground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeholderView: some View {
        switch placeholder {
        case .symbol(let name):
            Image(systemName: name)
                .font(size > Theme.ImageSize.row ? .largeTitle : .title3)
                .foregroundStyle(.secondary)
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .padding(size * 0.15)
        }
    }
}

// MARK: - Badge

/// A small coloured capsule label, such as a stock level or spirit type.
struct Badge: View {
    private let text: String
    private let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Item row

/// The standard list row: optional thumbnail, title (with a heart for favourites),
/// grey subtitle, and anything you like on the right.
///
///     ItemRow(bottle.brand ?? "", subtitle: "Bourbon", thumbnail: Thumbnail(data: bottle.image, placeholder: .bottle)) {
///         Badge("Low", color: .orange)
///     }
struct ItemRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let thumbnail: Thumbnail?
    private let isFavorite: Bool
    private let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        thumbnail: Thumbnail? = nil,
        isFavorite: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.thumbnail = thumbnail
        self.isFavorite = isFavorite
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail {
                thumbnail
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.favorite)
                            .accessibilityLabel("Favorite")
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 2)
    }
}

/// A heart on the right of a row that favorites or unfavorites it with one tap.
/// It sits apart from the rest of the row with its own 44-point tap area, so tapping the row still
/// opens it, and it bounces with a light haptic so a stray tap is noticed (tap again to undo).
struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.body)
                .foregroundStyle(isFavorite ? Theme.favorite : Color.secondary.opacity(0.6))
                .symbolEffect(.bounce, value: isFavorite)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}

extension ItemRow where Trailing == EmptyView {
    /// A row with nothing on the right.
    init(_ title: String, subtitle: String? = nil, thumbnail: Thumbnail? = nil, isFavorite: Bool = false) {
        self.init(title, subtitle: subtitle, thumbnail: thumbnail, isFavorite: isFavorite) { EmptyView() }
    }
}
