//
//  CameraCapture.swift
//  Lenslok
//
//  Created by James Weatherley on 22/11/2026.
//

import AVFoundation
import CoreImage

nonisolated final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Lenslok.camera")
    private let context = CIContext()
    // The decoder is accessed only on the capture queue.
    private var decoder = LenslokDecoder()
    // Set to false to hide the detected-guide diagnostics.
    private let showsGuideOverlay = true
    private var configured = false
    private var videoOutput: AVCaptureVideoDataOutput?
    #if os(iOS) || os(visionOS)
    @MainActor private var rotationObserver: CameraRotationObserver?
    #endif
    private var onFrame: (@Sendable (Result<CGImage, CameraError>) -> Void)?

    enum CameraError: Error {
        case unavailable
    }

    func start(onFrame: @escaping @Sendable (Result<CGImage, CameraError>) -> Void) {
        queue.async {
            self.onFrame = onFrame
            if !self.configured {
                guard self.configure() else {
                    onFrame(.failure(.unavailable))
                    return
                }
                self.configured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func setTitle(_ title: LenslokDecoder.LenslokTitle) {
        queue.async {
            self.decoder.title = title
        }
    }

    func stop() {
        queue.async {
            self.onFrame = nil
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        session.addInput(input)
        session.addOutput(output)
        videoOutput = output
        #if os(iOS) || os(visionOS)
        Task { @MainActor [weak self] in
            self?.observeRotation(for: device)
        }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        #endif
        return true
    }

    #if os(iOS) || os(visionOS)
    @MainActor
    private func observeRotation(for device: AVCaptureDevice) {
        rotationObserver = CameraRotationObserver(device: device) { [weak self] angle in
            guard let self else { return }
            self.queue.async {
                guard let connection = self.videoOutput?.connection(with: .video),
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
    }
    #endif

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame?(.success(decoder.unscramble(image: image, showsGuideOverlay: showsGuideOverlay, videoMode: true)))
    }
}
#if os(iOS) || os(visionOS)
@MainActor
private final class CameraRotationObserver {
    private let coordinator: AVCaptureDevice.RotationCoordinator
    private var observation: NSKeyValueObservation?

    init(device: AVCaptureDevice, apply: @escaping @MainActor (CGFloat) -> Void) {
        coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        apply(coordinator.videoRotationAngleForHorizonLevelCapture)
        observation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { _, change in
            guard let angle = change.newValue else { return }
            MainActor.assumeIsolated { apply(angle) }
        }
    }
}
#endif

