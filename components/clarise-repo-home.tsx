"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  ArrowRight,
  FileText,
  Landmark,
  ListChecks,
  Loader2,
  Milestone,
  Send,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { cn } from "@/lib/utils";
import type { ClariseProviderId } from "@/lib/clarise-chat";

type ChatRole = "user" | "assistant";

type ArtifactResult = {
  kind: string;
  type: string;
  id: string;
  title: string;
  status: string;
  href: string;
};

type ArtifactFailure = {
  artifactKind: string;
  title: string;
  error: string;
};

type ThreadMessage = {
  id: string;
  role: ChatRole;
  content: string;
  artifacts?: ArtifactResult[];
  failures?: ArtifactFailure[];
  setupHref?: string;
  pending?: boolean;
};

type StreamEvent =
  | { type: "message_delta"; text: string }
  | { type: "artifact_result"; artifact: ArtifactResult }
  | { type: "artifact_failure"; artifactKind: string; title: string; error: string }
  | { type: "done"; createdCount: number; failedCount: number }
  | { type: "missing_fields"; fields: { kind: string; field: string }[] }
  | { type: "tool_call"; name: string; artifactKind: string; title: string };

const PROVIDERS: { id: ClariseProviderId; label: string }[] = [
  { id: "codex_app_server", label: "Codex" },
  { id: "claude_code", label: "Claude Code" },
  { id: "gemini", label: "Gemini" },
  { id: "cursor", label: "Cursor" },
];

const STARTERS = [
  {
    label: "Create a milestone",
    icon: Milestone,
    prompt: "Create a milestone\nTitle: \nGoal: ",
  },
  {
    label: "Draft a decision",
    icon: Landmark,
    prompt: "Create a decision\nMilestone: \nTitle: \nDecision: ",
  },
  {
    label: "Capture a requirement",
    icon: ListChecks,
    prompt: "Create a requirement\nMilestone: \nTitle: \nRequirement: ",
  },
  {
    label: "Draft a plan",
    icon: FileText,
    prompt: "Create a plan\nMilestone: \nTitle: \nPlan: ",
  },
  {
    label: "Create an execution-ready task brief",
    icon: FileText,
    prompt: "Create an execution-ready task brief\nTitle: \nGoal: ",
  },
  {
    label: "Set up WORKFLOW.md",
    icon: ShieldCheck,
    prompt: "Set up WORKFLOW.md",
  },
];

export function ClariseRepoHome({ repoKey }: { repoKey: string }) {
  const repoSlug = repoKey.toLowerCase();
  const storageKey = `symphonia.clarise.provider.${repoKey}`;
  const router = useRouter();
  const [provider, setProvider] = useState<ClariseProviderId>("codex_app_server");
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<ThreadMessage[]>([
    {
      id: "welcome",
      role: "assistant",
      content:
        "Start by telling Clarise what you want to build. Clarise will create the private workspace structure for this repository.",
    },
  ]);
  const [pending, setPending] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey);
      if (
        stored === "codex_app_server" ||
        stored === "claude_code" ||
        stored === "gemini" ||
        stored === "cursor"
      ) {
        setProvider(stored);
      }
    } catch {
      /* ignore */
    }
  }, [storageKey]);

  useEffect(() => {
    try {
      window.localStorage.setItem(storageKey, provider);
    } catch {
      /* ignore */
    }
  }, [provider, storageKey]);

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" });
  }, [messages]);

  const visibleMessages = useMemo(() => messages.filter((message) => message.content), [messages]);

  const chooseStarter = (prompt: string) => {
    setDraft(prompt);
    requestAnimationFrame(() => inputRef.current?.focus());
  };

  const send = async (event?: FormEvent) => {
    event?.preventDefault();
    const text = draft.trim();
    if (!text || pending) return;

    const userMessage: ThreadMessage = {
      id: `u-${Date.now()}`,
      role: "user",
      content: text,
    };
    const assistantId = `a-${Date.now()}`;
    const assistantMessage: ThreadMessage = {
      id: assistantId,
      role: "assistant",
      content: "",
      artifacts: [],
      failures: [],
      pending: true,
    };

    const nextMessages = [...messages, userMessage, assistantMessage];
    setMessages(nextMessages);
    setDraft("");
    setPending(true);

    try {
      const response = await fetch(`/api/repositories/${encodeURIComponent(repoKey)}/clarise/chat`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          provider,
          messages: [...messages, userMessage].map((message) => ({
            role: message.role === "assistant" ? "assistant" : "user",
            content: message.content,
          })),
        }),
      });

      if (!response.ok) {
        const payload = (await response.json().catch(() => ({}))) as {
          error?: string;
          providerSetupHref?: string;
        };
        updateAssistant(assistantId, (message) => ({
          ...message,
          content: payload.error ?? "Clarise could not start.",
          setupHref: payload.providerSetupHref,
          pending: false,
        }));
        return;
      }

      await readClariseStream(response, (streamEvent) => {
        updateAssistant(assistantId, (message) => applyStreamEvent(message, streamEvent));
        if (streamEvent.type === "done" && streamEvent.createdCount > 0) {
          router.push(`/r/${repoSlug}/workspace?created=private`);
        }
      });
    } catch (error) {
      updateAssistant(assistantId, (message) => ({
        ...message,
        content: error instanceof Error ? error.message : "Clarise could not respond.",
        pending: false,
      }));
    } finally {
      setPending(false);
      updateAssistant(assistantId, (message) => ({ ...message, pending: false }));
    }
  };

  const updateAssistant = (id: string, updater: (message: ThreadMessage) => ThreadMessage) => {
    setMessages((current) => current.map((message) => (message.id === id ? updater(message) : message)));
  };

  return (
    <div className="flex min-h-full flex-col bg-background text-foreground">
      <header className="border-b bg-background/95 px-4 py-3 backdrop-blur sm:px-6">
        <div className="flex flex-wrap items-center gap-3">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="grid h-7 w-7 place-items-center rounded-[8px] bg-brand-accent-soft text-brand-accent-text">
                <Sparkles className="h-4 w-4" />
              </span>
              <p className="text-[12px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Clarise
              </p>
              <span className="rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[11px] font-medium text-emerald-300">
                Private
              </span>
            </div>
            <h1 className="mt-2 break-words text-[30px] font-bold leading-none sm:text-[42px]">
              {repoKey} repo planning
            </h1>
          </div>

          <label className="flex items-center gap-2 rounded-[8px] border bg-card px-3 py-2 text-[12px] text-muted-foreground">
            Provider
            <select
              value={provider}
              onChange={(event) => setProvider(event.target.value as ClariseProviderId)}
              className="bg-transparent text-[13px] font-medium text-foreground outline-none"
              aria-label="Clarise provider"
            >
              {PROVIDERS.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
        </div>
      </header>

      <main className="grid min-h-0 flex-1 gap-0 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <section className="flex min-h-0 flex-col">
          <div ref={listRef} className="min-h-0 flex-1 overflow-y-auto px-4 py-5 sm:px-6">
            <div className="mx-auto flex max-w-4xl flex-col gap-4">
              {visibleMessages.map((message) => (
                <MessageBubble key={message.id} message={message} />
              ))}
            </div>
          </div>

          <form onSubmit={send} className="border-t bg-background/95 px-4 py-4 sm:px-6">
            <div className="mx-auto max-w-4xl">
              <div className="mb-3 flex flex-wrap gap-2">
                {STARTERS.map((starter) => {
                  const Icon = starter.icon;
                  return (
                    <button
                      key={starter.label}
                      type="button"
                      onClick={() => chooseStarter(starter.prompt)}
                      className="inline-flex h-8 items-center gap-2 rounded-[8px] border bg-card px-3 text-[12px] font-medium text-muted-foreground transition hover:bg-accent hover:text-foreground"
                    >
                      <Icon className="h-3.5 w-3.5" />
                      {starter.label}
                    </button>
                  );
                })}
              </div>

              <div className="flex items-end gap-3 rounded-[10px] border bg-card p-3 shadow-[var(--elevation-card)]">
                <textarea
                  ref={inputRef}
                  value={draft}
                  onChange={(event) => setDraft(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" && !event.shiftKey) {
                      event.preventDefault();
                      void send();
                    }
                  }}
                  rows={2}
                  placeholder="Add the required fields, then Clarise saves the private doc."
                  aria-label="Message Clarise"
                  className="max-h-40 min-h-[3.5rem] flex-1 resize-none bg-transparent text-[15px] leading-6 outline-none placeholder:text-muted-foreground/60"
                />
                <button
                  type="submit"
                  disabled={pending || !draft.trim()}
                  aria-label="Send"
                  className="grid h-10 w-10 shrink-0 place-items-center rounded-[8px] bg-primary text-primary-foreground transition hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-45"
                >
                  {pending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                </button>
              </div>
            </div>
          </form>
        </section>

        <aside className="border-t bg-sidebar/45 px-4 py-4 lg:border-l lg:border-t-0">
          <div className="space-y-3">
            <Link
              href={`/r/${repoSlug}/workspace`}
              className="group flex items-center justify-between rounded-[8px] border bg-card px-3 py-2 text-[13px] font-medium text-foreground hover:bg-accent"
            >
              Workspace
              <ArrowRight className="h-3.5 w-3.5 text-muted-foreground group-hover:text-foreground" />
            </Link>
            <Link
              href={`/r/${repoSlug}/tasks`}
              className="group flex items-center justify-between rounded-[8px] border bg-card px-3 py-2 text-[13px] font-medium text-foreground hover:bg-accent"
            >
              Tasks
              <ArrowRight className="h-3.5 w-3.5 text-muted-foreground group-hover:text-foreground" />
            </Link>
            <Link
              href={`/r/${repoSlug}/settings`}
              className="group flex items-center justify-between rounded-[8px] border bg-card px-3 py-2 text-[13px] font-medium text-foreground hover:bg-accent"
            >
              Provider setup
              <ArrowRight className="h-3.5 w-3.5 text-muted-foreground group-hover:text-foreground" />
            </Link>
          </div>
        </aside>
      </main>
    </div>
  );
}

function MessageBubble({ message }: { message: ThreadMessage }) {
  const isUser = message.role === "user";

  return (
    <div className={cn("flex", isUser ? "justify-end" : "justify-start")}>
      <div
        className={cn(
          "max-w-[min(42rem,100%)] rounded-[10px] px-4 py-3 text-[14px] leading-6",
          isUser
            ? "bg-primary text-primary-foreground"
            : "border bg-card text-foreground shadow-[var(--elevation-card)]",
        )}
      >
        <p className="whitespace-pre-wrap">{message.content}</p>

        {message.pending && (
          <div className="mt-3 inline-flex items-center gap-2 text-[12px] text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            Working
          </div>
        )}

        {message.setupHref && (
          <Link
            href={message.setupHref}
            className="mt-3 inline-flex items-center gap-1 rounded-[8px] border px-3 py-1.5 text-[12px] font-medium hover:bg-accent"
          >
            Open settings
            <ArrowRight className="h-3.5 w-3.5" />
          </Link>
        )}

        {message.artifacts && message.artifacts.length > 0 && (
          <div className="mt-3 grid gap-2">
            {message.artifacts.map((artifact) => (
              <ArtifactCard key={`${artifact.type}:${artifact.id}`} artifact={artifact} />
            ))}
          </div>
        )}

        {message.failures && message.failures.length > 0 && (
          <div className="mt-3 grid gap-2">
            {message.failures.map((failure) => (
              <div
                key={`${failure.artifactKind}:${failure.title}`}
                className="rounded-[8px] border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-[12px] text-amber-300"
              >
                {failure.title}: {failure.error}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function ArtifactCard({ artifact }: { artifact: ArtifactResult }) {
  return (
    <div className="rounded-[8px] border bg-background/55 p-3">
      <div className="flex items-start gap-3">
        <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[8px] bg-brand-accent-soft text-brand-accent-text">
          <FileText className="h-4 w-4" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="truncate text-[14px] font-semibold">{artifact.title}</h3>
            <span className="rounded-full border border-emerald-500/30 px-2 py-0.5 text-[10px] font-medium uppercase text-emerald-300">
              Private
            </span>
          </div>
          <p className="mt-1 text-[12px] text-muted-foreground">{artifactLabel(artifact.kind)}</p>
        </div>
      </div>
      <Link
        href={artifact.href}
        className="mt-3 inline-flex items-center gap-1 rounded-[8px] border px-3 py-1.5 text-[12px] font-medium hover:bg-accent"
      >
        View in workspace
        <ArrowRight className="h-3.5 w-3.5" />
      </Link>
    </div>
  );
}

function artifactLabel(kind: string): string {
  if (kind === "milestone") return "Milestone";
  if (kind === "requirements") return "Requirement";
  if (kind === "plan") return "Plan";
  if (kind === "decision") return "Decision";
  return "Task brief";
}

async function readClariseStream(
  response: Response,
  onEvent: (event: StreamEvent) => void,
) {
  const reader = response.body?.getReader();
  if (!reader) return;

  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split("\n\n");
    buffer = events.pop() ?? "";

    for (const event of events) {
      const dataLine = event.split("\n").find((line) => line.startsWith("data: "));
      if (!dataLine) continue;
      onEvent(JSON.parse(dataLine.slice(6)) as StreamEvent);
    }
  }
}

function applyStreamEvent(message: ThreadMessage, event: StreamEvent): ThreadMessage {
  if (event.type === "message_delta") {
    return { ...message, content: `${message.content}${event.text}` };
  }

  if (event.type === "artifact_result") {
    return { ...message, artifacts: [...(message.artifacts ?? []), event.artifact] };
  }

  if (event.type === "artifact_failure") {
    return { ...message, failures: [...(message.failures ?? []), event] };
  }

  if (event.type === "done") {
    return { ...message, pending: false };
  }

  return message;
}
