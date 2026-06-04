// ProfileEditOptions.swift
// Feature: Profile
// Purpose: Profile module — ProfileEditOptions.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ProfileEditOptions {
    var majors: [String] = []
    var minors: [String] = []
    var concentrations: [String] = []
    var certificates: [String] = []

    static let empty = ProfileEditOptions()
}
