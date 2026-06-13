import AppKit
import Foundation

enum UninstallError: LocalizedError {
    case protectedApp(String)
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .protectedApp(let reason):
            return reason
        case .appleScriptFailed(let message):
            return message
        }
    }
}

struct UninstallService {
    func uninstall(_ plan: UninstallPlan, selectedResiduals: [ResidualItem]) async throws -> UninstallResult {
        if plan.app.isProtected {
            throw UninstallError.protectedApp(plan.app.protectionReason ?? "此应用受保护，不能卸载。")
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

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                throw UninstallError.appleScriptFailed(message)
            }
            throw UninstallError.appleScriptFailed("Finder 未能移到废纸篓。")
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
