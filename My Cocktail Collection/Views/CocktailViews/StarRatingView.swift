//
//  StarRatingView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/17/24.
//

import SwiftUI

import SwiftUI

struct StarRatingView: View {
    let rating: Double

    var body: some View {
        HStack {
            ForEach(0..<5) { index in
                if Double(index) < rating {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                } else if Double(index) - 0.5 == rating {
                    Image(systemName: "star.leadinghalf.fill")
                        .foregroundColor(.yellow)
                    Image(systemName: "star.trailinghalf.fill")
                        .foregroundColor(.yellow)
                } else {
                    Image(systemName: "star")
                        .foregroundColor(.yellow)
                }
            }
        }
    }
}
