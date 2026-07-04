// BackgroundServiceManifest+Tier0.swift
// Feature: Core/Platform
// Purpose: Tier 0 process infrastructure (documented, not lifecycle-managed).

import Foundation

enum BackgroundServiceManifestTier0 {
    struct Entry: Sendable {
        let id: String
        let displayName: String
        let role: String
    }

    static let entries: [Entry] = [
        Entry(id: "mlx_task_queue", displayName: "MLX Task Queue", role: "Serial gate for MLX/Metal work"),
        Entry(id: "mlx_error_handler", displayName: "MLX Error Handler", role: "C layer error hook"),
        Entry(id: "launch_startup_budget", displayName: "Launch Startup Budget", role: "DB/file I/O lane caps"),
        Entry(id: "job_board_scrape_pacing", displayName: "Job Board Scrape Pacing", role: "Per-host crawl delay"),
        Entry(id: "job_board_robots_policy", displayName: "Job Board Robots Policy", role: "robots.txt enforcement"),
    ]
}
