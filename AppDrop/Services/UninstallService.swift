import AppKit
import Dispatch
import Foundation

enum UninstallError: LocalizedError {
    case protectedApp(String)
    case appleScriptFailed(String)
    case appleScriptTimedOut

    var errorDescription: String? {
        switch self {
        case .protectedApp(let reason):
            return reason
        case .appleScriptFailed(let message):
            return message
        case .appleScriptTimedOut:
            return L10n.text(
                "Finder 移到废纸篓超时。请检查自动化权限后重试。",
                "Finder timed out while moving the item to Trash. Check Automation permission and try again."
            )
        }
    }
}

struct UninstallService {
    func uninstall(_ plan: UninstallPlan, selectedResiduals: [ResidualItem]) async throws -> UninstallResult {
        if plan.app.isProtected {
            throw UninstallError.protectedApp(plan.app.protectionReason ?? L10n.text("此应用受保护，不能卸载。", "This app is protected and cannot be uninstalled."))
        }

        await terminateRunningAppIfNeeded(plan.app)

        var trashed: [URL] = []
        var failed: [(URL, String)] = []
        let urls = [plan.app.url] + selectedResiduals.map(\.url)

        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let result = await moveToTrash(url)
            switch result {
            case .success(let trashedURL):
                trashed.append(trashedURL)
            case .failure(let error):
                failed.append((url, error.localizedDescription))
            }
        }

        return UninstallResult(trashed: trashed, failed: failed)
    }

    private func moveToTrash(_ url: URL) async -> Result<URL, Error> {
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            if let resultingURL {
                return .success(resultingURL as URL)
            }
            return .success(url)
        } catch {
            let fileManagerError = error

            if let workspaceURL = await recycleWithWorkspace(url) {
                return .success(workspaceURL)
            }

            do {
                try moveWithFinderAppleScript(url)
                return .success(url)
            } catch {
                if error.localizedDescription.isEmpty {
                    return .failure(fileManagerError)
                }
                return .failure(error)
            }
        }
    }

    private func recycleWithWorkspace(_ url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { newURLs, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: newURLs[url] ?? newURLs.values.first)
            }
        }
    }

    private func moveWithFinderAppleScript(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            """
            on run argv
                set targetPath to POSIX file (item 1 of argv)
                tell application "Finder" to delete targetPath
            end run
            """,
            url.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()

        if finished.wait(timeout: .now() + 20) == .timedOut {
            process.terminate()
            throw UninstallError.appleScriptTimedOut
        }

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                throw UninstallError.appleScriptFailed(message)
            }
            throw UninstallError.appleScriptFailed(L10n.text("Finder 未能移到废纸篓。", "Finder could not move the item to Trash."))
        }
    }

    @MainActor
    private func terminateRunningAppIfNeeded(_ app: AppRecord) {
        guard app.bundleIdentifier != "unknown" else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)

        for process in running {
            process.terminate()
        }
    }
}
