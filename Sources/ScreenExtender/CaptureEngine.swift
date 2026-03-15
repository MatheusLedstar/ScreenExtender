import Foundation
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class CaptureEngine: NSObject, @unchecked Sendable {
    var onFrame: ((Data) -> Void)?

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.screenextender.capture", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var jpegQuality: CGFloat = 0.5
    private var frameCount = 0
    private var lastFPSTime = Date()
    private(set) var currentFPS: Double = 0

    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.displays
    }

    /// Find a display by its CGDirectDisplayID. Retries up to 3 times for virtual displays.
    func findDisplay(byID displayID: CGDirectDisplayID, maxRetries: Int = 3) async -> SCDisplay? {
        for attempt in 0..<maxRetries {
            if let displays = try? await getAvailableDisplays(),
               let display = displays.first(where: { $0.displayID == displayID }) {
                return display
            }
            if attempt < maxRetries - 1 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        return nil
    }

    func startCapture(display: SCDisplay, quality: CGFloat = 0.5, frameRate: Int = 30) async throws {
        self.jpegQuality = quality

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.stream = stream
    }

    func stopCapture() {
        stream?.stopCapture { _ in }
        stream = nil
        currentFPS = 0
        frameCount = 0
    }

    private func encodeJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // FPS counter
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSTime)
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSTime = now
        }

        guard let jpegData = encodeJPEG(from: pixelBuffer) else { return }
        onFrame?(jpegData)
    }
}
