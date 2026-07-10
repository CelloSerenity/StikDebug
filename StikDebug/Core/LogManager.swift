//
//  LogManager.swift
//  StikDebug
//
//  Created by neoarz on 3/29/25.
//

import Foundation

final class LogManager: ObservableObject {
    static let shared = LogManager()

    @Published var logs: [LogEntry] = []

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let type: LogType
        let message: String

        enum LogType: String, Sendable {
            case info = "INFO"
            case error = "ERROR"
            case debug = "DEBUG"
            case warning = "WARNING"
        }

        init(timestamp: Date = Date(), type: LogType, message: String) {
            self.timestamp = timestamp
            self.type = type
            self.message = message
        }
    }

    private static let redundantPrefixes = [
        "Info: ", "INFO: ", "Information: ",
        "Error: ", "ERROR: ", "ERR: ",
        "Debug: ", "DEBUG: ", "DBG: ",
        "Warning: ", "WARN: ", "WARNING: "
    ]

    private init() {
        addInfoLog("StikDebug starting up")
    }

    func addLog(message: String, type: LogEntry.LogType) {
        let clean = Self.redundantPrefixes
            .first(where: { message.hasPrefix($0) })
            .map { String(message.dropFirst($0.count)) } ?? message

        onMain {
            if let last = self.logs.last, last.type == type, last.message == clean {
                return
            }
            self.logs.append(LogEntry(type: type, message: clean))
            if self.logs.count > 1000 {
                self.logs.removeFirst(100)
            }
        }
    }

    func addInfoLog(_ message: String) { addLog(message: message, type: .info) }
    func addErrorLog(_ message: String) { addLog(message: message, type: .error) }
    func addDebugLog(_ message: String) { addLog(message: message, type: .debug) }
    func addWarningLog(_ message: String) { addLog(message: message, type: .warning) }

    func setLogs(_ entries: [LogEntry]) {
        onMain { self.logs = entries }
    }

    func appendLogs(_ entries: [LogEntry], maxTotal: Int = 1000) {
        onMain {
            self.logs.append(contentsOf: entries)
            if self.logs.count > maxTotal {
                self.logs.removeFirst(self.logs.count - maxTotal)
            }
        }
    }

    func clearLogs() {
        onMain { self.logs.removeAll() }
    }

    private func onMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}
