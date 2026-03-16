import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Screen Extender")
                    .font(.title2.bold())
                Spacer()
                Circle()
                    .fill(state.isRunning ? .green : .gray)
                    .frame(width: 10, height: 10)
            }

            Divider()

            // Mode selector
            Picker("Modo", selection: $state.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(state.isRunning)

            // Virtual display resolution (only for extend mode)
            if state.displayMode == .extend {
                HStack {
                    Text("Resolucao virtual:")
                    Picker("", selection: Binding(
                        get: { "\(state.virtualWidth)x\(state.virtualHeight)" },
                        set: { val in
                            let parts = val.split(separator: "x")
                            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                                state.virtualWidth = w
                                state.virtualHeight = h
                            }
                        }
                    )) {
                        Text("1280x720").tag("1280x720")
                        Text("1280x800").tag("1280x800")
                        Text("1920x1080").tag("1920x1080")
                        Text("1920x1200").tag("1920x1200")
                        Text("2560x1440").tag("2560x1440")
                    }
                    .frame(width: 140)
                }
                .disabled(state.isRunning)
            }

            // Mirror display picker
            if state.displayMode == .mirror && state.displays.count > 1 {
                Picker("Display", selection: $state.selectedDisplayIndex) {
                    ForEach(0..<state.displays.count, id: \.self) { i in
                        Text("Display \(i + 1) (\(Int(state.displays[i].width))x\(Int(state.displays[i].height)))").tag(i)
                    }
                }
                .disabled(state.isRunning)
            }

            // Settings
            GroupBox("Streaming") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Qualidade:")
                        Slider(value: $state.quality, in: 0.1...1.0, step: 0.1)
                        Text("\(Int(state.quality * 100))%")
                            .frame(width: 36, alignment: .trailing)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("FPS:")
                        Picker("", selection: $state.frameRate) {
                            Text("15").tag(15)
                            Text("30").tag(30)
                            Text("60").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }

                    HStack {
                        Text("Porta:")
                        TextField("", value: $state.httpPort, format: .number)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(6)
            }
            .disabled(state.isRunning)

            // Start / Stop
            Button(action: {
                Task {
                    if state.isRunning {
                        state.stop()
                    } else {
                        await state.start()
                    }
                }
            }) {
                HStack {
                    Image(systemName: state.isRunning ? "stop.fill" : "play.fill")
                    Text(state.isRunning ? "Parar" : "Iniciar")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.isRunning ? .red : .blue)

            // Connection info
            if state.isRunning {
                GroupBox("Conexao") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Abra no tablet:")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }

                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                            Text("http://\(state.localIP):\(state.httpPort)")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("WiFi: abra o URL acima no browser do tablet")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .top) {
                                Text("USB:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("adb reverse tcp:\(state.httpPort) tcp:\(state.httpPort) && adb reverse tcp:\(state.httpPort + 1) tcp:\(state.httpPort + 1)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack {
                            Label("\(state.connectedClients) cliente(s)", systemImage: "person.2")
                            Spacer()
                            Label(String(format: "%.0f fps", state.fps), systemImage: "speedometer")
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                    .padding(6)
                }
            }

            // Status
            HStack {
                Text(state.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 440)
        .frame(minHeight: 420)
        .task {
            await state.loadDisplays()
            // Auto-start if launched with --auto-start
            if CommandLine.arguments.contains("--auto-start") && !state.isRunning {
                await state.start()
            }
        }
    }
}
