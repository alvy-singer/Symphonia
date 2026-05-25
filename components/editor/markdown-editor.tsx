"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
} from "lucide-react";
import { COMMON_ICONS, COVERS, useDocs, type DocPage } from "@/lib/docs-store";
import { cn } from "@/lib/utils";

interface Props {
  page: DocPage;
  /**
   * If true, the page is a draft that has never been saved. The UI shows a
   * "Save to repository" affordance and the path is computed from the title.
   */
  isDraft?: boolean;
  onSave?: () => void;
  onDiscard?: () => void;
  /** Hide title editing where the title is fixed. */
  fixedTitle?: boolean;
  /** Optional content rendered above the editor (e.g. cover/header). */
  className?: string;
  /** Slot rendered in the toolbar — used by the workflow editor for templates. */
  rightToolbarSlot?: React.ReactNode;
  /** Slot rendered below the body, such as a validation panel. */
  belowBodySlot?: React.ReactNode;
  /** Override placeholder for body. */
  bodyPlaceholder?: string;
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
  fixedTitle,
  className,
  rightToolbarSlot,
  belowBodySlot,
  bodyPlaceholder,
}: Props) {
  const { updateDraft, updatePage } = useDocs();
  const update = isDraft ? updateDraft : updatePage;

  const [title, setTitle] = useState(page.title);
  const [body, setBody] = useState(page.body);
  const [icon, setIcon] = useState(page.icon);
  const [cover, setCover] = useState(page.cover);
  const [savedAt, setSavedAt] = useState<number>(page.updatedAt);
  const [dirty, setDirty] = useState(false);
  const [iconOpen, setIconOpen] = useState(false);
  const [coverOpen, setCoverOpen] = useState(false);
  const bodyRef = useRef<HTMLTextAreaElement>(null);

  // If the underlying page swaps (different route), reset local state.
  useEffect(() => {
    setTitle(page.title);
    setBody(page.body);
    setIcon(page.icon);
    setCover(page.cover);
    setSavedAt(page.updatedAt);
    setDirty(false);
  }, [page.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Debounced autosave to store.
  useEffect(() => {
    if (!dirty) return;
    const t = setTimeout(() => {
      update(page.id, { title, body, icon, cover });
      setSavedAt(Date.now());
      setDirty(false);
    }, 400);
    return () => clearTimeout(t);
  }, [dirty, title, body, icon, cover, page.id, update]);

  // Cmd/Ctrl+S — flush immediately.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        update(page.id, { title, body, icon, cover });
        setSavedAt(Date.now());
        setDirty(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [title, body, icon, cover, page.id, update]);

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
          {cover && (
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
          <div className="-mt-6 flex items-center gap-1.5">
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

            {!cover && (
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
              {isDraft && (
                <>
                  <button
                    onClick={onDiscard}
                    className="rounded-md border px-2 py-1 text-[11px] text-muted-foreground hover:bg-muted"
                  >
                    Discard
                  </button>
                  <button
                    onClick={() => {
                      // Flush latest local edits into the draft before saving.
                      update(page.id, { title, body, icon, cover });
                      onSave?.();
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
          <textarea
            ref={bodyRef}
            value={body}
            onChange={(e) => {
              setBody(e.target.value);
              setDirty(true);
            }}
            spellCheck={false}
            aria-label="Page content"
            placeholder={
              bodyPlaceholder ?? "Press 'Cmd/Ctrl+S' to save anytime — formatting is preserved."
            }
            className="mt-3 min-h-[40svh] w-full resize-none bg-transparent font-mono text-[13px] leading-6 placeholder:text-muted-foreground/50 outline-none"
          />

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
