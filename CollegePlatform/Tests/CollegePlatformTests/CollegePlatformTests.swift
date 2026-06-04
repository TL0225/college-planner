import CollegePlatform
import Testing

@Test func integrationHealthStoreReportsFailure() {
    let store = IntegrationHealthStore()
    store.report(.google, .exportFailure("token expired"))
    #expect(store.snapshot(for: .google).isFailure)
}
