import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  StatusChip,
  TrailingInspector,
} from "@/design-system";
import { formatEventWhen } from "../format";

export type CareerPostingRow = {
  id: string;
  company: string;
  title: string;
  location: string;
  url: string;
  postedAt?: string | null;
  trackedApplicationId?: string | null;
};

export type CareerCompanyBoardRow = {
  id: string;
  displayName: string;
  enabled: boolean;
};

export type CareerSmartBoardRow = {
  id: string;
  name: string;
};

export type CareerOpeningsScope =
  | { kind: "all" }
  | { kind: "company"; id: string; name: string }
  | { kind: "smartBoard"; id: string; name: string };

export type CareerOpeningsViewProps = {
  openingsScope: CareerOpeningsScope;
  companyBoards: CareerCompanyBoardRow[];
  smartBoards: CareerSmartBoardRow[];
  visiblePostings: CareerPostingRow[];
  smartBoardPostingsBusy: boolean;
  selectedPostingId: string | null;
  selectedPosting: CareerPostingRow | null;
  lastApplyPostingId: string | null;
  onScopeAll: () => void;
  onScopeCompany: (id: string, name: string) => void;
  onScopeSmartBoard: (id: string, name: string) => void;
  onOpenSmartBoardEditor: (board?: CareerSmartBoardRow) => void;
  onSelectPosting: (id: string) => void;
  onClearPostingSelection: () => void;
  onTrackPosting: (postingId: string) => void | Promise<void>;
  onApplyInCollege: (posting: CareerPostingRow) => void;
  onMarkApplied: (posting: CareerPostingRow) => void;
  onOpenInBrowser: (url: string) => void;
  onDeletePosting: (posting: CareerPostingRow) => void | Promise<void>;
};

export function CareerOpeningsView({
  openingsScope,
  companyBoards,
  smartBoards,
  visiblePostings,
  smartBoardPostingsBusy,
  selectedPostingId,
  selectedPosting,
  lastApplyPostingId,
  onScopeAll,
  onScopeCompany,
  onScopeSmartBoard,
  onOpenSmartBoardEditor,
  onSelectPosting,
  onClearPostingSelection,
  onTrackPosting,
  onApplyInCollege,
  onMarkApplied,
  onOpenInBrowser,
  onDeletePosting,
}: CareerOpeningsViewProps) {
  return (
    <div className="min-h-0 flex-1 overflow-hidden p-3">
      <TrailingInspector
        open={Boolean(selectedPosting)}
        main={
          <AppCard title="Job openings" className="h-full overflow-auto">
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <button
                type="button"
                className={`rounded-full px-3 py-1 text-meta font-medium transition-colors ${
                  openingsScope.kind === "all"
                    ? "bg-[var(--color-primary)] text-white"
                    : "bg-[var(--color-chrome-fill)] text-[var(--color-text-main)] hover:bg-[var(--color-chrome-stroke)]"
                }`}
                onClick={onScopeAll}
              >
                All
              </button>
              {companyBoards
                .filter((c) => c.enabled)
                .map((c) => {
                  const active = openingsScope.kind === "company" && openingsScope.id === c.id;
                  return (
                    <button
                      key={c.id}
                      type="button"
                      className={`rounded-full px-3 py-1 text-meta font-medium transition-colors ${
                        active
                          ? "bg-[var(--color-primary)] text-white"
                          : "bg-[var(--color-chrome-fill)] text-[var(--color-text-main)] hover:bg-[var(--color-chrome-stroke)]"
                      }`}
                      onClick={() => onScopeCompany(c.id, c.displayName)}
                    >
                      {c.displayName}
                    </button>
                  );
                })}
              {smartBoards.map((board) => {
                const active =
                  openingsScope.kind === "smartBoard" && openingsScope.id === board.id;
                return (
                  <button
                    key={board.id}
                    type="button"
                    className={`rounded-full px-3 py-1 text-meta font-medium transition-colors ${
                      active
                        ? "bg-[color-mix(in_srgb,var(--color-primary)_85%,#6366f1)] text-white"
                        : "bg-[color-mix(in_srgb,var(--color-primary)_12%,var(--color-chrome-fill))] text-[var(--color-text-main)] hover:bg-[var(--color-chrome-stroke)]"
                    }`}
                    onClick={() => onScopeSmartBoard(board.id, board.name)}
                    onDoubleClick={() => onOpenSmartBoardEditor(board)}
                    title="Double-click to edit"
                  >
                    {board.name}
                  </button>
                );
              })}
              <Button size="sm" variant="ghost" onClick={() => onOpenSmartBoardEditor()}>
                + Smart board
              </Button>
            </div>
            {openingsScope.kind === "smartBoard" && smartBoardPostingsBusy ? (
              <p className="px-1 py-6 text-center text-meta">
                Loading smart board…
              </p>
            ) : visiblePostings.length === 0 ? (
              <EmptyState
                title={
                  openingsScope.kind === "smartBoard"
                    ? "No matches for this smart board"
                    : "No openings yet"
                }
                body={
                  openingsScope.kind === "smartBoard"
                    ? "Try editing filters or sync company boards to refresh postings."
                    : "Add roles from job boards, or reload sample data from Settings."
                }
              />
            ) : (
              <div className="space-y-4">
                {[
                  ...visiblePostings
                    .reduce((map, p) => {
                      const key = p.company.trim() || "Unknown company";
                      const list = map.get(key) ?? [];
                      list.push(p);
                      map.set(key, list);
                      return map;
                    }, new Map<string, CareerPostingRow[]>())
                    .entries(),
                ].map(([company, group]) => (
                  <div key={company}>
                    <div className="mb-2 flex items-center gap-2">
                      <h3 className="text-section-title">
                        {company}
                      </h3>
                      <StatusChip title={`${group.length} roles`} />
                    </div>
                    <ul className="divide-y divide-[var(--color-chrome-stroke)] rounded-lg border border-[var(--color-chrome-stroke)]">
                      {group.map((p) => (
                        <li key={p.id}>
                          <ListRow
                            selected={selectedPostingId === p.id}
                            onClick={() => onSelectPosting(p.id)}
                            title={p.title}
                            subtitle={p.location || undefined}
                            trailing={p.trackedApplicationId ? "Tracked" : undefined}
                          />
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
              </div>
            )}
          </AppCard>
        }
      >
        {selectedPosting && (
          <div className="flex h-full flex-col">
            <div className="border-b border-[var(--color-chrome-stroke)] px-4 py-3">
              <h3
                className="text-[var(--color-text-main)]"
                style={{
                  font: "var(--type-section-title)",
                  fontSize: 16,
                  letterSpacing: "-0.02em",
                }}
              >
                {selectedPosting.title}
              </h3>
              <p className="mt-0.5 text-meta">
                {selectedPosting.company}
              </p>
              {selectedPosting.location ? (
                <div className="mt-2">
                  <StatusChip title={selectedPosting.location} />
                </div>
              ) : null}
              {selectedPosting.url ? (
                <p className="mt-2 break-all text-caption">
                  {selectedPosting.url}
                </p>
              ) : null}
            </div>
            <div className="min-h-0 flex-1 overflow-auto p-4">
              {selectedPosting.postedAt ? (
                <p className="text-meta">
                  Posted {formatEventWhen(selectedPosting.postedAt)}
                </p>
              ) : (
                <p className="text-meta">
                  Open a posting link to review the role before applying in College.
                </p>
              )}
            </div>
            <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
              {!selectedPosting.trackedApplicationId ? (
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => void onTrackPosting(selectedPosting.id)}
                >
                  Track
                </Button>
              ) : null}
              {selectedPosting.url.trim() ? (
                <>
                  <Button size="sm" onClick={() => void onApplyInCollege(selectedPosting)}>
                    Apply in College
                  </Button>
                  {lastApplyPostingId === selectedPosting.id ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => void onMarkApplied(selectedPosting)}
                    >
                      Mark applied
                    </Button>
                  ) : null}
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => void onOpenInBrowser(selectedPosting.url)}
                  >
                    Open in browser
                  </Button>
                </>
              ) : null}
              <Button
                size="sm"
                variant="danger"
                onClick={() => void onDeletePosting(selectedPosting)}
              >
                Delete
              </Button>
              <Button size="sm" variant="ghost" onClick={onClearPostingSelection}>
                Close
              </Button>
            </div>
          </div>
        )}
      </TrailingInspector>
    </div>
  );
}
