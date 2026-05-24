import type { TaskStatus } from "@/lib/task-model";
import { cn } from "@/lib/utils";

export function TaskStatusIcon({
  status,
  className,
}: {
  status: TaskStatus;
  className?: string;
}) {
  const base = "inline-block shrink-0 h-3.5 w-3.5";
  switch (status) {
    case "todo":
      return (
        <svg viewBox="0 0 14 14" className={cn(base, "text-muted-foreground", className)}>
          <circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" strokeWidth="1.5" />
        </svg>
      );
    case "in_progress":
      return (
        <svg viewBox="0 0 14 14" className={cn(base, "text-amber-500", className)}>
          <circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" strokeWidth="1.5" />
          <path d="M7 7 L7 2 A5 5 0 0 1 12 7 Z" fill="currentColor" />
        </svg>
      );
    case "in_review":
      return (
        <svg viewBox="0 0 14 14" className={cn(base, "text-violet-500", className)}>
          <circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" strokeWidth="1.5" />
          <path d="M7 7 L7 2 A5 5 0 0 1 11.33 9.5 Z" fill="currentColor" />
        </svg>
      );
    case "paused":
      return (
        <svg viewBox="0 0 14 14" className={cn(base, "text-orange-500", className)}>
          <circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" strokeWidth="1.5" />
          <path d="M5 3.8 V10.2 M9 3.8 V10.2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      );
    case "completed":
      return (
        <svg viewBox="0 0 14 14" className={cn(base, "text-emerald-500", className)}>
          <circle cx="7" cy="7" r="6" fill="currentColor" />
          <path d="M4.2 7.2 L6.2 9 L9.8 5.2" fill="none" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "canceled":
      return (
        <svg viewBox="0 0 14 14" className={cn(base, "text-muted-foreground", className)}>
          <circle cx="7" cy="7" r="6" fill="currentColor" />
          <path d="M4.5 4.5 L9.5 9.5 M9.5 4.5 L4.5 9.5" stroke="var(--background)" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      );
  }
}
