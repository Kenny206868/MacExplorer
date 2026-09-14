import Foundation
import ExplorerJournal

extension FileOperationEngine {
    public func run(_ job: FileJob, control: OperationControl, progress: @escaping @Sendable (FileProgress) -> Void, resolve: @Sendable (FileCollision) async -> CollisionAnswer) async -> FileJobResult {
        await acquire(); defer { release() }
        var result = FileJobResult(title: job.title), sticky: CollisionChoice?
        let manager = FileManager.default
        do { try control.checkpoint(); try beginJournal(job.title) }
        catch is CancellationError { result.cancelled = true; return result }
        catch { result.errors = [error.localizedDescription]; return result }
        let reporter = TransferProgressReporter(total: job.sources.count, observer: progress)
        if job.kind == .copy {
            var total: Int64 = 0, completeEstimate = true
            for source in job.sources {
                reporter.phase(.calculating, name: source.lastPathComponent)
                do {
                    let size = try TransferInventory.logicalBytes(source, control: control)
                    let (sum, overflow) = total.addingReportingOverflow(size)
                    if overflow { completeEstimate = false } else { total = sum }
                } catch is CancellationError {
                    result.cancelled = true; result.finalProgress = reporter.finish(cancelled: true); finishJournal(&result); return result
                } catch { completeEstimate = false }
            }
            reporter.estimate(completeEstimate ? total : nil)
        }
        if [.createFolder, .createFile, .compress, .extract].contains(job.kind) {
            do {
                try control.checkpoint()
                guard let destination = job.destination else { throw ExplorerError.message("Choose a destination folder.") }
                let parent = job.kind == .createFolder || job.kind == .createFile ? destination.deletingLastPathComponent() : destination
                let container = try newStage(in: parent)
                let payload: URL, target: URL
                switch job.kind {
                case .createFolder, .createFile:
                    target = destination; payload = container.appendingPathComponent("payload")
                    try FileNames.validate(target.lastPathComponent)
                    guard !FileNames.exists(target) else { throw ExplorerError.message("An item with that name already exists.") }
                    if job.kind == .createFolder { try manager.createDirectory(at: payload, withIntermediateDirectories: false) }
                    else { try Data().write(to: payload, options: .withoutOverwriting) }
                case .compress:
                    let identities = try job.sources.map { ($0, try FileFingerprint($0)) }
                    payload = try ArchiveService.compress(job.sources, to: container, control: control)
                    guard identities.allSatisfy({ $0.1.matches($0.0) }) else { throw ExplorerError.message("A source changed while creating the archive.") }
                    target = FileNames.unique(parent.appendingPathComponent(payload.lastPathComponent))
                default:
                    guard let source = job.sources.first else { throw ExplorerError.message("Select an archive.") }
                    payload = try ArchiveService.extract(source, to: container, control: control, options: job.archiveOptions)
                    target = FileNames.unique(parent.appendingPathComponent(payload.lastPathComponent))
                }
                try JournalDurability.synchronizeTree(payload) { try control.checkpoint() }
                try control.checkpoint(); try moveDurably(payload, to: target)
                var receipt = result.receipt; receipt.steps = [try UndoStep(.trash, source: target)]
                try record(receipt); result.receipt = receipt; result.outputs = [target]
            } catch is CancellationError { result.cancelled = true }
            catch { result.errors.append(error.localizedDescription) }
            finishJournal(&result)
            let final = FileProgress(completed: result.outputs.isEmpty ? 0 : 1, total: 1, name: result.outputs.first?.lastPathComponent ?? job.title, phase: result.cancelled ? .cancelled : .finished)
            result.finalProgress = final; progress(final); return result
        }
        for source in job.sources {
            reporter.begin(name: source.lastPathComponent, copying: job.kind == .copy)
            var succeeded = false
            defer { reporter.end(success: succeeded) }
            do {
                try control.checkpoint(); try guardSource(source)
                var steps: [UndoStep] = [], output: URL?
                if job.kind == .trash {
                    let trashed = try transaction().external("trash", source: source) {
                        var output: NSURL?; try manager.trashItem(at: source, resultingItemURL: &output); return output.map { $0 as URL }
                    }
                    if let trashed { steps = [try UndoStep(.move, source: trashed, destination: source)] }
                    else { result.errors.append("macOS trashed \(source.lastPathComponent), but did not provide a restore URL.") }
                } else if job.kind == .delete {
                    _ = try transaction().external("delete", source: source) { try manager.removeItem(at: source); return nil }
                } else {
                    guard let directory = job.destination else { throw ExplorerError.message("Choose a destination folder.") }
                    let name = job.names[source.path] ?? source.lastPathComponent
                    try FileNames.validate(name)
                    var target = directory.appendingPathComponent(name)
                    if source.standardizedFileURL == target.standardizedFileURL && job.kind == .move { result.skippedSources.append(source); continue }
                    var replace = false, merge = false
                    if FileNames.exists(target) {
                        let collision = FileCollision(source: source, destination: target)
                        let originalAtPrompt = try FileFingerprint(source), targetAtPrompt = try FileFingerprint(target)
                        let answer: CollisionAnswer
                        if let sticky, sticky != .merge || collision.canMerge { answer = CollisionAnswer(sticky) }
                        else {
                            reporter.phase(.waiting, name: target.lastPathComponent); answer = await resolve(collision)
                            reporter.phase(job.kind == .copy ? .copying : .processing, name: source.lastPathComponent)
                        }
                        if answer.choice != .skip && answer.choice != .cancel {
                            guard originalAtPrompt.matches(source), targetAtPrompt.matches(target) else {
                                throw ExplorerError.message("A source or destination changed while its collision decision was open.")
                            }
                        }
                        if answer.applyToAll { sticky = answer.choice }
                        switch answer.choice {
                        case .cancel: control.cancel(); throw CancellationError()
                        case .skip: result.skippedSources.append(source); continue
                        case .keepBoth: target = FileNames.unique(target)
                        case .merge:
                            guard collision.canMerge, job.kind == .copy || job.kind == .move else { throw ExplorerError.message("Only distinct ordinary folders can be merged. Packages and symbolic links are not traversed.") }
                            merge = true
                        case .replace:
                            guard source.standardizedFileURL != target.standardizedFileURL else { throw ExplorerError.message("Choose Keep Both to duplicate an item in the same folder.") }
                            replace = true
                        }
                    }
                    if merge {
                        let merged = await mergeContents(job, source: source, target: target, receipt: result.receipt, control: control, reporter: reporter, resolve: resolve)
                        result.receipt = merged.receipt; result.errors += merged.errors; result.outputs += merged.outputs
                        result.completedSources += merged.completedSources; result.skippedSources += merged.skippedSources
                        succeeded = !merged.completedSources.isEmpty
                        if merged.cancelled || !merged.errors.isEmpty { result.cancelled = merged.cancelled; break }
                        continue
                    }
                    steps = try transfer(job, source: source, target: target, replace: replace, control: control, reporter: reporter); output = target
                }
                var receipt = result.receipt; receipt.steps.insert(contentsOf: steps, at: 0)
                try record(receipt); result.receipt = receipt
                if let output { result.outputs.append(output) }
                result.completedSources.append(source); succeeded = true
            } catch is CancellationError { result.cancelled = true; break }
            catch { result.errors.append("\(source.lastPathComponent): \(error.localizedDescription)"); if !rollbackJournal(into: &result) { break } }
        }
        finishJournal(&result)
        result.cancelled = result.cancelled || control.isCancelled; result.finalProgress = reporter.finish(cancelled: result.cancelled)
        return result
    }
}
