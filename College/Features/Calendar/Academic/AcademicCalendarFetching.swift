// AcademicCalendarFetching.swift
// Feature: Calendar
// Purpose: Injectable fetch port for academic calendar pipeline tests.

import Foundation

protocol AcademicCalendarFetching: Sendable {
  func fetch(urlString: String, etag: String?) async throws -> AcademicCalendarFetchResult
  func headValidate(urlString: String) async -> Bool
}

protocol AcademicCalendarClock: Sendable {
  var now: Date { get }
}

struct LiveAcademicCalendarClock: AcademicCalendarClock {
  var now: Date { Date() }
}

struct LiveAcademicCalendarFetcher: AcademicCalendarFetching {
  func fetch(urlString: String, etag: String?) async throws -> AcademicCalendarFetchResult {
    try await AcademicCalendarFetcher.fetch(urlString: urlString, etag: etag, lastModified: nil)
  }

  func headValidate(urlString: String) async -> Bool {
    await AcademicCalendarFetcher.headValidate(urlString: urlString)
  }
}

enum AcademicCalendarFetchPort {
  nonisolated(unsafe) static var shared: any AcademicCalendarFetching = LiveAcademicCalendarFetcher()
}
