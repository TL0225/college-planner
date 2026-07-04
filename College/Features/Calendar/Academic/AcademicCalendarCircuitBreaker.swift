// AcademicCalendarCircuitBreaker.swift
// Feature: Calendar
// Purpose: Per-config failure backoff for academic calendar imports.

import Foundation

enum AcademicCalendarCircuitBreaker {
  private static let storageKey = "calendar.academicCircuitBreaker.v1"
  private static let failureThreshold = 3
  private static let backoffInterval: TimeInterval = 24 * 60 * 60

  struct State: Codable, Sendable, Equatable {
    var configID: String
    var consecutiveFailures: Int
    var openedAt: Date?
  }

  static func shouldSkip(configID: String, now: Date = Date()) -> Bool {
    guard let state = loadStates().first(where: { $0.configID == configID }),
          let openedAt = state.openedAt else {
      return false
    }
    return now.timeIntervalSince(openedAt) < backoffInterval
  }

  static func recordSuccess(configID: String) {
    let states = loadStates().filter { $0.configID != configID }
    saveStates(states)
  }

  static func recordFailure(configID: String, now: Date = Date()) {
    var states = loadStates()
    var state = states.first(where: { $0.configID == configID })
      ?? State(configID: configID, consecutiveFailures: 0, openedAt: nil)
    state.consecutiveFailures += 1
    if state.consecutiveFailures >= failureThreshold {
      state.openedAt = now
    }
    states.removeAll { $0.configID == configID }
    states.append(state)
    saveStates(states)
  }

  static func needsAttention(configID: String, now: Date = Date()) -> Bool {
    shouldSkip(configID: configID, now: now)
  }

  private static func loadStates() -> [State] {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let decoded = try? JSONDecoder().decode([State].self, from: data) else {
      return []
    }
    return decoded
  }

  private static func saveStates(_ states: [State]) {
    guard let data = try? JSONEncoder().encode(states) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }
}
