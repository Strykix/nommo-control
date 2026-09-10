import AppKit
import SwiftUI

struct LogView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Journal").font(.headline)
                Spacer()
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bluetooth.logAsText(), forType: .string)
                }
                Button("Vider") { bluetooth.clearLog() }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(bluetooth.log) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.formatter.string(from: entry.date))
                                    .foregroundStyle(.secondary)
                                Text(entry.prefix)
                                    .foregroundStyle(color(for: entry.kind))
                                Text(entry.message)
                                    .textSelection(.enabled)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: bluetooth.log.count) { _ in
                    if let last = bluetooth.log.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .info: return .secondary
        case .tx: return .blue
        case .rx: return .green
        case .error: return .red
        }
    }
}
