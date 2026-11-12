//
//  SeedData.swift
//  My Cocktail Collection
//
//  The built-in spirits and recipes, plus corrections for older versions of them.
//  DataController adds anything missing at every launch, so new entries here reach existing installs.
//

import Foundation

/// A built-in spirit category.
struct SeedSpirit {
    let name: String
    let type: SpiritType
}

/// A built-in recipe. Ingredients and steps are stored one per line.
struct SeedCocktail {
    let name: String
    /// Name of the base spirit, matching a `SeedSpirit`.
    let spirit: String
    let ingredients: [String]
    let method: [String]

    init(_ name: String, spirit: String, ingredients: [String], method: [String]) {
        self.name = name
        self.spirit = spirit
        self.ingredients = ingredients
        self.method = method
    }

    var ingredientsText: String { ingredients.joined(separator: "\n") }
    var methodText: String { method.joined(separator: "\n") }
}

enum SeedData {
    /// Spirit categories added to every collection.
    static let spirits: [SeedSpirit] = [
        SeedSpirit(name: "Vodka", type: .liquor),
        SeedSpirit(name: "Bourbon", type: .liquor),
        SeedSpirit(name: "Rye", type: .liquor),
        SeedSpirit(name: "Whiskey", type: .liquor),
        SeedSpirit(name: "Scotch", type: .liquor),
        SeedSpirit(name: "Rum", type: .liquor),
        SeedSpirit(name: "Brandy", type: .liquor),
        SeedSpirit(name: "Pisco", type: .liquor),
        SeedSpirit(name: "Gin", type: .liquor),
        SeedSpirit(name: "Tequila", type: .liquor),
        SeedSpirit(name: "Mezcal", type: .liquor),
        SeedSpirit(name: "Aquavit", type: .liquor),
        SeedSpirit(name: "Aperol", type: .liqueur)
    ]

    /// Classic cocktails added to every collection.
    static let classics: [SeedCocktail] = [
        // Gin
        SeedCocktail("Martini", spirit: "Gin",
            ingredients: ["2½ oz Gin", "½ oz Dry Vermouth", "Olive or lemon twist, to garnish"],
            method: ["Stir the gin and vermouth with ice until very cold.", "Strain into a chilled martini glass.", "Garnish with an olive or a lemon twist."]),
        SeedCocktail("Negroni", spirit: "Gin",
            ingredients: ["1 oz Gin", "1 oz Campari", "1 oz Sweet Vermouth", "Orange peel, to garnish"],
            method: ["Stir the gin, Campari and vermouth with ice until well chilled.", "Strain into a rocks glass over a large ice cube.", "Express an orange peel over the drink and use it to garnish."]),
        SeedCocktail("Gimlet", spirit: "Gin",
            ingredients: ["2 oz Gin", "¾ oz Fresh Lime Juice", "¾ oz Simple Syrup", "Lime wheel, to garnish"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a chilled coupe.", "Garnish with a lime wheel."]),
        SeedCocktail("Tom Collins", spirit: "Gin",
            ingredients: ["2 oz Gin", "1 oz Fresh Lemon Juice", "½ oz Simple Syrup", "Club soda, to top", "Lemon wheel and cherry, to garnish"],
            method: ["Shake the gin, lemon juice and syrup with ice.", "Strain into a Collins glass filled with ice.", "Top with club soda and stir gently.", "Garnish with a lemon wheel and a cherry."]),
        SeedCocktail("French 75", spirit: "Gin",
            ingredients: ["1 oz Gin", "½ oz Fresh Lemon Juice", "½ oz Simple Syrup", "3 oz Champagne", "Lemon twist, to garnish"],
            method: ["Shake the gin, lemon juice and syrup with ice.", "Strain into a chilled flute.", "Top with Champagne.", "Garnish with a lemon twist."]),
        SeedCocktail("Bee's Knees", spirit: "Gin",
            ingredients: ["2 oz Gin", "¾ oz Fresh Lemon Juice", "¾ oz Honey Syrup (equal parts honey and warm water)", "Lemon twist, to garnish"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a chilled coupe.", "Garnish with a lemon twist."]),
        SeedCocktail("Last Word", spirit: "Gin",
            ingredients: ["¾ oz Gin", "¾ oz Green Chartreuse", "¾ oz Maraschino Liqueur", "¾ oz Fresh Lime Juice"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a chilled coupe."]),
        SeedCocktail("Aviation", spirit: "Gin",
            ingredients: ["2 oz Gin", "½ oz Maraschino Liqueur", "¼ oz Crème de Violette", "¾ oz Fresh Lemon Juice", "Brandied cherry, to garnish"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a chilled coupe.", "Garnish with a brandied cherry."]),

        // Bourbon, Rye and Whiskey
        SeedCocktail("Old Fashioned", spirit: "Bourbon",
            ingredients: ["2 oz Bourbon", "¼ oz Simple Syrup", "2–3 dashes Angostura Bitters", "Orange peel, to garnish"],
            method: ["Stir the bourbon, syrup and bitters with ice in a mixing glass until chilled.", "Strain into a rocks glass over a large ice cube.", "Express the oils from an orange peel over the drink and use it to garnish."]),
        SeedCocktail("Manhattan", spirit: "Rye",
            ingredients: ["2 oz Rye Whiskey", "1 oz Sweet Vermouth", "2 dashes Angostura Bitters", "Brandied cherry, to garnish"],
            method: ["Stir all ingredients with ice until well chilled.", "Strain into a chilled coupe.", "Garnish with a brandied cherry."]),
        SeedCocktail("Whiskey Sour", spirit: "Bourbon",
            ingredients: ["2 oz Bourbon", "¾ oz Fresh Lemon Juice", "¾ oz Simple Syrup", "1 Egg White (optional)", "Angostura Bitters and a cherry, to garnish"],
            method: ["If using egg white, shake all ingredients without ice for 10–15 seconds.", "Add ice and shake again until chilled.", "Strain into a rocks glass over fresh ice.", "Garnish with a few drops of bitters and a cherry."]),
        SeedCocktail("Mint Julep", spirit: "Bourbon",
            ingredients: ["2½ oz Bourbon", "½ oz Simple Syrup", "8–10 Mint Leaves", "Mint sprig, to garnish"],
            method: ["Gently muddle the mint leaves with the syrup in a julep cup.", "Add the bourbon, fill with crushed ice and stir until the cup frosts.", "Top with more crushed ice.", "Garnish with a mint sprig."]),
        SeedCocktail("Boulevardier", spirit: "Bourbon",
            ingredients: ["1¼ oz Bourbon", "1 oz Campari", "1 oz Sweet Vermouth", "Orange peel, to garnish"],
            method: ["Stir all ingredients with ice until well chilled.", "Strain into a rocks glass over a large ice cube.", "Garnish with an orange peel."]),
        SeedCocktail("Sazerac", spirit: "Rye",
            ingredients: ["2 oz Rye Whiskey", "¼ oz Simple Syrup", "3 dashes Peychaud's Bitters", "1 dash Angostura Bitters", "Absinthe, to rinse the glass", "Lemon peel, to garnish"],
            method: ["Rinse a chilled rocks glass with absinthe and discard the excess.", "Stir the rye, syrup and bitters with ice until chilled.", "Strain into the glass without ice.", "Express a lemon peel over the drink, then garnish or discard."]),
        SeedCocktail("Paper Plane", spirit: "Bourbon",
            ingredients: ["¾ oz Bourbon", "¾ oz Aperol", "¾ oz Amaro Nonino", "¾ oz Fresh Lemon Juice"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a chilled coupe."]),
        SeedCocktail("Gold Rush", spirit: "Bourbon",
            ingredients: ["2 oz Bourbon", "¾ oz Fresh Lemon Juice", "¾ oz Honey Syrup (equal parts honey and warm water)", "Lemon twist, to garnish"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a rocks glass over a large ice cube.", "Garnish with a lemon twist."]),

        // Scotch
        SeedCocktail("Rob Roy", spirit: "Scotch",
            ingredients: ["2 oz Scotch", "1 oz Sweet Vermouth", "2 dashes Angostura Bitters", "Brandied cherry, to garnish"],
            method: ["Stir all ingredients with ice until well chilled.", "Strain into a chilled coupe.", "Garnish with a brandied cherry."]),
        SeedCocktail("Penicillin", spirit: "Scotch",
            ingredients: ["2 oz Blended Scotch", "¾ oz Fresh Lemon Juice", "¾ oz Honey-Ginger Syrup", "¼ oz Islay Scotch, to float", "Candied ginger, to garnish"],
            method: ["Shake the blended Scotch, lemon juice and syrup with ice.", "Strain into a rocks glass over fresh ice.", "Gently float the Islay Scotch on top.", "Garnish with candied ginger."]),

        // Rum
        SeedCocktail("Daiquiri", spirit: "Rum",
            ingredients: ["2 oz Light Rum", "1 oz Fresh Lime Juice", "¾ oz Simple Syrup", "Lime wheel, to garnish"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a chilled coupe.", "Garnish with a lime wheel."]),
        SeedCocktail("Mojito", spirit: "Rum",
            ingredients: ["2 oz White Rum", "¾ oz Fresh Lime Juice", "½ oz Simple Syrup", "6–8 Mint Leaves", "Club soda, to top", "Mint sprig, to garnish"],
            method: ["Gently muddle the mint with the syrup and lime juice in a highball glass.", "Add the rum, fill with ice and stir.", "Top with club soda.", "Garnish with a mint sprig."]),
        SeedCocktail("Mai Tai", spirit: "Rum",
            ingredients: ["2 oz Aged Rum", "¾ oz Fresh Lime Juice", "½ oz Orange Curaçao", "½ oz Orgeat", "¼ oz Simple Syrup", "Mint sprig and lime shell, to garnish"],
            method: ["Shake all ingredients with crushed ice.", "Pour everything into a double rocks glass.", "Garnish with a mint sprig and the spent lime shell."]),
        SeedCocktail("Dark 'n' Stormy", spirit: "Rum",
            ingredients: ["2 oz Dark Rum", "4 oz Ginger Beer", "½ oz Fresh Lime Juice (optional)", "Lime wedge, to garnish"],
            method: ["Fill a highball glass with ice and add the ginger beer and lime juice.", "Float the dark rum on top.", "Garnish with a lime wedge."]),
        SeedCocktail("Piña Colada", spirit: "Rum",
            ingredients: ["2 oz White Rum", "1½ oz Cream of Coconut", "1½ oz Pineapple Juice", "½ oz Fresh Lime Juice", "Pineapple wedge and cherry, to garnish"],
            method: ["Blend all ingredients with a cup of ice until smooth, or shake hard with ice.", "Pour into a hurricane glass.", "Garnish with a pineapple wedge and a cherry."]),

        // Tequila and Mezcal
        SeedCocktail("Margarita", spirit: "Tequila",
            ingredients: ["2 oz Tequila Blanco", "1 oz Triple Sec", "1 oz Fresh Lime Juice", "Salt, for the rim (optional)", "Lime wheel, to garnish"],
            method: ["Rub a lime wedge around the rim of a chilled glass and dip it in salt, if you like.", "Shake the tequila, triple sec and lime juice with ice until chilled.", "Strain into the glass, over fresh ice or up.", "Garnish with a lime wheel."]),
        SeedCocktail("Paloma", spirit: "Tequila",
            ingredients: ["2 oz Tequila Blanco", "½ oz Fresh Lime Juice", "Pinch of salt", "Grapefruit soda, to top", "Lime wedge, to garnish"],
            method: ["Add the tequila, lime juice and salt to a highball glass filled with ice.", "Top with grapefruit soda and stir gently.", "Garnish with a lime wedge."]),
        SeedCocktail("Tommy's Margarita", spirit: "Tequila",
            ingredients: ["2 oz Tequila Blanco (100% agave)", "1 oz Fresh Lime Juice", "½ oz Agave Syrup (equal parts agave and water)", "Lime wheel, to garnish"],
            method: ["Shake all ingredients with ice until chilled.", "Strain into a rocks glass over fresh ice.", "Garnish with a lime wheel."]),
        SeedCocktail("Mezcal Negroni", spirit: "Mezcal",
            ingredients: ["1 oz Mezcal", "1 oz Campari", "1 oz Sweet Vermouth", "Orange peel, to garnish"],
            method: ["Stir all ingredients with ice until well chilled.", "Strain into a rocks glass over a large ice cube.", "Garnish with an orange peel."]),

        // Vodka
        SeedCocktail("Cosmopolitan", spirit: "Vodka",
            ingredients: ["1½ oz Citrus Vodka", "½ oz Triple Sec", "½ oz Fresh Lime Juice", "1 oz Cranberry Juice", "Orange twist, to garnish"],
            method: ["Shake all ingredients with ice for 10–15 seconds until chilled.", "Strain into a chilled martini glass.", "Garnish with an orange twist."]),
        SeedCocktail("Moscow Mule", spirit: "Vodka",
            ingredients: ["2 oz Vodka", "½ oz Fresh Lime Juice", "4 oz Ginger Beer", "Lime wedge, to garnish"],
            method: ["Fill a copper mug with ice and add the vodka and lime juice.", "Top with ginger beer and stir gently.", "Garnish with a lime wedge."]),
        SeedCocktail("Espresso Martini", spirit: "Vodka",
            ingredients: ["2 oz Vodka", "1 oz Fresh Espresso", "½ oz Coffee Liqueur", "¼ oz Simple Syrup (optional)", "3 coffee beans, to garnish"],
            method: ["Shake all ingredients hard with ice to build a foam.", "Strain into a chilled coupe.", "Garnish with three coffee beans."]),
        SeedCocktail("Bloody Mary", spirit: "Vodka",
            ingredients: ["1½ oz Vodka", "3 oz Tomato Juice", "½ oz Fresh Lemon Juice", "2 dashes Worcestershire Sauce", "2 dashes Hot Sauce", "Pinch of salt and pepper", "¼ tsp Horseradish (optional)", "Celery stalk and lemon wedge, to garnish"],
            method: ["Add all ingredients to a shaker with ice and gently roll between the shaker and a glass to mix.", "Strain into a highball glass filled with ice.", "Garnish with a celery stalk and a lemon wedge."]),
        SeedCocktail("White Russian", spirit: "Vodka",
            ingredients: ["2 oz Vodka", "1 oz Coffee Liqueur", "1 oz Heavy Cream"],
            method: ["Add the vodka and coffee liqueur to a rocks glass filled with ice.", "Float the cream on top and stir if you like."]),

        // Brandy and Pisco
        SeedCocktail("Sidecar", spirit: "Brandy",
            ingredients: ["2 oz Cognac", "¾ oz Triple Sec", "¾ oz Fresh Lemon Juice", "Sugar, for the rim (optional)", "Orange twist, to garnish"],
            method: ["Sugar the rim of a chilled coupe, if you like.", "Shake the cognac, triple sec and lemon juice with ice.", "Strain into the coupe.", "Garnish with an orange twist."]),
        SeedCocktail("Vieux Carré", spirit: "Brandy",
            ingredients: ["¾ oz Rye Whiskey", "¾ oz Cognac", "¾ oz Sweet Vermouth", "1 tsp Bénédictine", "2 dashes Peychaud's Bitters", "2 dashes Angostura Bitters", "Lemon twist or cherry, to garnish"],
            method: ["Stir all ingredients with ice until well chilled.", "Strain into a rocks glass over a large ice cube.", "Garnish with a lemon twist or a cherry."]),
        SeedCocktail("Pisco Sour", spirit: "Pisco",
            ingredients: ["2 oz Pisco", "1 oz Fresh Lime Juice", "¾ oz Simple Syrup", "1 Egg White", "Angostura Bitters, to garnish"],
            method: ["Shake all ingredients without ice for 10–15 seconds.", "Add ice and shake again until chilled.", "Strain into a chilled coupe.", "Add three drops of bitters on the foam."]),

        // Aperitivo
        SeedCocktail("Aperol Spritz", spirit: "Aperol",
            ingredients: ["3 oz Prosecco", "2 oz Aperol", "1 oz Club Soda", "Orange slice, to garnish"],
            method: ["Fill a wine glass with ice.", "Add the Prosecco, Aperol and club soda.", "Stir gently and garnish with an orange slice."])
    ]

    /// The house favorites added by "Add Our Favorite Cocktails". Kept in their original style.
    static let favorites: [SeedCocktail] = [
        SeedCocktail("Blood Orange Margarita", spirit: "Tequila",
            ingredients: ["3 parts Tequila, 2 parts Blood Orange Juice, 1 part Triple Sec, .5 parts Lime Juice, Optional .5 parts Agave Nectar"],
            method: ["Use a lime wedge to lightly salt the rim of a chilled glass, Mix ingredients into a cocktail shaker filled with ice, Shake until chilled, Strain into your glass over ice, garnish with a slice of blood orange"]),
        SeedCocktail("Irish Whiskey Sour", spirit: "Whiskey",
            ingredients: ["2 parts Irish Whiskey, 1 part Lemon Juice, .5-1 part Simple Syrup, Egg White"],
            method: ["Add all ingredients to a shaker without ice, Dry Shake 10-15 seconds to Froth the egg white, Add ice and shake again until chilled, Strain into a chilled low ball glass, Garnish with a twist of lemon and a Luxardo Cherry"]),
        SeedCocktail("Ranch Water", spirit: "Tequila",
            ingredients: ["2 parts Tequila, 1 part Lime Juice, Topo Chico"],
            method: ["Add Tequila and Lime Juice to a shaker, Fill with ice and shake until chilled, strain into a chilled glass or over ice, Fill the rest of the glass with Topo Chico, Garnish with a wedge of lime"]),
        SeedCocktail("Bourbon Renewal", spirit: "Bourbon",
            ingredients: ["2 parts Bourbon, 1 part Lemon Juice, .5 parts Creme de Cassis, .5 parts Simple Syrup"],
            method: ["Add ingredients to a cocktail shaker, fill with ice and shake until chilled, strain into a low ball glass over a large ice cube, garnish with a slice of lemon"]),
        SeedCocktail("Chocolate Peanutbutter Sundae", spirit: "Vodka",
            ingredients: ["2 parts Vodka, 1 part Creme de Cacao, .5 parts Peanut butter Whiskey, .5 parts Heavy Cream"],
            method: ["Add ingredients to a shaker, cover with ice and shake until chilled, strain ingredients into a chilled martini glass lined with a swirl of chocolate sauce, garnish with a luxardo cherry, and for an extra flourish float a touch of Luxardo Liqueur or Kirschwasser on top"]),
        SeedCocktail("Cherry Bourbon Sour", spirit: "Bourbon",
            ingredients: ["2 parts bourbon, 1 part lemon juice, 3-4 Luxardo or bourbon soaked cherries, .5 parts simple syrup (if desired)"],
            method: ["To an old fashioned glass add the cherries and simple syrup, muddle the cherries to a pulp, add a cube of ice to the glass and pour in the bourbon and lemon juice, stir with a bar spoon until combined and chilled, garnish with a cherry and lemon twist"])
    ]

    /// Built-in cocktails that were renamed. Old name → new name.
    static let renamedCocktails: [String: String] = [
        "Daquiri": "Daiquiri"
    ]

    /// The original five classics exactly as earlier versions stored them. If a cocktail still has
    /// this text (it was never edited), it's replaced with the updated recipe above.
    static let originalClassicRecipes: [String: (ingredients: String, method: String)] = [
        "Margarita": (ingredients: "2pt Tequila, 1pt Tripe Sec, 1pt Lime Juice", method: "Combine ingredients in a shaker, Add Ice and shake until chilled, Strain into a chilled glass or over ice"),
        "Old Fashioned": (ingredients: "2pt Bourbon, 1pt Simple Syrup, 2-4 dashes Angostura Bitters, Orange Peel", method: "Combine ingredients in a mixing glass, Add Ice and stir until chilled, Strain into a chilled glass or over ice, Express oil from orange peel over drink and use peel to garnish"),
        "Martini": (ingredients: "1pt Gin, 1pt Dry Vermouth, Olive", method: "Combine ingredients in a mixing glass, Add Ice and stir until chilled, Strain into a chilled martini glass, Garnish with olive"),
        "Daiquiri": (ingredients: "2pt Light Rum, 1pt Lime Juice, .5pt Simple Syrup", method: "Combine ingredients in a shaker, Add Ice and shake until chilled, Strain into a chilled coupe glass"),
        "Cosmopolitan": (ingredients: "2pt Vodka, 1pt Triple Sec, 1pt Cranberry Juice, .5pt Lime Juice, Orange Twist", method: "Combine ingredients in a shaker and top with ice, Shake for 10-15 seconds untile chilled, Strain into a chilled martini glass, garnisg with orange twist")
    ]

    /// Typos in earlier versions of the built-in recipes, fixed in place even if a recipe was edited.
    static let typoFixes: [(typo: String, correction: String)] = [
        (typo: "Tripe Sec", correction: "Triple Sec"),
        (typo: "untile chilled", correction: "until chilled"),
        (typo: "garnisg", correction: "garnish"),
        (typo: "cocktail shker", correction: "cocktail shaker"),
        (typo: "Add igredients", correction: "Add ingredients"),
        (typo: "To and old fashioned", correction: "To an old fashioned"),
        (typo: "mull the cherries", correction: "muddle the cherries"),
        (typo: "cube of lce", correction: "cube of ice")
    ]
}

extension SeedData {
    /// Applies the built-in recipe corrections to one recipe from an older database:
    /// renames (Daquiri → Daiquiri, unless that name is already taken), the updated recipe for an
    /// original classic that was never edited, and typo fixes for any other built-in recipe.
    /// Recipes that aren't built-in come back unchanged.
    static func corrected(name: String, ingredients: String?, method: String?, takenNames: Set<String>)
        -> (name: String, ingredients: String?, method: String?) {
        var name = name
        if let newName = renamedCocktails[name], !takenNames.contains(newName) {
            name = newName
        }
        guard (classics + favorites).contains(where: { $0.name == name }) else {
            return (name, ingredients, method)
        }
        if let original = originalClassicRecipes[name],
           ingredients == original.ingredients,
           method == original.method,
           let updated = classics.first(where: { $0.name == name }) {
            return (name, updated.ingredientsText, updated.methodText)
        }
        var fixedIngredients = ingredients
        var fixedMethod = method
        for fix in typoFixes {
            fixedIngredients = fixedIngredients?.replacingOccurrences(of: fix.typo, with: fix.correction)
            fixedMethod = fixedMethod?.replacingOccurrences(of: fix.typo, with: fix.correction)
        }
        return (name, fixedIngredients, fixedMethod)
    }
}

// MARK: - Templates

extension SeedData {
    /// Which Cocktail Codex template each built-in recipe follows.
    static let templates: [String: CocktailTemplate] = [
        // Old Fashioned: spirit, sugar, bitters
        "Old Fashioned": .oldFashioned, "Sazerac": .oldFashioned, "Mint Julep": .oldFashioned,
        // Martini: spirit and aromatized wine (including the Manhattan and Negroni lines)
        "Martini": .martini, "Manhattan": .martini, "Rob Roy": .martini, "Negroni": .martini,
        "Mezcal Negroni": .martini, "Boulevardier": .martini, "Vieux Carré": .martini,
        // Daiquiri: spirit, citrus, sugar
        "Daiquiri": .daiquiri, "Gimlet": .daiquiri, "Whiskey Sour": .daiquiri, "Bee's Knees": .daiquiri,
        "Gold Rush": .daiquiri, "Penicillin": .daiquiri, "Mojito": .daiquiri, "Tommy's Margarita": .daiquiri,
        "French 75": .daiquiri, "Pisco Sour": .daiquiri, "Irish Whiskey Sour": .daiquiri,
        "Cherry Bourbon Sour": .daiquiri, "Bourbon Renewal": .daiquiri,
        // Sidecar: spirit, citrus, liqueur
        "Sidecar": .sidecar, "Margarita": .sidecar, "Cosmopolitan": .sidecar, "Last Word": .sidecar,
        "Aviation": .sidecar, "Paper Plane": .sidecar, "Mai Tai": .sidecar, "Blood Orange Margarita": .sidecar,
        // Highball: spirit and a sparkling mixer
        "Tom Collins": .highball, "Paloma": .highball, "Moscow Mule": .highball, "Dark 'n' Stormy": .highball,
        "Aperol Spritz": .highball, "Ranch Water": .highball, "Bloody Mary": .highball,
        // Flip: rich, with egg, cream or another creamy ingredient
        "White Russian": .flip, "Piña Colada": .flip, "Espresso Martini": .flip,
        "Chocolate Peanutbutter Sundae": .flip,
    ]
}
