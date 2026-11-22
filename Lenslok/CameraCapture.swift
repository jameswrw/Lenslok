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
    private let decoder = LenslokDecoder()
    private var configured = false
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
        #if os(iOS) || os(visionOS)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        #endif
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame?(.success(decoder.unscramble(image: image)))
    }
}
