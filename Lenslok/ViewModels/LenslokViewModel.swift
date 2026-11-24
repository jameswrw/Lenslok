//
//  LenslokViewModel.swift
//  Lenslok
 //

import SwiftUI
import AVFoundation
import Observation

@MainActor
@Observable
final class LenslokViewModel {
    private let camera = CameraCapture()
    private(set) var frame: Image?
    private(set) var frameSize: CGSize = .zero
    private(set) var statusMessage: String?
    var selectedTitle: LenslokDecoder.LenslokTitle = .elite {
        didSet { camera.setTitle(selectedTitle) }
    }
    private var isActive = false

    var captureSession: AVCaptureSession { camera.session }

    func unscramble(image: Image) -> Image {
        var decoder = LenslokDecoder()
        decoder.title = selectedTitle
        return decoder.unscramble(image: image)
    }

    func start() async {
        isActive = true
        statusMessage = nil
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        guard isActive else { return }
        guard authorized else {
            statusMessage = "Camera access is required. Enable it in Settings."
            return
        }
        camera.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                switch result {
                case .success(let image):
                    self.frameSize = CGSize(width: image.width, height: image.height)
                    self.frame = Image(decorative: image, scale: 1).interpolation(.none)
                    self.statusMessage = nil
                case .failure:
                    self.statusMessage = "The camera is unavailable."
                }
            }
        }
    }

    func stop() {
        isActive = false
        camera.stop()
        frame = nil
    }
}
