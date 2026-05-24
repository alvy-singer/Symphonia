"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { ChevronRight, FolderGit2, Plus, Search } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import type { RepositorySummary } from "@/lib/repository-model";
import { cn } from "@/lib/utils";

export default function RepositoriesPage() {
  const [repositories, setRepositories] = useState<RepositorySummary[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetch("/api/repositories", { cache: "no-store" })
      .then(async (res) => {
        const payload = (await res.json()) as {
          repositories?: RepositorySummary[];
          error?: string;
        };
        if (!res.ok) throw new Error(payload.error ?? "Could not load repositories");
        return payload.repositories ?? [];
      })
      .then((next) => {
        if (!cancelled) {
          setRepositories(next);
          setError(null);
        }
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not load repositories");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return repositories;
    return repositories.filter((repo) =>
      `${repo.name} ${repo.key} ${repo.path}`.toLowerCase().includes(q),
    );
  }, [repositories, query]);

  return (
    <div className="min-h-svh bg-background text-foreground">
      <header className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b bg-background/95 px-4 py-2.5 backdrop-blur">
        <div className="flex items-center gap-2 text-sm">
          <span className="grid h-6 w-6 place-items-center rounded-md bg-foreground text-[11px] font-bold text-background">
            S
          </span>
          <span className="font-semibold">Symphonía</span>
          <span className="text-muted-foreground">/</span>
          <span className="text-muted-foreground">Repositories</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="relative hidden sm:block">
            <Search className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search repositories"
              className="w-56 rounded-md border bg-background py-1 pl-7 pr-2 text-[12px] focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
          <button
            onClick={() => setAddOpen(true)}
            className="inline-flex items-center gap-1.5 rounded-md bg-primary px-2.5 py-1 text-[12px] text-primary-foreground hover:opacity-90"
          >
            <Plus className="h-3.5 w-3.5" /> Add repository
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-5xl p-4 sm:p-6">
        <div className="mb-5 flex items-end justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Repositories</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Choose a repository to enter its workspace. Markdown files stay next to
              the code they describe.
            </p>
          </div>
          <span className="text-xs tabular-nums text-muted-foreground">
            {repositories.length} registered
          </span>
        </div>

        {error && (
          <div className="mb-4 rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-300">
            {error}
          </div>
        )}

        {loading ? (
          <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
            Loading repositories...
          </div>
        ) : filtered.length === 0 ? (
          <div className="rounded-lg border border-dashed p-8 text-center">
            <FolderGit2 className="mx-auto h-8 w-8 text-muted-foreground" />
            <h2 className="mt-3 text-sm font-medium">No repositories added</h2>
            <p className="mx-auto mt-1 max-w-sm text-sm text-muted-foreground">
              Add a local Git repository by absolute path to create or open its
              Symphonía workspace.
            </p>
            <button
              onClick={() => setAddOpen(true)}
              className="mt-4 inline-flex items-center gap-1.5 rounded-md bg-primary px-3 py-1.5 text-sm text-primary-foreground hover:opacity-90"
            >
              <Plus className="h-4 w-4" /> Add repository
            </button>
          </div>
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2">
            {filtered.map((repo) => (
              <li key={repo.key}>
                <RepositoryCard repository={repo} />
              </li>
            ))}
          </ul>
        )}
      </main>

      <AddRepositoryDialog
        open={addOpen}
        onOpenChange={setAddOpen}
        onAdded={(repo) => setRepositories((current) => upsertRepository(current, repo))}
      />
    </div>
  );
}

function RepositoryCard({ repository }: { repository: RepositorySummary }) {
  const workspace = repository.workspace;
  const folders = workspace?.initialized ? "Present" : "Missing";
  const workflow = workspace?.workflow.exists ? "Present" : "Missing";

  return (
    <Link
      href={`/r/${repository.key.toLowerCase()}/tasks`}
      className="group block rounded-lg border bg-card p-4 transition-colors hover:border-foreground/20"
    >
      <div className="flex items-center gap-3">
        <span
          className={cn(
            "grid h-9 w-9 place-items-center rounded-md bg-muted text-sm font-bold",
            colorForRepo(repository.key),
          )}
        >
          {repository.key[0]}
        </span>
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-sm font-semibold">{repository.name}</h3>
          <p className="truncate text-[11px] text-muted-foreground">
            {repository.key} / {repository.path}
          </p>
        </div>
        <ChevronRight className="h-4 w-4 text-muted-foreground transition-colors group-hover:text-foreground" />
      </div>

      <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
        <Stat label="Tasks" value={String(repository.taskCount ?? 0)} />
        <Stat label="Folders" value={folders} muted={!workspace?.initialized} />
        <Stat label="Workflow" value={workflow} muted={!workspace?.workflow.exists} />
      </dl>
    </Link>
  );
}

function Stat({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="rounded-md bg-muted/40 py-2">
      <dt className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</dt>
      <dd className={cn("text-sm font-semibold tabular-nums", muted && "text-amber-600")}>
        {value}
      </dd>
    </div>
  );
}

function AddRepositoryDialog({
  open,
  onOpenChange,
  onAdded,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAdded: (repo: RepositorySummary) => void;
}) {
  const [path, setPath] = useState("");
  const [key, setKey] = useState("");
  const [name, setName] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!path.trim()) return;
    setPending(true);
    setError(null);

    try {
      const res = await fetch("/api/repositories", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          path: path.trim(),
          key: key.trim() || undefined,
          name: name.trim() || undefined,
        }),
      });
      const payload = (await res.json()) as { repository?: RepositorySummary; error?: string };
      if (!res.ok || !payload.repository) {
        throw new Error(payload.error ?? "Could not add repository");
      }

      onAdded(payload.repository);
      onOpenChange(false);
      setPath("");
      setKey("");
      setName("");
      router.push(`/r/${payload.repository.key.toLowerCase()}/tasks`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not add repository");
    } finally {
      setPending(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <div>
          <DialogTitle className="text-base font-semibold">Add repository</DialogTitle>
          <DialogDescription className="mt-1 text-sm text-muted-foreground">
            Enter the absolute path to a local Git repository.
          </DialogDescription>
        </div>

        <form onSubmit={submit} className="space-y-3">
          <label className="block text-xs font-medium">
            Repository path
            <input
              autoFocus
              value={path}
              onChange={(event) => setPath(event.target.value)}
              placeholder="/Users/alvy/Projects/Symphonia"
              className="mt-1 w-full rounded-md border bg-background px-2 py-1.5 text-sm font-mono outline-none focus:ring-2 focus:ring-ring"
            />
          </label>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block text-xs font-medium">
              Key
              <input
                value={key}
                onChange={(event) => setKey(event.target.value)}
                placeholder="SYM"
                className="mt-1 w-full rounded-md border bg-background px-2 py-1.5 text-sm outline-none focus:ring-2 focus:ring-ring"
              />
            </label>
            <label className="block text-xs font-medium">
              Name
              <input
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="agora-creations/Symphonia"
                className="mt-1 w-full rounded-md border bg-background px-2 py-1.5 text-sm outline-none focus:ring-2 focus:ring-ring"
              />
            </label>
          </div>

          {error && (
            <p className="rounded-md border border-amber-500/30 bg-amber-500/10 px-2 py-1.5 text-xs text-amber-700 dark:text-amber-300">
              {error}
            </p>
          )}

          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => onOpenChange(false)}
              className="rounded-md border px-3 py-1.5 text-sm hover:bg-muted"
            >
              Cancel
            </button>
            <button
              disabled={!path.trim() || pending}
              className="rounded-md bg-primary px-3 py-1.5 text-sm text-primary-foreground hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {pending ? "Adding..." : "Add repository"}
            </button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function upsertRepository(
  repositories: RepositorySummary[],
  repository: RepositorySummary,
): RepositorySummary[] {
  return [
    repository,
    ...repositories.filter((item) => item.key !== repository.key),
  ].sort((a, b) => a.key.localeCompare(b.key));
}

function colorForRepo(key: string): string {
  const colors = ["text-rose-500", "text-sky-500", "text-violet-500", "text-emerald-500"];
  return colors[key.charCodeAt(0) % colors.length] ?? colors[0];
}
