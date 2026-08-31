import {
  AppCard,
  Button,
  EmptyState,
  ListRow,
  StatusChip,
  TrailingInspector,
} from "@/design-system";
import { formatDateLabel } from "../format";
import type { NetworkContactRow } from "../growthTypes";

export function CareerNetworkingView({
  contacts,
  selectedContact,
  onSelectContact,
  onCloseContact,
  onEditContact,
  onDeleteContact,
}: {
  contacts: NetworkContactRow[];
  selectedContact: NetworkContactRow | null;
  onSelectContact: (id: string) => void;
  onCloseContact: () => void;
  onEditContact: (contact: NetworkContactRow) => void;
  onDeleteContact: (contact: NetworkContactRow) => void;
}) {
  return (
    <div className="min-h-0 flex-1 p-3 pt-1">
      <TrailingInspector
        open={!!selectedContact}
        storageKey="career.inspectorWidth"
        main={
          <AppCard title="Contacts">
            {contacts.length === 0 ? (
              <EmptyState
                title="No contacts yet"
                body="Track recruiters, alumni, and mentors you meet along the way."
              />
            ) : (
              <ul className="divide-y divide-[var(--color-chrome-stroke)]">
                {contacts.map((contact) => (
                  <li key={contact.id}>
                    <ListRow
                      selected={selectedContact?.id === contact.id}
                      onClick={() => onSelectContact(contact.id)}
                      title={contact.name}
                      subtitle={[contact.roleTitle, contact.organization, contact.email]
                        .filter(Boolean)
                        .join(" · ")}
                      trailing={
                        <StatusChip
                          title={formatDateLabel(contact.lastContactAt)}
                          tint="var(--color-primary)"
                        />
                      }
                    />
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        }
      >
        {selectedContact && (
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
                {selectedContact.name}
              </h3>
              <p className="mt-0.5 text-meta">
                {[selectedContact.roleTitle, selectedContact.organization]
                  .filter(Boolean)
                  .join(" @ ") || "No org"}
              </p>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {selectedContact.email ? (
                  <StatusChip title={selectedContact.email} tint="var(--color-primary)" />
                ) : null}
                <StatusChip
                  title={`Last: ${formatDateLabel(selectedContact.lastContactAt)}`}
                  filled
                />
              </div>
            </div>
            <div className="min-h-0 flex-1 overflow-auto p-4">
              <p className="text-meta leading-relaxed">
                {selectedContact.notes.trim()
                  ? selectedContact.notes
                  : "No notes yet — add context when you edit this contact."}
              </p>
            </div>
            <div className="flex flex-wrap gap-2 border-t border-[var(--color-chrome-stroke)] p-3">
              <Button size="sm" variant="secondary" onClick={() => onEditContact(selectedContact)}>
                Edit
              </Button>
              <Button
                size="sm"
                variant="danger"
                onClick={() => onDeleteContact(selectedContact)}
              >
                Delete
              </Button>
              <Button size="sm" variant="ghost" onClick={onCloseContact}>
                Close
              </Button>
            </div>
          </div>
        )}
      </TrailingInspector>
    </div>
  );
}
