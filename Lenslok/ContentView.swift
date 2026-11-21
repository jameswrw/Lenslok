import SwiftUI
import Playgrounds

struct ContentView: View {
    let lenslok = Lenslok()
    
    var body: some View {
        VStack {
            Text("Hello, world!")
                .padding()
            lenslok.unscramble(
                image: Image(
                    ImageResource(
                        name: "Elite", bundle: Bundle.main
                    )
                )
            )
            .resizable()
            .scaledToFit()
            
            lenslok.unscramble(
                image: Image(
                    ImageResource(
                        name: "GameCode", bundle: Bundle.main
                    )
                )
            )
            .resizable()
            .scaledToFit()
            
            lenslok.unscramble(
                image: Image(
                    ImageResource(
                        name: "GameCode2", bundle: Bundle.main
                    )
                )
            )
            .resizable()
            .scaledToFit()
        }
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
