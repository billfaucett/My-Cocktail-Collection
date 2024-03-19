//
//  SpiritListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/26/24.
//

import SwiftUI

struct SpiritListView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
    @State private var showAddNewSpirit = false
    
    var body: some View {
        NavigationView{
            VStack {
                HStack {
                    Button("Close") {
                        dismiss()
                    }
                    Spacer()
                    Button("Add New Spirit") {
                        showAddNewSpirit = true
                    }
                }
                .padding()
                Divider()
                
                VStack {
                    Text("Base Spirits")
                        .font(.title)
                    Divider()
                }
                
                List(spirits) { spirit in
                    HStack {
                        NavigationLink(destination: AddEditSpirit(spirit: spirit)) {
                            Text(spirit.spiritName ?? "")
                                .bold()
                            Spacer()
                            if let type = SpiritType(rawValue: spirit.type) {
                                Text(type.description)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddNewSpirit) {
            AddEditSpirit()
        }
    }
}

struct SpiritListView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext

        let spirit1 = Spirit(context: context)
        spirit1.spiritName = "Whiskey"
        spirit1.type = SpiritType.liquor.rawValue
        
        let spirit2 = Spirit(context: context)
        spirit2.spiritName = "Vodka"
        spirit2.type = SpiritType.liquor.rawValue
        
        try? context.save()
        
        return SpiritListView()
            .environment(\.managedObjectContext, context)
    }
}

