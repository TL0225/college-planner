import { motion } from "framer-motion";
import { cn } from "../cn";
import { withReduceMotion, standardSpring } from "../motion/springPresets";

/** Press/hover feedback matching DesignSystemInteractiveSurface */
export function InteractiveSurface({
  children,
  className,
  style,
  reduceMotion = false,
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
  return (
    <motion.button
      type={type}
      disabled={disabled}
      title={title}
      aria-label={ariaLabel}
      onClick={onClick}
      whileHover={reduceMotion || disabled ? undefined : { scale: 1.01 }}
      whileTap={reduceMotion || disabled ? undefined : { scale: 0.97 }}
      transition={withReduceMotion(reduceMotion, standardSpring)}
      className={cn("origin-center", className)}
      style={style}
    >
      {children}
    </motion.button>
  );
}
