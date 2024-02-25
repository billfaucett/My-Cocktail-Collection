//
//  MessageComposer.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/25/24.
//

import SwiftUI
import MessageUI

struct MessageComposer: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    let cocktailName: String
    let ingredients: String
    let method: String

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composeVC = MFMessageComposeViewController()
        composeVC.messageComposeDelegate = context.coordinator
        composeVC.body = "Cocktail Name: \(cocktailName)\nIngredients: \(ingredients)\nMethod: \(method)"
        return composeVC
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
        // Nothing to do here
    }
}
