import {
  AppCard,
  fieldControlClass,
  usePlatform,
  useTheme,
} from "@/design-system";
import { StatusNote, insetPanelStyle } from "../shared";
import { useSettings } from "../useSettings";

/** Student-facing appearance and notification preferences. */
export function SettingsAppearancePage() {
  const { modKey } = usePlatform();
  const { theme: activeTheme, resolvedTheme, setTheme: updateTheme } = useTheme();
  const { reduceMotion, windowStrokeSubtle, density, dueNotifications, setPref } = useSettings();

  return (
    <AppCard title="Look & feel">
      <div className="space-y-2 text-body">
        <div
          className="flex items-center justify-between gap-3 px-2.5 py-2.5"
          style={insetPanelStyle}
        >
          <div>
            <div className="font-medium">Theme</div>
            <div className="text-caption text-[var(--color-text-light)]">
              {activeTheme === "system"
                ? `Following OS preference (currently ${resolvedTheme})`
                : activeTheme === "dark"
                  ? "Dark mode"
                  : "Light mode"}
            </div>
          </div>
          <select
            className={`${fieldControlClass} w-[130px] py-1`}
            value={activeTheme}
            onChange={(e) => {
              const val = e.target.value as "system" | "light" | "dark";
              void updateTheme(val);
            }}
          >
            <option value="system">Match system</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </div>
        <div
          className="flex items-center justify-between gap-3 px-2.5 py-2.5"
          style={insetPanelStyle}
        >
          <span>Reduce motion</span>
          <input
            type="checkbox"
            checked={reduceMotion}
            onChange={(e) => void setPref("ui.reduceMotion", e.target.checked ? "true" : "false")}
          />
        </div>
        <div
          className="flex items-center justify-between gap-3 px-2.5 py-2.5"
          style={insetPanelStyle}
        >
          <span>Window border</span>
          <select
            className={`${fieldControlClass} w-[120px] py-1`}
            value={windowStrokeSubtle ? "subtle" : "none"}
            onChange={(e) =>
              void setPref("ui.windowStroke", e.target.value === "subtle" ? "subtle" : "none")
            }
          >
            <option value="none">None</option>
            <option value="subtle">Subtle</option>
          </select>
        </div>
        <div
          className="flex items-center justify-between gap-3 px-2.5 py-2.5"
          style={insetPanelStyle}
        >
          <span>Display density</span>
          <select
            className={`${fieldControlClass} w-[120px] py-1`}
            value={density}
            onChange={(e) => {
              const value = e.target.value;
              if (
                value === "compact" ||
                value === "default" ||
                value === "comfortable" ||
                value === "auto"
              ) {
                void setPref("ui.density", value);
              }
            }}
          >
            <option value="auto">Auto</option>
            <option value="compact">Compact</option>
            <option value="default">Default</option>
            <option value="comfortable">Comfortable</option>
          </select>
        </div>
        <div
          className="flex items-center justify-between gap-3 px-2.5 py-2.5"
          style={insetPanelStyle}
        >
          <span>Due-item reminders</span>
          <input
            type="checkbox"
            checked={dueNotifications}
            onChange={(e) =>
              void setPref("notify.dueItems", e.target.checked ? "true" : "false")
            }
          />
        </div>
      </div>
      <StatusNote>
        Keyboard shortcuts: {modKey}+K search, {modKey}+J assistant.
      </StatusNote>
    </AppCard>
  );
}
