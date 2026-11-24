import SwiftUI

struct ContentView: View {
    @State private var viewModel = LenslokViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var viewModel = viewModel

        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            let layout = isWide ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 4))

            layout {
                Picker("Lenslok title", selection: $viewModel.selectedTitle) {
                    ForEach(LenslokDecoder.LenslokTitle.allCases) { title in
                        Text(title.displayName).tag(title)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                Group {
                    if let frame = viewModel.frame, viewModel.frameSize.width > 0, viewModel.frameSize.height > 0 {
                        LenslokChromeView(frame: frame, frameSize: viewModel.frameSize)
                    } else if let message = viewModel.statusMessage {
                        Text(message)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        ProgressView("Starting camera…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .preferredColorScheme(.dark)
}
