import { useCallback, useState } from "react";
import { showToast } from "@/lib/toast";
import { formatIpcError } from "@/lib/ipc";

type OneClickOptions<T> = {
  action: () => Promise<T>;
  successMessage: string;
  onSuccess?: (result: T) => void;
};

/** One-click action with loading guard and toast feedback. */
export function useOneClickAction() {
  const [busy, setBusy] = useState(false);

  const run = useCallback(async <T>(opts: OneClickOptions<T>) => {
    if (busy) return;
    setBusy(true);
    try {
      const result = await opts.action();
      showToast(opts.successMessage, "success");
      opts.onSuccess?.(result);
      return result;
    } catch (e) {
      showToast(formatIpcError(e), "error");
      return undefined;
    } finally {
      setBusy(false);
    }
  }, [busy]);

  return { run, busy };
}
