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
                        LenslokCameraView(frame: frame, frameSize: viewModel.frameSize)
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

private struct LenslokCameraView: View {
    let frame: Image
    let frameSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            let tabHeight: CGFloat = isWide ? 10 : 24
            let scale = min(
                max(0, geometry.size.width - 24) / frameSize.width,
                max(0, geometry.size.height - 16 - 2 * tabHeight) / frameSize.height
            )
            let imageSize = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
            let search = LenslokDecoder.videoSearchRect(width: Int(frameSize.width), height: Int(frameSize.height))

            VStack(spacing: 0) {
                LenslokTab()
                    .frame(height: tabHeight)

                ZStack(alignment: .topLeading) {
                    frame
                        .resizable()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Rectangle()
                        .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                        .frame(width: search.width * scale, height: search.height * scale)
                        .position(x: search.midX * scale, y: search.midY * scale)
                        .accessibilityHidden(true)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.black.opacity(0.65), lineWidth: 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                LenslokTab()
                    .frame(height: tabHeight)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.19, blue: 0.10),
                                     Color(red: 0.66, green: 0.08, blue: 0.04),
                                     Color(red: 0.84, green: 0.13, blue: 0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                            .padding(2)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 4)
            }
            .fixedSize()
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

private struct LenslokTab: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.black.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}

#Preview("Lenslok housing") {
    LenslokCameraView(frame: Image("Elite"), frameSize: CGSize(width: 1392, height: 810))
        .padding()
}
