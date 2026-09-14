import SwiftUI
import ExplorerCore

struct OperationTransferDetails: View {
    @ObservedObject var job: OperationRow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let stale = ProcessInfo.processInfo.systemUptime - job.progress.timestamp > 2
            let measuring = stale || job.paused || job.progress.phase != .copying
            VStack(alignment: .leading, spacing: 9) {
                if job.progress.phase == .calculating {
                    HStack { ProgressView().controlSize(.small); Text("Calculating the selected size…").font(.caption).foregroundStyle(.secondary) }
                } else {
                    if !job.finished {
                        if let total = job.progress.totalBytes, total > 0 {
                            ProgressView(value: Double(min(total, job.progress.logicalBytes)), total: Double(total))
                        } else { ProgressView(value: Double(job.progress.completed), total: Double(max(1, job.progress.total))) }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(byteCount(job.progress.logicalBytes)).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                        if let total = job.progress.totalBytes { Text("of \(byteCount(total))").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if job.paused { Text("Paused") }
                        else if !measuring, let rate = job.statistics.bytesPerSecond { Text(byteCount(Int64(min(rate, Double(Int64.max / 2)))) + "/s").monospacedDigit() }
                        else if job.progress.clonedFiles > 0 && job.progress.bytes == 0 { Text("Filesystem clone") }
                        else if !job.finished { Text(stale ? "Waiting for filesystem…" : "Measuring…") }
                    }.font(.caption).foregroundStyle(.secondary)
                    if job.statistics.samples.count > 1 {
                        ZStack {
                            RateGrid().stroke(.quaternary, lineWidth: 0.5)
                            TransferRateGraph(samples: job.statistics.samples, fill: true).fill(Color.accentColor.opacity(0.13))
                            TransferRateGraph(samples: job.statistics.samples, fill: false).stroke(Color.accentColor, lineWidth: 1.6)
                        }.frame(height: 58).clipped().opacity(job.paused ? 0.45 : 1)
                            .accessibilityLabel("Transfer speed history")
                            .accessibilityValue(job.statistics.bytesPerSecond.map { "\(Int64(min($0, Double(Int64.max / 2)))) bytes per second" } ?? "No measured rate")
                    }
                    HStack {
                        if !measuring, let remaining = job.statistics.secondsRemaining(totalBytes: job.progress.totalBytes, completedBytes: job.progress.logicalBytes), remaining.isFinite {
                            Text("About " + duration(remaining) + " remaining")
                        } else if !job.finished { Text("Time remaining is being estimated") }
                        Spacer()
                        if job.progress.clonedFiles > 0 { Text("\(job.progress.clonedFiles) cloned item(s)") }
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func byteCount(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file) }
    private func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "a moment" }
        if seconds < 60 { return "\(Int(seconds.rounded(.up))) seconds" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded(.up))) minutes" }
        if seconds < 86400 { return String(format: "%.1f hours", seconds / 3600) }
        return String(format: "%.1f days", seconds / 86400)
    }
}

private struct RateGrid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for row in 1..<4 {
                let y = rect.height * CGFloat(row) / 4
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
            }
            for column in 1..<8 {
                let x = rect.width * CGFloat(column) / 8
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
            }
        }
    }
}

private struct TransferRateGraph: Shape {
    let samples: [TransferStatistics.Sample]
    let fill: Bool
    func path(in rect: CGRect) -> Path {
        guard let first = samples.first, let last = samples.last else { return Path() }
        let span = max(12, last.time - first.time)
        let start = last.time - span
        let peak = max(1, (samples.map(\.bytesPerSecond).max() ?? 1) * 1.15)
        let points = samples.map { sample in
            CGPoint(x: rect.width * CGFloat((sample.time - start) / span),
                    y: rect.height * CGFloat(1 - max(0, min(1, sample.bytesPerSecond / peak))))
        }
        return Path { path in
            guard let point = points.first else { return }
            path.move(to: fill ? CGPoint(x: point.x, y: rect.maxY) : point)
            if fill { path.addLine(to: point) }
            for point in points.dropFirst() { path.addLine(to: point) }
            if fill, let end = points.last { path.addLine(to: CGPoint(x: end.x, y: rect.maxY)); path.closeSubpath() }
        }
    }
}
