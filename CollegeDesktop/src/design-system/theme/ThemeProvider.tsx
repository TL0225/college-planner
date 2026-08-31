import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { ipc } from "@/lib/ipc";
import { syncWindowsTheme } from "@/lib/windowsIntegration";

export type Theme = "system" | "light" | "dark";
export type ResolvedTheme = "light" | "dark";

type ThemeContextValue = {
  theme: Theme;
  resolvedTheme: ResolvedTheme;
  isDark: boolean;
  setTheme: (theme: Theme) => Promise<void>;
};

const ThemeContext = createContext<ThemeContextValue>({
  theme: "system",
  resolvedTheme: "light",
  isDark: false,
  setTheme: async () => {},
});

function getSystemTheme(): ResolvedTheme {
  if (typeof window === "undefined" || !window.matchMedia) return "light";
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function applyThemeToDom(theme: Theme, resolved: ResolvedTheme) {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  root.dataset.theme = theme;
  if (resolved === "dark") {
    root.classList.add("dark");
  } else {
    root.classList.remove("dark");
  }
  root.style.colorScheme = resolved;
}

export function ThemeProvider({
  children,
  defaultTheme = "system",
}: {
  children: ReactNode;
  defaultTheme?: Theme;
}) {
  const [theme, setThemeState] = useState<Theme>(defaultTheme);
  const [systemTheme, setSystemTheme] = useState<ResolvedTheme>(getSystemTheme);

  const resolvedTheme: ResolvedTheme = useMemo(() => {
    if (theme === "system") return systemTheme;
    return theme;
  }, [theme, systemTheme]);

  // Apply to DOM whenever theme or resolved theme changes
  useEffect(() => {
    applyThemeToDom(theme, resolvedTheme);
    void syncWindowsTheme(resolvedTheme === "dark");
  }, [theme, resolvedTheme]);

  // Listen to OS system dark/light preference changes
  useEffect(() => {
    if (typeof window === "undefined" || !window.matchMedia) return;
    const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");

    const handleChange = (e: MediaQueryListEvent) => {
      setSystemTheme(e.matches ? "dark" : "light");
    };

    mediaQuery.addEventListener("change", handleChange);
    return () => mediaQuery.removeEventListener("change", handleChange);
  }, []);

  // Load saved preference from settings IPC
  useEffect(() => {
    void ipc.settingsGet().then((s) => {
      const saved = s.values["ui.theme"];
      if (saved === "light" || saved === "dark" || saved === "system") {
        setThemeState(saved);
      }
    });

    const onSettings = (ev: Event) => {
      const detail = (ev as CustomEvent<{ key: string; value: string }>).detail;
      if (detail?.key === "ui.theme") {
        const val = detail.value;
        if (val === "light" || val === "dark" || val === "system") {
          setThemeState(val);
        }
      }
    };

    window.addEventListener("college:settings", onSettings);
    return () => window.removeEventListener("college:settings", onSettings);
  }, []);

  const setTheme = useCallback(async (next: Theme) => {
    setThemeState(next);
    const resolved = next === "system" ? getSystemTheme() : next;
    applyThemeToDom(next, resolved);
    await ipc.settingsSet("ui.theme", next);
    window.dispatchEvent(
      new CustomEvent("college:settings", {
        detail: { key: "ui.theme", value: next },
      }),
    );
  }, []);

  const value = useMemo(
    (): ThemeContextValue => ({
      theme,
      resolvedTheme,
      isDark: resolvedTheme === "dark",
      setTheme,
    }),
    [theme, resolvedTheme, setTheme],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  return useContext(ThemeContext);
}
