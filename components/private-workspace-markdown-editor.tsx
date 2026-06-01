"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  AlertTriangle,
  Bold,
  Check,
  CircleDot,
  Code,
  FileText,
  Heading1,
  Heading2,
  Heading3,
  ImagePlus,
  Italic,
  Link2,
  List as ListIcon,
  ListChecks,
  ListOrdered,
  Loader2,
  MoreHorizontal,
  Quote,
  Redo2,
  Smile,
  Table2,
  Trash2,
  Type,
  Undo2,
  X,
} from "lucide-react";
import {
  defaultValueCtx,
  editorViewCtx,
  editorViewOptionsCtx,
  Editor,
  remarkStringifyOptionsCtx,
  rootCtx,
  type Editor as MilkdownEditor,
} from "@milkdown/kit/core";
import { commonmark } from "@milkdown/kit/preset/commonmark";
import { gfm } from "@milkdown/kit/preset/gfm";
import { clipboard } from "@milkdown/kit/plugin/clipboard";
import { cursor } from "@milkdown/kit/plugin/cursor";
import { history, historyProviderConfig, redoCommand, undoCommand } from "@milkdown/kit/plugin/history";
import { indent } from "@milkdown/kit/plugin/indent";
import { listener, listenerCtx } from "@milkdown/kit/plugin/listener";
import { trailing } from "@milkdown/kit/plugin/trailing";
import { callCommand, insert } from "@milkdown/kit/utils";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { COMMON_ICONS, COVERS, type DocPage } from "@/lib/docs-store";
import {
  composeWithLegacyFrontmatter,
  normalizeMilkdownMarkdown,
  PRIVATE_WORKSPACE_SLASH_COMMANDS,
  splitLegacyFrontmatter,
  type PrivateWorkspaceSlashCommand,
} from "@/lib/private-workspace-markdown";
import { cn } from "@/lib/utils";

type EditorPatch = Partial<
  Pick<DocPage, "title" | "body" | "icon" | "cover" | "published">
>;

type SaveState = "saved" | "dirty" | "saving" | "failed" | "read-only";

interface SavedSnapshot {
  title: string;
  body: string;
  icon?: string;
  cover?: string;
  published: boolean;
}

interface Props {
  page: DocPage;
  onPersist: (patch: EditorPatch) => void | Promise<void>;
  onPersistError?: (error: unknown) => void;
  readOnly?: boolean;
  actionsMenuContent?: ReactNode;
  toolbarAction?: ReactNode;
  stateRevision?: string | number;
  belowBodySlot?: ReactNode;
  bodyPlaceholder?: string;
}

export function PrivateWorkspaceMarkdownEditor({
  page,
  onPersist,
  onPersistError,
  readOnly = false,
  actionsMenuContent,
  toolbarAction,
  stateRevision,
  belowBodySlot,
  bodyPlaceholder,
}: Props) {
  const rootRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<MilkdownEditor | null>(null);
  const editorReadyRef = useRef(false);
  const frontmatterRef = useRef<string | null>(null);
  const latestEditableBodyRef = useRef("");
  const draftRef = useRef<SavedSnapshot>(snapshotFromPage(page));
  const lastSavedRef = useRef<SavedSnapshot>(snapshotFromPage(page));
  const persistTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const savingRef = useRef(false);
  const rerunSaveRef = useRef(false);
  const saveNowRef = useRef<() => void>(() => undefined);

  const [title, setTitle] = useState(page.title);
  const [icon, setIcon] = useState(page.icon);
  const [cover, setCover] = useState(page.cover);
  const [published, setPublished] = useState(page.published);
  const [savedAt, setSavedAt] = useState<number>(page.updatedAt);
  const [saveState, setSaveState] = useState<SaveState>(readOnly ? "read-only" : "saved");
  const [bodyEmpty, setBodyEmpty] = useState(splitLegacyFrontmatter(page.body).body.trim() === "");
  const [editorLoading, setEditorLoading] = useState(true);
  const [editorError, setEditorError] = useState<string | null>(null);
  const [iconOpen, setIconOpen] = useState(false);
  const [coverOpen, setCoverOpen] = useState(false);
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [slashIndex, setSlashIndex] = useState(0);

  const coverClassName = useMemo(
    () => COVERS.find((item) => item.id === cover)?.className,
    [cover],
  );

  const filteredSlashCommands = useMemo(() => {
    const query = slashQuery.trim().toLowerCase();
    if (!query) return PRIVATE_WORKSPACE_SLASH_COMMANDS;
    return PRIVATE_WORKSPACE_SLASH_COMMANDS.filter((command) =>
      `${command.label} ${command.description}`.toLowerCase().includes(query),
    );
  }, [slashQuery]);

  const markDraft = useCallback((patch: EditorPatch) => {
    const next = {
      ...draftRef.current,
      ...patch,
      title: patch.title ?? draftRef.current.title,
      body: patch.body ?? draftRef.current.body,
      published: patch.published ?? draftRef.current.published,
    };
    draftRef.current = next;

    if (snapshotsEqual(next, lastSavedRef.current)) {
      setSaveState(readOnly ? "read-only" : "saved");
      return false;
    }

    if (!readOnly) setSaveState("dirty");
    return true;
  }, [readOnly]);

  const saveNow = useCallback(async () => {
    if (readOnly) return;

    if (persistTimerRef.current) {
      clearTimeout(persistTimerRef.current);
      persistTimerRef.current = null;
    }

    if (savingRef.current) {
      rerunSaveRef.current = true;
      return;
    }

    const snapshotAtStart = { ...draftRef.current };
    const patch = snapshotToPatch(snapshotAtStart);
    if (snapshotsEqual(draftRef.current, lastSavedRef.current)) {
      setSaveState("saved");
      return;
    }

    savingRef.current = true;
    setSaveState("saving");

    try {
      await onPersist(patch);
      lastSavedRef.current = snapshotAtStart;
      setSavedAt(Date.now());

      if (rerunSaveRef.current || !snapshotsEqual(draftRef.current, lastSavedRef.current)) {
        rerunSaveRef.current = false;
        savingRef.current = false;
        persistTimerRef.current = setTimeout(() => saveNowRef.current(), 0);
        return;
      }

      setSaveState("saved");
    } catch (error) {
      setSaveState("failed");
      onPersistError?.(error);
    } finally {
      savingRef.current = false;
    }
  }, [onPersist, onPersistError, readOnly]);

  useEffect(() => {
    saveNowRef.current = () => {
      void saveNow();
    };
  }, [saveNow]);

  const schedulePersist = useCallback((delay = 550) => {
    if (readOnly) return;
    if (persistTimerRef.current) clearTimeout(persistTimerRef.current);
    persistTimerRef.current = setTimeout(() => saveNowRef.current(), delay);
  }, [readOnly]);

  const updateDraft = useCallback((patch: EditorPatch, delay?: number) => {
    if (readOnly) return;
    const changed = markDraft(patch);
    if (changed) schedulePersist(delay);
  }, [markDraft, readOnly, schedulePersist]);

  useEffect(() => {
    const split = splitLegacyFrontmatter(page.body);
    frontmatterRef.current = split.frontmatter;
    latestEditableBodyRef.current = split.body;

    const nextSnapshot = snapshotFromPage(page);
    draftRef.current = nextSnapshot;
    lastSavedRef.current = nextSnapshot;

    setTitle(page.title);
    setIcon(page.icon);
    setCover(page.cover);
    setPublished(page.published);
    setSavedAt(page.updatedAt);
    setBodyEmpty(split.body.trim() === "");
    setSaveState(readOnly ? "read-only" : "saved");
    setEditorError(null);
    setSlashOpen(false);
    setSlashQuery("");
    setSlashIndex(0);
  }, [page.body, page.cover, page.icon, page.id, page.published, page.title, page.updatedAt, readOnly, stateRevision]);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;

    let disposed = false;
    let editor: MilkdownEditor | null = null;
    const editableBody = splitLegacyFrontmatter(page.body).body;

    editorReadyRef.current = false;
    setEditorLoading(true);
    setEditorError(null);
    root.innerHTML = "";

    Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root);
        ctx.set(defaultValueCtx, editableBody);
        ctx.set(historyProviderConfig.key, { depth: 200, newGroupDelay: 500 });
        ctx.update(remarkStringifyOptionsCtx, (prev) => ({
          ...prev,
          bullet: "-" as const,
          fences: true,
          incrementListMarker: false,
        }));
        ctx.update(editorViewOptionsCtx, (prev) => ({
          ...prev,
          editable: () => !readOnly,
        }));
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown, prevMarkdown) => {
          if (disposed || !editorReadyRef.current || markdown === prevMarkdown) return;
          const normalized = normalizeMilkdownMarkdown(markdown);
          latestEditableBodyRef.current = normalized;
          setBodyEmpty(normalized.trim() === "");
          const body = composeWithLegacyFrontmatter(frontmatterRef.current, normalized);
          updateDraft({ body });
        });
      })
      .use(commonmark)
      .use(gfm)
      .use(history)
      .use(listener)
      .use(clipboard)
      .use(cursor)
      .use(indent)
      .use(trailing)
      .create()
      .then((created) => {
        if (disposed) {
          void created.destroy();
          return;
        }
        editor = created;
        editorRef.current = created;
        editorReadyRef.current = true;
        setEditorLoading(false);
      })
      .catch((error: unknown) => {
        if (disposed) return;
        setEditorLoading(false);
        setEditorError(error instanceof Error ? error.message : "Could not start editor");
      });

    return () => {
      disposed = true;
      editorReadyRef.current = false;
      editorRef.current = null;
      if (persistTimerRef.current) {
        clearTimeout(persistTimerRef.current);
        persistTimerRef.current = null;
      }
      if (editor) void editor.destroy();
      root.innerHTML = "";
    };
  }, [page.body, page.id, readOnly, stateRevision, updateDraft]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void saveNow();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [saveNow]);

  const insertMarkdown = useCallback((markdown: string, inline = false) => {
    const editor = editorRef.current;
    if (!editor || readOnly) return;
    editor.action(insert(markdown, inline));
    editor.action((ctx) => ctx.get(editorViewCtx).focus());
  }, [readOnly]);

  const runMilkdownCommand = useCallback((command: "undo" | "redo") => {
    const editor = editorRef.current;
    if (!editor || readOnly) return;
    editor.action(callCommand(command === "undo" ? undoCommand.key : redoCommand.key));
    editor.action((ctx) => ctx.get(editorViewCtx).focus());
  }, [readOnly]);

  const applySlashCommand = useCallback((command: PrivateWorkspaceSlashCommand) => {
    insertMarkdown(command.markdown, command.inline);
    setSlashOpen(false);
    setSlashQuery("");
    setSlashIndex(0);
  }, [insertMarkdown]);

  const onEditorKeyDownCapture = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (readOnly) return;

    if (!slashOpen && event.key === "/" && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault();
      setSlashOpen(true);
      setSlashQuery("");
      setSlashIndex(0);
      return;
    }

    if (!slashOpen) return;

    if (event.key === "Escape") {
      event.preventDefault();
      setSlashOpen(false);
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setSlashIndex((index) => (index + 1) % Math.max(filteredSlashCommands.length, 1));
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setSlashIndex(
        (index) =>
          (index - 1 + Math.max(filteredSlashCommands.length, 1)) %
          Math.max(filteredSlashCommands.length, 1),
      );
      return;
    }

    if (event.key === "Enter" && filteredSlashCommands[slashIndex]) {
      event.preventDefault();
      applySlashCommand(filteredSlashCommands[slashIndex]);
      return;
    }

    if (event.key === "Backspace") {
      event.preventDefault();
      setSlashQuery((query) => query.slice(0, -1));
      setSlashIndex(0);
      return;
    }

    if (event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault();
      setSlashQuery((query) => `${query}${event.key}`);
      setSlashIndex(0);
    }
  };

  const updateTitle = (nextTitle: string) => {
    setTitle(nextTitle);
    updateDraft({ title: nextTitle });
  };

  const updateIcon = (nextIcon: string | undefined) => {
    setIcon(nextIcon);
    setIconOpen(false);
    updateDraft({ icon: nextIcon });
  };

  const updateCover = (nextCover: string | undefined) => {
    setCover(nextCover);
    setCoverOpen(false);
    updateDraft({ cover: nextCover });
  };

  const togglePublished = () => {
    const next = !published;
    setPublished(next);
    updateDraft({ published: next }, 0);
  };

  return (
    <div className="flex h-full flex-col">
      <div className="relative">
        {cover ? (
          <div className={cn("h-36 w-full sm:h-44", coverClassName)} aria-hidden />
        ) : (
          <div className="h-6" aria-hidden />
        )}
        <div className="absolute right-3 top-3 flex items-center gap-1.5">
          {!readOnly && cover ? (
            <button
              type="button"
              onClick={() => updateCover(undefined)}
              className="inline-flex items-center gap-1 rounded-md border bg-background/80 px-2 py-1 text-[11px] backdrop-blur hover:bg-background"
            >
              <X className="h-3 w-3" /> Remove cover
            </button>
          ) : null}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl px-4 pb-16 sm:px-8">
          <div className={cn("flex items-center gap-1.5", cover ? "-mt-6" : "mt-3")}>
            <div className="relative">
              <button
                type="button"
                onClick={() => {
                  if (!readOnly) setIconOpen((open) => !open);
                }}
                aria-label={icon ? "Change page icon" : "Add page icon"}
                disabled={readOnly}
                className={cn(
                  "grid place-items-center rounded-md border bg-background text-2xl transition disabled:cursor-not-allowed disabled:opacity-70",
                  icon ? "h-12 w-12" : "h-7 px-2 text-[11px] text-muted-foreground hover:text-foreground",
                )}
              >
                {icon ?? (
                  <span className="inline-flex items-center gap-1">
                    <Smile className="h-3.5 w-3.5" /> Add icon
                  </span>
                )}
              </button>
              {iconOpen ? (
                <div
                  role="dialog"
                  aria-label="Pick an icon"
                  className="absolute z-20 mt-1 w-60 rounded-lg border bg-popover p-2 shadow-xl"
                >
                  <div className="grid grid-cols-6 gap-1">
                    {COMMON_ICONS.map((item) => (
                      <button
                        key={item}
                        type="button"
                        onClick={() => updateIcon(item)}
                        className="grid h-8 place-items-center rounded text-lg hover:bg-accent"
                        aria-label={`Use icon ${item}`}
                      >
                        {item}
                      </button>
                    ))}
                  </div>
                  <div className="mt-2 flex items-center justify-between border-t pt-2">
                    <button
                      type="button"
                      onClick={() => updateIcon(undefined)}
                      className="inline-flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground"
                    >
                      <Trash2 className="h-3 w-3" /> Remove
                    </button>
                    <button
                      type="button"
                      onClick={() => setIconOpen(false)}
                      className="text-[11px] text-muted-foreground hover:text-foreground"
                    >
                      Close
                    </button>
                  </div>
                </div>
              ) : null}
            </div>

            {!readOnly && !cover ? (
              <div className="relative">
                <button
                  type="button"
                  onClick={() => setCoverOpen((open) => !open)}
                  className="inline-flex items-center gap-1 rounded-md border bg-background px-2 py-1 text-[11px] text-muted-foreground hover:text-foreground"
                >
                  <ImagePlus className="h-3 w-3" /> Add cover
                </button>
                {coverOpen ? (
                  <div className="absolute z-20 mt-1 w-64 rounded-lg border bg-popover p-2 shadow-xl">
                    <div className="grid grid-cols-3 gap-1.5">
                      {COVERS.map((item) => (
                        <button
                          key={item.id}
                          type="button"
                          onClick={() => updateCover(item.id)}
                          className={cn("h-12 rounded border", item.className)}
                          aria-label={`Use cover ${item.id}`}
                        />
                      ))}
                    </div>
                    <p className="mt-1.5 text-[11px] text-muted-foreground">
                      Private metadata, no upload.
                    </p>
                  </div>
                ) : null}
              </div>
            ) : null}

            <div className="ml-auto flex items-center gap-2">
              <SaveStatus state={saveState} savedAt={savedAt} />
              {toolbarAction ?? (
                <button
                  type="button"
                  onClick={togglePublished}
                  disabled={readOnly || saveState === "saving"}
                  className={cn(
                    "rounded-md border px-2.5 py-1 text-[11px] font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50",
                    published
                      ? "bg-primary text-primary-foreground hover:bg-primary-hover"
                      : "bg-background text-foreground hover:bg-muted",
                  )}
                >
                  {published ? "Published" : "Publish"}
                </button>
              )}
              <Popover>
                <PopoverTrigger asChild>
                  <button
                    type="button"
                    aria-label="Artifact actions"
                    title="Artifact actions"
                    className="grid h-7 w-7 place-items-center rounded-md border text-muted-foreground hover:bg-muted hover:text-foreground"
                  >
                    <MoreHorizontal className="h-3.5 w-3.5" />
                  </button>
                </PopoverTrigger>
                <PopoverContent align="end" className="w-48 p-1">
                  {actionsMenuContent}
                </PopoverContent>
              </Popover>
            </div>
          </div>

          <div className="mt-3">
            <input
              value={title}
              onChange={(event) => updateTitle(event.target.value)}
              placeholder="Untitled"
              aria-label="Artifact title"
              readOnly={readOnly}
              className="w-full bg-transparent text-3xl font-semibold tracking-tight outline-none placeholder:text-muted-foreground/40 read-only:cursor-default"
            />
            <p className="mt-1 text-[11px] text-muted-foreground">
              Private workspace artifact
            </p>
          </div>

          <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-b pb-2">
            <div className="flex flex-wrap items-center gap-0.5">
              <ToolBtn label="Undo" disabled={readOnly} onClick={() => runMilkdownCommand("undo")}>
                <Undo2 className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Redo" disabled={readOnly} onClick={() => runMilkdownCommand("redo")}>
                <Redo2 className="h-3.5 w-3.5" />
              </ToolBtn>
              <span className="mx-1 h-4 w-px bg-border" aria-hidden />
              <ToolBtn label="Title" disabled={readOnly} onClick={() => insertMarkdown("# Title\n\n")}>
                <Heading1 className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Subtitle" disabled={readOnly} onClick={() => insertMarkdown("## Subtitle\n\n")}>
                <Heading2 className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Heading" disabled={readOnly} onClick={() => insertMarkdown("### Heading\n\n")}>
                <Heading3 className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Body text" disabled={readOnly} onClick={() => insertMarkdown("Body text\n\n")}>
                <Type className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Bold" disabled={readOnly} onClick={() => insertMarkdown("**bold**", true)}>
                <Bold className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Italic" disabled={readOnly} onClick={() => insertMarkdown("*italic*", true)}>
                <Italic className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Link" disabled={readOnly} onClick={() => insertMarkdown("[label](https://example.com)", true)}>
                <Link2 className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Artifact link" disabled={readOnly} onClick={() => insertMarkdown("[[decision-001]]", true)}>
                <FileText className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Bullet list" disabled={readOnly} onClick={() => insertMarkdown("- Item\n")}>
                <ListIcon className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Numbered list" disabled={readOnly} onClick={() => insertMarkdown("1. First\n")}>
                <ListOrdered className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Task list" disabled={readOnly} onClick={() => insertMarkdown("- [ ] Task\n")}>
                <ListChecks className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Code block" disabled={readOnly} onClick={() => insertMarkdown("```ts\n// code\n```\n\n")}>
                <Code className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Table" disabled={readOnly} onClick={() => insertMarkdown("| Item | Status |\n| --- | --- |\n| Example | Draft |\n\n")}>
                <Table2 className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Callout" disabled={readOnly} onClick={() => insertMarkdown("> [!NOTE]\n> Add context here.\n\n")}>
                <Quote className="h-3.5 w-3.5" />
              </ToolBtn>
              <ToolBtn label="Run summary" disabled={readOnly} onClick={() => insertMarkdown("## Run summary\n\n### Validation\n\n- \n")}>
                <FileText className="h-3.5 w-3.5" />
              </ToolBtn>
            </div>
            <span className="text-[11px] text-muted-foreground">
              {readOnly ? "Read-only" : "Type / for blocks"}
            </span>
          </div>

          <div
            className="relative"
            onKeyDownCapture={onEditorKeyDownCapture}
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
                setSlashOpen(false);
              }
            }}
          >
            {slashOpen ? (
              <SlashMenu
                commands={filteredSlashCommands}
                selectedIndex={slashIndex}
                query={slashQuery}
                onSelect={applySlashCommand}
              />
            ) : null}

            <div className="private-workspace-milkdown relative mt-3 min-h-[42svh]">
              {editorLoading ? (
                <div className="absolute inset-x-0 top-0 flex items-center gap-2 rounded-md border border-dashed px-3 py-3 text-sm text-muted-foreground">
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Loading editor
                </div>
              ) : null}
              {editorError ? (
                <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-300">
                  <AlertTriangle className="mr-2 inline h-4 w-4" />
                  {editorError}
                </div>
              ) : null}
              {!editorLoading && !editorError && bodyEmpty ? (
                <button
                  type="button"
                  onClick={() => editorRef.current?.action((ctx) => ctx.get(editorViewCtx).focus())}
                  className="pointer-events-auto absolute left-0 top-0 z-10 text-left text-sm text-muted-foreground/60"
                >
                  {bodyPlaceholder ?? "Enter text or type '/' for commands"}
                </button>
              ) : null}
              <div
                ref={rootRef}
                aria-label="Artifact body"
                className={cn(
                  "min-h-[42svh]",
                  readOnly ? "cursor-default opacity-90" : "cursor-text",
                )}
              />
            </div>
          </div>

          {belowBodySlot}
        </div>
      </div>
    </div>
  );
}

function ToolBtn({
  children,
  label,
  disabled,
  onClick,
}: {
  children: ReactNode;
  label: string;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={label}
      aria-label={label}
      className="grid h-7 w-7 place-items-center rounded text-muted-foreground hover:bg-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-40"
    >
      {children}
    </button>
  );
}

function SlashMenu({
  commands,
  selectedIndex,
  query,
  onSelect,
}: {
  commands: PrivateWorkspaceSlashCommand[];
  selectedIndex: number;
  query: string;
  onSelect: (command: PrivateWorkspaceSlashCommand) => void;
}) {
  if (commands.length === 0) {
    return (
      <div className="absolute left-0 top-3 z-30 w-80 rounded-md border bg-popover p-3 text-sm text-muted-foreground shadow-xl">
        No blocks found.
      </div>
    );
  }

  let previousSection: PrivateWorkspaceSlashCommand["section"] | null = null;

  return (
    <div
      role="listbox"
      aria-label="Private workspace blocks"
      className="absolute left-0 top-3 z-30 max-h-[30rem] w-[22rem] max-w-[min(22rem,calc(100vw-3rem))] overflow-y-auto rounded-md border bg-popover p-2 shadow-xl"
    >
      <div className="px-2 pb-1 text-[12px] text-muted-foreground">
        /{query}
      </div>
      {commands.map((command, index) => {
        const showSection = command.section !== previousSection;
        previousSection = command.section;

        return (
          <div key={command.id}>
            {showSection ? (
              <div className="px-2 pb-1 pt-2 text-[11px] font-medium text-muted-foreground">
                {command.section}
              </div>
            ) : null}
            <button
              type="button"
              role="option"
              aria-selected={index === selectedIndex}
              onMouseDown={(event) => {
                event.preventDefault();
                onSelect(command);
              }}
              className={cn(
                "flex w-full items-center gap-3 rounded px-2 py-2 text-left",
                index === selectedIndex ? "bg-muted text-foreground" : "hover:bg-muted/70",
              )}
            >
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded bg-muted text-muted-foreground">
                {iconForCommand(command.id)}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-medium">{command.label}</span>
                <span className="block truncate text-[11px] text-muted-foreground">
                  {command.description}
                </span>
              </span>
            </button>
          </div>
        );
      })}
    </div>
  );
}

function iconForCommand(id: string): ReactNode {
  switch (id) {
    case "title":
      return <Heading1 className="h-4 w-4" />;
    case "subtitle":
      return <Heading2 className="h-4 w-4" />;
    case "heading":
      return <Heading3 className="h-4 w-4" />;
    case "body-text":
      return <Type className="h-4 w-4" />;
    case "bold":
      return <Bold className="h-4 w-4" />;
    case "italic":
      return <Italic className="h-4 w-4" />;
    case "link":
      return <Link2 className="h-4 w-4" />;
    case "bullet-list":
      return <ListIcon className="h-4 w-4" />;
    case "numbered-list":
      return <ListOrdered className="h-4 w-4" />;
    case "task-list":
      return <ListChecks className="h-4 w-4" />;
    case "code-block":
      return <Code className="h-4 w-4" />;
    case "table":
      return <Table2 className="h-4 w-4" />;
    case "callout":
    case "blockquote":
      return <Quote className="h-4 w-4" />;
    case "artifact-link":
    case "evidence-ref":
      return <Link2 className="h-4 w-4" />;
    case "decision-note":
    case "run-summary":
    default:
      return <FileText className="h-4 w-4" />;
  }
}

function SaveStatus({ state, savedAt }: { state: SaveState; savedAt: number }) {
  if (state === "read-only") {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
        <CircleDot className="h-3 w-3" />
        Read-only
      </span>
    );
  }

  if (state === "saving") {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
        <Loader2 className="h-3 w-3 animate-spin" />
        Saving
      </span>
    );
  }

  if (state === "failed") {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-amber-700 dark:text-amber-300">
        <AlertTriangle className="h-3 w-3" />
        Save failed
      </span>
    );
  }

  if (state === "dirty") {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
        <CircleDot className="h-3 w-3 text-amber-500" />
        Unsaved
      </span>
    );
  }

  return (
    <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
      <Check className="h-3 w-3 text-emerald-500" />
      Saved {relTime(savedAt)}
    </span>
  );
}

function snapshotFromPage(page: DocPage): SavedSnapshot {
  return {
    title: page.title,
    body: page.body,
    icon: page.icon,
    cover: page.cover,
    published: Boolean(page.published),
  };
}

function snapshotToPatch(snapshot: SavedSnapshot): EditorPatch {
  return {
    title: snapshot.title,
    body: snapshot.body,
    icon: snapshot.icon,
    cover: snapshot.cover,
    published: snapshot.published,
  };
}

function snapshotsEqual(left: SavedSnapshot, right: SavedSnapshot): boolean {
  return (
    left.title === right.title &&
    left.body === right.body &&
    left.icon === right.icon &&
    left.cover === right.cover &&
    left.published === right.published
  );
}

function relTime(ts: number): string {
  const diff = Math.max(0, Date.now() - ts);
  if (diff < 60_000) return "just now";
  const minutes = Math.round(diff / 60_000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  return `${days}d ago`;
}
