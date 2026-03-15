import Foundation
import Network

final class StreamServer: @unchecked Sendable {
    private var httpListener: NWListener?
    private var wsListener: NWListener?
    private var clients: [NWConnection] = []
    private var clientReady: [ObjectIdentifier: Bool] = [:]
    private let serverQueue = DispatchQueue(label: "com.screenextender.server", qos: .userInteractive)
    private let clientLock = NSLock()

    var onClientCountChanged: ((Int) -> Void)?
    var onTouchEvent: ((TouchEvent) -> Void)?

    private var wsPort: UInt16 = 7681

    func start(httpPort: UInt16 = 7680, wsPort: UInt16 = 7681) throws {
        self.wsPort = wsPort
        try startHTTPServer(port: httpPort)
        try startWebSocketServer(port: wsPort)
    }

    func stop() {
        httpListener?.cancel()
        wsListener?.cancel()
        httpListener = nil
        wsListener = nil

        clientLock.lock()
        for client in clients { client.cancel() }
        clients.removeAll()
        clientReady.removeAll()
        clientLock.unlock()

        onClientCountChanged?(0)
    }

    /// Send a JPEG frame to all connected WebSocket clients.
    /// Skips clients that haven't finished receiving the previous frame (backpressure).
    func broadcastFrame(_ data: Data) {
        clientLock.lock()
        let currentClients = clients
        clientLock.unlock()

        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])

        for client in currentClients {
            let id = ObjectIdentifier(client)

            clientLock.lock()
            let ready = clientReady[id] ?? true
            clientLock.unlock()

            guard ready else { continue }

            clientLock.lock()
            clientReady[id] = false
            clientLock.unlock()

            client.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.removeClient(client)
                } else {
                    self?.clientLock.lock()
                    self?.clientReady[id] = true
                    self?.clientLock.unlock()
                }
            })
        }
    }

    // MARK: - HTTP Server (serves web client page)

    private func startHTTPServer(port: UInt16) throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: port))

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleHTTPConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[HTTP] Server failed: \(error)")
            }
        }

        listener.start(queue: serverQueue)
        self.httpListener = listener
    }

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            guard request.hasPrefix("GET") else {
                connection.cancel()
                return
            }

            // Check if requesting favicon (ignore it)
            if request.contains("favicon.ico") {
                let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: notFound.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let html = WebClient.html(wsPort: self.wsPort)
            let headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: text/html; charset=utf-8",
                "Content-Length: \(html.utf8.count)",
                "Connection: close",
                "Cache-Control: no-cache",
            ].joined(separator: "\r\n")

            let response = "\(headers)\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - WebSocket Server (streams frames + receives touch)

    private func startWebSocketServer(port: UInt16) throws {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleWebSocketConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[WS] Server failed: \(error)")
            }
        }

        listener.start(queue: serverQueue)
        self.wsListener = listener
    }

    private func handleWebSocketConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)

        clientLock.lock()
        clients.append(connection)
        clientReady[ObjectIdentifier(connection)] = true
        let count = clients.count
        clientLock.unlock()

        print("[WS] Client connected (\(count) total)")
        onClientCountChanged?(count)
        receiveMessage(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.removeClient(connection)
            default:
                break
            }
        }
    }

    private func receiveMessage(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if error != nil {
                self.removeClient(connection)
                return
            }

            if let data,
               let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .text:
                    if let event = try? JSONDecoder().decode(TouchEvent.self, from: data) {
                        self.onTouchEvent?(event)
                    }
                case .close:
                    self.removeClient(connection)
                    return
                default:
                    break
                }
            }

            self.receiveMessage(connection)
        }
    }

    private func removeClient(_ connection: NWConnection) {
        clientLock.lock()
        let id = ObjectIdentifier(connection)
        let wasPresent = clients.contains(where: { ObjectIdentifier($0) == id })
        clients.removeAll { ObjectIdentifier($0) == id }
        clientReady.removeValue(forKey: id)
        let count = clients.count
        clientLock.unlock()

        connection.cancel()

        if wasPresent {
            print("[WS] Client disconnected (\(count) remaining)")
            onClientCountChanged?(count)
        }
    }
}
