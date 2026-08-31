import { motion } from "framer-motion";
import { cn } from "../cn";
import { withReduceMotion, standardSpring } from "../motion/springPresets";
import { useReduceMotion } from "../motion/useReduceMotion";

/** Press/hover feedback matching DesignSystemInteractiveSurface */
export function InteractiveSurface({
  children,
  className,
  style,
  reduceMotion,
  onClick,
  disabled,
  type = "button",
  title,
  "aria-label": ariaLabel,
}: {
  children: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
  reduceMotion?: boolean;
  onClick?: () => void;
  disabled?: boolean;
  type?: "button" | "submit" | "reset";
  title?: string;
  "aria-label"?: string;
}) {
  const motionOff = useReduceMotion(reduceMotion);
  return (
    <motion.button
      type={type}
      disabled={disabled}
      title={title}
      aria-label={ariaLabel}
      onClick={onClick}
      whileHover={motionOff || disabled ? undefined : { scale: 1.01 }}
      whileTap={motionOff || disabled ? undefined : { scale: 0.97 }}
      transition={withReduceMotion(motionOff, standardSpring)}
      className={cn("origin-center", className)}
      style={style}
    >
      {children}
    </motion.button>
  );
}
