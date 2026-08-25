"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Reveals a section when it scrolls into view, and holds the scene's animations
 * until then — otherwise every illustration on the page plays once, off-screen,
 * before anyone has scrolled to it.
 */
export function Reveal({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;

    // Anyone who has asked for less motion gets the finished state immediately.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setShown(true);
      return;
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true);
          observer.disconnect();
        }
      },
      { threshold: 0.25 },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={ref} className={`${className} reveal ${shown ? "shown" : ""}`}>
      {children}
    </div>
  );
}
