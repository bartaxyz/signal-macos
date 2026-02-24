import Foundation

@MainActor
final class SignalCLIService: Sendable {
    nonisolated static let signalCLIPath = "/usr/local/bin/signal-cli"
    
    private(set) var daemonProcess: Process?
    private var daemonStdin: FileHandle?
    
    nonisolated init() {}
    
    // MARK: - Link Device
    
    struct LinkResult: Sendable {
        let uri: String
        let process: Process
    }
    
    nonisolated func link(deviceName: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.signalCLIPath)
        process.arguments = ["link", "-n", deviceName]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        // Read URI from stdout - signal-cli outputs it on the first line
        let uri: String = try await withCheckedThrowingContinuation { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("tsdevice:") || trimmed.hasPrefix("sgnl:") {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(returning: trimmed)
                        return
                    }
                }
            }
        }
        
        // Don't wait for process to finish - linking completes when user scans QR
        // The process will keep running until linking succeeds or fails
        Task.detached {
            process.waitUntilExit()
        }
        
        return uri
    }
    
    // MARK: - Daemon
    
    func startDaemon(account: String, onMessage: @escaping @Sendable (SignalEnvelope) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.signalCLIPath)
        process.arguments = ["-a", account, "--output=json", "daemon"]
        
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdinPipe
        
        self.daemonProcess = process
        self.daemonStdin = stdinPipe.fileHandleForWriting
        
        try process.run()
        
        // Read incoming JSON messages
        let handle = stdoutPipe.fileHandleForReading
        Task.detached {
            var buffer = Data()
            while true {
                let data = handle.availableData
                if data.isEmpty { break } // EOF
                buffer.append(data)
                
                // Process complete lines
                while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                    
                    guard !lineData.isEmpty else { continue }
                    if let envelope = try? JSONDecoder().decode(SignalEnvelope.self, from: lineData) {
                        onMessage(envelope)
                    }
                }
            }
        }
    }
    
    func send(message: String, to recipient: String) throws {
        // Send via JSON-RPC to daemon stdin
        let request = JSONRPCRequest(
            jsonrpc: "2.0",
            method: "send",
            params: SendParams(recipient: [recipient], message: message),
            id: UUID().uuidString
        )
        
        guard let stdinHandle = daemonStdin else {
            throw SignalError.daemonNotRunning
        }
        
        let data = try JSONEncoder().encode(request)
        stdinHandle.write(data)
        stdinHandle.write(Data("\n".utf8))
    }
    
    nonisolated func loadContacts(account: String) async -> [SignalContact] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.signalCLIPath)
        process.arguments = ["-a", account, "--output=json", "listContacts"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            guard let data = output.data(using: .utf8) else { return [] }
            // Output is a JSON array
            if let contacts = try? JSONDecoder().decode([SignalContact].self, from: data) {
                return contacts
            }
            // Fallback: line-delimited JSON
            var contacts: [SignalContact] = []
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let lineData = trimmed.data(using: .utf8),
                   let contact = try? JSONDecoder().decode(SignalContact.self, from: lineData) {
                    contacts.append(contact)
                }
            }
            return contacts
        } catch {
            return []
        }
    }
    
    func stopDaemon() {
        daemonProcess?.terminate()
        daemonProcess = nil
        daemonStdin = nil
    }
    
    // MARK: - Account Discovery
    
    nonisolated static func findLinkedAccount() -> String? {
        let dataPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/signal-cli/data/accounts.json")
        
        guard let data = try? Data(contentsOf: dataPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = json["accounts"] as? [[String: Any]],
              let first = accounts.first,
              let number = first["number"] as? String else {
            
            // Fallback: scan data directory for account folders
            let dataDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/signal-cli/data")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dataDir.path) {
                return contents.first { $0.hasPrefix("+") }
            }
            return nil
        }
        return number
    }
}

// MARK: - JSON Models

struct SignalEnvelope: Codable, Sendable {
    let envelope: Envelope?
    
    struct Envelope: Codable, Sendable {
        let source: String?
        let sourceName: String?
        let sourceDevice: Int?
        let timestamp: Int64?
        let dataMessage: DataMessage?
        let syncMessage: SyncMessage?
    }
    
    struct DataMessage: Codable, Sendable {
        let timestamp: Int64?
        let message: String?
        let groupInfo: GroupInfo?
    }
    
    struct SyncMessage: Codable, Sendable {
        let sentMessage: SentMessage?
    }
    
    struct SentMessage: Codable, Sendable {
        let destination: String?
        let destinationName: String?
        let timestamp: Int64?
        let message: String?
        let groupInfo: GroupInfo?
    }
    
    struct GroupInfo: Codable, Sendable {
        let groupId: String?
    }
}

struct SignalContact: Codable, Sendable {
    let number: String?
    let name: String?
    let uuid: String?
    let profile: SignalProfile?
    
    var displayName: String {
        // Try profile name first, then top-level name, then number
        let profileName = [profile?.givenName, profile?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !profileName.isEmpty { return profileName }
        if let name = name, !name.isEmpty { return name }
        return number ?? uuid ?? "Unknown"
    }
}

struct SignalProfile: Codable, Sendable {
    let givenName: String?
    let familyName: String?
}

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let params: SendParams
    let id: String
}

struct SendParams: Codable, Sendable {
    let recipient: [String]
    let message: String
}

enum SignalError: Error, LocalizedError {
    case daemonNotRunning
    case linkFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .daemonNotRunning: return "Signal daemon is not running"
        case .linkFailed(let msg): return "Link failed: \(msg)"
        }
    }
}
