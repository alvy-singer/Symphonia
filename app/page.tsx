import Link from "next/link";
import { Plus, Search, ChevronRight, Github } from "lucide-react";
import { repositories, projects } from "@/data/mock";
import { cn } from "@/lib/utils";

export default function RepositoriesPage() {
  const enriched = repositories.map((r) => {
    const repoProjects = projects.filter((p) => p.repo === r.key);
    const active = repoProjects.filter((p) => p.status === "in-progress").length;
    return { ...r, projects: repoProjects, active };
  });

  return (
    <div className="min-h-svh bg-background text-foreground">
      <header className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b bg-background/95 backdrop-blur px-4 py-2.5">
        <div className="flex items-center gap-2 text-sm">
          <span className="grid h-6 w-6 place-items-center rounded-md bg-foreground text-background text-[11px] font-bold">
            S
          </span>
          <span className="font-semibold">Symphonia</span>
          <span className="text-muted-foreground">/</span>
          <span className="text-muted-foreground">Repositories</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="relative hidden sm:block">
            <Search className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
            <input
              placeholder="Search repositories"
              className="rounded-md border bg-background pl-7 pr-2 py-1 text-[12px] w-56 focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
          <button className="inline-flex items-center gap-1.5 rounded-md bg-primary text-primary-foreground px-2.5 py-1 text-[12px] hover:opacity-90">
            <Plus className="h-3.5 w-3.5" /> Add repository
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-5xl p-4 sm:p-6">
        <div className="mb-5 flex items-end justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Repositories</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Choose a repository to enter its workspace — every brief, run and review
              lives next to the code it ships against.
            </p>
          </div>
          <span className="text-xs text-muted-foreground tabular-nums">
            {repositories.length} connected
          </span>
        </div>

        <ul className="grid gap-3 sm:grid-cols-2">
          {enriched.map((r) => (
            <li key={r.id}>
              <Link
                href={`/r/${r.key.toLowerCase()}/tasks`}
                className="group block rounded-lg border bg-card p-4 hover:border-foreground/20 transition-colors"
              >
                <div className="flex items-center gap-3">
                  <span
                    className={cn(
                      "grid h-9 w-9 place-items-center rounded-md bg-muted text-sm font-bold",
                      r.color,
                    )}
                  >
                    {r.key[0]}
                  </span>
                  <div className="min-w-0 flex-1">
                    <h3 className="text-sm font-semibold truncate">{r.name}</h3>
                    <p className="text-[11px] text-muted-foreground flex items-center gap-1">
                      <Github className="h-3 w-3" /> {r.key}
                    </p>
                  </div>
                  <ChevronRight className="h-4 w-4 text-muted-foreground group-hover:text-foreground transition-colors" />
                </div>

                <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
                  <div className="rounded-md bg-muted/40 py-2">
                    <dt className="text-[10px] uppercase tracking-wider text-muted-foreground">
                      Projects
                    </dt>
                    <dd className="text-sm font-semibold tabular-nums">{r.projects.length}</dd>
                  </div>
                  <div className="rounded-md bg-muted/40 py-2">
                    <dt className="text-[10px] uppercase tracking-wider text-muted-foreground">
                      Active
                    </dt>
                    <dd className="text-sm font-semibold tabular-nums">{r.active}</dd>
                  </div>
                  <div className="rounded-md bg-muted/40 py-2">
                    <dt className="text-[10px] uppercase tracking-wider text-muted-foreground">
                      Status
                    </dt>
                    <dd className="text-sm font-semibold tabular-nums text-emerald-500">Synced</dd>
                  </div>
                </dl>
              </Link>
            </li>
          ))}
        </ul>
      </main>
    </div>
  );
}
