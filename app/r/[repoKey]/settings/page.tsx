import { SettingsView } from "@/components/settings-view";

export default async function SettingsPage({
  params,
}: {
  params: Promise<{ repoKey: string }>;
}) {
  const { repoKey } = await params;
  return <SettingsView repoKey={repoKey.toUpperCase()} />;
}
