export type SettingsPage =
  | "you"
  | "appearance"
  | "connections"
  | "school-work"
  | "advanced"
  // Detail pages (deep links from Connections / Advanced)
  | "profile"
  | "academics"
  | "calendar"
  | "assistant"
  | "documents"
  | "finance"
  | "discovery"
  | "career"
  | "lms"
  | "shortcuts"
  | "app"
  | "privacy";

export const PAGE_TITLES: Record<SettingsPage, string> = {
  you: "You",
  appearance: "Look & feel",
  connections: "Connections",
  "school-work": "School & work",
  advanced: "Advanced",
  profile: "Profile",
  academics: "Academics",
  calendar: "Calendar",
  assistant: "Assistant",
  documents: "Documents",
  finance: "Finance",
  discovery: "Discovery",
  career: "Career",
  lms: "Course portal",
  shortcuts: "Shortcuts",
  app: "Developer",
  privacy: "Privacy & Security",
};

/** Detail pages reachable via deep links but not shown in the settings sidebar. */
export const SETTINGS_DETAIL_PAGES: SettingsPage[] = [
  "profile",
  "academics",
  "calendar",
  "assistant",
  "documents",
  "finance",
  "discovery",
  "career",
  "lms",
  "shortcuts",
  "app",
  "privacy",
];

export function isSettingsDetailPage(page: string): page is SettingsPage {
  return SETTINGS_DETAIL_PAGES.includes(page as SettingsPage);
}

/** Map legacy settings page IDs to new category landing pages. */
export function normalizeSettingsPage(page: string): SettingsPage {
  const legacyMap: Record<string, SettingsPage> = {
    app: "advanced",
    profile: "you",
    privacy: "you",
    academics: "school-work",
    discovery: "school-work",
    calendar: "connections",
    lms: "connections",
    finance: "connections",
    career: "connections",
    assistant: "advanced",
    documents: "advanced",
  };
  if (page in PAGE_TITLES) return page as SettingsPage;
  return legacyMap[page] ?? "appearance";
}
