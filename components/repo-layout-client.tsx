"use client";

import { useState, type ReactNode } from "react";
import { CommandPaletteProvider } from "@/components/command-palette";
import { DraftHost, useDraftHost } from "@/components/draft-host";
import { AppSidebar } from "@/components/app-sidebar";
import { ClariseProvider } from "@/components/clarise";
import { useNewTask } from "@/components/new-task-dialog";

/**
 * Bridges the per-repo providers so they share the in-memory view-mode state
 * and the draft host. The CommandPalette can call `onNewDraft` to start a
 * draft, and `onSwitchView` to toggle Board/List on the Tasks view (the value
 * is stored in localStorage so the Tasks page can pick it up).
 */
export function RepoLayoutClient({
  children,
  repoKey,
}: {
  children: ReactNode;
  repoKey: string;
}) {
  const [askClarise, setAskClarise] = useState(0);

  return (
    <DraftHost>
      <CommandPaletteWithDraftHandle
        repoKey={repoKey}
        onAsk={() => setAskClarise((n) => n + 1)}
      >
        <ClariseProvider askPing={askClarise}>
          <div className="flex min-h-svh w-full bg-background text-foreground">
            <AppSidebar repoKey={repoKey} />
            <main className="flex min-w-0 flex-1 flex-col">
              <div className="flex-1 overflow-auto">{children}</div>
            </main>
          </div>
        </ClariseProvider>
      </CommandPaletteWithDraftHandle>
    </DraftHost>
  );
}

/**
 * The command palette needs `useDraftHost`, which only exists below the
 * <DraftHost> boundary, so we mount it here as an inner client wrapper.
 */
function CommandPaletteWithDraftHandle({
  children,
  repoKey,
  onAsk,
}: {
  children: ReactNode;
  repoKey: string;
  onAsk: () => void;
}) {
  const { startDraft } = useDraftHost();
  const newTask = useNewTask();

  return (
    <CommandPaletteProvider
      defaultRepoKey={repoKey}
      onAskClarise={onAsk}
      onSwitchView={(mode) => {
        try {
          window.localStorage.setItem(`symphonia.viewMode.${repoKey}`, mode);
          window.dispatchEvent(
            new CustomEvent("symphonia:viewMode", { detail: { repoKey, mode } }),
          );
        } catch {
          /* ignore */
        }
      }}
      onNewDraft={(repo, category) => startDraft(repo, category)}
      onNewTask={() => newTask.open()}
    >
      {children}
    </CommandPaletteProvider>
  );
}
