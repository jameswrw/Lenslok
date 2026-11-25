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

#Preview("Phone") {
    let image = Image(
        ImageResource(
            name: "Phone", bundle: Bundle.main
        )
    )
    LenslokView(sourceImage: image)
}

#Preview("Tomahawk") {
    let image = Image(ImageResource(name: "Tomahawk", bundle: Bundle.main))
    LenslokDecoder(title: .tomahawk).unscramble(image: image)
        .resizable()
        .scaledToFit()
}

#Preview("Inverse") {
    let image = Image(
        ImageResource(
            name: "Inverse", bundle: Bundle.main
        )
    )
    LenslokDecoder(title: .artStudio).unscramble(image: image)
        .resizable()
        .scaledToFit()
}

#Preview("ttRacer") {
    let image = Image(
        ImageResource(
            name: "ttRacer", bundle: Bundle.main
        )
    )
    LenslokDecoder(title: .artStudio).unscramble(image: image)
        .resizable()
        .scaledToFit()
}
