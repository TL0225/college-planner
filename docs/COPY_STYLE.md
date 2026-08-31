# Copy style guide

User-facing strings in College Desktop follow these rules.

## Voice

- **Sentence case** for labels, buttons, and sidebar items: "Add event" not "Add Event"
- **Verb-first buttons**: "Add course", "Import receipt", "Connect account"
- **Plain language**: "Degree progress" not "Audit panel"
- **Actionable empty states**: "No events today" + button "Add event"
- **Errors say what to do**: "Couldn't save — check your connection and try again"

## Hub vocabulary

| Hub | Use in UI | Avoid |
|-----|-----------|-------|
| Home | Home | Overview (as hub name) |
| School | School | College, Academics (as hub name) |
| Career | Career | — |
| Life | Life | Finance + Calendar (as separate hubs) |
| Library | Library | Documents, Profile (as hub names) |

Internal page IDs may differ from display labels.

## Typography classes

Use semantic utilities from `styles.css`: `text-page-title`, `text-section-title`, `text-body`, `text-chrome`, `text-caption`.

Do not add `text-[Npx]` in `modules/` — use design-system tokens only.
