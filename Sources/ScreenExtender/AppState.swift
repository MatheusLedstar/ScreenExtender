import Foundation
import ScreenCaptureKit
import VirtualDisplayBridge

enum DisplayMode: String, CaseIterable {
    case extend = "Estender (display virtual)"
    case mirror = "Espelhar (display principal)"
}

@MainActor
final class AppState: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var localIP = ""
    @Published var displays: [SCDisplay] = []
    @Published var selectedDisplayIndex = 0
    @Published var quality: Double = 0.5
    @Published var frameRate: Int = 30
    @Published var fps: Double = 0
    @Published var statusMessage = "Parado"
    @Published var httpPort: UInt16 = 7680
    @Published var displayMode: DisplayMode = .extend
    @Published var virtualWidth: Int = 1920
    @Published var virtualHeight: Int = 1080

    let captureEngine = CaptureEngine()
    let streamServer = StreamServer()
    let inputHandler = InputHandler()

    private var fpsTimer: Timer?
    private var virtualDisplayID: CGDirectDisplayID = 0

    init() {
        localIP = NetworkUtils.getLocalIPAddress()

        streamServer.onClientCountChanged = { [weak self] count in
            Task { @MainActor in self?.connectedClients = count }
        }

        streamServer.onTouchEvent = { [weak self] event in
            self?.inputHandler.handleTouch(event)
        }

        captureEngine.onFrame = { [weak self] data in
            self?.streamServer.broadcastFrame(data)
        }
    }

    func loadDisplays() async {
        do {
            displays = try await captureEngine.getAvailableDisplays()
        } catch {
            statusMessage = "Erro ao listar displays: \(error.localizedDescription)"
        }
    }

    func start() async {
        do {
            // 1. Start servers
            let wsPort = httpPort + 1
            try streamServer.start(httpPort: httpPort, wsPort: wsPort)

            // 2. Get target display
            let targetDisplay: SCDisplay

            if displayMode == .extend {
                // Try to create a virtual display
                let vdID = VDBCreateVirtualDisplay(
                    UInt32(virtualWidth),
                    UInt32(virtualHeight),
                    0, // no HiDPI for simplicity
                    "Screen Extender"
                )

                if vdID != 0 {
                    virtualDisplayID = vdID
                    statusMessage = "Display virtual criado (ID: \(vdID)). Buscando..."

                    // Wait for ScreenCaptureKit to discover the new display
                    if let vDisplay = await captureEngine.findDisplay(byID: vdID) {
                        targetDisplay = vDisplay
                        // Set input handler bounds to virtual display position
                        let bounds = VDBGetDisplayBounds()
                        inputHandler.displayBounds = bounds
                        statusMessage = "Capturando display virtual"
                    } else {
                        // Fallback: virtual display created but SCK can't find it
                        statusMessage = "Display virtual criado mas nao detectado pelo SCK. Usando mirror."
                        VDBDestroyVirtualDisplay()
                        virtualDisplayID = 0
                        guard let fallback = await getMirrorDisplay() else {
                            statusMessage = "Nenhum display disponivel"
                            streamServer.stop()
                            return
                        }
                        targetDisplay = fallback
                        inputHandler.displayBounds = CGRect(
                            x: 0, y: 0,
                            width: CGFloat(targetDisplay.width),
                            height: CGFloat(targetDisplay.height)
                        )
                    }
                } else {
                    // CGVirtualDisplay not available, fallback to mirror
                    statusMessage = "API de display virtual nao disponivel. Usando mirror."
                    guard let fallback = await getMirrorDisplay() else {
                        statusMessage = "Nenhum display disponivel"
                        streamServer.stop()
                        return
                    }
                    targetDisplay = fallback
                    inputHandler.displayBounds = CGRect(
                        x: 0, y: 0,
                        width: CGFloat(targetDisplay.width),
                        height: CGFloat(targetDisplay.height)
                    )
                }
            } else {
                // Mirror mode: use selected display
                guard let display = await getMirrorDisplay() else {
                    statusMessage = "Nenhum display disponivel"
                    streamServer.stop()
                    return
                }
                targetDisplay = display
                inputHandler.displayBounds = CGDisplayBounds(targetDisplay.displayID)
            }

            // 3. Start capture
            try await captureEngine.startCapture(
                display: targetDisplay,
                quality: CGFloat(quality),
                frameRate: frameRate
            )

            isRunning = true
            localIP = NetworkUtils.getLocalIPAddress()
            if statusMessage.hasPrefix("Capturando") || statusMessage.hasPrefix("API") || statusMessage.hasPrefix("Display virtual criado mas") {
                // keep existing message
            } else {
                statusMessage = "Rodando"
            }

            // FPS timer
            fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.fps = self?.captureEngine.currentFPS ?? 0
                }
            }
        } catch {
            statusMessage = "Erro: \(error.localizedDescription)"
            streamServer.stop()
        }
    }

    func stop() {
        captureEngine.stopCapture()
        streamServer.stop()
        fpsTimer?.invalidate()
        fpsTimer = nil

        if virtualDisplayID != 0 {
            VDBDestroyVirtualDisplay()
            virtualDisplayID = 0
        }

        isRunning = false
        connectedClients = 0
        fps = 0
        statusMessage = "Parado"
    }

    private func getMirrorDisplay() async -> SCDisplay? {
        await loadDisplays()
        guard !displays.isEmpty else { return nil }
        let idx = min(selectedDisplayIndex, displays.count - 1)
        return displays[idx]
    }
}
