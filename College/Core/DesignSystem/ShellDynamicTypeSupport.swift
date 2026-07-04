// ShellDynamicTypeSupport.swift
// Feature: Core / DesignSystem
// Purpose: Dynamic Type policy for preserved shell pages and sheets (M30-063).

import SwiftUI

extension View {
    /// Allows text to scale through accessibility sizes on preserved shell surfaces.
    func shellDynamicTypeReadable() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}
