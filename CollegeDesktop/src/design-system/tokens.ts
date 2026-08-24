/** Design tokens ported 1:1 from Packages/CollegeDesignSystem */

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 20,
  xl: 24,
  xxl: 32,
  section: 40,
} as const;

export const radius = {
  xs: 4,
  sm: 6,
  md: 10,
  lg: 14,
  xl: 20,
  sheet: 24,
  sidebarRow: 8,
} as const;

export const elevation = {
  floatingShadowRadius: 16,
  floatingShadowY: 6,
  floatingShadowOpacity: 0.18,
  pillShadow: "0 1px 4px rgba(0,0,0,0.06)",
} as const;

export const sheetMetrics = {
  widthCompact: 440,
  widthDefault: 520,
  widthWide: 620,
  minHeight: 420,
  heightDefault: 560,
  closeHitTarget: 28,
} as const;

export const inspectorMetrics = {
  widthDefault: 400,
  widthMin: 360,
  widthMax: 520,
} as const;

export const motion = {
  durationQuick: 0.15,
  durationStandard: 0.28,
  durationSheet: 0.28,
  durationInspector: 0.28,
  durationReduceMotionFallback: 0.12,
} as const;

export const colors = {
  primary: "#6366f1",
  secondary: "#a855f7",
  accent: "#ec4899",
  success: "#10b981",
  warning: "#f59e0b",
  error: "#ef4444",
  info: "#06b6d4",
  careerLaneInterested: "#64748b",
  careerLaneApplied: "#3b82f6",
  careerLaneInterviewing: "#8b5cf6",
  careerLaneOffer: "#f59e0b",
  careerLaneRejected: "#ef4444",
  careerLaneAccepted: "#10b981",
  careerPayGreen: "#16a34a",
} as const;

/** ShellSidebarLayout + SidebarMetrics */
export const shell = {
  sidebarWidth: 208,
  sidebarCollapsedWidth: 64,
  pillBarHeight: 36,
  chromeTitlebarHitAvoidance: 32,
  chromeInteractiveBandHeight: 44,
  get chromeHeaderTotalHeight() {
    return this.chromeTitlebarHitAvoidance + this.chromeInteractiveBandHeight;
  },
  titlebarLeadingInset: 78,
  sidebarContentHorizontalPadding: 8,
  sidebarRowMinHeight: 28,
} as const;

export type ModuleId =
  | "college"
  | "finance"
  | "calendar"
  | "career"
  | "documents"
  | "assistant"
  | "profile"
  | "settings";
