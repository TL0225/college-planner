import type { Transition } from "framer-motion";
import { motion as motionTokens } from "../tokens";

/** Matches DesignSystem.Motion.pillIndicatorSpring (response 0.28, damping 0.86) */
export const pillSpring: Transition = {
  type: "spring",
  stiffness: 380,
  damping: 32,
  mass: 0.85,
};

/** Matches DesignSystem.Motion.springOrEase (response 0.32, damping 0.86) */
export const standardSpring: Transition = {
  type: "spring",
  stiffness: 350,
  damping: 30,
  mass: 0.9,
};

/** Matches DesignSystem.Motion.sidebarSpring */
export const sidebarSpring: Transition = {
  type: "spring",
  stiffness: 420,
  damping: 34,
  mass: 0.8,
};

export const sheetTransition: Transition = {
  type: "tween",
  duration: motionTokens.durationSheet,
  ease: [0.4, 0, 0.2, 1],
};

export const quickEase: Transition = {
  type: "tween",
  duration: motionTokens.durationQuick,
  ease: "easeOut",
};

export function withReduceMotion(reduce: boolean, transition: Transition): Transition {
  if (!reduce) return transition;
  return {
    type: "tween",
    duration: motionTokens.durationReduceMotionFallback,
    ease: "easeOut",
  };
}
