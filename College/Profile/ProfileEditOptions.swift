import Foundation

struct ProfileEditOptions {
    var majors: [String] = []
    var minors: [String] = []
    var concentrations: [String] = []
    var certificates: [String] = []

    static let empty = ProfileEditOptions()
}
