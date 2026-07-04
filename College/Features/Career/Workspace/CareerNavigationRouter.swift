// CareerNavigationRouter.swift
// Feature: Career / Workspace
// Purpose: Typed navigation surface for cross-career actions.
// Data: Local career workspace state only.

import Foundation
import CollegeCareer
import Observation

@MainActor
@Observable
final class CareerNavigationRouter {
    var openAddApplication: (() -> Void)? {
        didSet {
            if pendingAddApplication, let openAddApplication {
                pendingAddApplication = false
                openAddApplication()
            }
        }
    }
    var openEditApplication: ((UUID) -> Void)? {
        didSet {
            if let id = pendingEditApplicationID, let openEditApplication {
                pendingEditApplicationID = nil
                openEditApplication(id)
            }
        }
    }
    var openBoardJob: ((UUID) -> Void)? {
        didSet {
            if let id = pendingBoardJobID, let openBoardJob {
                pendingBoardJobID = nil
                openBoardJob(id)
            }
        }
    }
    var openJobOpenings: (() -> Void)? {
        didSet {
            if pendingJobOpenings, let openJobOpenings {
                pendingJobOpenings = false
                openJobOpenings()
            }
        }
    }
    var filterApplicationsByStage: ((CareerApplicationStatus) -> Void)? {
        didSet {
            if let status = pendingFilterStage, let filterApplicationsByStage {
                pendingFilterStage = nil
                filterApplicationsByStage(status)
            }
        }
    }

    private var pendingAddApplication = false
    private var pendingEditApplicationID: UUID?
    private var pendingBoardJobID: UUID?
    private var pendingJobOpenings = false
    private var pendingFilterStage: CareerApplicationStatus?

    func addApplication() {
        if let openAddApplication {
            openAddApplication()
        } else {
            pendingAddApplication = true
        }
    }

    func editApplication(id: UUID) {
        if let openEditApplication {
            openEditApplication(id)
        } else {
            pendingEditApplicationID = id
        }
    }

    func boardJob(id: UUID) {
        if let openBoardJob {
            openBoardJob(id)
        } else {
            pendingBoardJobID = id
        }
    }

    func jobOpenings() {
        if let openJobOpenings {
            openJobOpenings()
        } else {
            pendingJobOpenings = true
        }
    }

    func filterByStage(_ status: CareerApplicationStatus) {
        if let filterApplicationsByStage {
            filterApplicationsByStage(status)
        } else {
            pendingFilterStage = status
        }
    }

    func clearHandlers() {
        openAddApplication = nil
        openEditApplication = nil
        openBoardJob = nil
        openJobOpenings = nil
        filterApplicationsByStage = nil
    }
}
