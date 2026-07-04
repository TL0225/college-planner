// CollegeWebSearchDefaults.swift
// Feature: Assistant
// Purpose: Shared loopback host/port for the bundled DeGoog sidecar.

import Foundation

enum CollegeWebSearchDefaults {
  /// Loopback only — the sidecar must not bind on the LAN.
  static let host = "127.0.0.1"

  /// College-owned port (avoids DeGoog 4444 and common dev ports).
  static let port = 47_863

  static let portFallbackSpan = 3

  static var localBaseURLString: String {
    "http://\(host):\(port)"
  }

  static var localBaseURL: URL {
    URL(string: localBaseURLString)!
  }

  static func localBaseURL(port: Int) -> URL {
    URL(string: "http://\(host):\(port)")!
  }
}
