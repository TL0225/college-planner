import { motion } from "framer-motion";
import { useMotion } from "./MotionProvider";
import { standardSpring } from "./springPresets";

export function StaggeredList({
  children,
  className,
  style,
}: {
  children: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
}) {
  const { reduceMotion } = useMotion();
  if (reduceMotion) {
    return (
      <div className={className} style={style}>
        {children}
      </div>
    );
  }
  return (
    <motion.div
      className={className}
      style={style}
      initial="hidden"
      animate="visible"
      variants={{
        hidden: {},
        visible: { transition: { staggerChildren: 0.04 } },
      }}
    >
      {children}
    </motion.div>
  );
}

export function StaggeredItem({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  const { reduceMotion } = useMotion();
  if (reduceMotion) {
    return <div className={className}>{children}</div>;
  }
  return (
    <motion.div
      className={className}
      variants={{
        hidden: { opacity: 0, y: 10 },
        visible: { opacity: 1, y: 0 },
      }}
      transition={standardSpring}
    >
      {children}
    </motion.div>
  );
}
