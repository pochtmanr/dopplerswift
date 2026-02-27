import SwiftUI

struct TunnelDebugView: View {
    @State private var logContent = ""
    @State private var timer: Timer?

    private static let appGroupID = "group.com.pulsingroutes.vpn"
    private static let logFileName = "tunnel_debug.log"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logContent.isEmpty ? "No tunnel logs yet.\nTry connecting to a server, then come back here." : logContent)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(logContent.isEmpty ? Design.Colors.textTertiary : Design.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.md)
                    .id("bottom")
            }
        }
        .background(Design.Colors.surfaceBackground)
        .navigationTitle("Tunnel Logs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { loadLogs() }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Copy Logs") {
                        #if os(iOS)
                        UIPasteboard.general.string = logContent
                        #endif
                    }
                    Button("Clear Logs", role: .destructive) {
                        clearLogs()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadLogs()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                loadLogs()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var logFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.logFileName)
    }

    private func loadLogs() {
        guard let url = logFileURL else {
            logContent = "App Group container not available."
            return
        }
        logContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func clearLogs() {
        guard let url = logFileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
        logContent = ""
    }
}
