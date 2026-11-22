//
//  LenslokView.swift
//  Lenslok
//
//  Created by James Weatherley on 21/11/2026.
//

import SwiftUI

struct LenslokView: View {
    let viewModel = LenslokViewModel()
    let sourceImage: Image
    
    var body: some View {
        viewModel.unscramble(image: sourceImage)
            .resizable()
            .scaledToFit()
    }
}

#Preview("Elite") {
    let image = Image(
        ImageResource(
            name: "Elite", bundle: Bundle.main
        )
    )
    LenslokView(sourceImage: image)
}

#Preview("Rotated") {
    let image = Image(
        ImageResource(
            name: "Rotated", bundle: Bundle.main
        )
    )
    LenslokView(sourceImage: image)
}

#Preview("GameCode") {
    let image = Image(
        ImageResource(
            name: "GameCode", bundle: Bundle.main
        )
    )
    LenslokView(sourceImage: image)
}

#Preview("GameCode2") {
    let image = Image(
        ImageResource(
            name: "GameCode2", bundle: Bundle.main
        )
    )
    LenslokView(sourceImage: image)
}
