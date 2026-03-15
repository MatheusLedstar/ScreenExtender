import Foundation
import VirtualDisplayBridge
import ScreenCaptureKit

/// Standalone test: creates a virtual display, checks if macOS sees it, then cleans up.
/// Run with: swift run ScreenExtender --test
enum VirtualDisplayTest {
    static func run() async {
        print("=== Screen Extender: Virtual Display Test ===\n")

        // 1. List displays BEFORE
        print("[1] Displays ANTES da criacao:")
        await listDisplays()

        // 2. Create virtual display
        print("\n[2] Criando virtual display 1920x1080...")
        let displayID = VDBCreateVirtualDisplay(1920, 1080, 0, "ScreenExtender Test")

        if displayID == 0 {
            print("    FALHOU: CGVirtualDisplay nao disponivel ou erro na criacao.")
            print("    Isso pode significar:")
            print("    - macOS nao suporta CGVirtualDisplay neste contexto")
            print("    - Permissoes insuficientes")
            print("    - API privada mudou nesta versao do macOS")
            print("\n    O app vai funcionar em modo ESPELHAR (mirror) como fallback.")
            return
        }

        print("    SUCESSO! Display ID: \(displayID)")

        // 3. Wait for macOS to register
        print("\n[3] Aguardando macOS registrar o display...")
        try? await Task.sleep(for: .seconds(2))

        // 4. Check bounds
        let bounds = VDBGetDisplayBounds()
        print("    Bounds: origin=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y))) size=\(Int(bounds.width))x\(Int(bounds.height))")

        // 5. List displays AFTER
        print("\n[4] Displays DEPOIS da criacao:")
        await listDisplays()

        // 6. Check ScreenCaptureKit detection
        print("\n[5] ScreenCaptureKit detecta o display virtual?")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let found = content.displays.first(where: { $0.displayID == displayID })
            if let d = found {
                print("    SIM! SCDisplay: \(d.width)x\(d.height), ID=\(d.displayID)")
            } else {
                print("    NAO encontrado no ScreenCaptureKit.")
                print("    Displays disponiveis via SCK:")
                for d in content.displays {
                    print("      - ID=\(d.displayID) \(d.width)x\(d.height)")
                }
            }
        } catch {
            print("    Erro ao consultar SCK: \(error.localizedDescription)")
            print("    (Pode ser necessario conceder permissao de Screen Recording)")
        }

        // 7. Keep alive briefly for manual inspection
        print("\n[6] Display virtual ativo por 5 segundos para inspecao...")
        print("    Verifique: Ajustes do Sistema > Telas")
        try? await Task.sleep(for: .seconds(5))

        // 8. Cleanup
        print("\n[7] Removendo display virtual...")
        VDBDestroyVirtualDisplay()
        print("    Display removido.")

        print("\n=== Teste concluido ===")
    }

    private static func listDisplays() async {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            let bounds = CGDisplayBounds(id)
            let isMain = CGDisplayIsMain(id) != 0
            print("    [\(i)] ID=\(id) \(Int(bounds.width))x\(Int(bounds.height)) \(isMain ? "(principal)" : "")")
        }

        if displayCount == 0 {
            print("    (nenhum display encontrado)")
        }
    }
}
