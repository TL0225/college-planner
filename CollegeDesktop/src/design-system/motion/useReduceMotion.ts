import { useMotion } from "./MotionProvider";

/** Explicit override wins; otherwise honor MotionProvider (user setting + system). */
export function useReduceMotion(override?: boolean): boolean {
  const { reduceMotion } = useMotion();
  if (override !== undefined) return override;
  return reduceMotion;
}
