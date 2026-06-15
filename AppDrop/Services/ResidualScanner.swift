import Foundation

struct ResidualScanner {
    private let fileManager = FileManager.default

    func makePlan(for app: AppRecord) async -> UninstallPlan {
        let measuredApp = app.size > 0 ? app : app.withSize(allocatedSize(of: app.url))
        let userItems = uniqueExistingItems(from: userCandidates(for: app), scope: .user)
        let systemItems = uniqueExistingItems(from: systemReviewCandidates(for: app), scope: .systemReview)
        let sensitive = userItems.contains { isSensitivePath($0.path) }
        return UninstallPlan(app: measuredApp, userResiduals: userItems, systemReviewItems: systemItems, containsSensitivePaths: sensitive)
    }

    private func userCandidates(for app: AppRecord) -> [Candidate] {
        let home = fileManager.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        let names = nameVariants(for: app.displayName)
        let bundleID = isReverseDNS(app.bundleIdentifier) ? app.bundleIdentifier : nil
        let relatedBundleIDs = relatedBundleIdentifiers(for: app)
        var candidates: [Candidate] = []

        for name in names where name.count >= 2 {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(name)"), "Application Support"),
                Candidate(library.appendingPathComponent("Caches/\(name)"), L10n.text("缓存", "Caches")),
                Candidate(library.appendingPathComponent("Logs/\(name)"), L10n.text("日志", "Logs")),
                Candidate(library.appendingPathComponent("Preferences/\(name)"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Preferences/\(name).plist"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Saved Application State/\(name).savedState"), L10n.text("窗口状态", "Saved State")),
                Candidate(library.appendingPathComponent("Services/\(name).workflow"), L10n.text("服务", "Services")),
                Candidate(library.appendingPathComponent("QuickLook/\(name).qlgenerator"), "Quick Look"),
                Candidate(library.appendingPathComponent("Internet Plug-Ins/\(name).plugin"), L10n.text("插件", "Plug-ins")),
                Candidate(library.appendingPathComponent("PreferencePanes/\(name).prefPane"), L10n.text("偏好面板", "Preference Pane")),
                Candidate(library.appendingPathComponent("Input Methods/\(name).app"), L10n.text("输入法", "Input Method")),
                Candidate(library.appendingPathComponent("Screen Savers/\(name).saver"), L10n.text("屏幕保护程序", "Screen Saver")),
                Candidate(library.appendingPathComponent("Frameworks/\(name).framework"), L10n.text("框架", "Framework")),
                Candidate(home.appendingPathComponent(".config/\(name)"), L10n.text("配置", "Config")),
                Candidate(home.appendingPathComponent(".cache/\(name)"), L10n.text("缓存", "Caches")),
                Candidate(home.appendingPathComponent(".local/share/\(name)"), L10n.text("应用数据", "Application Data")),
                Candidate(home.appendingPathComponent(".\(name)"), L10n.text("隐藏配置", "Hidden Config"))
            ])
        }

        if let bundleID {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(bundleID)"), "Application Support"),
                Candidate(library.appendingPathComponent("Caches/\(bundleID)"), L10n.text("缓存", "Caches")),
                Candidate(library.appendingPathComponent("Logs/\(bundleID)"), L10n.text("日志", "Logs")),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID).plist"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID)"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Saved Application State/\(bundleID).savedState"), L10n.text("窗口状态", "Saved State")),
                Candidate(library.appendingPathComponent("Containers/\(bundleID)"), L10n.text("容器", "Container")),
                Candidate(library.appendingPathComponent("WebKit/\(bundleID)"), "WebKit"),
                Candidate(library.appendingPathComponent("HTTPStorages/\(bundleID)"), "HTTP Storage"),
                Candidate(library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"), "Cookies"),
                Candidate(library.appendingPathComponent("Cookies/\(bundleID).binarycookies"), "Cookies"),
                Candidate(library.appendingPathComponent("Application Scripts/\(bundleID)"), L10n.text("脚本", "Scripts")),
                Candidate(library.appendingPathComponent("Autosave Information/\(bundleID)"), L10n.text("自动保存", "Autosave")),
                Candidate(library.appendingPathComponent("SyncedPreferences/\(bundleID).plist"), L10n.text("同步偏好", "Synced Preferences")),
                Candidate(library.appendingPathComponent("Caches/com.apple.nsurlsessiond/Downloads/\(bundleID)"), L10n.text("下载缓存", "Download Cache"))
            ])

            candidates.append(contentsOf: byHostPreferences(bundleID: bundleID, library: library))
            candidates.append(contentsOf: launchPlists(
                root: library.appendingPathComponent("LaunchAgents"),
                app: app,
                relatedBundleIDs: relatedBundleIDs,
                category: "LaunchAgent"
            ))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Group Containers"), bundleID: bundleID, category: "Group Container"))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Containers"), bundleID: bundleID, category: L10n.text("容器扩展", "Container Extension")))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Application Scripts"), bundleID: bundleID, category: L10n.text("脚本扩展", "Script Extension")))
            candidates.append(contentsOf: sharedFileLists(bundleID: bundleID, library: library))
        }

        candidates.append(contentsOf: diagnosticReports(for: app, directory: library.appendingPathComponent("Logs/DiagnosticReports"), scopeTitle: L10n.text("诊断报告", "Diagnostic Report")))
        return candidates
    }

    private func systemReviewCandidates(for app: AppRecord) -> [Candidate] {
        guard isReverseDNS(app.bundleIdentifier) || app.displayName.count >= 2 else { return [] }
        let library = URL(fileURLWithPath: "/Library")
        let names = nameVariants(for: app.displayName)
        let relatedBundleIDs = relatedBundleIdentifiers(for: app)
        var candidates: [Candidate] = []

        for name in names where name.count >= 2 {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(name)"), L10n.text("系统 Application Support", "System Application Support"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Caches/\(name)"), L10n.text("系统缓存", "System Caches"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Logs/\(name)"), L10n.text("系统日志", "System Logs"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Preferences/\(name).plist"), L10n.text("系统偏好", "System Preferences"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Frameworks/\(name).framework"), L10n.text("系统框架", "System Framework"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Internet Plug-Ins/\(name).plugin"), L10n.text("系统插件", "System Plug-in"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Input Methods/\(name).app"), L10n.text("系统输入法", "System Input Method"), riskLevel: .high),
                Candidate(library.appendingPathComponent("QuickLook/\(name).qlgenerator"), L10n.text("系统 Quick Look", "System Quick Look"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("PreferencePanes/\(name).prefPane"), L10n.text("系统偏好面板", "System Preference Pane"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Screen Savers/\(name).saver"), L10n.text("系统屏保", "System Screen Saver"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("StartupItems/\(name)"), L10n.text("启动项", "Startup Item"), riskLevel: .high)
            ])
        }

        if isReverseDNS(app.bundleIdentifier) {
            let bundleID = app.bundleIdentifier
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(bundleID)"), L10n.text("系统 Application Support", "System Application Support"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID).plist"), L10n.text("系统偏好", "System Preferences"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Receipts/\(bundleID).bom"), L10n.text("安装收据", "Install Receipt"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Receipts/\(bundleID).plist"), L10n.text("安装收据", "Install Receipt"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Caches/\(bundleID)"), L10n.text("系统缓存", "System Caches"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Logs/\(bundleID)"), L10n.text("系统日志", "System Logs"), riskLevel: .requiresAdmin)
            ])

            for relatedID in relatedBundleIDs {
                candidates.append(contentsOf: [
                    Candidate(library.appendingPathComponent("PrivilegedHelperTools/\(relatedID)"), L10n.text("特权后台工具", "Privileged Helper Tool"), riskLevel: .high),
                    Candidate(library.appendingPathComponent("StartupItems/\(relatedID)"), L10n.text("启动项", "Startup Item"), riskLevel: .high)
                ])
            }

            candidates.append(contentsOf: launchPlists(
                root: library.appendingPathComponent("LaunchAgents"),
                app: app,
                relatedBundleIDs: relatedBundleIDs,
                category: L10n.text("系统 LaunchAgent", "System LaunchAgent"),
                riskLevel: .requiresAdmin
            ))
            candidates.append(contentsOf: launchPlists(
                root: library.appendingPathComponent("LaunchDaemons"),
                app: app,
                relatedBundleIDs: relatedBundleIDs,
                category: L10n.text("系统 LaunchDaemon", "System LaunchDaemon"),
                riskLevel: .high
            ))
            candidates.append(contentsOf: boundaryMatchedChildren(
                root: library.appendingPathComponent("PrivilegedHelperTools"),
                bundleIDs: relatedBundleIDs,
                category: L10n.text("特权后台工具", "Privileged Helper Tool"),
                riskLevel: .high
            ))
        }

        candidates.append(contentsOf: diagnosticReports(
            for: app,
            directory: library.appendingPathComponent("Logs/DiagnosticReports"),
            scopeTitle: L10n.text("系统诊断报告", "System Diagnostic Report"),
            riskLevel: .requiresAdmin
        ))
        return candidates
    }

    private func uniqueExistingItems(from candidates: [Candidate], scope: ResidualItem.Scope) -> [ResidualItem] {
        var seen = Set<String>()
        var items: [ResidualItem] = []

        for candidate in candidates {
            let url = candidate.url.standardizedFileURL
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            guard fileManager.fileExists(atPath: path) else { continue }

            if scope == .user {
                guard isSafeUserCandidate(url) else { continue }
                guard !belongsToIndependentCLI(url) else { continue }
            }

            items.append(ResidualItem(
                id: path,
                url: url,
                title: url.lastPathComponent,
                category: candidate.category,
                size: allocatedSize(of: url),
                scope: scope,
                riskLevel: candidate.riskLevel
            ))
        }

        return items.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private func byHostPreferences(bundleID: String, library: URL) -> [Candidate] {
        let root = library.appendingPathComponent("Preferences/ByHost")
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter { $0.lastPathComponent.hasPrefix(bundleID + ".") && $0.pathExtension == "plist" }
            .map { Candidate($0, L10n.text("ByHost 偏好", "ByHost Preferences")) }
    }

    private func launchPlists(
        root: URL,
        app: AppRecord,
        relatedBundleIDs: Set<String>,
        category: String,
        riskLevel: ResidualRiskLevel = .normal
    ) -> [Candidate] {
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter {
                $0.pathExtension == "plist" && launchPlistLooksRelated($0, app: app, relatedBundleIDs: relatedBundleIDs)
            }
            .map { Candidate($0, category, riskLevel: riskLevel) }
    }

    private func boundaryMatchedChildren(root: URL, bundleID: String, category: String) -> [Candidate] {
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter { nameHasBundleBoundary($0.lastPathComponent, bundleID: bundleID) }
            .map { Candidate($0, category) }
    }

    private func boundaryMatchedChildren(
        root: URL,
        bundleIDs: Set<String>,
        category: String,
        riskLevel: ResidualRiskLevel
    ) -> [Candidate] {
        guard !bundleIDs.isEmpty else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter { child in
                bundleIDs.contains { nameHasBundleBoundary(child.lastPathComponent, bundleID: $0) }
            }
            .map { Candidate($0, category, riskLevel: riskLevel) }
    }

    private func sharedFileLists(bundleID: String, library: URL) -> [Candidate] {
        let root = library.appendingPathComponent("Application Support/com.apple.sharedfilelist")
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var result: [Candidate] = []

        for case let url as URL in enumerator {
            if url.lastPathComponent == "\(bundleID).sfl4" {
                result.append(Candidate(url, L10n.text("最近项目", "Recent Items")))
            }
        }

        return result
    }

    private func launchPlistLooksRelated(_ url: URL, app: AppRecord, relatedBundleIDs: Set<String>) -> Bool {
        let label = url.deletingPathExtension().lastPathComponent
        if relatedBundleIDs.contains(where: { nameHasBundleBoundary(label, bundleID: $0) }) {
            return true
        }

        let strings = plistStrings(at: url)
        guard !strings.isEmpty else { return false }

        let appPath = app.url.standardizedFileURL.path
        if strings.contains(where: { $0 == appPath || $0.hasPrefix(appPath + "/") }) {
            return true
        }

        if relatedBundleIDs.contains(where: { bundleID in
            let lowercasedBundleID = bundleID.lowercased()
            return strings.contains { string in
                let lowercasedString = string.lowercased()
                return lowercasedString == lowercasedBundleID || lowercasedString.contains(lowercasedBundleID)
            }
        }) {
            return true
        }

        let appBundleNames = nameVariants(for: app.displayName)
            .filter { $0.count >= 3 }
            .map { "\($0).app" }
        return strings.contains { string in
            appBundleNames.contains { appName in
                string == appName || string.contains("/\(appName)/") || string.hasSuffix("/\(appName)")
            }
        }
    }

    private func relatedBundleIdentifiers(for app: AppRecord) -> Set<String> {
        var identifiers = Set<String>()
        if isReverseDNS(app.bundleIdentifier) {
            identifiers.insert(app.bundleIdentifier)
        }

        for infoURL in appInfoPlistURLs(for: app.url) {
            guard let info = plistDictionary(at: infoURL) else { continue }
            addRelatedIdentifiers(from: info, to: &identifiers)
        }

        guard fileManager.fileExists(atPath: app.url.path) else { return identifiers }
        guard let enumerator = fileManager.enumerator(
            at: app.url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return identifiers
        }

        for case let url as URL in enumerator where shouldReadRelatedBundleInfoPlist(url, appURL: app.url) {
            guard let info = plistDictionary(at: url) else { continue }
            addRelatedIdentifiers(from: info, to: &identifiers)
        }

        return identifiers
    }

    private func appInfoPlistURLs(for appURL: URL) -> [URL] {
        [
            appURL.appendingPathComponent("Contents/Info.plist"),
            appURL.appendingPathComponent("Info.plist")
        ]
    }

    private func shouldReadRelatedBundleInfoPlist(_ url: URL, appURL: URL) -> Bool {
        guard url.lastPathComponent == "Info.plist" else { return false }

        let standardizedURL = url.standardizedFileURL
        if appInfoPlistURLs(for: appURL.standardizedFileURL).contains(standardizedURL) {
            return true
        }

        let bundleURL = standardizedURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundleExtensions = ["app", "xpc", "appex", "plugin"]
        return bundleExtensions.contains(bundleURL.pathExtension)
    }

    private func addRelatedIdentifiers(from info: [String: Any], to identifiers: inout Set<String>) {
        if let bundleID = info["CFBundleIdentifier"] as? String, isReverseDNS(bundleID) {
            identifiers.insert(bundleID)
        }

        if let privilegedExecutables = info["SMPrivilegedExecutables"] as? [String: String] {
            for (identifier, requirement) in privilegedExecutables {
                if isReverseDNS(identifier) {
                    identifiers.insert(identifier)
                }
                for token in reverseDNSIdentifiers(in: requirement) {
                    identifiers.insert(token)
                }
            }
        }

        if let loginItems = info["SMLoginItemIdentifiers"] as? [String] {
            for identifier in loginItems where isReverseDNS(identifier) {
                identifiers.insert(identifier)
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

    private func plistDictionary(at url: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        return dictionary
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

    private func diagnosticReports(
        for app: AppRecord,
        directory: URL,
        scopeTitle: String,
        riskLevel: ResidualRiskLevel = .normal
    ) -> [Candidate] {
        guard let executable = app.executableName, executable.count >= 3 else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }

        return children.filter { url in
            let name = url.lastPathComponent
            let hasPrefix = name.hasPrefix(executable + ".") || name.hasPrefix(executable + "_") || name.hasPrefix(executable + "-")
            let isDiagnostic = ["ips", "crash", "spin", "diag"].contains(url.pathExtension)
            return hasPrefix && isDiagnostic
        }
        .map { Candidate($0, scopeTitle, riskLevel: riskLevel) }
    }

    private func nameVariants(for appName: String) -> [String] {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var names: [String] = [
            trimmed,
            trimmed.replacingOccurrences(of: " ", with: ""),
            trimmed.replacingOccurrences(of: " ", with: "_"),
            trimmed.replacingOccurrences(of: " ", with: "-"),
            trimmed.lowercased(),
            trimmed.replacingOccurrences(of: " ", with: "").lowercased(),
            trimmed.replacingOccurrences(of: " ", with: "_").lowercased(),
            trimmed.replacingOccurrences(of: " ", with: "-").lowercased()
        ]

        let suffixes = [" Nightly", " Beta", " Alpha", " Dev", " Canary", " Preview", " Insider", " Developer Edition", " Technology Preview"]
        for suffix in suffixes where trimmed.hasSuffix(suffix) {
            let base = String(trimmed.dropLast(suffix.count))
            if base.count > 2 {
                names.append(base)
                names.append(base.lowercased())
            }
        }

        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private func isReverseDNS(_ value: String) -> Bool {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return false }
        return value.contains { $0.isLetter }
    }

    private func nameHasBundleBoundary(_ name: String, bundleID: String) -> Bool {
        let normalizedName = name.lowercased()
        let normalizedBundleID = bundleID.lowercased()
        guard normalizedName.contains(normalizedBundleID) else { return false }
        if normalizedName == normalizedBundleID { return true }
        return normalizedName.hasPrefix(normalizedBundleID + ".") ||
            normalizedName.hasPrefix(normalizedBundleID + "-") ||
            normalizedName.hasSuffix("." + normalizedBundleID)
    }

    private func isSafeUserCandidate(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let allowedPrefixes = [
            "\(home)/Library/",
            "\(home)/.config/",
            "\(home)/.cache/",
            "\(home)/.local/share/",
            "\(home)/."
        ]

        guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else { return false }

        let forbiddenExact = [
            "\(home)", "\(home)/Library", "\(home)/Library/Application Support",
            "\(home)/Library/Caches", "\(home)/Library/Logs", "\(home)/Library/Preferences",
            "\(home)/Library/Containers", "\(home)/Library/Group Containers",
            "\(home)/.config", "\(home)/.cache", "\(home)/.local/share"
        ]

        guard !forbiddenExact.contains(path) else { return false }

        let protectedFragments = [
            "com.apple.Settings", "com.apple.SystemSettings", "com.apple.controlcenter",
            "com.apple.finder", "com.apple.dock", "Keychains", "Mobile Documents",
            "Library/Mail", "Library/Accounts", "Library/Calendars", "Library/Contacts"
        ]

        return !protectedFragments.contains(where: { path.contains($0) })
    }

    private func belongsToIndependentCLI(_ url: URL) -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let base = url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let cliNames = ["claude", "opencode", "codex", "gemini"]
        let protectedParents = [home, "\(home)/.config", "\(home)/.local/share", "\(home)/.cache"]
        return cliNames.contains(base) && protectedParents.contains(parent)
    }

    private func isSensitivePath(_ path: String) -> Bool {
        let fragments = [
            "/.ssh/", "/.gnupg/", "/Documents/", "/Desktop/", "/Downloads/",
            "/Pictures/", "/Movies/", "/Music/", "/Cookies/", "/Accounts/",
            "/.aws/", "/.kube/", "/credentials/", "/secrets/", "/User Data/"
        ]
        return fragments.contains(where: { path.localizedCaseInsensitiveContains($0) })
    }

    private func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

        if let values = try? url.resourceValues(forKeys: keys),
           let size = values.fileAllocatedSize ?? values.totalFileAllocatedSize {
            total += Int64(size)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return total
        }

        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            if values.isRegularFile == true {
                total += Int64(values.fileAllocatedSize ?? values.totalFileAllocatedSize ?? 0)
            }
        }

        return total
    }

    private struct Candidate {
        let url: URL
        let category: String
        let riskLevel: ResidualRiskLevel

        init(_ url: URL, _ category: String, riskLevel: ResidualRiskLevel = .normal) {
            self.url = url
            self.category = category
            self.riskLevel = riskLevel
        }
    }
}
