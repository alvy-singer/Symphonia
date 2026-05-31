"use client";

import { useChat, type UIMessage } from "@ai-sdk/react";
import { createAssistantStream } from "assistant-stream";
import {
  AssistantRuntimeProvider,
  AttachmentPrimitive,
  ComposerPrimitive,
  ThreadListItemPrimitive,
  ThreadListPrimitive,
  ThreadPrimitive,
  useAui,
  useAuiState,
  useComposer,
  useComposerRuntime,
  useRemoteThreadListRuntime,
  type Attachment,
  type DataMessagePart,
  type ExportedMessageRepository,
  type ExportedMessageRepositoryItem,
  type FileMessagePart,
  type ImageMessagePart,
  type MessageFormatAdapter,
  type MessageFormatRepository,
  type MessageStorageEntry,
  type MessageState,
  type ReasoningMessagePart,
  type RemoteThreadListAdapter,
  type SourceMessagePart,
  type ThreadHistoryAdapter,
  type ThreadMessage,
  type ToolCallMessagePart,
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
  BookOpen,
  Brain,
  ChevronDown,
  CheckCircle2,
  Code2,
  Copy,
  File as FileIcon,
  FileText,
  ImageIcon,
  Info,
  Landmark,
  Link2,
  ListChecks,
  Loader2,
  Menu,
  MessageSquareText,
  Milestone,
  Paperclip,
  Plus,
  Send,
  ShieldCheck,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  Trash2,
  X,
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
import { ProgressTracker, type ProgressStep } from "@/components/tool-ui/progress-tracker";
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

type ClariseToolCall = {
  name: "create_private_artifact";
  artifactKind: string;
  title: string;
};

type ClariseDone = {
  createdCount: number;
  failedCount: number;
};

type ClariseDataTypes = {
  artifact_result: { artifact: ArtifactResult };
  artifact_failure: ArtifactFailure;
  missing_fields: { fields: { kind: string; field: string }[] };
  tool_call: ClariseToolCall;
  done: ClariseDone;
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

const PROMPT_SUGGESTIONS = [
  {
    label: "Map this repo",
    prompt: "/codebase Create a private codebase map for this repository.",
  },
  {
    label: "Plan a feature",
    prompt:
      "/new-project Create a private milestone, requirements, plan, and first task brief.",
  },
  {
    label: "Verify work",
    prompt: "/verify-work Prepare a verification task brief for the current changes.",
  },
  {
    label: "Record decision",
    prompt: "/decision Capture a private decision with options and recommendation.",
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

        <ClariseThreadSidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

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

              <ThreadPrimitive.ViewportFooter className="sticky bottom-0 z-10 -mx-4 mt-4 sm:-mx-6">
                <div className="pointer-events-none flex justify-center pb-2">
                  <ThreadPrimitive.ScrollToBottom
                    behavior="smooth"
                    aria-label="Scroll to latest message"
                    className="pointer-events-auto grid h-9 w-9 place-items-center rounded-full border bg-card text-muted-foreground shadow-[var(--elevation-card)] transition hover:bg-accent hover:text-foreground disabled:hidden"
                  >
                    <ChevronDown className="h-4 w-4" />
                  </ThreadPrimitive.ScrollToBottom>
                </div>
                <ClariseComposer />
              </ThreadPrimitive.ViewportFooter>
            </ThreadPrimitive.Viewport>
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

function ClariseThreadSidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  const threadCount = useAuiState((state) => state.threads.threadIds.length);
  const isLoading = useAuiState((state) => state.threads.isLoading);

  return (
    <aside
      className={cn(
        "fixed inset-y-0 left-0 z-40 flex w-[19rem] max-w-[86vw] flex-col border-r bg-sidebar text-sidebar-foreground transition-transform md:static md:z-auto md:max-w-none md:translate-x-0",
        open ? "translate-x-0" : "-translate-x-full",
      )}
    >
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
  const isSystem = message.role === "system";
  const text = message.content
    .flatMap((part) => (part.type === "text" ? [part.text] : []))
    .join("\n\n");
  const visibleText = shouldShowClariseMessageText(text) ? text : "";
  const reasoningParts = message.content.flatMap((part) =>
    isReasoningMessagePart(part) ? [part] : [],
  );
  const imageParts = message.content.flatMap((part) =>
    isImageMessagePart(part) ? [part] : [],
  );
  const fileParts = message.content.flatMap((part) =>
    isFileMessagePart(part) ? [part] : [],
  );
  const sourceParts = message.content.flatMap((part) =>
    isSourceMessagePart(part) ? [part] : [],
  );
  const messageToolCalls = message.content.flatMap((part) =>
    isToolCallMessagePart(part) ? [part] : [],
  );
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
  const toolCalls = dataParts.flatMap((part) =>
    part.name === "tool_call" && isClariseToolCall(part.data) ? [part.data] : [],
  );
  const missingFields = dataParts.find(
    (part) => part.name === "missing_fields" && isMissingFieldsPayload(part.data),
  );
  const done = dataParts.find((part) => part.name === "done" && isDonePayload(part.data));
  const running = message.status?.type === "running";
  const progressSteps = clariseProgressSteps({
    artifacts,
    done: done && isDonePayload(done.data) ? done.data : undefined,
    failures,
    hasMissingFields: Boolean(
      missingFields &&
        isMissingFieldsPayload(missingFields.data) &&
        missingFields.data.fields.length > 0,
    ),
    isRunning: running,
    toolCalls,
  });

  return (
    <div className={cn("flex", isUser ? "justify-end" : isSystem ? "justify-center" : "justify-start")}>
      <div
        className={cn(
          "max-w-[min(42rem,100%)] rounded-[10px] px-4 py-3 text-[14px] leading-6",
          isUser
            ? "bg-primary text-primary-foreground"
            : isSystem
              ? "border bg-muted/50 text-muted-foreground"
              : "border bg-card text-foreground shadow-[var(--elevation-card)]",
        )}
      >
        <div className="space-y-3">
          {visibleText && (
            isSystem ? (
              <ClariseSystemMessage>{visibleText}</ClariseSystemMessage>
            ) : (
              <ClariseMarkdown content={visibleText} inverted={isUser} />
            )
          )}

          {reasoningParts.length > 0 && (
            <ClariseReasoning parts={reasoningParts} />
          )}

          {imageParts.length > 0 && <ClariseImages images={imageParts} />}

          {fileParts.length > 0 && <ClariseFiles files={fileParts} />}

          {sourceParts.length > 0 && <ClariseSources sources={sourceParts} />}

          {messageToolCalls.length > 0 && <ClariseToolParts tools={messageToolCalls} />}

          {running && <ClariseThinkingBar />}

          {progressSteps.length > 0 && (
            <div className="mt-1">
              <ProgressTracker
                id={`clarise-progress-${message.id}`}
                steps={progressSteps}
                className="max-w-full min-w-0"
              />
            </div>
          )}

          {artifacts.length > 0 && (
            <ClariseSources
              sources={artifacts.map((artifact) => artifactToSource(artifact))}
            />
          )}

          {!isUser && !isSystem && (
            <ClariseFeedbackBar messageId={message.id} text={visibleText} />
          )}
        </div>
      </div>
    </div>
  );
}

function ClariseComposer() {
  const composer = useComposerRuntime();
  const text = useComposer((state) => state.text);
  const isSlashQuery = text.startsWith("/") && !/\s/.test(text);
  const showSuggestions = text.trim().length === 0;
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

        {showSuggestions && !showMenu && (
          <PromptSuggestions
            onSelect={(prompt) => {
              composer.setText(prompt);
            }}
          />
        )}

        <ComposerPrimitive.AttachmentDropzone className="rounded-[12px] border border-transparent transition data-[dragging=true]:border-brand-accent/70 data-[dragging=true]:bg-brand-accent-soft">
          <ComposerPrimitive.Root className="flex flex-col gap-3 rounded-[10px] border bg-card p-3 shadow-[var(--elevation-card)]">
            <ComposerPrimitive.Attachments>
              {({ attachment }) => <ClariseComposerAttachment attachment={attachment} />}
            </ComposerPrimitive.Attachments>

            <div className="flex items-end gap-2 sm:gap-3">
              <ComposerPrimitive.AddAttachment
                multiple
                aria-label="Attach files"
                title="Attach files"
                className="grid h-10 w-10 shrink-0 place-items-center rounded-[8px] border bg-background/55 text-muted-foreground transition hover:bg-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-45"
              >
                <Paperclip className="h-4 w-4" />
              </ComposerPrimitive.AddAttachment>
              <ComposerPrimitive.Input
                rows={2}
                submitMode="enter"
                placeholder="Message Clarise or type / for artifact commands."
                aria-label="Message Clarise"
                addAttachmentOnPaste
                className="max-h-40 min-h-[3.5rem] flex-1 resize-none bg-transparent text-[15px] leading-6 outline-none placeholder:text-muted-foreground/60"
              />
              <ComposerPrimitive.Send
                aria-label="Send"
                className="grid h-10 w-10 shrink-0 place-items-center rounded-[8px] bg-primary text-primary-foreground transition hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-45"
              >
                <Send className="h-4 w-4" />
              </ComposerPrimitive.Send>
            </div>
          </ComposerPrimitive.Root>
        </ComposerPrimitive.AttachmentDropzone>
      </div>
    </div>
  );
}

function PromptSuggestions({ onSelect }: { onSelect: (prompt: string) => void }) {
  return (
    <div className="mb-2 flex flex-wrap gap-2">
      {PROMPT_SUGGESTIONS.map((suggestion) => (
        <button
          key={suggestion.label}
          type="button"
          onMouseDown={(event) => {
            event.preventDefault();
            onSelect(suggestion.prompt);
          }}
          className="rounded-[7px] border bg-card px-3 py-1.5 text-[12px] font-medium text-muted-foreground transition hover:bg-accent hover:text-foreground"
        >
          {suggestion.label}
        </button>
      ))}
    </div>
  );
}

function ClariseComposerAttachment({ attachment }: { attachment: Attachment }) {
  const isImage =
    attachment.type === "image" || Boolean(attachment.contentType?.startsWith("image/"));
  const runningProgress =
    attachment.status.type === "running"
      ? Math.round(
          attachment.status.progress <= 1
            ? attachment.status.progress * 100
            : attachment.status.progress,
        )
      : null;

  return (
    <AttachmentPrimitive.Root className="flex min-w-0 items-center gap-2 rounded-[8px] border bg-background/55 px-2 py-1.5 text-[12px] text-muted-foreground">
      <span className="grid h-7 w-7 shrink-0 place-items-center rounded-[6px] bg-brand-accent-soft text-brand-accent-text">
        {isImage ? <ImageIcon className="h-3.5 w-3.5" /> : <FileIcon className="h-3.5 w-3.5" />}
      </span>
      <span className="min-w-0 flex-1 truncate text-foreground">
        <AttachmentPrimitive.Name />
      </span>
      <span className="hidden shrink-0 text-[11px] sm:inline">
        {runningProgress === null ? attachment.contentType ?? attachment.type : `${runningProgress}%`}
      </span>
      <AttachmentPrimitive.Remove
        aria-label={`Remove ${attachment.name}`}
        title="Remove attachment"
        className="grid h-7 w-7 shrink-0 place-items-center rounded-[6px] text-muted-foreground transition hover:bg-accent hover:text-foreground"
      >
        <X className="h-3.5 w-3.5" />
      </AttachmentPrimitive.Remove>
    </AttachmentPrimitive.Root>
  );
}

type MarkdownBlock =
  | { type: "paragraph"; text: string }
  | { type: "heading"; level: 2 | 3; text: string }
  | { type: "list"; items: string[] }
  | { type: "code"; language?: string; code: string };

function ClariseMarkdown({
  content,
  inverted = false,
}: {
  content: string;
  inverted?: boolean;
}) {
  const blocks = useMemo(() => parseMarkdownBlocks(content), [content]);

  return (
    <div className="space-y-3">
      {blocks.map((block, index) => {
        if (block.type === "code") {
          return (
            <ClariseCodeBlock
              key={`${block.type}-${index}`}
              code={block.code}
              language={block.language}
            />
          );
        }

        if (block.type === "heading") {
          const HeadingTag = block.level === 2 ? "h2" : "h3";
          return (
            <HeadingTag
              key={`${block.type}-${index}`}
              className={cn(
                "break-words font-semibold leading-6",
                block.level === 2 ? "text-[15px]" : "text-[14px]",
              )}
            >
              <InlineMarkdown text={block.text} inverted={inverted} />
            </HeadingTag>
          );
        }

        if (block.type === "list") {
          return (
            <ul key={`${block.type}-${index}`} className="list-disc space-y-1 pl-5">
              {block.items.map((item, itemIndex) => (
                <li key={`${item}-${itemIndex}`} className="break-words">
                  <InlineMarkdown text={item} inverted={inverted} />
                </li>
              ))}
            </ul>
          );
        }

        return (
          <p key={`${block.type}-${index}`} className="whitespace-pre-wrap break-words">
            <InlineMarkdown text={block.text} inverted={inverted} />
          </p>
        );
      })}
    </div>
  );
}

function InlineMarkdown({ text, inverted }: { text: string; inverted: boolean }) {
  const parts = text.split(/(`[^`]+`)/g);

  return (
    <>
      {parts.map((part, index) => {
        if (part.startsWith("`") && part.endsWith("`") && part.length > 1) {
          return (
            <code
              key={`${part}-${index}`}
              className={cn(
                "rounded-[5px] px-1.5 py-0.5 font-mono text-[0.9em]",
                inverted ? "bg-primary-foreground/15" : "bg-muted text-foreground",
              )}
            >
              {part.slice(1, -1)}
            </code>
          );
        }

        return <span key={`${part}-${index}`}>{part}</span>;
      })}
    </>
  );
}

function ClariseCodeBlock({ code, language }: { code: string; language?: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    if (!navigator.clipboard) return;
    await navigator.clipboard.writeText(code);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1200);
  }, [code]);

  return (
    <div className="overflow-hidden rounded-[8px] border bg-background/70">
      <div className="flex min-h-9 items-center justify-between border-b px-3">
        <span className="inline-flex items-center gap-1.5 text-[11px] font-medium uppercase text-muted-foreground">
          <Code2 className="h-3.5 w-3.5" />
          {language || "code"}
        </span>
        <button
          type="button"
          onClick={handleCopy}
          aria-label="Copy code"
          title="Copy code"
          className="grid h-7 w-7 place-items-center rounded-[6px] text-muted-foreground transition hover:bg-accent hover:text-foreground"
        >
          {copied ? <CheckCircle2 className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
        </button>
      </div>
      <pre className="max-h-80 overflow-auto p-3 text-[12px] leading-5">
        <code>{code}</code>
      </pre>
    </div>
  );
}

function ClariseThinkingBar() {
  return (
    <div
      className="flex min-h-10 items-center gap-2 rounded-[8px] border bg-background/55 px-3 text-[12px] text-muted-foreground"
      role="status"
      aria-live="polite"
    >
      <Brain className="h-3.5 w-3.5 text-brand-accent-text" />
      <span className="motion-safe:shimmer shimmer-invert text-foreground">Clarise is thinking</span>
      <span className="ml-auto flex items-center gap-1" aria-hidden="true">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-brand-accent-text" />
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-brand-accent-text [animation-delay:120ms]" />
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-brand-accent-text [animation-delay:240ms]" />
      </span>
    </div>
  );
}

function ClariseReasoning({ parts }: { parts: ReasoningMessagePart[] }) {
  const [open, setOpen] = useState(false);
  const text = parts.map((part) => part.text).join("\n\n").trim();
  if (!text) return null;

  return (
    <div className="rounded-[8px] border bg-background/55 text-[13px]">
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center gap-2 px-3 py-2 text-left text-muted-foreground transition hover:bg-accent hover:text-foreground"
        aria-expanded={open}
      >
        <Brain className="h-3.5 w-3.5" />
        <span className="font-medium">Reasoning</span>
        <ChevronDown
          className={cn("ml-auto h-3.5 w-3.5 transition-transform", open && "rotate-180")}
        />
      </button>
      {open && (
        <div className="border-t px-3 py-2 text-muted-foreground">
          <ClariseMarkdown content={text} />
        </div>
      )}
    </div>
  );
}

function ClariseSystemMessage({ children }: { children: string }) {
  return (
    <div className="flex items-start gap-2 text-[13px] text-muted-foreground">
      <Info className="mt-1 h-3.5 w-3.5 shrink-0" />
      <p className="whitespace-pre-wrap break-words">{children}</p>
    </div>
  );
}

function ClariseImages({ images }: { images: ImageMessagePart[] }) {
  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {images.map((image, index) => (
        <figure
          key={`${image.filename ?? "image"}-${index}`}
          className="overflow-hidden rounded-[8px] border bg-background/55"
        >
          <img
            src={image.image}
            alt={image.filename ?? "Image attachment"}
            className="max-h-80 w-full object-contain"
          />
          {image.filename && (
            <figcaption className="border-t px-3 py-2 text-[12px] text-muted-foreground">
              {image.filename}
            </figcaption>
          )}
        </figure>
      ))}
    </div>
  );
}

function ClariseFiles({ files }: { files: FileMessagePart[] }) {
  return (
    <div className="grid gap-2">
      {files.map((file, index) => {
        const filename = file.filename ?? `Attachment ${index + 1}`;
        const canDownload = file.data.startsWith("data:");

        const content = (
          <>
            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[6px] bg-brand-accent-soft text-brand-accent-text">
              <FileIcon className="h-4 w-4" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[13px] font-medium text-foreground">
                {filename}
              </span>
              <span className="block truncate text-[11px] text-muted-foreground">
                {file.mimeType}
              </span>
            </span>
          </>
        );

        return canDownload ? (
          <a
            key={`${filename}-${index}`}
            href={file.data}
            download={filename}
            className="flex min-w-0 items-center gap-3 rounded-[8px] border bg-background/55 p-3 transition hover:bg-accent"
          >
            {content}
          </a>
        ) : (
          <div
            key={`${filename}-${index}`}
            className="flex min-w-0 items-center gap-3 rounded-[8px] border bg-background/55 p-3"
          >
            {content}
          </div>
        );
      })}
    </div>
  );
}

type ClariseRenderedSource =
  | SourceMessagePart
  | {
      type: "source";
      sourceType: "url";
      id: string;
      url: string;
      title: string;
      label: string;
      privateArtifact: true;
    };

function ClariseSources({ sources }: { sources: ClariseRenderedSource[] }) {
  if (sources.length === 0) return null;

  return (
    <div className="grid gap-2">
      <div className="flex items-center gap-2 text-[12px] font-medium text-muted-foreground">
        <BookOpen className="h-3.5 w-3.5" />
        Sources
      </div>
      {sources.map((source) => (
        <ClariseSourceItem key={source.id} source={source} />
      ))}
    </div>
  );
}

function ClariseSourceItem({ source }: { source: ClariseRenderedSource }) {
  const title =
    source.title ??
    (source.sourceType === "document" ? source.filename ?? "Document source" : source.url);
  const label =
    "privateArtifact" in source
      ? source.label
      : source.sourceType === "document"
        ? source.mediaType
        : source.url;
  const content = (
    <>
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[6px] bg-brand-accent-soft text-brand-accent-text">
        {"privateArtifact" in source ? <FileText className="h-4 w-4" /> : <Link2 className="h-4 w-4" />}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[13px] font-medium text-foreground">{title}</span>
        <span className="block truncate text-[11px] text-muted-foreground">{label}</span>
      </span>
      {"privateArtifact" in source && (
        <span className="shrink-0 rounded-full border border-emerald-500/30 px-2 py-0.5 text-[10px] font-medium uppercase text-emerald-300">
          Private
        </span>
      )}
      {"privateArtifact" in source && (
        <span className="hidden shrink-0 text-[12px] font-medium text-muted-foreground sm:inline">
          View in workspace
        </span>
      )}
    </>
  );

  if (source.sourceType === "url") {
    if (source.url.startsWith("/")) {
      return (
        <Link
          href={source.url}
          className="flex min-w-0 items-center gap-3 rounded-[8px] border bg-background/55 p-3 transition hover:bg-accent"
        >
          {content}
          <ArrowRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
        </Link>
      );
    }

    return (
      <a
        href={source.url}
        target="_blank"
        rel="noreferrer"
        className="flex min-w-0 items-center gap-3 rounded-[8px] border bg-background/55 p-3 transition hover:bg-accent"
      >
        {content}
        <ArrowRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
      </a>
    );
  }

  return (
    <div className="flex min-w-0 items-center gap-3 rounded-[8px] border bg-background/55 p-3">
      {content}
    </div>
  );
}

function ClariseToolParts({ tools }: { tools: ToolCallMessagePart[] }) {
  return (
    <div className="grid gap-2">
      {tools.map((tool) => {
        const status = tool.isError ? "Failed" : tool.result === undefined ? "Running" : "Complete";
        return (
          <div
            key={tool.toolCallId}
            className="flex min-w-0 items-center gap-3 rounded-[8px] border bg-background/55 p-3"
          >
            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[6px] bg-brand-accent-soft text-brand-accent-text">
              <ListChecks className="h-4 w-4" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-[13px] font-medium text-foreground">
                {tool.toolName}
              </span>
              <span className="block text-[11px] text-muted-foreground">{status}</span>
            </span>
          </div>
        );
      })}
    </div>
  );
}

function ClariseFeedbackBar({ messageId, text }: { messageId: string; text: string }) {
  const [feedback, setFeedback] = useState<"positive" | "negative" | null>(null);
  const [copied, setCopied] = useState(false);
  const canCopy = text.trim().length > 0;

  const handleCopy = useCallback(async () => {
    if (!canCopy || !navigator.clipboard) return;
    await navigator.clipboard.writeText(text);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1200);
  }, [canCopy, text]);

  return (
    <div
      className="flex items-center gap-1 border-t pt-2"
      data-message-id={messageId}
    >
      <button
        type="button"
        aria-label="Mark response helpful"
        title="Helpful"
        onClick={() => setFeedback((value) => (value === "positive" ? null : "positive"))}
        className={cn(
          "grid h-8 w-8 place-items-center rounded-[7px] text-muted-foreground transition hover:bg-accent hover:text-foreground",
          feedback === "positive" && "bg-brand-accent-soft text-brand-accent-text",
        )}
      >
        <ThumbsUp className="h-3.5 w-3.5" />
      </button>
      <button
        type="button"
        aria-label="Mark response unhelpful"
        title="Needs work"
        onClick={() => setFeedback((value) => (value === "negative" ? null : "negative"))}
        className={cn(
          "grid h-8 w-8 place-items-center rounded-[7px] text-muted-foreground transition hover:bg-accent hover:text-foreground",
          feedback === "negative" && "bg-amber-500/10 text-amber-300",
        )}
      >
        <ThumbsDown className="h-3.5 w-3.5" />
      </button>
      <button
        type="button"
        aria-label="Copy response"
        title="Copy response"
        onClick={handleCopy}
        disabled={!canCopy}
        className="grid h-8 w-8 place-items-center rounded-[7px] text-muted-foreground transition hover:bg-accent hover:text-foreground disabled:cursor-not-allowed disabled:opacity-45"
      >
        {copied ? <CheckCircle2 className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
      </button>
    </div>
  );
}

function parseMarkdownBlocks(content: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const lines = content.replace(/\r\n/g, "\n").split("\n");
  let textBuffer: string[] = [];
  let codeBuffer: string[] | null = null;
  let codeLanguage: string | undefined;

  const flushText = () => {
    const text = textBuffer.join("\n").trim();
    textBuffer = [];
    if (!text) return;
    blocks.push(...parseMarkdownTextBlocks(text));
  };

  for (const line of lines) {
    const fence = line.match(/^```([\w-]+)?\s*$/);
    if (fence) {
      if (codeBuffer) {
        blocks.push({
          type: "code",
          language: codeLanguage,
          code: codeBuffer.join("\n").replace(/\n$/, ""),
        });
        codeBuffer = null;
        codeLanguage = undefined;
      } else {
        flushText();
        codeBuffer = [];
        codeLanguage = fence[1];
      }
      continue;
    }

    if (codeBuffer) {
      codeBuffer.push(line);
    } else {
      textBuffer.push(line);
    }
  }

  if (codeBuffer) {
    blocks.push({
      type: "code",
      language: codeLanguage,
      code: codeBuffer.join("\n").replace(/\n$/, ""),
    });
  }
  flushText();

  return blocks;
}

function parseMarkdownTextBlocks(content: string): MarkdownBlock[] {
  return content
    .split(/\n{2,}/)
    .map((chunk) => chunk.trim())
    .filter(Boolean)
    .flatMap((chunk): MarkdownBlock[] => {
      const lines = chunk.split("\n").map((line) => line.trim()).filter(Boolean);
      if (lines.length === 1) {
        const heading = lines[0]?.match(/^(#{2,3})\s+(.+)$/);
        if (heading) {
          return [
            {
              type: "heading",
              level: heading[1].length === 2 ? 2 : 3,
              text: heading[2],
            },
          ];
        }
      }

      const listItems = lines.flatMap((line) => {
        const match = line.match(/^(?:[-*]|\d+[.)])\s+(.+)$/);
        return match ? [match[1]] : [];
      });
      if (listItems.length === lines.length && listItems.length > 0) {
        return [{ type: "list", items: listItems }];
      }

      return [{ type: "paragraph", text: chunk }];
    });
}

function artifactToSource(artifact: ArtifactResult): ClariseRenderedSource {
  return {
    type: "source",
    sourceType: "url",
    id: `${artifact.type}:${artifact.id}`,
    url: artifact.href,
    title: artifact.title,
    label: artifactLabel(artifact.kind),
    privateArtifact: true,
  };
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

function shouldShowClariseMessageText(text: string): boolean {
  return !text.trim().toLowerCase().startsWith("missing fields:");
}

function clariseProgressSteps({
  artifacts,
  done,
  failures,
  hasMissingFields,
  isRunning,
  toolCalls,
}: {
  artifacts: ArtifactResult[];
  done?: ClariseDone;
  failures: ArtifactFailure[];
  hasMissingFields: boolean;
  isRunning: boolean;
  toolCalls: ClariseToolCall[];
}): ProgressStep[] {
  const hasArtifactActivity = toolCalls.length > 0 || artifacts.length > 0 || failures.length > 0;
  const shouldShowProgress = isRunning || hasArtifactActivity || hasMissingFields;

  if (!shouldShowProgress) return [];

  const steps: ProgressStep[] = [
    {
      id: "shape-request",
      label: "Shape private workspace request",
      status:
        hasArtifactActivity || hasMissingFields || done
          ? "completed"
          : isRunning
            ? "in-progress"
            : "pending",
    },
  ];

  if (hasMissingFields && !hasArtifactActivity) {
    steps.push({
      id: "collect-missing-fields",
      label: "Collect missing details",
      status: "in-progress",
      description: "Clarise needs a little more structure before writing workspace files.",
    });
    return steps;
  }

  for (const [index, toolCall] of toolCalls.entries()) {
    const result = artifacts.find((artifact) => isSameArtifactStep(artifact, toolCall));
    const failure = failures.find((item) => isSameFailureStep(item, toolCall));
    const status: ProgressStep["status"] = failure
      ? "failed"
      : result
        ? "completed"
        : isRunning
          ? "in-progress"
          : "pending";

    steps.push({
      id: `artifact-${toolCall.artifactKind}-${index}-${slugifyToolId(toolCall.title)}`,
      label: `Create ${artifactLabel(toolCall.artifactKind).toLowerCase()}`,
      status,
      description: result?.title ?? failure?.error ?? toolCall.title,
    });
  }

  if (toolCalls.length === 0 && isRunning) {
    steps.push({
      id: "prepare-artifacts",
      label: "Prepare private artifacts",
      status: "pending",
    });
  }

  return steps;
}

function isSameArtifactStep(artifact: ArtifactResult, toolCall: ClariseToolCall): boolean {
  return artifact.kind === toolCall.artifactKind && artifact.title === toolCall.title;
}

function isSameFailureStep(failure: ArtifactFailure, toolCall: ClariseToolCall): boolean {
  return failure.artifactKind === toolCall.artifactKind && failure.title === toolCall.title;
}

function slugifyToolId(value: string): string {
  return (
    value
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 48) || "untitled"
  );
}

function isReasoningMessagePart(value: unknown): value is ReasoningMessagePart {
  return isRecord(value) && value.type === "reasoning" && typeof value.text === "string";
}

function isImageMessagePart(value: unknown): value is ImageMessagePart {
  return isRecord(value) && value.type === "image" && typeof value.image === "string";
}

function isFileMessagePart(value: unknown): value is FileMessagePart {
  return (
    isRecord(value) &&
    value.type === "file" &&
    typeof value.data === "string" &&
    typeof value.mimeType === "string"
  );
}

function isSourceMessagePart(value: unknown): value is SourceMessagePart {
  if (!isRecord(value) || value.type !== "source") return false;
  if (value.sourceType === "url") {
    return typeof value.id === "string" && typeof value.url === "string";
  }
  return (
    value.sourceType === "document" &&
    typeof value.id === "string" &&
    typeof value.title === "string" &&
    typeof value.mediaType === "string"
  );
}

function isToolCallMessagePart(value: unknown): value is ToolCallMessagePart {
  return (
    isRecord(value) &&
    value.type === "tool-call" &&
    typeof value.toolCallId === "string" &&
    typeof value.toolName === "string"
  );
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

function isClariseToolCall(value: unknown): value is ClariseToolCall {
  return (
    isRecord(value) &&
    value.name === "create_private_artifact" &&
    typeof value.artifactKind === "string" &&
    typeof value.title === "string"
  );
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

function isDonePayload(value: unknown): value is ClariseDone {
  return (
    isRecord(value) &&
    typeof value.createdCount === "number" &&
    typeof value.failedCount === "number"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
