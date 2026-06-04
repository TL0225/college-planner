import Foundation
import Observation

/// Generation token for cache/UI invalidation after batched calendar writes or sync.
@MainActor
@Observable
public final class CalendarChangePublisher {
    public private(set) var generationToken: Int = 0

    public init() {}

    public func bump() {
        generationToken &+= 1
    }
}
