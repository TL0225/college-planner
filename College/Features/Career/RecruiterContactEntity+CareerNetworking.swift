// RecruiterContactEntity+CareerNetworking.swift
// Feature: Career
// Purpose: Career module — RecruiterContactEntity+CareerNetworking.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension RecruiterContact {
    /// Prefer the linked application's company; fall back to orphan-only `companyName`.
    var displayCompanyName: String? {
        if let linked = application?.company?.trimmingCharacters(in: .whitespacesAndNewlines), !linked.isEmpty {
            return linked
        }
        let orphan = companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return orphan.isEmpty ? nil : orphan
    }

    /// When linking a contact to a job, company line comes from the application; clear orphan storage.
    func applyNetworkingLinkWritePolicyForLinkedJob() {
        companyName = nil
    }
}
