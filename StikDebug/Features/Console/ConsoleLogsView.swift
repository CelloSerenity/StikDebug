//
//  ConsoleLogsView.swift
//  StikDebug
//
//  Created by neoarz on 3/29/25.
//

import SwiftUI
import UIKit

struct ConsoleLogsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var logManager = LogManager.shared
    @StateObject private var systemLogStream = SystemLogStream()

    @State private var selectedConsoleTab: ConsoleTab = .idevice
    @State private var jitScrollProxy: ScrollViewProxy?
    @State private var showingCustomAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isViewActive = false
    @State private var isLoadingLogs = false
    @State private var jitIsAtBottom = true
    @State private var syslogIsAtBottom = true
    @State private var syslogSearchText = ""
    @State private var showingSyslogSpeedSelector = false
    @State private var logPollTask: Task<Void, Never>?
    @State private var lastKnownFileSize: UInt64 = 0
    @State private var lastProcessedByteOffset: UInt64 = 0

    private let appLogRefreshInterval: TimeInterval = 2.0
    private let syslogIntervalOptions: [Double] = [0.0, 0.2, 0.5, 1.0, 1.5, 2.0]
    private let maxDisplayedLogs = 500

    private var filteredSyslogEntries: [SystemLogStream.Entry] {
        if syslogSearchText.isEmpty {
            return systemLogStream.entries
        }
        let query = syslogSearchText.lowercased()
        return systemLogStream.entries.filter { $0.searchableRaw.contains(query) }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedConsoleTab == .idevice {
                    jitLogsPane
                } else {
                    syslogLogsPane
                }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $selectedConsoleTab) {
                        Text("App").tag(ConsoleTab.idevice)
                        Text("System").tag(ConsoleTab.syslog)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if selectedConsoleTab == .idevice {
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await loadIdeviceLogs(fullReload: true) }
                            }
                            Button("Clear", systemImage: "trash", role: .destructive) {
                                logManager.clearLogs()
                            }
                            Button("Copy Logs", systemImage: "doc.on.doc") {
                                copyJITLogs()
                            }
                            exportMenuOption
                        } else {
                            Button(syslogControlLabel, systemImage: syslogControlIcon) {
                                toggleSyslogPlayback()
                            }
                            Button("Clear", systemImage: "trash", role: .destructive) {
                                systemLogStream.clear()
                            }
                            Button("Copy Logs", systemImage: "doc.on.doc") {
                                copySyslogToClipboard()
                            }
                            Button("Adjust Speed", systemImage: "slider.horizontal.3") {
                                showingSyslogSpeedSelector = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert(alertTitle, isPresented: $showingCustomAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog("Syslog Speed", isPresented: $showingSyslogSpeedSelector) {
                ForEach(syslogIntervalOptions, id: \.self) { option in
                    Button(intervalLabel(for: option)) {
                        systemLogStream.updateInterval = option
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose how quickly new relay entries appear.")
            }
            .onChange(of: selectedConsoleTab) { _, tab in
                if tab == .syslog {
                    if !systemLogStream.isStreaming {
                        systemLogStream.start()
                    }
                } else {
                    systemLogStream.stop()
                }
            }
            .onChange(of: systemLogStream.lastError) { _, newError in
                if let error = newError {
                    presentAlert(title: "Syslog Error", message: error)
                    systemLogStream.lastError = nil
                }
            }
            .onDisappear {
                isViewActive = false
                stopLogPolling()
                systemLogStream.stop()
            }
        }
    }

    private var jitLogsPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("=== DEVICE INFORMATION ===")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(primaryLogColor)
                            .padding(.vertical, 4)

                        Text("iOS Version: \(UIDevice.current.systemVersion)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(primaryLogColor)

                        Text("Device: \(UIDevice.current.name)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(primaryLogColor)

                        Text("Model: \(UIDevice.current.model)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(primaryLogColor)

                        Text("StikDebug: \(appVersion)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(primaryLogColor)

                        Text("=== LOG ENTRIES ===")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(primaryLogColor)
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    ForEach(logManager.logs) { logEntry in
                        AppLogRow(logEntry: logEntry, colorScheme: colorScheme)
                            .equatable()
                            .id(logEntry.id)
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("jitScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "jitScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                updateJITBottomState(offset > -20)
            }
            .onChange(of: logManager.logs.count) { _, _ in
                guard jitIsAtBottom, let lastLog = logManager.logs.last else { return }
                withAnimation {
                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                }
            }
            .onAppear {
                jitScrollProxy = proxy
                isViewActive = true
                Task { await loadIdeviceLogs(fullReload: true) }
                startLogPolling()
            }
            .onDisappear {
                isViewActive = false
                stopLogPolling()
            }
        }
    }

    private var syslogLogsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter logs", text: $syslogSearchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !syslogSearchText.isEmpty {
                    Button {
                        syslogSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredSyslogEntries) { entry in
                            SyslogRow(entry: entry, colorScheme: colorScheme)
                                .equatable()
                                .id(entry.id)
                        }
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("syslogScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "syslogScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    updateSyslogBottomState(offset > -20)
                }
                .onChange(of: systemLogStream.entries.count) { _, _ in
                    guard syslogIsAtBottom, syslogSearchText.isEmpty,
                          let lastLog = systemLogStream.entries.last else { return }
                    withAnimation {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if selectedConsoleTab == .syslog && !systemLogStream.isStreaming {
                        systemLogStream.start()
                    }
                }
            }
        }
    }

    private var primaryLogColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func copyJITLogs() {
        var logsContent = "=== DEVICE INFORMATION ===\n"
        logsContent += "Version: \(UIDevice.current.systemVersion)\n"
        logsContent += "Name: \(UIDevice.current.name)\n"
        logsContent += "Model: \(UIDevice.current.model)\n"
        logsContent += "StikDebug Version: \(appVersion)\n\n"
        logsContent += "=== LOG ENTRIES ===\n"
        logsContent += logManager.logs.map {
            "[\(DateFormatter.consoleLogsFormatter.string(from: $0.timestamp))] [\($0.type.rawValue)] \($0.message)"
        }.joined(separator: "\n")
        UIPasteboard.general.string = logsContent
        presentAlert(title: "Logs Copied", message: "Logs have been copied to clipboard.")
    }

    @ViewBuilder
    private var exportMenuOption: some View {
        let logURL = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
        if FileManager.default.fileExists(atPath: logURL.path) {
            ShareLink(
                item: logURL,
                preview: SharePreview("idevice_log.txt", image: Image(systemName: "doc.text"))
            ) {
                Label("Export Logs", systemImage: "square.and.arrow.up")
            }
        } else {
            Button("Export Logs", systemImage: "square.and.arrow.up") {
                presentAlert(title: "Export Failed", message: "No idevice logs found")
            }
        }
    }

    private func intervalLabel(for value: Double) -> String {
        if value <= 0 {
            return "Live"
        }
        return "\(String(format: "%.1f", value))s"
    }

    // MARK: - Efficient log tailing

    private func loadIdeviceLogs(fullReload: Bool) async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true

        let logURL = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
        let logPath = logURL.path

        guard FileManager.default.fileExists(atPath: logPath) else {
            await MainActor.run {
                if fullReload {
                    logManager.addInfoLog("No idevice logs found (Restart the app to continue reading)")
                }
                isLoadingLogs = false
            }
            return
        }

        let previousOffset = fullReload ? 0 : lastProcessedByteOffset
        let maxLogs = maxDisplayedLogs

        let result: LogTailResult? = await Task.detached(priority: .utility) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
                let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

                // File shrank (rotated/cleared) → force full reload
                let effectiveOffset: UInt64
                if previousOffset > fileSize {
                    effectiveOffset = 0
                } else if !fullReload && previousOffset == fileSize {
                    return LogTailResult(entries: [], newOffset: fileSize, replaced: false, unchanged: true)
                } else {
                    effectiveOffset = previousOffset
                }

                let handle = try FileHandle(forReadingFrom: logURL)
                defer { try? handle.close() }

                try handle.seek(toOffset: effectiveOffset)
                let data = handle.readDataToEndOfFile()
                guard let chunk = String(data: data, encoding: .utf8) else {
                    return nil
                }

                let lines = chunk.components(separatedBy: .newlines)
                let skipPrefixes = [
                    "=== DEVICE INFORMATION ===",
                    "Version:",
                    "Name:",
                    "Model:",
                    "=== LOG ENTRIES ===",
                    "StikDebug:"
                ]

                // When starting from mid-file, drop a partial first line.
                let linesToParse: ArraySlice<String>
                if effectiveOffset > 0, let firstNewline = chunk.firstIndex(of: "\n") {
                    let afterPartial = chunk.index(after: firstNewline)
                    let remainder = String(chunk[afterPartial...])
                    linesToParse = remainder.components(separatedBy: .newlines)[...]
                } else {
                    linesToParse = lines[...]
                }

                var parsed = Self.parseAppLogEntries(from: linesToParse, skipPrefixes: skipPrefixes)

                let replaced = fullReload || previousOffset > fileSize || effectiveOffset == 0
                if replaced && parsed.count > maxLogs {
                    parsed = Array(parsed.suffix(maxLogs))
                }

                return LogTailResult(
                    entries: parsed,
                    newOffset: fileSize,
                    replaced: replaced,
                    unchanged: false
                )
            } catch {
                return nil
            }
        }.value

        await MainActor.run {
            defer { isLoadingLogs = false }

            guard let result else {
                if fullReload {
                    logManager.addErrorLog("Failed to read idevice logs")
                }
                return
            }

            if result.unchanged {
                return
            }

            lastProcessedByteOffset = result.newOffset
            lastKnownFileSize = result.newOffset

            if result.replaced {
                logManager.setLogs(result.entries)
            } else if !result.entries.isEmpty {
                logManager.appendLogs(result.entries, maxTotal: maxDisplayedLogs)
            }

            if jitIsAtBottom, let last = logManager.logs.last {
                jitScrollProxy?.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func startLogPolling() {
        stopLogPolling()
        logPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(appLogRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled, isViewActive else { continue }
                await loadIdeviceLogs(fullReload: false)
            }
        }
    }

    private func stopLogPolling() {
        logPollTask?.cancel()
        logPollTask = nil
    }

    private func toggleSyslogPlayback() {
        if !systemLogStream.isStreaming {
            systemLogStream.start()
        } else {
            systemLogStream.togglePause()
        }
    }

    private func copySyslogToClipboard() {
        let entries = filteredSyslogEntries
        guard !entries.isEmpty else {
            let message = syslogSearchText.isEmpty
                ? "No syslog entries to copy."
                : "No matching syslog entries to copy."
            presentAlert(title: "Export Failed", message: message)
            return
        }

        let content = entries.map { entry in
            "[\(DateFormatter.consoleLogsFormatter.string(from: entry.timestamp))] \(entry.raw)"
        }.joined(separator: "\n")

        UIPasteboard.general.string = content
        let message = syslogSearchText.isEmpty
            ? "Latest syslog entries copied to clipboard."
            : "\(entries.count) filtered syslog entries copied to clipboard."
        presentAlert(title: "Logs Copied", message: message)
    }

    private var syslogControlIcon: String {
        if !systemLogStream.isStreaming || systemLogStream.isPaused {
            return "play.fill"
        }
        return "pause.fill"
    }

    private var syslogControlLabel: String {
        if !systemLogStream.isStreaming {
            return "Start syslog relay"
        }
        return systemLogStream.isPaused ? "Resume syslog stream" : "Pause syslog stream"
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingCustomAlert = true
    }

    private func updateJITBottomState(_ isAtBottom: Bool) {
        guard jitIsAtBottom != isAtBottom else { return }
        jitIsAtBottom = isAtBottom
    }

    private func updateSyslogBottomState(_ isAtBottom: Bool) {
        guard syslogIsAtBottom != isAtBottom else { return }
        syslogIsAtBottom = isAtBottom
    }

    nonisolated private static func parseAppLogEntries<S: Sequence>(
        from lines: S,
        skipPrefixes: [String] = []
    ) -> [LogManager.LogEntry] where S.Element == String {
        var parsed: [LogManager.LogEntry] = []
        parsed.reserveCapacity(lines.underestimatedCount)

        for line in lines {
            if line.isEmpty { continue }
            if skipPrefixes.contains(where: { line.contains($0) }) { continue }
            parsed.append(LogEntryFactory.make(from: line))
        }
        return parsed
    }
}

private struct LogTailResult: Sendable {
    let entries: [LogManager.LogEntry]
    let newOffset: UInt64
    let replaced: Bool
    let unchanged: Bool
}

private enum LogEntryFactory {
    nonisolated static func make(from line: String) -> LogManager.LogEntry {
        LogManager.LogEntry(timestamp: Date(), type: logType(for: line), message: line)
    }

    nonisolated static func logType(for line: String) -> LogManager.LogEntry.LogType {
        let lowercase = line.lowercased()
        if lowercase.contains("error") {
            return .error
        } else if lowercase.contains("warning") {
            return .warning
        } else if lowercase.contains("debug") {
            return .debug
        } else {
            return .info
        }
    }
}

struct ConsoleLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleLogsView()
    }
}

private struct AppLogRow: View, Equatable {
    let logEntry: LogManager.LogEntry
    let colorScheme: ColorScheme

    static func == (lhs: AppLogRow, rhs: AppLogRow) -> Bool {
        lhs.logEntry.id == rhs.logEntry.id && lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        Text(AttributedString(attributedString))
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
    }

    private var attributedString: NSAttributedString {
        let fullString = NSMutableAttributedString()

        fullString.append(NSAttributedString(
            string: "[\(DateFormatter.consoleLogsFormatter.string(from: logEntry.timestamp))]",
            attributes: [.foregroundColor: secondaryTextColor]
        ))
        fullString.append(NSAttributedString(string: " "))
        fullString.append(NSAttributedString(
            string: "[\(logEntry.type.rawValue)]",
            attributes: [.foregroundColor: UIColor(logEntry.type.consoleColor)]
        ))
        fullString.append(NSAttributedString(string: " "))
        fullString.append(NSAttributedString(
            string: logEntry.message,
            attributes: [.foregroundColor: primaryTextColor]
        ))

        return fullString
    }

    private var primaryTextColor: UIColor {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: UIColor {
        colorScheme == .dark ? .gray : .darkGray
    }
}

private struct SyslogRow: View, Equatable {
    let entry: SystemLogStream.Entry
    let colorScheme: ColorScheme

    static func == (lhs: SyslogRow, rhs: SyslogRow) -> Bool {
        lhs.entry.id == rhs.entry.id && lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        Text(AttributedString(attributedString))
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
    }

    private var attributedString: NSAttributedString {
        let type = LogEntryFactory.logType(for: entry.raw)
        let fullString = NSMutableAttributedString()

        fullString.append(NSAttributedString(
            string: "[\(DateFormatter.consoleLogsFormatter.string(from: entry.timestamp))]",
            attributes: [.foregroundColor: secondaryTextColor]
        ))
        fullString.append(NSAttributedString(string: " "))
        fullString.append(NSAttributedString(
            string: "[\(type.rawValue)]",
            attributes: [.foregroundColor: UIColor(type.consoleColor)]
        ))
        fullString.append(NSAttributedString(string: " "))
        fullString.append(NSAttributedString(
            string: entry.raw,
            attributes: [.foregroundColor: primaryTextColor]
        ))

        return fullString
    }

    private var primaryTextColor: UIColor {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: UIColor {
        colorScheme == .dark ? .gray : .darkGray
    }
}

private enum ConsoleTab: Hashable {
    case idevice
    case syslog
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension DateFormatter {
    static let consoleLogsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension LogManager.LogEntry.LogType {
    var consoleColor: Color {
        switch self {
        case .info:
            return .green
        case .error:
            return .red
        case .debug:
            return .blue
        case .warning:
            return .orange
        }
    }
}
