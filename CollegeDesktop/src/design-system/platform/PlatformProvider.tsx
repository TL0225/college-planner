import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { ipc } from "@/lib/ipc";

export type PlatformId = "macos" | "windows" | "linux";

type PlatformContextValue = {
  platform: PlatformId;
  isMac: boolean;
  modKey: string;
};

const PlatformContext = createContext<PlatformContextValue>({
  platform: "windows",
  isMac: false,
  modKey: "Ctrl",
});

function normalizePlatform(os: string): PlatformId {
  const lower = os.toLowerCase();
  if (lower.includes("mac") || lower.includes("darwin")) return "macos";
  if (lower.includes("linux")) return "linux";
  return "windows";
}

export function PlatformProvider({ children }: { children: ReactNode }) {
  const [platform, setPlatform] = useState<PlatformId>("windows");

  useEffect(() => {
    void ipc.getPlatformInfo().then((info) => {
      const id = normalizePlatform(info.os);
      setPlatform(id);
      document.documentElement.dataset.platform = id;
    });
  }, []);

  const value = useMemo(
    (): PlatformContextValue => ({
      platform,
      isMac: platform === "macos",
      modKey: platform === "macos" ? "⌘" : "Ctrl",
    }),
    [platform],
  );

  return <PlatformContext.Provider value={value}>{children}</PlatformContext.Provider>;
}

export function usePlatform() {
  return useContext(PlatformContext);
}
