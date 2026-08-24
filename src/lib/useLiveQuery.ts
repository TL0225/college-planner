import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatIpcError } from "./ipc";
import { onDbChange } from "./events";

/** Re-run `load` on mount and whenever matching db:change events fire. */
export function useLiveQuery(load: () => Promise<void>, domains?: string[]) {
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const loadRef = useRef(load);
  loadRef.current = load;
  const domainKey = useMemo(() => (domains ?? []).join("|"), [domains]);

  const refresh = useCallback(async () => {
    try {
      setLoading(true);
      await loadRef.current();
      setError(null);
    } catch (e) {
      setError(formatIpcError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    const allowed = domainKey ? domainKey.split("|") : [];
    let unlisten: (() => void) | undefined;
    void onDbChange((payload) => {
      if (allowed.length === 0 || allowed.includes(payload.domain)) {
        void refresh();
      }
    }).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, [domainKey, refresh]);

  return { refresh, error, loading };
}
