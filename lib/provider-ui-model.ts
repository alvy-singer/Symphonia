import type {
  CodingAssistantProviderStatus,
  CodingAssistantProviderStatusValue,
} from "@/lib/repository-model";

export type ProviderTone = "ready" | "warning" | "neutral";

const CAPABILITY_LABELS: Record<string, string> = {
  context_pack: "ContextPack",
  persistent_workspace: "persistent workspace",
  streamed_public_steps: "public steps",
  change_detection: "change detection",
  validation_pipeline: "validation",
  curated_summary: "curated summary",
  review_branch: "review branch",
  handoff: "handoff",
  retry_classification: "retry classification",
};

export function providerStatusLabel(provider: CodingAssistantProviderStatus): string {
  if (provider.id === "gemini_cli" && provider.ready) return "Manual only";
  if (provider.id === "gemini_cli") return "Needs setup";
  if (provider.runnableByHarness && provider.ready) return "Ready";
  if (provider.runnableByHarness) return "Needs setup";
  if (provider.status === "experimental") return "Coming later";
  if (provider.id === "codex") return "Legacy/manual only";
  return statusLabel(provider.status);
}

export function providerStatusTone(provider: CodingAssistantProviderStatus): ProviderTone {
  if (provider.id === "gemini_cli" && provider.ready) return "ready";
  if (provider.id === "gemini_cli") return "warning";
  if (provider.runnableByHarness && provider.ready) return "ready";
  if (provider.runnableByHarness || provider.status === "blocked") return "warning";
  return "neutral";
}

export function providerMissingCapabilityLabels(
  provider: CodingAssistantProviderStatus,
): string[] {
  return (provider.missingCapabilities ?? []).map(
    (capability) => CAPABILITY_LABELS[capability] ?? capability.replaceAll("_", " "),
  );
}

export function providerSupportedCapabilityLabels(
  provider: CodingAssistantProviderStatus,
): string[] {
  return Object.entries(provider.capabilities ?? {})
    .filter((entry): entry is [string, true] => entry[1] === true)
    .map(([capability]) => CAPABILITY_LABELS[capability] ?? capability.replaceAll("_", " "));
}

export function canHarnessRunProvider(provider: CodingAssistantProviderStatus): boolean {
  return provider.runnableByHarness === true && provider.ready === true && provider.runnable === true;
}

function statusLabel(status: CodingAssistantProviderStatusValue): string {
  switch (status) {
    case "ready":
      return "Ready";
    case "not_configured":
      return "Needs setup";
    case "blocked":
      return "Blocked";
    case "experimental":
      return "Coming later";
    case "disabled":
    default:
      return "Disabled";
  }
}
