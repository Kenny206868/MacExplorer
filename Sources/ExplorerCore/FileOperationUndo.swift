import Foundation

extension FileOperationEngine {
    public func undo(_ receipt: OperationReceipt, control: OperationControl) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: receipt.title)
        do { try control.checkpoint(); try beginJournal("Undo " + receipt.title) }
        catch is CancellationError { result.cancelled = true; result.remaining = receipt.steps; return result }
        catch { result.errors = [error.localizedDescription]; result.remaining = receipt.steps; return result }
        if receipt.renameBatch == true {
            do {
                for step in receipt.steps {
                    guard step.kind == .move, let destination = step.destination,
                          destination.deletingLastPathComponent() == step.source.deletingLastPathComponent(), step.expected.matches(step.source) else {
                        throw ExplorerError.message("A renamed item changed or its recorded destination is invalid. Recovery stopped without modifying the batch.")
                    }
                }
                let mapping = receipt.steps.compactMap { step -> (URL, String)? in step.destination.map { (step.source, $0.lastPathComponent) } }
                result = performRename(mapping, control: control, replacing: receipt.id)
                if !result.errors.isEmpty || result.cancelled { result.remaining = receipt.steps }
            } catch { result.errors.append(error.localizedDescription); result.remaining = receipt.steps }
            finishJournal(&result); return result
        }
        for (index, step) in receipt.steps.enumerated() {
            do {
                try control.checkpoint(); try guardSource(step.source)
                guard step.canRestore() else { throw ExplorerError.message("\(step.source.lastPathComponent) changed since the operation. Undo stopped to protect newer changes.") }
                var updated = result.receipt
                var outputURL: URL?
                switch step.kind {
                case .move:
                    guard let destination = step.destination, !FileNames.exists(destination) else { throw ExplorerError.message("Undo destination is occupied. Move the conflicting item first.") }
                    try moveDurably(step.source, to: destination, emptyDirectory: step.emptyDirectory == true)
                    updated.steps.insert(try UndoStep(.move, source: destination, destination: step.source, emptyDirectory: step.emptyDirectory == true), at: 0)
                    outputURL = destination
                case .trash:
                    let trashed = try transaction().external("trash", source: step.source) {
                        var output: NSURL?; try FileManager.default.trashItem(at: step.source, resultingItemURL: &output); return output.map { $0 as URL }
                    }
                    if let trashed { updated.steps.insert(try UndoStep(.move, source: trashed, destination: step.source), at: 0) }
                }
                var remainder = receipt; remainder.steps = Array(receipt.steps.dropFirst(index + 1))
                try record(updated, replacing: receipt.id, remaining: remainder.steps.isEmpty ? nil : remainder)
                result.receipt = updated
                if let outputURL { result.outputs.append(outputURL) }
            } catch {
                result.errors.append(error.localizedDescription); result.remaining = Array(receipt.steps[index...])
                _ = rollbackJournal(into: &result); break
            }
        }
        finishJournal(&result); return result
    }
    /// Stage all names before installing any, so swaps and cycles are reversible.
    public func rename(_ mapping: [(URL, String)], control: OperationControl, expected: [String: FileFingerprint] = [:]) async -> FileJobResult {
        await acquire(); defer { release() }
        for (source, _) in mapping {
            if let fingerprint = expected[source.standardizedFileURL.path], !fingerprint.matches(source) {
                var result = FileJobResult(title: "Rename")
                result.errors = ["\(source.lastPathComponent) changed while its name was being edited. No rename was performed."]; return result
            }
        }
        var result = FileJobResult(title: "Rename")
        do { try control.checkpoint(); try beginJournal("Rename") }
        catch is CancellationError { result.cancelled = true; return result }
        catch { result.errors = [error.localizedDescription]; return result }
        result = performRename(mapping, control: control); finishJournal(&result); return result
    }
    private func performRename(_ mapping: [(URL, String)], control: OperationControl, replacing: UUID? = nil) -> FileJobResult {
        var result = FileJobResult(title: "Rename"); result.receipt.renameBatch = true
        var staged: [(source: URL, stage: URL, target: URL)] = [], installed: [(source: URL, target: URL)] = []
        do {
            let sources = Set(mapping.map { $0.0.standardizedFileURL })
            var targets = Set<URL>()
            for (source, name) in mapping {
                try guardSource(source); try FileNames.validate(name)
                let target = source.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
                guard targets.insert(target).inserted else { throw ExplorerError.message("Two items would have the same name.") }
                if FileNames.exists(target) && !sources.contains(target) {
                    let a = try? FileFingerprint(source), b = try? FileFingerprint(target)
                    guard a?.inode == b?.inode && a?.device == b?.device else { throw ExplorerError.message("The name \(name) already exists.") }
                }
            }
            for (source, name) in mapping {
                try control.checkpoint()
                let stage = source.deletingLastPathComponent().appendingPathComponent(".MacExplorer-rename-" + UUID().uuidString)
                try moveDurably(source, to: stage)
                staged.append((source, stage, source.deletingLastPathComponent().appendingPathComponent(name)))
            }
            for item in staged {
                try moveDurably(item.stage, to: item.target)
                installed.append((item.source, item.target)); result.outputs.append(item.target)
            }
            for item in installed.reversed() { result.receipt.steps.append(try UndoStep(.move, source: item.target, destination: item.source)) }
            try record(result.receipt, replacing: replacing)
        } catch {
            result.outputs = []; result.receipt.steps = []
            if error is CancellationError { result.cancelled = true } else { result.errors.append(error.localizedDescription) }
            _ = rollbackJournal(into: &result)
        }
        return result
    }
}
