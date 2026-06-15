import AppKit
import Darwin
import Dispatch
import Foundation

enum UninstallError: LocalizedError {
    case protectedApp(String)
    case appleScriptFailed(String)
    case appleScriptTimedOut
    case commandTimedOut(String)

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
        case .commandTimedOut(let command):
            return L10n.text(
                "\(command) 执行超时。",
                "\(command) timed out."
            )
        }
    }
}

struct UninstallService {
    func uninstall(_ plan: UninstallPlan, selectedResiduals: [ResidualItem]) async throws -> UninstallResult {
        if plan.app.isProtected {
            throw UninstallError.protectedApp(plan.app.protectionReason ?? L10n.text("此应用受保护，不能卸载。", "This app is protected and cannot be uninstalled."))
        }

        var trashed: [URL] = []
        var failed: [(URL, String)] = []
        var warnings: [(URL, String)] = []
        let urls = uniqueURLs([plan.app.url] + selectedResiduals.map(\.url))

        await terminateRunningApps(for: plan.app, selectedResiduals: selectedResiduals)

        for residual in selectedResiduals {
            if let warning = unloadLaunchdItemIfNeeded(residual.url) {
                warnings.append(warning)
            }
        }

        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let result = await moveToTrash(url)
            switch result {
            case .success(let trashedURL):
                trashed.append(trashedURL)
            case .failure(let error):
                failed.append((url, error.localizedDescription))
            }
        }

        return UninstallResult(trashed: trashed, failed: failed, warnings: warnings)
    }

    private func unloadLaunchdItemIfNeeded(_ url: URL) -> (URL, String)? {
        let path = url.standardizedFileURL.path
        guard url.pathExtension == "plist" else { return nil }

        let domain: String
        if path.contains("/LaunchAgents/") {
            domain = "gui/\(getuid())"
        } else if path.contains("/LaunchDaemons/") {
            domain = "system"
        } else {
            return nil
        }

        do {
            let result = try runCommand(
                executablePath: "/bin/launchctl",
                arguments: ["bootout", domain, path],
                timeout: 5,
                timeoutError: UninstallError.commandTimedOut("launchctl")
            )

            guard result.terminationStatus != 0 else { return nil }
            guard shouldReportLaunchctlFailure(result.stderr) else { return nil }

            let stderr = result.stderr ?? ""
            let message = stderr.isEmpty
                ? L10n.text("后台任务未能立即卸载。", "Background item could not be unloaded immediately.")
                : stderr
            return (url, message)
        } catch {
            return (url, error.localizedDescription)
        }
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
        let result = try runCommand(
            executablePath: "/usr/bin/osascript",
            arguments: [
            "-e",
            """
            on run argv
                set targetPath to POSIX file (item 1 of argv)
                tell application "Finder" to delete targetPath
            end run
            """,
            url.path
            ],
            timeout: 20,
            timeoutError: UninstallError.appleScriptTimedOut
        )

        if result.terminationStatus != 0 {
            let message = result.stderr
            if let message, !message.isEmpty {
                throw UninstallError.appleScriptFailed(message)
            }
            throw UninstallError.appleScriptFailed(L10n.text("Finder 未能移到废纸篓。", "Finder could not move the item to Trash."))
        }
    }

    @MainActor
    private func terminateRunningApps(for app: AppRecord, selectedResiduals: [ResidualItem]) async {
        let bundleIdentifiers = terminationBundleIdentifiers(for: app, selectedResiduals: selectedResiduals)
        let executableNames = terminationExecutableNames(for: app, selectedResiduals: selectedResiduals)

        let running = NSWorkspace.shared.runningApplications.filter { process in
            if let bundleIdentifier = process.bundleIdentifier,
               bundleIdentifiers.contains(bundleIdentifier) {
                return true
            }

            if let bundleURL = process.bundleURL?.standardizedFileURL,
               bundleURL == app.url.standardizedFileURL {
                return true
            }

            if let executableName = process.executableURL?.lastPathComponent,
               executableNames.contains(executableName) {
                return true
            }

            return false
        }

        for process in running {
            process.terminate()
        }

        guard !running.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 1_200_000_000)

        for process in running where !process.isTerminated {
            process.forceTerminate()
        }
    }

    private func terminationBundleIdentifiers(for app: AppRecord, selectedResiduals: [ResidualItem]) -> Set<String> {
        var identifiers = Set<String>()
        if isReverseDNS(app.bundleIdentifier) {
            identifiers.insert(app.bundleIdentifier)
        }

        for residual in selectedResiduals {
            let baseName = residual.url.deletingPathExtension().lastPathComponent
            if isReverseDNS(baseName), !baseName.hasPrefix("com.apple.") {
                identifiers.insert(baseName)
            }

            if residual.url.pathExtension == "plist" {
                for token in plistStrings(at: residual.url).flatMap(reverseDNSIdentifiers) where !token.hasPrefix("com.apple.") {
                    identifiers.insert(token)
                }
            }
        }

        return identifiers
    }

    private func terminationExecutableNames(for app: AppRecord, selectedResiduals: [ResidualItem]) -> Set<String> {
        var names = Set<String>()
        if let executableName = app.executableName, executableName.count >= 3 {
            names.insert(executableName)
        }

        for residual in selectedResiduals where residual.url.pathExtension == "plist" {
            for string in plistStrings(at: residual.url) {
                guard string.hasPrefix("/") else { continue }
                let lastComponent = URL(fileURLWithPath: string).lastPathComponent
                if lastComponent.count >= 3, !lastComponent.contains(".") {
                    names.insert(lastComponent)
                }
            }
        }

        return names
    }

    private func shouldReportLaunchctlFailure(_ stderr: String?) -> Bool {
        guard let stderr, !stderr.isEmpty else { return false }
        let ignoredFragments = [
            "No such process",
            "Could not find service",
            "Service is disabled",
            "not loaded"
        ]
        return !ignoredFragments.contains { stderr.localizedCaseInsensitiveContains($0) }
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            result.append(standardized)
        }

        return result
    }

    private func runCommand(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        timeoutError: Error
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw timeoutError
        }

        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = outputPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(terminationStatus: process.terminationStatus, stderr: stderr)
    }

    private func plistStrings(at url: URL) -> [String] {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else {
            return []
        }

        var strings: [String] = []
        collectStrings(from: plist, into: &strings)
        return strings
    }

    private func collectStrings(from value: Any, into strings: inout [String]) {
        if let string = value as? String {
            strings.append(string)
        } else if let array = value as? [Any] {
            for item in array {
                collectStrings(from: item, into: &strings)
            }
        } else if let dictionary = value as? [String: Any] {
            for (key, item) in dictionary {
                strings.append(key)
                collectStrings(from: item, into: &strings)
            }
        } else if let dictionary = value as? NSDictionary {
            for (key, item) in dictionary {
                if let key = key as? String {
                    strings.append(key)
                }
                collectStrings(from: item, into: &strings)
            }
        }
    }

    private func reverseDNSIdentifiers(in string: String) -> [String] {
        let pattern = #"[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.matches(in: string, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: string) else { return nil }
            let value = String(string[matchRange])
            return isReverseDNS(value) ? value : nil
        }
    }

    private func isReverseDNS(_ value: String) -> Bool {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return false }
        return value.contains { $0.isLetter }
    }

    private struct CommandResult {
        let terminationStatus: Int32
        let stderr: String?
    }
}
