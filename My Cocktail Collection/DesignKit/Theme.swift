//
//  Theme.swift
//  My Cocktail Collection
//
//  The app's shared look: image sizes, corner radii and colours.
//  Change a value here to update every screen that uses the DesignKit.
//

import SwiftUI

enum Theme {
    /// Square image sizes, in points.
    enum ImageSize {
        static let row: CGFloat = 48
        static let form: CGFloat = 80
        static let detail: CGFloat = 220
    }

    /// Corner radii that go with each image size.
    enum Radius {
        static let row: CGFloat = 8
        static let form: CGFloat = 12
        static let detail: CGFloat = 20
    }

    static let placeholderBackground = Color(.secondarySystemBackground)
    static let favorite = Color.pink
}

extension StockLevel {
    var color: Color {
        switch self {
        case .full: return .green
        case .half: return .teal
        case .low: return .orange
        case .out: return .red
        }
    }
}

extension SpiritType {
    var color: Color {
        switch self {
        case .liquor: return .brown
        case .liqueur: return .purple
        case .wine: return .red
        case .fortifiedWine: return .pink
        case .beer: return .orange
        case .sake: return .teal
        case .mead: return .yellow
        case .cider: return .green
        }
    }
}
