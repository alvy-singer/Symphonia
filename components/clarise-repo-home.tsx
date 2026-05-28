"use client";

import { useChat, type UIMessage } from "@ai-sdk/react";
import { createAssistantStream } from "assistant-stream";
import {
  AssistantRuntimeProvider,
  ComposerPrimitive,
  ThreadListItemPrimitive,
  ThreadListPrimitive,
  ThreadPrimitive,
  useAui,
  useAuiState,
  useComposer,
  useComposerRuntime,
  useRemoteThreadListRuntime,
  type DataMessagePart,
  type ExportedMessageRepository,
  type ExportedMessageRepositoryItem,
  type MessageFormatAdapter,
  type MessageFormatRepository,
  type MessageStorageEntry,
  type MessageState,
  type RemoteThreadListAdapter,
  type ThreadHistoryAdapter,
  type ThreadMessage,
} from "@assistant-ui/react";
import {
  createSimpleTitleAdapter,
  RuntimeAdapterProvider,
  type AsyncStorageLike,
} from "@assistant-ui/core/react";
import { AssistantChatTransport, useAISDKRuntime } from "@assistant-ui/react-ai-sdk";
import type { DataUIPart } from "ai";
import Link from "next/link";
import {
  ArrowRight,
  CheckCircle2,
  FileText,
  Landmark,
  ListChecks,
  Loader2,
  Menu,
  MessageSquareText,
  Milestone,
  PanelLeftClose,
  Plus,
  Send,
  ShieldCheck,
  Sparkles,
  Trash2,
} from "lucide-react";
import {
  type FC,
  type PropsWithChildren,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import { cn } from "@/lib/utils";
import type { ClariseModelProfile, ClariseProviderId } from "@/lib/clarise-chat";

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

type ClariseDataTypes = {
  artifact_result: { artifact: ArtifactResult };
  artifact_failure: ArtifactFailure;
  extraction_fallback: { reason: string };
  missing_fields: { fields: { kind: string; field: string }[] };
  tool_call: { name: "create_private_artifact"; artifactKind: string; title: string };
  done: { createdCount: number; failedCount: number };
};

type ClariseUIMessage = UIMessage<unknown, ClariseDataTypes>;

type StoredClariseThreadMetadata = {
  remoteId: string;
  externalId?: string;
  status: "regular" | "archived";
  title?: string;
};

type StoredFormattedMessages = {
  headId?: string | null;
  messages: MessageStorageEntry<Record<string, unknown>>[];
};

const PROVIDERS: { id: ClariseProviderId; label: string }[] = [
  { id: "codex_app_server", label: "Codex" },
  { id: "claude_code", label: "Claude Code" },
  { id: "gemini", label: "Gemini" },
  { id: "cursor", label: "Cursor" },
];

const MODEL_PROFILES: { id: ClariseModelProfile; label: string }[] = [
  { id: "balanced", label: "Balanced" },
  { id: "quality", label: "Quality" },
  { id: "budget", label: "Budget" },
];

const SLASH_COMMANDS = [
  {
    command: "/codebase",
    label: "Codebase map",
    description: "Create private codebase context.",
    icon: FileText,
  },
  {
    command: "/new-project",
    label: "New project",
    description: "Start a milestone, requirement, plan, and first task brief.",
    icon: Milestone,
  },
  {
    command: "/discuss-phase",
    label: "Discuss phase",
    description: "Capture phase decisions before implementation.",
    icon: MessageSquareText,
  },
  {
    command: "/plan-phase",
    label: "Plan phase",
    description: "Create a phase plan.",
    icon: ShieldCheck,
  },
  {
    command: "/execute-phase",
    label: "Execute phase",
    description: "Prepare an execution-ready task brief.",
    icon: ListChecks,
  },
  {
    command: "/verify-work",
    label: "Verify work",
    description: "Prepare a verification task brief.",
    icon: CheckCircle2,
  },
  {
    command: "/ship",
    label: "Ship phase",
    description: "Prepare a ship checklist brief.",
    icon: ArrowRight,
  },
  {
    command: "/milestone",
    label: "Milestone",
    description: "Create a private milestone.",
    icon: Milestone,
  },
  {
    command: "/requirement",
    label: "Requirement",
    description: "Create a private requirement.",
    icon: ListChecks,
  },
  {
    command: "/plan",
    label: "Plan",
    description: "Create a private plan.",
    icon: FileText,
  },
  {
    command: "/decision",
    label: "Decision",
    description: "Create a private decision.",
    icon: Landmark,
  },
  {
    command: "/task-brief",
    label: "Task brief",
    description: "Create an execution-ready task brief.",
    icon: FileText,
  },
  {
    command: "/workflow",
    label: "WORKFLOW.md",
    description: "Prepare repository rules planning.",
    icon: ShieldCheck,
  },
];

const browserStorage: AsyncStorageLike = {
  async getItem(key) {
    if (typeof window === "undefined") return null;
    return window.localStorage.getItem(key);
  },
  async setItem(key, value) {
    if (typeof window === "undefined") return;
    window.localStorage.setItem(key, value);
  },
  async removeItem(key) {
    if (typeof window === "undefined") return;
    window.localStorage.removeItem(key);
  },
};

export function ClariseRepoHome({ repoKey }: { repoKey: string }) {
  const providerStorageKey = `symphonia.clarise.provider.${repoKey}`;
  const profileStorageKey = `symphonia.clarise.modelProfile.${repoKey}`;
  const [provider, setProvider] = useStoredClariseProvider(providerStorageKey);
  const [modelProfile, setModelProfile] = useStoredClariseModelProfile(profileStorageKey);
  const [sidebarOpen, setSidebarOpen] = useState(false);

  const initialMessages = useMemo<ClariseUIMessage[]>(
    () => [
      {
        id: "welcome",
        role: "assistant",
        parts: [
          {
            type: "text",
            text:
              "Start by telling Clarise what you want to build. Clarise will create the private workspace structure for this repository.",
          },
        ],
      },
    ],
    [],
  );

  const runtime = usePersistentClariseRuntime({
    repoKey,
    provider,
    modelProfile,
    initialMessages,
    onData: () => {},
  });

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <div className="relative flex min-h-full bg-background text-foreground">
        <div
          className={cn(
            "fixed inset-0 z-30 bg-black/55 transition-opacity md:hidden",
            sidebarOpen ? "opacity-100" : "pointer-events-none opacity-0",
          )}
          aria-hidden="true"
          onClick={() => setSidebarOpen(false)}
        />

        <ClariseThreadSidebar
          repoKey={repoKey}
          open={sidebarOpen}
          onClose={() => setSidebarOpen(false)}
        />

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="border-b bg-background/95 px-4 py-3 backdrop-blur sm:px-6">
            <div className="flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={() => setSidebarOpen(true)}
                aria-label="Open threads"
                className="grid h-9 w-9 place-items-center rounded-[8px] border bg-card text-muted-foreground transition hover:bg-accent hover:text-foreground md:hidden"
              >
                <Menu className="h-4 w-4" />
              </button>

              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="grid h-7 w-7 place-items-center rounded-[8px] bg-brand-accent-soft text-brand-accent-text">
                    <Sparkles className="h-4 w-4" />
                  </span>
                </div>
                <h1 className="mt-2 break-words text-[30px] font-bold leading-none sm:text-[42px]">
                  Clarise
                </h1>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <label className="flex h-8 items-center gap-1.5 rounded-[6px] border bg-card px-2 text-[11px] text-muted-foreground">
                  Provider
                  <select
                    value={provider}
                    onChange={(event) => setProvider(event.target.value as ClariseProviderId)}
                    className="max-w-28 bg-transparent text-[11px] font-medium text-foreground outline-none"
                    aria-label="Clarise provider"
                  >
                    {PROVIDERS.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="flex h-8 items-center gap-1.5 rounded-[6px] border bg-card px-2 text-[11px] text-muted-foreground">
                  Profile
                  <select
                    value={modelProfile}
                    onChange={(event) =>
                      setModelProfile(event.target.value as ClariseModelProfile)
                    }
                    className="max-w-24 bg-transparent text-[11px] font-medium text-foreground outline-none"
                    aria-label="Clarise model profile"
                  >
                    {MODEL_PROFILES.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
            </div>
          </header>

          <ThreadPrimitive.Root className="flex min-h-0 flex-1 flex-col">
            <ThreadPrimitive.Viewport className="min-h-0 flex-1 overflow-y-auto px-4 py-5 sm:px-6">
              <div className="mx-auto flex max-w-4xl flex-col gap-4">
                <ThreadPrimitive.Messages>
                  {({ message }) => <ClariseMessage key={message.id} message={message} />}
                </ThreadPrimitive.Messages>
              </div>
            </ThreadPrimitive.Viewport>

            <ClariseComposer />
          </ThreadPrimitive.Root>
        </div>
      </div>
    </AssistantRuntimeProvider>
  );
}

function usePersistentClariseRuntime({
  repoKey,
  provider,
  modelProfile,
  initialMessages,
  onData,
}: {
  repoKey: string;
  provider: ClariseProviderId;
  modelProfile: ClariseModelProfile;
  initialMessages: ClariseUIMessage[];
  onData: (part: DataUIPart<ClariseDataTypes>) => void;
}) {
  const transport = useMemo(
    () =>
      new AssistantChatTransport<ClariseUIMessage>({
        api: `/api/repositories/${encodeURIComponent(repoKey)}/clarise/chat`,
        body: { provider, modelProfile },
      }),
    [modelProfile, provider, repoKey],
  );

  const adapter = useMemo<RemoteThreadListAdapter>(
    () => createClariseThreadListAdapter(`symphonia.clarise.threads.${repoKey}.`),
    [repoKey],
  );

  const runtimeHook = useCallback(
    function ClariseRuntimeHook() {
      return useClariseThreadRuntime({
        initialMessages,
        onData,
        transport,
      });
    },
    [initialMessages, onData, transport],
  );

  return useRemoteThreadListRuntime({
    adapter,
    runtimeHook,
  });
}

function useClariseThreadRuntime({
  initialMessages,
  onData,
  transport,
}: {
  initialMessages: ClariseUIMessage[];
  onData: (part: DataUIPart<ClariseDataTypes>) => void;
  transport: AssistantChatTransport<ClariseUIMessage>;
}) {
  const id = useAuiState((state) => state.threadListItem.id);
  const aui = useAui();
  const chat = useChat<ClariseUIMessage>({
    id,
    messages: initialMessages,
    transport,
    onData,
  });
  const runtime = useAISDKRuntime<ClariseUIMessage>(chat);

  transport.setRuntime(runtime);
  transport.__internal_setGetThreadListItem(() =>
    aui.threadListItem.source ? aui.threadListItem() : undefined,
  );

  return runtime;
}

class FormattedLocalHistoryAdapter implements ThreadHistoryAdapter {
  constructor(
    private storage: AsyncStorageLike,
    private aui: ReturnType<typeof useAui>,
    private prefix: string,
  ) {}

  private messagesKey(remoteId: string) {
    return `${this.prefix}messages:${remoteId}`;
  }

  private currentRemoteId() {
    return this.aui.threadListItem().getState().remoteId ?? null;
  }

  async load(): Promise<ExportedMessageRepository> {
    return { messages: [] };
  }

  async append(_item: ExportedMessageRepositoryItem): Promise<void> {}

  withFormat<TMessage, TStorageFormat extends Record<string, unknown>>(
    formatAdapter: MessageFormatAdapter<TMessage, TStorageFormat>,
  ) {
    const loadStored = async (remoteId: string): Promise<StoredFormattedMessages> => {
      const raw = await this.storage.getItem(this.messagesKey(remoteId));
      if (!raw) return { messages: [] };

      const parsed = JSON.parse(raw) as Partial<StoredFormattedMessages>;
      return {
        headId: parsed.headId ?? null,
        messages: Array.isArray(parsed.messages) ? parsed.messages : [],
      };
    };

    const saveStored = async (remoteId: string, repo: StoredFormattedMessages) => {
      await this.storage.setItem(this.messagesKey(remoteId), JSON.stringify(repo));
    };

    const toEntry = (item: { parentId: string | null; message: TMessage }) => ({
      id: formatAdapter.getId(item.message),
      parent_id: item.parentId,
      format: formatAdapter.format,
      content: formatAdapter.encode(item),
    });

    return {
      load: async (): Promise<MessageFormatRepository<TMessage>> => {
        const remoteId = this.currentRemoteId();
        if (!remoteId) return { messages: [] };

        const repo = await loadStored(remoteId);
        return {
          headId: repo.headId,
          messages: repo.messages
            .filter((message) => message.format === formatAdapter.format)
            .map((message) =>
              formatAdapter.decode(message as MessageStorageEntry<TStorageFormat>),
            ),
        };
      },
      append: async (item: { parentId: string | null; message: TMessage }) => {
        const { remoteId } = await this.aui.threadListItem().initialize();
        const repo = await loadStored(remoteId);
        const entry = toEntry(item);
        const index = repo.messages.findIndex((message) => message.id === entry.id);

        if (index >= 0) {
          repo.messages[index] = entry;
        } else {
          repo.messages.push(entry);
        }

        repo.headId = entry.id;
        await saveStored(remoteId, repo);
      },
      update: async (
        item: { parentId: string | null; message: TMessage },
        localMessageId: string,
      ) => {
        const { remoteId } = await this.aui.threadListItem().initialize();
        const repo = await loadStored(remoteId);
        const entry = toEntry(item);
        const index = repo.messages.findIndex((message) => message.id === localMessageId);

        if (index >= 0) {
          repo.messages[index] = entry;
        } else {
          repo.messages.push(entry);
        }

        repo.headId = entry.id;
        await saveStored(remoteId, repo);
      },
    };
  }
}

function createClariseHistoryProvider(prefix: string): FC<PropsWithChildren> {
  function ClariseHistoryProvider({ children }: PropsWithChildren) {
    const aui = useAui();
    const history = useMemo(
      () => new FormattedLocalHistoryAdapter(browserStorage, aui, prefix),
      [aui, prefix],
    );
    const adapters = useMemo(() => ({ history }), [history]);

    return <RuntimeAdapterProvider adapters={adapters}>{children}</RuntimeAdapterProvider>;
  }

  return ClariseHistoryProvider;
}

function createClariseThreadListAdapter(prefix: string): RemoteThreadListAdapter {
  const titleGenerator = createSimpleTitleAdapter();
  const threadsKey = `${prefix}threads`;
  const messagesKey = (threadId: string) => `${prefix}messages:${threadId}`;

  const loadThreadMetadata = async (): Promise<StoredClariseThreadMetadata[]> => {
    const raw = await browserStorage.getItem(threadsKey);
    return raw ? (JSON.parse(raw) as StoredClariseThreadMetadata[]) : [];
  };

  const saveThreadMetadata = async (threads: StoredClariseThreadMetadata[]) => {
    await browserStorage.setItem(threadsKey, JSON.stringify(threads));
  };

  return {
    unstable_Provider: createClariseHistoryProvider(prefix),

    async list() {
      const threads = await loadThreadMetadata();
      return {
        threads: threads.map((thread) => ({
          remoteId: thread.remoteId,
          externalId: thread.externalId,
          status: thread.status,
          title: thread.title,
        })),
      };
    },

    async initialize(threadId: string) {
      const threads = await loadThreadMetadata();

      if (!threads.some((thread) => thread.remoteId === threadId)) {
        threads.unshift({ remoteId: threadId, status: "regular" });
        await saveThreadMetadata(threads);
      }

      return { remoteId: threadId, externalId: undefined };
    },

    async rename(remoteId: string, newTitle: string): Promise<void> {
      const threads = await loadThreadMetadata();
      const thread = threads.find((item) => item.remoteId === remoteId);
      if (!thread) return;

      thread.title = newTitle;
      await saveThreadMetadata(threads);
    },

    async archive(remoteId: string): Promise<void> {
      const threads = await loadThreadMetadata();
      const thread = threads.find((item) => item.remoteId === remoteId);
      if (!thread) return;

      thread.status = "archived";
      await saveThreadMetadata(threads);
    },

    async unarchive(remoteId: string): Promise<void> {
      const threads = await loadThreadMetadata();
      const thread = threads.find((item) => item.remoteId === remoteId);
      if (!thread) return;

      thread.status = "regular";
      await saveThreadMetadata(threads);
    },

    async delete(remoteId: string): Promise<void> {
      const threads = await loadThreadMetadata();
      await saveThreadMetadata(threads.filter((thread) => thread.remoteId !== remoteId));
      await browserStorage.removeItem(messagesKey(remoteId));
    },

    async fetch(threadId: string) {
      const threads = await loadThreadMetadata();
      const thread = threads.find((item) => item.remoteId === threadId);
      if (!thread) throw new Error("Thread not found");

      return {
        remoteId: thread.remoteId,
        externalId: thread.externalId,
        status: thread.status,
        title: thread.title,
      };
    },

    async generateTitle(remoteId: string, messages: readonly ThreadMessage[]) {
      const title = await titleGenerator.generateTitle(messages);
      const threads = await loadThreadMetadata();
      const thread = threads.find((item) => item.remoteId === remoteId);

      if (thread) {
        thread.title = title;
        await saveThreadMetadata(threads);
      }

      return createAssistantStream((controller) => {
        controller.appendText(title);
      });
    },
  };
}

function ClariseThreadSidebar({
  repoKey,
  open,
  onClose,
}: {
  repoKey: string;
  open: boolean;
  onClose: () => void;
}) {
  const threadCount = useAuiState((state) => state.threads.threadIds.length);
  const isLoading = useAuiState((state) => state.threads.isLoading);

  return (
    <aside
      className={cn(
        "fixed inset-y-0 left-0 z-40 flex w-[19rem] max-w-[86vw] flex-col border-r bg-sidebar text-sidebar-foreground transition-transform md:static md:z-auto md:max-w-none md:translate-x-0",
        open ? "translate-x-0" : "-translate-x-full",
      )}
    >
      <div className="flex h-[65px] items-center gap-3 border-b border-sidebar-border px-3">
        <div className="grid h-8 w-8 place-items-center rounded-[8px] bg-brand-accent-soft text-brand-accent-text">
          <Sparkles className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] font-semibold">Clarise</p>
          <p className="truncate text-[11px] text-muted-foreground">{repoKey} workspace</p>
        </div>
        <button
          type="button"
          onClick={onClose}
          aria-label="Close threads"
          className="grid h-8 w-8 place-items-center rounded-[8px] text-muted-foreground transition hover:bg-sidebar-accent hover:text-foreground md:hidden"
        >
          <PanelLeftClose className="h-4 w-4" />
        </button>
      </div>

      <ThreadListPrimitive.Root className="min-h-0 flex-1 overflow-y-auto p-2">
        <ThreadListPrimitive.New
          className="mb-2 flex h-9 w-full items-center gap-2 rounded-[8px] border border-sidebar-border bg-sidebar-accent px-3 text-left text-[13px] font-medium text-foreground transition hover:bg-accent data-[active=true]:border-primary/40"
          onClick={onClose}
        >
          <Plus className="h-4 w-4" />
          New thread
        </ThreadListPrimitive.New>

        <div className="mb-2 flex items-center justify-between px-1.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
          <span>Threads</span>
          <span className="tabular-nums">{threadCount}</span>
        </div>

        {isLoading ? (
          <div className="flex items-center gap-2 px-2 py-3 text-[12px] text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            Loading
          </div>
        ) : threadCount === 0 ? (
          <p className="px-2 py-3 text-[12px] leading-5 text-muted-foreground">
            No saved threads yet.
          </p>
        ) : (
          <div className="space-y-1">
            <ThreadListPrimitive.Items>
              {() => <ClariseThreadListItem onNavigate={onClose} />}
            </ThreadListPrimitive.Items>
          </div>
        )}
      </ThreadListPrimitive.Root>

    </aside>
  );
}

function ClariseThreadListItem({ onNavigate }: { onNavigate: () => void }) {
  return (
    <ThreadListItemPrimitive.Root className="group flex items-center gap-1 rounded-[8px] px-1 py-1 data-[active=true]:bg-sidebar-accent">
      <ThreadListItemPrimitive.Trigger
        onClick={onNavigate}
        className="flex min-w-0 flex-1 items-center gap-2 rounded-[7px] px-2 py-2 text-left text-[13px] text-muted-foreground transition hover:bg-sidebar-accent hover:text-foreground data-[active=true]:text-foreground"
      >
        <MessageSquareText className="h-3.5 w-3.5 shrink-0" />
        <span className="truncate">
          <ThreadListItemPrimitive.Title fallback="New thread" />
        </span>
      </ThreadListItemPrimitive.Trigger>
      <ThreadListItemPrimitive.Delete
        aria-label="Delete thread"
        className="grid h-8 w-8 shrink-0 place-items-center rounded-[7px] text-muted-foreground opacity-0 transition hover:bg-sidebar-accent hover:text-destructive group-hover:opacity-100 focus:opacity-100"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </ThreadListItemPrimitive.Delete>
    </ThreadListItemPrimitive.Root>
  );
}

function ClariseMessage({ message }: { message: MessageState }) {
  const isUser = message.role === "user";
  const text = message.content
    .flatMap((part) => (part.type === "text" ? [part.text] : []))
    .join("");
  const dataParts = message.content.flatMap((part) =>
    part.type === "data" ? [part as DataMessagePart] : [],
  );
  const artifacts = dataParts.flatMap((part) =>
    part.name === "artifact_result" && isArtifactResultPayload(part.data)
      ? [part.data.artifact]
      : [],
  );
  const failures = dataParts.flatMap((part) =>
    part.name === "artifact_failure" && isArtifactFailure(part.data) ? [part.data] : [],
  );
  const fallback = dataParts.find(
    (part) => part.name === "extraction_fallback" && isFallbackPayload(part.data),
  );
  const missingFields = dataParts.find(
    (part) => part.name === "missing_fields" && isMissingFieldsPayload(part.data),
  );
  const running = message.status?.type === "running";

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
        {text && <p className="whitespace-pre-wrap">{text}</p>}

        {running && (
          <div className="mt-3 inline-flex items-center gap-2 text-[12px] text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            Working
          </div>
        )}

        {fallback && isFallbackPayload(fallback.data) && (
          <div className="mt-3 border-l border-amber-500/40 bg-amber-500/10 px-3 py-2 text-[12px] text-amber-300">
            Codex extraction fell back to the deterministic parser: {fallback.data.reason}
          </div>
        )}

        {missingFields && isMissingFieldsPayload(missingFields.data) && (
          <div className="mt-3 border-l bg-background/55 px-3 py-2 text-[12px] text-muted-foreground">
            {missingFields.data.fields.map((field) => `${artifactLabel(field.kind)}: ${field.field}`).join("; ")}
          </div>
        )}

        {artifacts.length > 0 && (
          <div className="mt-3 grid gap-2">
            {artifacts.map((artifact) => (
              <ArtifactCard key={`${artifact.type}:${artifact.id}`} artifact={artifact} />
            ))}
          </div>
        )}

        {failures.length > 0 && (
          <div className="mt-3 grid gap-2">
            {failures.map((failure) => (
              <div
                key={`${failure.artifactKind}:${failure.title}`}
                className="border-l border-amber-500/40 bg-amber-500/10 px-3 py-2 text-[12px] text-amber-300"
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

function ClariseComposer() {
  const composer = useComposerRuntime();
  const text = useComposer((state) => state.text);
  const isSlashQuery = text.startsWith("/") && !/\s/.test(text);
  const query = isSlashQuery ? text.slice(1).toLowerCase() : "";
  const activeCommand = text.startsWith("/")
    ? SLASH_COMMANDS.find(
        (item) => text === item.command || text.startsWith(`${item.command} `),
      )
    : undefined;
  const showMenu = isSlashQuery;
  const commands = SLASH_COMMANDS.filter((item) => {
    if (!query) return true;
    return (
      item.command.slice(1).includes(query) ||
      item.label.toLowerCase().includes(query) ||
      item.description.toLowerCase().includes(query)
    );
  });

  return (
    <div className="border-t bg-background/95 px-4 py-4 sm:px-6">
      <div className="relative mx-auto max-w-4xl">
        {showMenu && commands.length > 0 && (
          <div className="absolute bottom-[calc(100%+0.5rem)] left-0 z-10 w-full max-w-md rounded-[8px] border bg-popover p-1 shadow-[var(--elevation-card)]">
            {commands.map((item) => {
              const Icon = item.icon;
              return (
                <button
                  key={item.command}
                  type="button"
                  onMouseDown={(event) => {
                    event.preventDefault();
                    composer.setText(`${item.command} `);
                  }}
                  className="flex w-full items-center gap-3 rounded-[6px] px-3 py-2 text-left text-[13px] hover:bg-accent"
                  aria-label={`Use ${item.command}`}
                >
                  <span className="grid h-7 w-7 place-items-center rounded-[6px] bg-brand-accent-soft text-brand-accent-text">
                    <Icon className="h-3.5 w-3.5" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block font-medium text-foreground">{item.command}</span>
                    <span className="block text-[12px] text-muted-foreground">
                      {item.description}
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
        )}

        {activeCommand && (
          <div className="mb-2 flex min-h-6 items-center gap-2 text-[12px]">
            <span className="rounded-[5px] bg-brand-accent-soft px-2 py-1 font-medium text-brand-accent-text">
              {activeCommand.command}
            </span>
            <span className="text-muted-foreground">{activeCommand.description}</span>
          </div>
        )}

        <ComposerPrimitive.Root className="flex items-end gap-3 rounded-[10px] border bg-card p-3 shadow-[var(--elevation-card)]">
          <ComposerPrimitive.Input
            rows={2}
            submitMode="enter"
            placeholder="Message Clarise or type / for artifact commands."
            aria-label="Message Clarise"
            className="max-h-40 min-h-[3.5rem] flex-1 resize-none bg-transparent text-[15px] leading-6 outline-none placeholder:text-muted-foreground/60"
          />
          <ComposerPrimitive.Send
            aria-label="Send"
            className="grid h-10 w-10 shrink-0 place-items-center rounded-[8px] bg-primary text-primary-foreground transition hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-45"
          >
            <Send className="h-4 w-4" />
          </ComposerPrimitive.Send>
        </ComposerPrimitive.Root>
      </div>
    </div>
  );
}

function ArtifactCard({ artifact }: { artifact: ArtifactResult }) {
  return (
    <div className="border bg-background/55 p-3">
      <div className="flex items-start gap-3">
        <span className="grid h-8 w-8 shrink-0 place-items-center bg-brand-accent-soft text-brand-accent-text">
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
        className="mt-3 inline-flex items-center gap-1 border px-3 py-1.5 text-[12px] font-medium hover:bg-accent"
      >
        View in workspace
        <ArrowRight className="h-3.5 w-3.5" />
      </Link>
    </div>
  );
}

function useStoredClariseProvider(
  storageKey: string,
): [ClariseProviderId, (provider: ClariseProviderId) => void] {
  const [provider, setProvider] = useState<ClariseProviderId>("codex_app_server");

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
  }, [setProvider, storageKey]);

  useEffect(() => {
    try {
      window.localStorage.setItem(storageKey, provider);
    } catch {
      /* ignore */
    }
  }, [provider, storageKey]);

  return [provider, setProvider];
}

function useStoredClariseModelProfile(
  storageKey: string,
): [ClariseModelProfile, (profile: ClariseModelProfile) => void] {
  const [profile, setProfile] = useState<ClariseModelProfile>("balanced");

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey);
      if (stored === "balanced" || stored === "quality" || stored === "budget") {
        setProfile(stored);
      }
    } catch {
      /* ignore */
    }
  }, [setProfile, storageKey]);

  useEffect(() => {
    try {
      window.localStorage.setItem(storageKey, profile);
    } catch {
      /* ignore */
    }
  }, [profile, storageKey]);

  return [profile, setProfile];
}

function artifactLabel(kind: string): string {
  if (kind === "codebase_map") return "Codebase map";
  if (kind === "milestone") return "Milestone";
  if (kind === "requirements") return "Requirement";
  if (kind === "plan") return "Plan";
  if (kind === "decision") return "Decision";
  return "Task brief";
}

function isArtifactResultPayload(value: unknown): value is { artifact: ArtifactResult } {
  return isRecord(value) && isArtifact(value.artifact);
}

function isArtifact(value: unknown): value is ArtifactResult {
  return (
    isRecord(value) &&
    typeof value.kind === "string" &&
    typeof value.type === "string" &&
    typeof value.id === "string" &&
    typeof value.title === "string" &&
    typeof value.status === "string" &&
    typeof value.href === "string"
  );
}

function isArtifactFailure(value: unknown): value is ArtifactFailure {
  return (
    isRecord(value) &&
    typeof value.artifactKind === "string" &&
    typeof value.title === "string" &&
    typeof value.error === "string"
  );
}

function isFallbackPayload(value: unknown): value is { reason: string } {
  return isRecord(value) && typeof value.reason === "string";
}

function isMissingFieldsPayload(
  value: unknown,
): value is { fields: { kind: string; field: string }[] } {
  return (
    isRecord(value) &&
    Array.isArray(value.fields) &&
    value.fields.every(
      (field) =>
        isRecord(field) &&
        typeof field.kind === "string" &&
        typeof field.field === "string",
    )
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
