//
//  UIFormatingHelpers.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/25/24.
//

import Foundation

enum SourceType: Int16, CustomStringConvertible {
    case classic = 0
    case website = 1
    case menu = 2
    case original = 3
    
    var description: String {
        switch self {
        case .original:
            return "Original"
        case .website:
            return "Website"
        case .menu:
            return "Menu"
        case .classic:
            return "Classic"
        }
    }
}
    
enum SpiritType: Int16, CustomStringConvertible, CaseIterable {
    case liquor = 0
    case liqueur = 1
    case wine = 2
    case fortifiedWine = 3
    case beer = 4
    case sake = 5
    case mead = 6
    case cider = 7
        
    var description: String {
        switch self {
        case .liquor:
            return "Liquor"
        case .liqueur:
            return "Liqueur"
        case .wine:
            return "Wine"
        case .fortifiedWine:
            return "Fortified Wine"
        case .beer:
            return "Beer"
        case .sake:
            return "Sake"
        case .mead:
            return "Mead"
        case .cider:
            return "Hard Cider"
        }
    }
}
