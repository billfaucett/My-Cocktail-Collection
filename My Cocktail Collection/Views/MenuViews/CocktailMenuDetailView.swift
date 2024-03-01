//
//  CocktailMenuDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/1/24.
//

import SwiftUI

struct CocktailMenuDetailView: View {
    @Environment(\.managedObjectContext) var context
    var menu: Menu?
    
    var body: some View {
        Section {
            VStack {
                Text("Menu Details")
                    .font(.title)
                    .padding()
                Spacer()
                HStack {
                    Text(menu?.menuName ?? "Not Found")
                    let date = menu?.dateCreated?.formatted()
                    Text(date ?? "no date")
                }
                Spacer()
                Divider()
                VStack {
                    
                }
            }
        }
    }
}

struct CocktailMenuDetailView_Preview: PreviewProvider {
    static var previews: some View {
        CocktailMenuDetailView()
    }
}
