// SettingsComponents.swift
// Shared Settings cards, rows, and grouped-content chrome.

import SwiftUI

// MARK: - SettingsCard (AppCard + grouped row container)

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    /// Inset applied inside the grouped box. Leave at `0` for full-bleed grouped rows
    /// (``SRow``, ``SToggleRow``, …) which supply their own padding; use a positive value for
    /// free-form content (plain text/buttons) so it doesn't touch the inner border.
    let contentPadding: CGFloat
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String,
        icon: String,
        iconColor: Color = DesignSystem.Colors.primary,
        contentPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        AppCard(title: title, icon: icon, iconColor: iconColor) {
            VStack(spacing: 0) {
                content
            }
            .padding(contentPadding)
            .background(rowGroupBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            }
        }
    }

    private var rowGroupBackground: some ShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(DesignSystem.Colors.surface)
        } else {
            AnyShapeStyle(Color.primary.opacity(0.03))
        }
    }
}

// MARK: - Row chrome

private enum SettingsRowMetrics {
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 12
}

private struct SettingsRowLabel: View {
    let label: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DesignSystem.Fonts.body(weight: .medium))
                .foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsRowChrome<Trailing: View>: View {
  let label: String
  var subtitle: String?
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(alignment: subtitle != nil ? .top : .center) {
      SettingsRowLabel(label: label, subtitle: subtitle)
      Spacer()
      trailing()
    }
    .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
    .padding(.vertical, SettingsRowMetrics.verticalPadding)
    .background(Color.primary.opacity(0.015))
  }
}

// MARK: - SLabeledRow (label + arbitrary trailing control)

struct SLabeledRow<Trailing: View>: View {
    let label: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle, trailing: trailing)
    }
}

// MARK: - SettingsInfoRow (full-width informational text)

struct SettingsInfoRow: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
        .padding(.vertical, SettingsRowMetrics.verticalPadding)
    }
}

// MARK: - SettingsStatusRow (icon + tinted message)

struct SettingsStatusRow: View {
    let message: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Label(message, systemImage: systemImage)
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsRowMetrics.horizontalPadding)
        .padding(.vertical, SettingsRowMetrics.verticalPadding)
    }
}

// MARK: - SRow

struct SRow: View {
    let label: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueSelectable: Bool = false

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            if let value {
                Group {
                    if valueSelectable {
                        Text(value)
                            .textSelection(.enabled)
                    } else {
                        Text(value)
                    }
                }
                .font(DesignSystem.Fonts.body())
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SToggleRow

struct SToggleRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

// MARK: - SActionRow

struct SActionRow: View {
    let label: String
    var subtitle: String? = nil
    let actionLabel: String
    var actionColor: Color = DesignSystem.Colors.primary
    var role: ButtonRole? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            Button(actionLabel, role: role, action: action)
                .font(DesignSystem.Fonts.caption1(weight: .semibold))
                .foregroundStyle(isDisabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(actionColor))
                .buttonStyle(.plain)
                .disabled(isDisabled)
        }
    }
}

// MARK: - SCustomRow

/// Shared grouped-row chrome with a caller-provided trailing control. Use when the
/// trailing accessory cannot be expressed by ``SMenuRow``/``SPickerRow`` (e.g. nested menus).
struct SCustomRow<Trailing: View>: View {
    let label: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle, trailing: trailing)
    }
}

// MARK: - SMenuRow

struct SMenuRow<SelectionType: Hashable>: View {
    let label: String
    var subtitle: String? = nil
    let currentDisplay: String
    let options: [SelectionType]
    let optionLabel: (SelectionType) -> String
    let onSelect: (SelectionType) -> Void

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(optionLabel(option)) { onSelect(option) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentDisplay)
                        .font(DesignSystem.Fonts.body())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DesignSystem.Fonts.caption2())
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.monochrome)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

// MARK: - STextFieldRow

struct STextFieldRow: View {
    let label: String
    var subtitle: String? = nil
    var placeholder: String = ""
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var fieldWidth: CGFloat = 240

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: fieldWidth)
                .font(DesignSystem.Fonts.body())
                .onSubmit { onSubmit?() }
        }
    }
}

// MARK: - SPickerRow

struct SPickerRow<Selection: Hashable>: View {
    let label: String
    var subtitle: String? = nil
    @Binding var selection: Selection
    let options: [Selection]
    let optionLabel: (Selection) -> String

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// MARK: - SStepperRow

struct SStepperRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var value: Int
    var range: ClosedRange<Int>
    var valueLabel: (Int) -> String = { "\($0)" }

    var body: some View {
        SettingsRowChrome(label: label, subtitle: subtitle) {
            Stepper(valueLabel(value), value: $value, in: range)
                .font(DesignSystem.Fonts.body())
        }
    }
}

// MARK: - SAdvancedDisclosure

struct SAdvancedDisclosure<Content: View>: View {
    let title: String
  var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                content()
            }
            .padding(.top, DesignSystem.Spacing.sm)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.body(weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
    }
}
