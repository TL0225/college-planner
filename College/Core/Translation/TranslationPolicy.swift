// TranslationPolicy.swift
// Feature: Core
// Purpose: Phase 12 v1 translation policy — machine-only on-device models.

@preconcurrency import Translation

enum TranslationPolicy {
    /// Phase 12 v1 uses traditional on-device models only (no Apple Intelligence high-fidelity path).
    static var preferredStrategy: TranslationSession.Strategy { .lowLatency }
}
