import SwiftUI
import Playgrounds

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
        Image(ImageResource(name: "Elite", bundle: Bundle.main))
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
