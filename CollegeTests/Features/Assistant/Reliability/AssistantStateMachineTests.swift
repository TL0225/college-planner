// AssistantStateMachineTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant State Machine")
struct AssistantStateMachineTests {

    @Test("View model starts idle")
    @MainActor
    func viewModelStartsIdle() {
        let vm = AIAssistantViewModel()
        #expect(!vm.isResponding)
    }

    @Test("Start generation sets responding")
    @MainActor
    func startGenerationSetsResponding() async {
        let vm = AIAssistantViewModel()
        vm.startGeneration {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.isResponding)
        vm.cancelActiveGeneration()
        #expect(!vm.isResponding)
    }

    @Test("Cancel active generation clears responding")
    @MainActor
    func cancelActiveGenerationClearsResponding() {
        let vm = AIAssistantViewModel()
        vm.startGeneration { }
        vm.cancelActiveGeneration()
        #expect(!vm.isResponding)
        #expect(vm.streamingMessageID == nil)
    }
}
