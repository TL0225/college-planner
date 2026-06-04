// CollegePersistence+ChangeTokens.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+ChangeTokens.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine

extension CollegePersistence {
    private static var calendarNotifyDebounceWork: DispatchWorkItem?

    func notifyCalendarDidChange() {
        DispatchQueue.main.async {
            Self.calendarNotifyDebounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.bumpCalendarChangeToken()
                self?.objectWillChange.send()
            }
            Self.calendarNotifyDebounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
    }

    func noteCareerStoreDidChange() {
        bumpCareerRevision()
    }

    func noteVaultStoreDidChange() {
        bumpVaultRevision()
    }
}