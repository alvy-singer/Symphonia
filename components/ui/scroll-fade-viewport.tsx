"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { scrollFadeEdges } from "@/lib/scroll-fade-model";
import { cn } from "@/lib/utils";

interface ScrollFadeViewportProps {
  children: ReactNode;
  className?: string;
  scrollClassName?: string;
}

export function ScrollFadeViewport({
  children,
  className,
  scrollClassName,
}: ScrollFadeViewportProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ left: false, right: false });

  const updateEdges = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const next = scrollFadeEdges(el);
    setEdges((current) =>
      current.left === next.left && current.right === next.right ? current : next,
    );
  }, []);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    updateEdges();
    el.addEventListener("scroll", updateEdges, { passive: true });
    window.addEventListener("resize", updateEdges);
    const observer =
      typeof ResizeObserver === "undefined" ? null : new ResizeObserver(updateEdges);
    observer?.observe(el);
    if (el.firstElementChild) observer?.observe(el.firstElementChild);
    return () => {
      el.removeEventListener("scroll", updateEdges);
      window.removeEventListener("resize", updateEdges);
      observer?.disconnect();
    };
  }, [updateEdges]);

  return (
    <div className={cn("relative overflow-hidden", className)}>
      <div ref={ref} className={scrollClassName}>
        {children}
      </div>
      <div
        aria-hidden="true"
        className={cn(
          "pointer-events-none absolute left-0 top-0 h-full w-8 bg-gradient-to-r from-background to-transparent opacity-0 transition-opacity",
          edges.left && "opacity-100",
        )}
      />
      <div
        aria-hidden="true"
        className={cn(
          "pointer-events-none absolute right-0 top-0 h-full w-8 bg-gradient-to-l from-background to-transparent opacity-0 transition-opacity",
          edges.right && "opacity-100",
        )}
      />
    </div>
  );
}
