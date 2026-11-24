import SwiftUI

struct ContentView: View {
    @State private var viewModel = LenslokViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let frame = viewModel.frame, viewModel.frameSize.width > 0, viewModel.frameSize.height > 0 {
                GeometryReader { geometry in
                    let size = viewModel.frameSize
                    let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
                    let search = LenslokDecoder.videoSearchRect(width: Int(size.width), height: Int(size.height))
                    let imageOrigin = CGPoint(x: (geometry.size.width - size.width * scale) / 2,
                                              y: (geometry.size.height - size.height * scale) / 2)
                    ZStack(alignment: .topLeading) {
                        frame
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        Rectangle()
                            .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                            .frame(width: search.width * scale, height: search.height * scale)
                            .position(x: imageOrigin.x + search.midX * scale,
                                      y: imageOrigin.y + search.midY * scale)
                            .accessibilityHidden(true)
                    }
                }
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
