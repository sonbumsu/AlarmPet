// LocalServerSource.swift
// Tiny HTTP endpoint on 127.0.0.1 so scripts can make the pet talk:
//
//   curl -X POST localhost:7777/say -d '{"app":"카카오톡","body":"집가고싶어ㅠㅠ","sender":"손범수"}'
//   curl -X POST localhost:7777/say -d '빌드 끝!'          (plain text body also works)
//
// Accepted JSON keys: app, body | text, sender | title, pet (name or id; omit = every matching pet).

import Foundation
import Network

final class LocalServerSource: NotificationSource {

    var onMessage: ((PetMessage) -> Void)?
    /// nil once listening; a message for the settings panel if the port couldn't be opened.
    var onStatusChange: ((String?) -> Void)?

    private let port: UInt16
    private var listener: NWListener?

    private enum Constants {
        static let maxRequestSize = 64 * 1024
        static let defaultApp = "알림펫"
    }

    init(port: UInt16) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Loopback only — notifications never leave this Mac.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)

        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.onStatusChange?(nil)
                case .failed(let error), .waiting(let error):
                    NSLog("LocalServerSource: listener failed on port %d: %@", Int(nwPort.rawValue), String(describing: error))
                    self?.onStatusChange?(Self.describe(error, port: nwPort.rawValue))
                default:
                    break
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("LocalServerSource: could not start on port %d: %@", Int(port), String(describing: error))
            onStatusChange?("포트 \(port)을(를) 열 수 없어요")
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
    }

    private static func describe(_ error: NWError, port: UInt16) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "포트 \(port)을(를) 다른 프로그램이 쓰고 있어요. 다른 번호로 바꿔 주세요."
        }
        return "포트 \(port)을(를) 열 수 없어요 (\(error.localizedDescription))"
    }

    // MARK: - HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Constants.maxRequestSize) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || buffer.count > Constants.maxRequestSize {
                self.send(status: "400 Bad Request", body: #"{"ok":false,"error":"bad request"}"#, on: connection)
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("POST", "/say"):
            guard let message = Self.message(from: request.body) else {
                send(status: "400 Bad Request", body: #"{"ok":false,"error":"body is empty"}"#, on: connection)
                return
            }
            onMessage?(message)
            send(status: "200 OK", body: #"{"ok":true}"#, on: connection)
        case ("GET", "/health"):
            send(status: "200 OK", body: #"{"ok":true}"#, on: connection)
        default:
            send(status: "404 Not Found", body: #"{"ok":false,"error":"use POST /say"}"#, on: connection)
        }
    }

    private func send(status: String, body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func message(from body: Data) -> PetMessage? {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let text = (json["body"] as? String) ?? (json["text"] as? String) ?? ""
            guard !text.isEmpty else { return nil }
            let app = (json["app"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Constants.defaultApp
            let sender = (json["sender"] as? String) ?? (json["title"] as? String)
            var message = PetMessage(app: app, body: text, sender: sender)
            message.target = (json["pet"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return message
        }
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : PetMessage(app: Constants.defaultApp, body: text, sender: nil)
    }
}

/// Minimal HTTP/1.1 request parser. Returns nil until headers + full body have arrived.
private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(_ data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }

        method = String(requestLine[0]).uppercased()
        path = String(requestLine[1].split(separator: "?").first ?? "")
        body = data[bodyStart..<(bodyStart + contentLength)]
    }
}
