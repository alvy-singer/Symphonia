import { CheckCheck, Paperclip, Search, Send } from "lucide-react";
import { UserAvatar } from "@/components/avatar-stack";
import { userRoles, users } from "@/data/mock";
import { cn } from "@/lib/utils";

type ChatMessage = {
  id: string;
  senderId: string;
  sentAt: string;
  text: string;
  mine?: boolean;
};

const MOCK_MESSAGES: ChatMessage[] = [
  {
    id: "m1",
    senderId: "u3",
    sentAt: "09:18",
    text: "Morning. I grouped the workspace feedback into the next visual QA pass.",
  },
  {
    id: "m2",
    senderId: "u1",
    sentAt: "09:21",
    text: "Good. Keep the sidebar changes focused on the repository shell first.",
    mine: true,
  },
  {
    id: "m3",
    senderId: "u3",
    sentAt: "09:24",
    text: "Clarise should stay the first stop, then tasks, workspace documents, and team surfaces.",
  },
  {
    id: "m4",
    senderId: "u1",
    sentAt: "09:31",
    text: "Agree. I will leave task briefs out of the nav until they have a stronger review flow.",
    mine: true,
  },
  {
    id: "m5",
    senderId: "u3",
    sentAt: "09:44",
    text: "I added notes for the dropdown behavior. Codebase, milestone, plans, and decisions should open on demand.",
  },
  {
    id: "m6",
    senderId: "u1",
    sentAt: "09:52",
    text: "Ship the Team group next with group chat and members together.",
    mine: true,
  },
];

export function GroupChatView({ repoKey }: { repoKey: string }) {
  const members = users
    .map((user) => ({
      ...user,
      role: userRoles[user.id]?.role ?? "Member",
      repos: userRoles[user.id]?.repos ?? [],
    }))
    .filter((user) => user.repos.includes(repoKey));

  return (
    <div className="flex h-full flex-col bg-[var(--card-alt)]">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b bg-background px-5 py-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h1 className="text-[15px] font-bold tracking-[-0.02em]">Group chat</h1>
            <span className="rounded-full border px-2 py-0.5 text-[11px] text-muted-foreground">
              Team
            </span>
          </div>
          <p className="mt-1 truncate text-[12px] text-muted-foreground">
            Mock WhatsApp-style room for {repoKey} repository coordination.
          </p>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="flex -space-x-2">
            {members.slice(0, 4).map((member) => (
              <UserAvatar key={member.id} user={member} size={26} />
            ))}
          </div>
          <button
            type="button"
            disabled
            title="Mock search"
            className="grid h-8 w-8 cursor-not-allowed place-items-center rounded-[8px] border bg-card text-muted-foreground opacity-70"
          >
            <Search className="h-4 w-4" />
          </button>
        </div>
      </header>

      <div className="flex-1 overflow-auto px-5 py-5">
        <div className="mx-auto flex max-w-3xl flex-col gap-3">
          <div className="self-center rounded-full border bg-background px-3 py-1 text-[11px] text-muted-foreground">
            Today
          </div>
          {MOCK_MESSAGES.map((message) => {
            const sender = users.find((user) => user.id === message.senderId) ?? users[0];
            return (
              <div
                key={message.id}
                className={cn("flex items-end gap-2", message.mine ? "justify-end" : "justify-start")}
              >
                {!message.mine && <UserAvatar user={sender} size={28} />}
                <div
                  className={cn(
                    "max-w-[min(34rem,78%)] rounded-[10px] px-3 py-2 shadow-[var(--elevation-card)]",
                    message.mine
                      ? "rounded-br-[3px] bg-primary text-primary-foreground"
                      : "rounded-bl-[3px] border bg-background text-foreground",
                  )}
                >
                  {!message.mine && (
                    <div className="mb-1 text-[11px] font-semibold text-brand-accent-text">
                      {sender.name}
                    </div>
                  )}
                  <p className="text-[14px] leading-6">{message.text}</p>
                  <div
                    className={cn(
                      "mt-1 flex items-center justify-end gap-1 text-[10px]",
                      message.mine ? "text-primary-foreground/75" : "text-muted-foreground",
                    )}
                  >
                    <span>{message.sentAt}</span>
                    {message.mine && <CheckCheck className="h-3.5 w-3.5" />}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <footer className="border-t bg-background px-5 py-3">
        <div className="mx-auto flex max-w-3xl items-center gap-2">
          <button
            type="button"
            disabled
            title="Mock attachment"
            className="grid h-9 w-9 cursor-not-allowed place-items-center rounded-[8px] border bg-card text-muted-foreground opacity-70"
          >
            <Paperclip className="h-4 w-4" />
          </button>
          <div className="flex h-9 flex-1 items-center rounded-[8px] border bg-card px-3 text-[13px] text-muted-foreground">
            Message the team
          </div>
          <button
            type="button"
            disabled
            title="Mock send"
            className="grid h-9 w-9 cursor-not-allowed place-items-center rounded-[8px] bg-primary text-primary-foreground opacity-70"
          >
            <Send className="h-4 w-4" />
          </button>
        </div>
      </footer>
    </div>
  );
}
