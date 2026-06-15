import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var apps: [AppRecord] = []
    @Published private(set) var plan: UninstallPlan?
    @Published private(set) var isScanning = false
    @Published private(set) var isPlanning = false
    @Published private(set) var isUninstalling = false
    @Published private(set) var message: String?
    @Published private(set) var lastResult: UninstallResult?
    @Published private(set) var permissionStatus = PermissionStatus.allowed
    @Published var searchText = ""
    @Published var selectedAppID: AppRecord.ID? {
        didSet {
            if selectedAppID != oldValue {
                lastResult = nil
            }
        }
    }
    @Published var selectedResidualIDs = Set<ResidualItem.ID>()

    private let appScanner = ApplicationScanner()
    private let residualScanner = ResidualScanner()
    private let uninstallService = UninstallService()
    private let permissionService = PermissionService()
    private var planScanToken = UUID()
    private var permissionCheckedAt: Date?

    var filteredApps: [AppRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }

        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query) ||
            $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedApp: AppRecord? {
        apps.first { $0.id == selectedAppID }
    }

    func refresh(clearSelection: Bool = false) async {
        isScanning = true
        message = nil
        lastResult = nil
        plan = nil
        selectedResidualIDs.removeAll()
        updatePermissionStatus()

        let scanned = await appScanner.scanInstalledApps()
        apps = scanned
        if clearSelection {
            selectedAppID = nil
        } else if let selectedAppID, !scanned.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
        }
        isScanning = false
    }

    func openFullDiskAccessSettings() {
        permissionService.openFullDiskAccessSettings()
    }

    func updatePermissionStatus(force: Bool = false) {
        if !force,
           let permissionCheckedAt,
           Date().timeIntervalSince(permissionCheckedAt) < 10 {
            return
        }

        permissionStatus = permissionService.checkPrivacyAccess()
        permissionCheckedAt = Date()
    }

    func dismissLastResult() {
        lastResult = nil
    }

    func preparePlanForSelection() async {
        guard let app = selectedApp else {
            planScanToken = UUID()
            plan = nil
            selectedResidualIDs.removeAll()
            isPlanning = false
            return
        }

        let token = UUID()
        planScanToken = token
        isPlanning = true
        message = nil
        lastResult = nil
        plan = nil
        selectedResidualIDs.removeAll()
        let nextPlan = await residualScanner.makePlan(for: app)

        guard planScanToken == token, selectedAppID == app.id else {
            if planScanToken == token {
                isPlanning = false
            }
            return
        }
        plan = nextPlan
        selectedResidualIDs = Set(nextPlan.userResiduals.map(\.id))
        isPlanning = false
    }

    func uninstallSelection() async {
        guard let currentPlan = plan else { return }

        isUninstalling = true
        defer { isUninstalling = false }

        do {
            let selectedResiduals = currentPlan.selectedResiduals(selectedResidualIDs)
            let result = try await uninstallService.uninstall(currentPlan, selectedResiduals: selectedResiduals)

            await refresh(clearSelection: true)
            selectedAppID = nil
            plan = nil
            selectedResidualIDs.removeAll()
            lastResult = result
            message = nil
        } catch {
            lastResult = nil
            message = error.localizedDescription
        }
    }
}
