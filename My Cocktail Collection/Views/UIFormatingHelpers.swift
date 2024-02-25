//
//  UIFormatingHelpers.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/25/24.
//

import Foundation

enum SourceType: Int16, CustomStringConvertible {
    case original = 0
    case website = 1
    case menu = 2
    
    var description: String {
        switch self {
        case .original:
            return "Original"
        case .website:
            return "Website"
        case .menu:
            return "Menu"
        }
    }
}
