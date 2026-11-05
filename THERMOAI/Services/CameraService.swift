//
//  CameraService.swift
//  THERMOAI — Services
//
//  Purpose: AVFoundation capture pipeline for the food scanner (preview + still
//           capture). All AVCaptureSession work runs on a private serial queue.
//  Dependencies: AVFoundation, UIKit
//

import AVFoundation
import UIKit

final class CameraService: NSObject, @unchecked Sendable {
    // @unchecked Sendable: all mutable state is confined to `sessionQueue`.

    enum CameraError: Error, LocalizedError {
        case unauthorized, unavailable, captureFailed
        var errorDescription: String? {
            switch self {
            case .unauthorized: "Camera access is off. Enable it in Settings › THERMO AI."
            case .unavailable: "No camera is available on this device."
            case .captureFailed: "The photo couldn't be captured. Please try again."
            }
        }
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "thermoai.camera.session")
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    // MARK: Permission

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: Lifecycle

    func start() async throws {
        guard await Self.requestAccess() else { throw CameraError.unauthorized }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: Capture

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard captureContinuation == nil else {
                    continuation.resume(throwing: CameraError.captureFailed); return
                }
                captureContinuation = continuation
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: Configuration

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        isConfigured = true
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        sessionQueue.async { [self] in
            defer { captureContinuation = nil }
            guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                captureContinuation?.resume(throwing: CameraError.captureFailed)
                return
            }
            captureContinuation?.resume(returning: image)
        }
    }
}
