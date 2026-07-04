// ProductAnalyticsTests.swift
// M30-081 — opt-in product funnel events.

import Foundation
import Testing
@testable import College

@Suite("Product Analytics")
struct ProductAnalyticsTests {
    @Test("Opt-in flag round trip and suppressed tracking when off")
    func optInRoundTrip() {
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: ProductAnalytics.optInKey)
        defer {
            if let prior {
                defaults.set(prior, forKey: ProductAnalytics.optInKey)
            } else {
                defaults.removeObject(forKey: ProductAnalytics.optInKey)
            }
        }

        ProductAnalytics.setOptedIn(false)
        #expect(ProductAnalytics.isOptedIn == false)
        ProductAnalytics.track(.pageVisited, properties: ["page": "overview"])

        ProductAnalytics.setOptedIn(true)
        #expect(ProductAnalytics.isOptedIn == true)
        ProductAnalytics.track(.onboardingCompleted)

        ProductAnalytics.setOptedIn(false)
        #expect(ProductAnalytics.isOptedIn == false)
    }
}
