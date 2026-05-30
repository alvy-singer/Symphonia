"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Smile,
  ImagePlus,
  Check,
  CircleDot,
  X,
  Trash2,
  Bold,
  Italic,
  Heading1,
  Heading2,
  List as ListIcon,
  ListChecks,
  Quote,
  Code,
  Heading3,
  ListOrdered,
  Type,
  MoreHorizontal,
} from "lucide-react";
import { COMMON_ICONS, COVERS, useDocs, type DocPage } from "@/lib/docs-store";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

type EditorPatch = Partial<
  Pick<DocPage, "title" | "body" | "icon" | "cover" | "published">
>;

interface Props {
  page: DocPage;
  /**
   * If true, the page is a draft that has never been saved. The UI shows a
   * "Save to repository" affordance and the path is computed from the title.
   */
  isDraft?: boolean;
  onSave?: (patch: EditorPatch) => void | Promise<void>;
  onDiscard?: () => void;
  onPersist?: (patch: EditorPatch) => void | Promise<void>;
  onPersistError?: (error: unknown) => void;
  onDraftChange?: (patch: EditorPatch) => void;
  /** Hide title editing where the title is fixed. */
  fixedTitle?: boolean;
  /** Hide page icon/cover controls for fixed repository files without metadata. */
  metadataControls?: boolean;
  /** Optional content rendered above the editor (e.g. cover/header). */
  className?: string;
  /** Slot rendered in the toolbar — used by the workflow editor for templates. */
  rightToolbarSlot?: React.ReactNode;
  /** Slot rendered after the save indicator. */
  afterSaveStatusSlot?: React.ReactNode;
  /** Force the Publish/actions controls on or off. Defaults to saved doc pages only. */
  showPageActions?: boolean;
  /** Optional replacement for the default page actions menu content. */
  actionsMenuContent?: React.ReactNode;
  /** Reset editor state when external metadata changes without changing page id. */
  stateRevision?: string | number;
  /** Slot rendered below the body, such as a validation panel. */
  belowBodySlot?: React.ReactNode;
  /** Override placeholder for body. */
  bodyPlaceholder?: string;
}

interface SlashCommand {
  id: string;
  section: "Headings" | "Basic blocks" | "Media";
  label: string;
  description: string;
  shortcut?: string;
  insert: string;
  icon: React.ReactNode;
}

/**
 * Notion-like Markdown page editor.
 *
 * - Cover area + emoji icon affordances (lightweight, local metadata only).
 * - Title and body inputs are plain Markdown text (Markdown is preserved).
 * - Autosaves to the docs store; clearly indicates Saved / Saving / Unsaved.
 * - Cmd/Ctrl+S forces a save tick (mostly UX — autosave already runs).
 * - Empty state placeholders mimic Notion ("Untitled", "Press '/' or just
 *   start writing — Markdown is preserved").
 */
export function MarkdownEditor({
  page,
  isDraft,
  onSave,
  onDiscard,
  onPersist,
  onPersistError,
  onDraftChange,
  fixedTitle,
  metadataControls = true,
  className,
  rightToolbarSlot,
  afterSaveStatusSlot,
  showPageActions,
  actionsMenuContent,
  stateRevision,
  belowBodySlot,
  bodyPlaceholder,
}: Props) {
  const { archivePage, updateDraft, updatePage } = useDocs();
  const router = useRouter();
  const update = isDraft ? updateDraft : updatePage;

  const [title, setTitle] = useState(page.title);
  const [body, setBody] = useState(page.body);
  const [icon, setIcon] = useState(page.icon);
  const [cover, setCover] = useState(page.cover);
  const [published, setPublished] = useState(page.published);
  const [savedAt, setSavedAt] = useState<number>(page.updatedAt);
  const [dirty, setDirty] = useState(false);
  const [iconOpen, setIconOpen] = useState(false);
  const [coverOpen, setCoverOpen] = useState(false);
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [slashRange, setSlashRange] = useState<{ start: number; end: number } | null>(null);
  const [slashIndex, setSlashIndex] = useState(0);
  const bodyRef = useRef<HTMLTextAreaElement>(null);

  const slashCommands = useMemo<SlashCommand[]>(
    () => [
      {
        id: "h1",
        section: "Headings",
        label: "Heading",
        description: "Used for a top-level heading",
        shortcut: "⌘-ALT-1",
        insert: "# ",
        icon: <Heading1 className="h-4 w-4" />,
      },
      {
        id: "h2",
        section: "Headings",
        label: "Heading 2",
        description: "Used for key sections",
        shortcut: "⌘-ALT-2",
        insert: "## ",
        icon: <Heading2 className="h-4 w-4" />,
      },
      {
        id: "h3",
        section: "Headings",
        label: "Heading 3",
        description: "Used for subsections and group headings",
        shortcut: "⌘-ALT-3",
        insert: "### ",
        icon: <Heading3 className="h-4 w-4" />,
      },
      {
        id: "bullet",
        section: "Basic blocks",
        label: "Bullet List",
        description: "Used to display an unordered list",
        shortcut: "⌘-ALT-9",
        insert: "- ",
        icon: <ListIcon className="h-4 w-4" />,
      },
      {
        id: "numbered",
        section: "Basic blocks",
        label: "Numbered List",
        description: "Used to display a numbered list",
        shortcut: "⌘-ALT-7",
        insert: "1. ",
        icon: <ListOrdered className="h-4 w-4" />,
      },
      {
        id: "paragraph",
        section: "Basic blocks",
        label: "Paragraph",
        description: "Used for the body of your document",
        shortcut: "⌘-ALT-0",
        insert: "",
        icon: <Type className="h-4 w-4" />,
      },
      {
        id: "image",
        section: "Media",
        label: "Image",
        description: "Insert an image",
        insert: "![Image]()",
        icon: <ImagePlus className="h-4 w-4" />,
      },
    ],
    [],
  );

  const filteredSlashCommands = useMemo(() => {
    const query = slashQuery.trim().toLowerCase();
    if (!query) return slashCommands;
    return slashCommands.filter((command) =>
      `${command.label} ${command.description}`.toLowerCase().includes(query),
    );
  }, [slashCommands, slashQuery]);

  // If the underlying page swaps (different route), reset local state.
  useEffect(() => {
    setTitle(page.title);
    setBody(page.body);
    setIcon(page.icon);
    setCover(page.cover);
    setPublished(page.published);
    setSavedAt(page.updatedAt);
    setDirty(false);
  }, [page.id, stateRevision]); // eslint-disable-line react-hooks/exhaustive-deps

  const currentPatch = useCallback(
    (overrides: EditorPatch = {}): EditorPatch => ({
      title,
      body,
      icon,
      cover,
      published,
      ...overrides,
    }),
    [body, cover, icon, published, title],
  );

  const persistCurrent = useCallback(
    (overrides: EditorPatch = {}) => {
      const patch = currentPatch(overrides);
      if (onPersist) {
        Promise.resolve(onPersist(patch)).catch((err) => {
          onPersistError?.(err);
        });
      } else {
        update(page.id, patch);
      }
      setSavedAt(Date.now());
      setDirty(false);
      return patch;
    },
    [currentPatch, onPersist, onPersistError, page.id, update],
  );

  // Debounced autosave to store.
  useEffect(() => {
    if (!dirty) return;
    const t = setTimeout(() => {
      persistCurrent();
    }, 400);
    return () => clearTimeout(t);
  }, [dirty, persistCurrent]);

  // Cmd/Ctrl+S — flush immediately.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        persistCurrent();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [persistCurrent]);

  const cls = useMemo(
    () => COVERS.find((c) => c.id === cover)?.className,
    [cover],
  );

  // Markdown body: insert helper.
  const insertMd = useCallback(
    (prefix: string, suffix = "", placeholder = "") => {
      const ta = bodyRef.current;
      if (!ta) return;
      const start = ta.selectionStart;
      const end = ta.selectionEnd;
      const sel = body.slice(start, end);
      const text = sel || placeholder;
      const next = body.slice(0, start) + prefix + text + suffix + body.slice(end);
      setBody(next);
      setDirty(true);
      requestAnimationFrame(() => {
        ta.focus();
        const cursor = start + prefix.length + text.length;
        ta.setSelectionRange(cursor, cursor);
      });
    },
    [body],
  );

  const updateSlashState = useCallback((nextBody: string, cursor: number) => {
    const lineStart = nextBody.lastIndexOf("\n", Math.max(0, cursor - 1)) + 1;
    const lineBeforeCursor = nextBody.slice(lineStart, cursor);
    const match = lineBeforeCursor.match(/^\/([^\n]*)$/);

    if (!match) {
      setSlashOpen(false);
      setSlashRange(null);
      setSlashQuery("");
      setSlashIndex(0);
      return;
    }

    setSlashOpen(true);
    setSlashRange({ start: lineStart, end: cursor });
    setSlashQuery(match[1] ?? "");
    setSlashIndex(0);
  }, []);

  const applySlashCommand = useCallback(
    (command: SlashCommand) => {
      if (!slashRange) return;
      const next = body.slice(0, slashRange.start) + command.insert + body.slice(slashRange.end);
      const cursor = slashRange.start + command.insert.length;
      setBody(next);
      setDirty(true);
      setSlashOpen(false);
      setSlashRange(null);
      setSlashQuery("");
      setSlashIndex(0);
      requestAnimationFrame(() => {
        bodyRef.current?.focus();
        bodyRef.current?.setSelectionRange(cursor, cursor);
      });
    },
    [body, slashRange],
  );

  const onBodyKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (!slashOpen) return;

    if (event.key === "Escape") {
      event.preventDefault();
      setSlashOpen(false);
      setSlashRange(null);
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
    }
  };

  const togglePublished = () => {
    const next = !published;
    setPublished(next);
    persistCurrent({ published: next });
  };

  const deleteCurrentPage = async () => {
    await archivePage(page.id);
    router.push(`/r/${page.repo.toLowerCase()}`);
  };

  const showDocActions = showPageActions ?? (!isDraft && page.category === "doc");

  return (
    <div className={cn("flex h-full flex-col", className)}>
      {/* Cover */}
      <div className="relative">
        {cover ? (
          <div className={cn("h-36 w-full sm:h-44", cls)} aria-hidden />
        ) : (
          <div className="h-6" aria-hidden />
        )}
        <div className="absolute right-3 top-3 flex items-center gap-1.5">
          {metadataControls && cover && (
            <button
              onClick={() => {
                setCover(undefined);
                setDirty(true);
              }}
              className="inline-flex items-center gap-1 rounded-md border bg-background/80 px-2 py-1 text-[11px] backdrop-blur hover:bg-background"
            >
              <X className="h-3 w-3" /> Remove cover
            </button>
          )}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl px-4 sm:px-8 pb-16">
          {/* Affordances above title */}
          <div className={cn("flex items-center gap-1.5", cover ? "-mt-6" : "mt-3")}>
            {metadataControls && (
              <div className="relative">
                <button
                  onClick={() => setIconOpen((v) => !v)}
                  aria-label={icon ? "Change page icon" : "Add page icon"}
                  className={cn(
                    "grid place-items-center rounded-md border bg-background text-2xl transition",
                    icon ? "h-12 w-12" : "h-7 px-2 text-[11px] text-muted-foreground hover:text-foreground",
                  )}
                >
                  {icon ?? (
                    <span className="inline-flex items-center gap-1">
                      <Smile className="h-3.5 w-3.5" /> Add icon
                    </span>
                  )}
                </button>
                {iconOpen && (
                  <div
                    role="dialog"
                    aria-label="Pick an icon"
                    className="absolute z-20 mt-1 w-60 rounded-lg border bg-popover p-2 shadow-xl"
                  >
                    <div className="grid grid-cols-6 gap-1">
                      {COMMON_ICONS.map((ic) => (
                        <button
                          key={ic}
                          onClick={() => {
                            setIcon(ic);
                            setIconOpen(false);
                            setDirty(true);
                          }}
                          className="grid h-8 place-items-center rounded hover:bg-accent text-lg"
                          aria-label={`Use icon ${ic}`}
                        >
                          {ic}
                        </button>
                      ))}
                    </div>
                    <div className="mt-2 flex items-center justify-between border-t pt-2">
                      <button
                        onClick={() => {
                          setIcon(undefined);
                          setIconOpen(false);
                          setDirty(true);
                        }}
                        className="inline-flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground"
                      >
                        <Trash2 className="h-3 w-3" /> Remove
                      </button>
                      <button
                        onClick={() => setIconOpen(false)}
                        className="text-[11px] text-muted-foreground hover:text-foreground"
                      >
                        Close
                      </button>
                    </div>
                  </div>
                )}
              </div>
            )}

            {metadataControls && !cover && (
              <div className="relative">
                <button
                  onClick={() => setCoverOpen((v) => !v)}
                  className="inline-flex items-center gap-1 rounded-md border bg-background px-2 py-1 text-[11px] text-muted-foreground hover:text-foreground"
                >
                  <ImagePlus className="h-3 w-3" /> Add cover
                </button>
                {coverOpen && (
                  <div className="absolute z-20 mt-1 w-64 rounded-lg border bg-popover p-2 shadow-xl">
                    <div className="grid grid-cols-3 gap-1.5">
                      {COVERS.map((c) => (
                        <button
                          key={c.id}
                          onClick={() => {
                            setCover(c.id);
                            setCoverOpen(false);
                            setDirty(true);
                          }}
                          className={cn("h-12 rounded border", c.className)}
                          aria-label={`Use cover ${c.id}`}
                        />
                      ))}
                    </div>
                    <p className="mt-1.5 text-[11px] text-muted-foreground">
                      Local metadata — no upload.
                    </p>
                  </div>
                )}
              </div>
            )}

            <div className="ml-auto flex items-center gap-2">
              {rightToolbarSlot}
              <SaveStatus dirty={dirty} savedAt={savedAt} isDraft={!!isDraft} />
              {afterSaveStatusSlot}
              {showDocActions && (
                <>
                  <button
                    type="button"
                    onClick={togglePublished}
                    className={cn(
                      "rounded-md border px-2.5 py-1 text-[11px] font-medium transition-colors",
                      published
                        ? "bg-primary text-primary-foreground hover:bg-primary-hover"
                        : "bg-background text-foreground hover:bg-muted",
                    )}
                  >
                    {published ? "Published" : "Publish"}
                  </button>
                  <Popover>
                    <PopoverTrigger asChild>
                      <button
                        type="button"
                        aria-label="Page actions"
                        title="Page actions"
                        className="grid h-7 w-7 place-items-center rounded-md border text-muted-foreground hover:bg-muted hover:text-foreground"
                      >
                        <MoreHorizontal className="h-3.5 w-3.5" />
                      </button>
                    </PopoverTrigger>
                    <PopoverContent align="end" className="w-44 p-1">
                      {actionsMenuContent ?? (
                        <button
                          type="button"
                          onClick={() => void deleteCurrentPage()}
                          className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-[12px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                          Delete
                        </button>
                      )}
                    </PopoverContent>
                  </Popover>
                </>
              )}
              {isDraft && (
                <>
                  <button
                    onClick={onDiscard}
                    className="rounded-md border px-2 py-1 text-[11px] text-muted-foreground hover:bg-muted"
                  >
                    Discard
                  </button>
                  <button
                    onClick={async () => {
                      await onSave?.(persistCurrent());
                    }}
                    disabled={!title.trim()}
                    className="rounded-md bg-primary px-2.5 py-1 text-[11px] font-medium text-primary-foreground hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Save to repository
                  </button>
                </>
              )}
            </div>
          </div>

          {/* Title */}
          <div className="mt-3">
            {fixedTitle ? (
              <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
            ) : (
              <input
                value={title}
                onChange={(e) => {
                  setTitle(e.target.value);
                  setDirty(true);
                }}
                placeholder="Untitled"
                aria-label="Page title"
                className="w-full bg-transparent text-3xl font-semibold tracking-tight placeholder:text-muted-foreground/40 outline-none"
              />
            )}
            <p className="mt-1 text-[11px] text-muted-foreground">Saved in repository</p>
          </div>

          {/* Markdown formatting toolbar */}
          <div className="mt-4 flex flex-wrap items-center gap-0.5 border-b pb-2">
            <ToolBtn label="Heading 1" onClick={() => insertMd("# ", "", "Heading")}>
              <Heading1 className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Heading 2" onClick={() => insertMd("## ", "", "Subheading")}>
              <Heading2 className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Bold" onClick={() => insertMd("**", "**", "bold")}>
              <Bold className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Italic" onClick={() => insertMd("*", "*", "italic")}>
              <Italic className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Bulleted list" onClick={() => insertMd("- ", "", "list item")}>
              <ListIcon className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Task list" onClick={() => insertMd("- [ ] ", "", "task")}>
              <ListChecks className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Quote" onClick={() => insertMd("> ", "", "quote")}>
              <Quote className="h-3.5 w-3.5" />
            </ToolBtn>
            <ToolBtn label="Code" onClick={() => insertMd("`", "`", "code")}>
              <Code className="h-3.5 w-3.5" />
            </ToolBtn>
          </div>

          {/* Body */}
          <div className="relative">
            {slashOpen && (
              <SlashMenu
                commands={filteredSlashCommands}
                selectedIndex={slashIndex}
                onSelect={applySlashCommand}
              />
            )}
            <textarea
              ref={bodyRef}
              value={body}
              onChange={(e) => {
                const next = e.target.value;
                setBody(next);
                setDirty(true);
                onDraftChange?.({ body: next });
                updateSlashState(next, e.currentTarget.selectionStart);
              }}
              onKeyDown={onBodyKeyDown}
              onClick={(e) => updateSlashState(body, e.currentTarget.selectionStart)}
              onSelect={(e) => updateSlashState(body, e.currentTarget.selectionStart)}
              spellCheck={false}
              aria-label="Page content"
              placeholder={bodyPlaceholder ?? "Enter text or type '/' for commands"}
              className="mt-3 min-h-[40svh] w-full resize-none bg-transparent font-mono text-[13px] leading-6 placeholder:text-muted-foreground/50 outline-none"
            />
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
  onClick,
}: {
  children: React.ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      className="grid h-7 w-7 place-items-center rounded text-muted-foreground hover:bg-muted hover:text-foreground"
    >
      {children}
    </button>
  );
}

function SlashMenu({
  commands,
  selectedIndex,
  onSelect,
}: {
  commands: SlashCommand[];
  selectedIndex: number;
  onSelect: (command: SlashCommand) => void;
}) {
  if (commands.length === 0) {
    return (
      <div className="absolute left-0 top-3 z-30 w-80 rounded-md border bg-popover p-3 text-sm text-muted-foreground shadow-xl">
        No blocks found.
      </div>
    );
  }

  let previousSection: SlashCommand["section"] | null = null;

  return (
    <div
      role="listbox"
      aria-label="Block commands"
      className="absolute left-0 top-3 z-30 max-h-[30rem] w-[22rem] max-w-[min(22rem,calc(100vw-3rem))] overflow-y-auto rounded-md border bg-popover p-2 shadow-xl"
    >
      <div className="px-2 pb-1 text-[12px] italic text-muted-foreground">Type to filter</div>
      {commands.map((command, index) => {
        const showSection = command.section !== previousSection;
        previousSection = command.section;

        return (
          <div key={command.id}>
            {showSection && (
              <div className="px-2 pb-1 pt-2 text-[11px] font-medium text-muted-foreground">
                {command.section}
              </div>
            )}
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
                {command.icon}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-medium">{command.label}</span>
                <span className="block truncate text-[11px] text-muted-foreground">
                  {command.description}
                </span>
              </span>
              {command.shortcut && (
                <kbd className="rounded-full bg-muted px-2 py-0.5 text-[10px] text-muted-foreground">
                  {command.shortcut}
                </kbd>
              )}
            </button>
          </div>
        );
      })}
    </div>
  );
}

function SaveStatus({
  dirty,
  savedAt,
  isDraft,
}: {
  dirty: boolean;
  savedAt: number;
  isDraft: boolean;
}) {
  if (isDraft) {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
        <CircleDot className="h-3 w-3 text-amber-500" />
        Draft — not saved to repository
      </span>
    );
  }
  if (dirty) {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
        <CircleDot className="h-3 w-3 text-amber-500" /> Unsaved
      </span>
    );
  }
  const label = relTime(savedAt);
  return (
    <span className="inline-flex items-center gap-1 text-[11px] text-muted-foreground">
      <Check className="h-3 w-3 text-emerald-500" /> Saved {label}
    </span>
  );
}

function relTime(ts: number): string {
  const diff = Math.max(0, Date.now() - ts);
  if (diff < 60_000) return "just now";
  const m = Math.round(diff / 60_000);
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.round(h / 24);
  return `${d}d ago`;
}
