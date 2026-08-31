import { motion } from "framer-motion";
import { useMotion } from "./MotionProvider";
import { standardSpring, withReduceMotion } from "./springPresets";

export function PageTransition({
  children,
  pageKey,
}: {
  children: React.ReactNode;
  pageKey: string;
}) {
  const { reduceMotion } = useMotion();
  return (
    <motion.div
      key={pageKey}
      className="h-full min-h-0"
      initial={reduceMotion ? false : { opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={withReduceMotion(reduceMotion, standardSpring)}
    >
      {children}
    </motion.div>
  );
}
