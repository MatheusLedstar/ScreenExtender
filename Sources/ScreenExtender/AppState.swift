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
            log("Displays carregados: \(displays.count)")
            for (i, d) in displays.enumerated() {
                log("  [\(i)] ID=\(d.displayID) \(d.width)x\(d.height)")
            }
        } catch {
            log("Erro ao listar displays: \(error)")
            statusMessage = "Erro ao listar displays: \(error.localizedDescription)"
        }
    }

    func start() async {
        log("=== START ===")
        log("Mode: \(displayMode.rawValue)")

        do {
            // 1. Start servers
            let wsPort = httpPort + 1
            log("Iniciando servidores HTTP:\(httpPort) WS:\(wsPort)...")
            try streamServer.start(httpPort: httpPort, wsPort: wsPort)
            log("Servidores iniciados OK")

            // 2. Get target display
            let targetDisplay: SCDisplay

            if displayMode == .extend {
                log("Criando display virtual \(virtualWidth)x\(virtualHeight)...")
                let vdID = VDBCreateVirtualDisplay(
                    UInt32(virtualWidth),
                    UInt32(virtualHeight),
                    0,
                    "Screen Extender"
                )

                if vdID != 0 {
                    virtualDisplayID = vdID
                    log("Display virtual criado: ID=\(vdID)")
                    statusMessage = "Display virtual criado (ID: \(vdID)). Buscando no SCK..."

                    // Wait for ScreenCaptureKit to discover it
                    if let vDisplay = await captureEngine.findDisplay(byID: vdID) {
                        targetDisplay = vDisplay
                        let bounds = VDBGetDisplayBounds()
                        inputHandler.displayBounds = bounds
                        log("SCK encontrou display virtual: \(vDisplay.width)x\(vDisplay.height) at \(bounds)")
                        statusMessage = "Capturando display virtual"
                    } else {
                        log("SCK NAO encontrou display virtual, fallback para mirror")
                        statusMessage = "Display virtual nao detectado pelo SCK. Usando mirror."
                        VDBDestroyVirtualDisplay()
                        virtualDisplayID = 0
                        guard let fallback = await getMirrorDisplay() else {
                            log("Nenhum display para mirror, abortando")
                            statusMessage = "Nenhum display disponivel"
                            streamServer.stop()
                            return
                        }
                        targetDisplay = fallback
                        inputHandler.displayBounds = CGDisplayBounds(targetDisplay.displayID)
                    }
                } else {
                    log("CGVirtualDisplay falhou, fallback para mirror")
                    statusMessage = "API de display virtual nao disponivel. Usando mirror."
                    guard let fallback = await getMirrorDisplay() else {
                        log("Nenhum display para mirror, abortando")
                        statusMessage = "Nenhum display disponivel"
                        streamServer.stop()
                        return
                    }
                    targetDisplay = fallback
                    inputHandler.displayBounds = CGDisplayBounds(targetDisplay.displayID)
                }
            } else {
                guard let display = await getMirrorDisplay() else {
                    log("Nenhum display disponivel")
                    statusMessage = "Nenhum display disponivel"
                    streamServer.stop()
                    return
                }
                targetDisplay = display
                inputHandler.displayBounds = CGDisplayBounds(targetDisplay.displayID)
            }

            // 3. Start capture
            log("Iniciando captura de display ID=\(targetDisplay.displayID) \(targetDisplay.width)x\(targetDisplay.height)...")
            try await captureEngine.startCapture(
                display: targetDisplay,
                quality: CGFloat(quality),
                frameRate: frameRate
            )
            log("Captura iniciada!")

            isRunning = true
            localIP = NetworkUtils.getLocalIPAddress()
            if !statusMessage.hasPrefix("Capturando") {
                statusMessage = "Rodando - http://\(localIP):\(httpPort)"
            }
            log("URL: http://\(localIP):\(httpPort)")

            // FPS timer
            fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.fps = self?.captureEngine.currentFPS ?? 0
                }
            }

            log("=== START COMPLETE ===")
        } catch {
            log("ERRO no start: \(error)")
            statusMessage = "Erro: \(error.localizedDescription)"
            // Cleanup on error
            if virtualDisplayID != 0 {
                VDBDestroyVirtualDisplay()
                virtualDisplayID = 0
            }
            streamServer.stop()
        }
    }

    func stop() {
        log("=== STOP ===")
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

    private func log(_ message: String) {
        print("[ScreenExtender] \(message)")
    }
}
