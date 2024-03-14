//
//  TextFile.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/14/24.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct TextFile: FileDocument {
    static var readableContentTypes = [UTType.plainText]
    var text = ""
    
    init(initialText: String = "") {
        text = initialText
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
