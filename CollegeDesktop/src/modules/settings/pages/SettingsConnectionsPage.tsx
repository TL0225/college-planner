import { useEffect, useState } from "react";
import { AppCard, Button, ListRow, StatusChip } from "@/design-system";
import { ipc } from "@/lib/ipc";
import { navigate } from "@/lib/shellNavigate";
import { useSettings } from "../useSettings";

type ConnectionCard = {
  id: string;
  title: string;
  subtitle: string;
  connected: boolean;
  settingsPage: string;
};

export function SettingsConnectionsPage() {
  const { googleClientId, outlookClientId, oauthConfigured, settings } = useSettings();
  const [googleConnected, setGoogleConnected] = useState(false);
  const [outlookConnected, setOutlookConnected] = useState(false);
  const [lmsConnected, setLmsConnected] = useState(false);
  const [careerConnected, setCareerConnected] = useState(false);

  const coinbaseConnected = Boolean(settings["finance.coinbase.apiKey"]?.trim());

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const [oauthStatus, portals, companies] = await Promise.all([
        ipc.calendarOauthStatus().catch(() => null),
        ipc.lmsListPortals().catch(() => []),
        ipc.careerListJobBoardCompanies().catch(() => []),
      ]);
      if (cancelled) return;
      const accounts = oauthStatus?.accounts ?? [];
      setGoogleConnected(accounts.some((a) => a.provider === "google"));
      setOutlookConnected(accounts.some((a) => a.provider === "outlook"));
      setLmsConnected(portals.length > 0);
      setCareerConnected(companies.some((c) => c.enabled));
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const cards: ConnectionCard[] = [
    {
      id: "google-calendar",
      title: "Google Calendar",
      subtitle: googleConnected
        ? "Account connected"
        : googleClientId
          ? "Client ID saved — connect in Calendar"
          : "Sync events with your Google account",
      connected: googleConnected,
      settingsPage: "calendar",
    },
    {
      id: "outlook",
      title: "Outlook Calendar",
      subtitle: outlookConnected
        ? "Account connected"
        : outlookClientId
          ? "Client ID saved — connect in Calendar"
          : "Sync events with Microsoft Outlook",
      connected: outlookConnected,
      settingsPage: "calendar",
    },
    {
      id: "lms",
      title: "Course portal",
      subtitle: lmsConnected
        ? "Canvas or LMS portal configured"
        : "Connect Canvas or your school's LMS",
      connected: lmsConnected,
      settingsPage: "lms",
    },
    {
      id: "finance",
      title: "Bank accounts",
      subtitle: coinbaseConnected
        ? "Coinbase API key saved"
        : "Link accounts for spending insights",
      connected: coinbaseConnected,
      settingsPage: "finance",
    },
    {
      id: "career",
      title: "Job boards",
      subtitle: careerConnected
        ? "Company boards enabled"
        : "Find openings from popular job sites",
      connected: careerConnected,
      settingsPage: "career",
    },
  ];

  return (
    <div className="space-y-4 lg:col-span-2">
      <AppCard title="Connections">
        <p className="mb-3 text-meta leading-relaxed">
          Connect the services you use. Each opens a focused setup — no technical jargon required.
        </p>
        <ul className="divide-y divide-[var(--color-chrome-stroke)]">
          {cards.map((card) => (
            <li key={card.id}>
              <ListRow
                title={card.title}
                subtitle={card.subtitle}
                trailing={
                  <div className="flex items-center gap-2">
                    <StatusChip
                      title={card.connected ? "Connected" : "Not connected"}
                      tint={card.connected ? "var(--color-success)" : "var(--color-text-light)"}
                      filled={card.connected}
                    />
                    <Button
                      size="sm"
                      variant={card.connected ? "secondary" : undefined}
                      onClick={() => navigate({ hub: "settings", page: card.settingsPage })}
                    >
                      {card.connected ? "Manage" : "Connect"}
                    </Button>
                  </div>
                }
              />
            </li>
          ))}
        </ul>
      </AppCard>
      {oauthConfigured && (
        <p className="text-meta text-[var(--color-text-light)]">
          OAuth is configured. Open Calendar to finish connecting your accounts.
        </p>
      )}
    </div>
  );
}
