import SwiftUI

struct ContentView: View {
    @State private var viewModel = LenslokViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let frame = viewModel.frame {
                frame
                    .resizable()
                    .scaledToFit()
            } else if let message = viewModel.statusMessage {
                Text(message)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView("Starting camera…")
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.start()
            } else {
                viewModel.stop()
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

#Preview {
    ContentView()
}
