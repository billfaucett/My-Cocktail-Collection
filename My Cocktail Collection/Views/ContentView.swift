//
//  ContentView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var drinks: FetchedResults<Drink>
    
    var body: some View {
        NavigationView{
            VStack {
                NavigationLink(destination: AddEditCocktailRecipeView()){
                    Text("Add a New Cocktail")
                        .padding()
                        .background(Color.mint)
                        .foregroundColor(.indigo)
                        .cornerRadius(15)
                        .foregroundColor(.white)
                }
                NavigationLink(destination: CocktailListView()){
                    Text("View Cocktails")
                        .padding()
                        .background(Color.mint)
                        .foregroundColor(.indigo)
                        .cornerRadius(15)
                        .foregroundColor(.white)
                }
                .padding()
            }
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
