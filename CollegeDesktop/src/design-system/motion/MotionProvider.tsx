import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

type MotionContextValue = {
  reduceMotion: boolean;
};

const MotionContext = createContext<MotionContextValue>({ reduceMotion: false });

export function MotionProvider({
  reduceMotion: userPref,
  children,
}: {
  reduceMotion: boolean;
  children: ReactNode;
}) {
  const [systemReduced, setSystemReduced] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setSystemReduced(mq.matches);
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);

  const value = useMemo(
    () => ({ reduceMotion: userPref || systemReduced }),
    [userPref, systemReduced],
  );

  return <MotionContext.Provider value={value}>{children}</MotionContext.Provider>;
}

export function useMotion() {
  return useContext(MotionContext);
}
