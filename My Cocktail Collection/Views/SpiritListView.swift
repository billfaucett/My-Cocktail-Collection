//
//  SpiritListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/26/24.
//

import SwiftUI

struct SpiritListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
    
    var body: some View {
        NavigationView{
            VStack {
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

