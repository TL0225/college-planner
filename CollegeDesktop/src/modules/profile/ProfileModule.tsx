import { useCallback, useMemo, useState } from "react";
import {
  AppCard,
  AppPageHeader,
  Button,
  EmptyState,
  FormField,
  MetricTile,
  ModalSheet,
  ProgressBar,
  StatusChip,
  fieldControlClass,
  NotesEditor,
} from "@/design-system";
import { ipc, formatIpcError, type ProfileIdentity } from "@/lib/ipc";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { useLiveQuery } from "@/lib/useLiveQuery";

type ProfileView = "identity" | "experiences" | "achievements" | "portfolio" | "advisor";

function resolveProfileView(page: string): ProfileView {
  if (page === "achievements") return "achievements";
  if (page === "experiences") return "experiences";
  if (page === "portfolio") return "portfolio";
  if (page === "advisor") return "advisor";
  return "identity";
}

const ADVISOR_CHECKLIST_KEYS = [
  "profile.advisor.transcript",
  "profile.advisor.degreeAudit",
  "profile.advisor.gradPlan",
  "profile.advisor.questions",
  "profile.advisor.internships",
] as const;

const ADVISOR_CHECKLIST_LABELS: Record<(typeof ADVISOR_CHECKLIST_KEYS)[number], string> = {
  "profile.advisor.transcript": "Bring unofficial transcript",
  "profile.advisor.degreeAudit": "Review degree audit gaps",
  "profile.advisor.gradPlan": "Update graduation plan",
  "profile.advisor.questions": "Prepare questions for advisor",
  "profile.advisor.internships": "Discuss internships / research",
};

export function ProfileModule({ page = "identity" }: { page?: string }) {
  const view = resolveProfileView(page);
  const [identity, setIdentity] = useState<ProfileIdentity | null>(null);
  const [experiences, setExperiences] = useState<
    Array<{
      id: string;
      title: string;
      organization: string;
      summary: string;
      startDate?: string | null;
      endDate?: string | null;
    }>
  >([]);
  const [achievements, setAchievements] = useState<
    Array<{ id: string; title: string; issuer: string; notes: string }>
  >([]);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [expSheet, setExpSheet] = useState(false);
  const [achSheet, setAchSheet] = useState(false);
  const [form, setForm] = useState({
    fullName: "",
    email: "",
    universityName: "",
    major: "",
    graduationYear: new Date().getFullYear() + 2,
  });
  const [expForm, setExpForm] = useState({
    title: "",
    organization: "",
    summary: "",
    startDate: "",
    endDate: "",
  });
  const [achForm, setAchForm] = useState({
    title: "",
    issuer: "",
    notes: "",
  });
  const [editingExpId, setEditingExpId] = useState<string | null>(null);
  const [editingAchId, setEditingAchId] = useState<string | null>(null);
  const [advisorChecks, setAdvisorChecks] = useState<Record<string, boolean>>({});
  type PortfolioProject = {
    id: string;
    title: string;
    role: string;
    tech: string;
    summary: string;
    url: string;
  };
  const [projects, setProjects] = useState<PortfolioProject[]>([]);
  const [phone, setPhone] = useState("");
  const [projectSheet, setProjectSheet] = useState(false);
  const [editingProjectId, setEditingProjectId] = useState<string | null>(null);
  const [projectForm, setProjectForm] = useState({
    title: "",
    role: "",
    tech: "",
    summary: "",
    url: "",
  });

  const load = useCallback(async () => {
    const [i, e, a, settings] = await Promise.all([
      ipc.profileGetIdentity(),
      ipc.profileListExperiences(),
      ipc.profileListAchievements(),
      ipc.settingsGet(),
    ]);
    setIdentity(i);
    setExperiences(e);
    setAchievements(a);
    const checks: Record<string, boolean> = {};
    for (const key of ADVISOR_CHECKLIST_KEYS) {
      checks[key] = settings.values[key] === "true";
    }
    setAdvisorChecks(checks);
    setPhone(settings.values["profile.phone"]?.trim() ?? "");
    try {
      const raw = settings.values["profile.portfolio.projects.v1"];
      const parsed = raw ? (JSON.parse(raw) as PortfolioProject[]) : [];
      setProjects(Array.isArray(parsed) ? parsed : []);
    } catch {
      setProjects([]);
    }
    setForm({
      fullName: i.fullName || "",
      email: i.email || "",
      universityName: i.universityName || "",
      major: i.major || "",
      graduationYear: i.graduationYear ?? new Date().getFullYear() + 2,
    });
  }, []);

  const { refresh, error } = useLiveQuery(load, ["profile"]);

  const profileCompleteness = useMemo(() => {
    let filled = 0;
    let total = 5;
    if (identity?.fullName?.trim()) filled += 1;
    if (identity?.email?.trim()) filled += 1;
    if (identity?.universityName?.trim()) filled += 1;
    if (identity?.major?.trim()) filled += 1;
    if (identity?.graduationYear != null) filled += 1;
    if (experiences.length > 0) {
      filled += 1;
      total += 1;
    } else total += 1;
    if (achievements.length > 0) {
      filled += 1;
      total += 1;
    } else total += 1;
    return { ratio: total > 0 ? filled / total : 0, filled, total };
  }, [identity, experiences.length, achievements.length]);

  const pageTitle =
    view === "achievements"
      ? "Achievements"
      : view === "experiences"
        ? "Experiences"
        : view === "portfolio"
          ? "Portfolio"
          : view === "advisor"
            ? "Advisor prep"
            : "Identity";

  const toggleAdvisorCheck = async (key: (typeof ADVISOR_CHECKLIST_KEYS)[number]) => {
    const next = !advisorChecks[key];
    setAdvisorChecks((prev) => ({ ...prev, [key]: next }));
    await ipc.settingsSet(key, next ? "true" : "false");
  };

  return (
    <div className="flex h-full flex-col">
      <AppPageHeader
        title={pageTitle}
        actions={
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={() => void refresh()}>
              Refresh
            </Button>
            {view === "achievements" ? (
              <Button
                size="sm"
                onClick={() => {
                  setEditingAchId(null);
                  setAchForm({ title: "", issuer: "", notes: "" });
                  setAchSheet(true);
                }}
              >
                Add achievement
              </Button>
            ) : view === "experiences" ? (
              <Button
                size="sm"
                onClick={() => {
                  setEditingExpId(null);
                  setExpForm({ title: "", organization: "", summary: "", startDate: "", endDate: "" });
                  setExpSheet(true);
                }}
              >
                Add experience
              </Button>
            ) : view === "portfolio" || view === "advisor" ? null : (
              <Button size="sm" onClick={() => setSheetOpen(true)}>
                Edit
              </Button>
            )}
          </div>
        }
      />
      {error && <p className="px-3 text-meta text-[var(--color-error)]">{error}</p>}

      {view === "identity" && (
        <div className="min-h-0 flex-1 overflow-auto p-3 pt-1">
          <AppCard title="Profile">
            <div
              className="mb-4 overflow-hidden px-4 py-4"
              style={{
                borderRadius: 12,
                border: "1px solid var(--color-chrome-stroke)",
                background:
                  "linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 10%, var(--color-surface)), var(--color-content-surface))",
                boxShadow: "inset 0 1px 0 color-mix(in srgb, white 40%, transparent)",
              }}
            >
              <div className="flex items-start gap-3">
                <span
                  className="flex h-12 w-12 shrink-0 items-center justify-center text-section-title font-semibold tracking-tight text-[var(--color-primary)]"
                  style={{
                    borderRadius: 999,
                    border: "1px solid var(--color-chrome-stroke)",
                    background: "var(--color-surface)",
                  }}
                >
                  {(identity?.fullName || "?").trim().charAt(0).toUpperCase() || "?"}
                </span>
                <div className="min-w-0">
                  <h3
                    className="truncate text-[var(--color-text-main)]"
                    style={{
                      font: "var(--type-section-title)",
                      fontSize: 18,
                      letterSpacing: "-0.02em",
                    }}
                  >
                    {identity?.fullName || "Your name"}
                  </h3>
                  <p className="mt-0.5 truncate text-meta">
                    {identity?.email || "No email yet"}
                  </p>
                  {phone ? (
                    <p className="mt-0.5 truncate text-meta">{phone}</p>
                  ) : null}
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {identity?.major ? (
                      <StatusChip title={identity.major} tint="var(--color-primary)" filled />
                    ) : null}
                    {identity?.graduationYear != null ? (
                      <StatusChip title={`Class of ${identity.graduationYear}`} />
                    ) : null}
                  </div>
                </div>
              </div>
            </div>
            <dl className="space-y-2.5 text-body">
              <Row label="University" value={identity?.universityName || "—"} />
              <Row label="Major" value={identity?.major || "—"} />
              <Row label="Phone" value={phone || "—"} />
              <Row
                label="Graduation"
                value={identity?.graduationYear != null ? String(identity.graduationYear) : "—"}
              />
            </dl>
            {experiences.length > 0 && (
              <p className="mt-4 text-meta">
                {experiences.length} experience{experiences.length === 1 ? "" : "s"} — open
                Experiences in the sidebar to manage roles and activities.
              </p>
            )}
          </AppCard>
        </div>
      )}

      {view === "experiences" && (
        <div className="min-h-0 flex-1 overflow-auto p-3 pt-1">
          <AppCard title="Roles & activities">
            {experiences.length === 0 ? (
              <EmptyState
                title="No experience yet"
                body="Add roles and activities, or load sample data from Settings."
              />
            ) : (
              <ul className="space-y-2">
                {experiences.map((e) => (
                  <li
                    key={e.id}
                    className="flex items-start gap-2 px-2.5 py-2.5"
                    style={{
                      borderRadius: 10,
                      border: "1px solid var(--color-chrome-stroke)",
                      background: "var(--color-content-surface)",
                    }}
                  >
                    <div className="min-w-0 flex-1">
                      <div className="text-section-title tracking-[-0.01em] text-[var(--color-text-main)]">
                        {e.title}
                      </div>
                      <div className="mt-1 flex flex-wrap items-center gap-1.5">
                        <StatusChip title={e.organization} filled />
                        {(e.startDate || e.endDate) && (
                          <span className="text-caption">
                            {[e.startDate?.slice(0, 10), e.endDate?.slice(0, 10)]
                              .filter(Boolean)
                              .join(" – ") || "Dates TBD"}
                          </span>
                        )}
                      </div>
                      {e.summary && (
                        <p className="mt-1.5 text-meta leading-relaxed">
                          {e.summary}
                        </p>
                      )}
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setEditingExpId(e.id);
                        setExpForm({
                          title: e.title,
                          organization: e.organization,
                          summary: e.summary,
                          startDate: e.startDate?.slice(0, 10) ?? "",
                          endDate: e.endDate?.slice(0, 10) ?? "",
                        });
                        setExpSheet(true);
                      }}
                    >
                      Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        if (!confirmDelete(e.title || "experience")) return;
                        void ipc
                          .profileDeleteExperience(e.id)
                          .then(() => showToast("Experience deleted", "success"))
                          .catch((err) => showToast(formatIpcError(err), "error"));
                      }}
                    >
                      Delete
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {view === "achievements" && (
        <div className="min-h-0 flex-1 overflow-auto p-3 pt-1">
          <AppCard title="Awards & certifications">
            {achievements.length === 0 ? (
              <EmptyState
                title="No achievements yet"
                body="Add awards, certifications, or honors — or load sample data from Settings."
              />
            ) : (
              <ul className="space-y-2">
                {achievements.map((a) => (
                  <li
                    key={a.id}
                    className="flex items-start gap-2 px-2.5 py-2.5"
                    style={{
                      borderRadius: 10,
                      border: "1px solid var(--color-chrome-stroke)",
                      background: "var(--color-content-surface)",
                      boxShadow: "inset 0 1px 0 color-mix(in srgb, white 30%, transparent)",
                    }}
                  >
                    <div className="min-w-0 flex-1">
                      <div className="text-section-title tracking-[-0.01em] text-[var(--color-text-main)]">
                        {a.title}
                      </div>
                      <div className="mt-1">
                        <StatusChip
                          title={a.issuer || "Award"}
                          tint="var(--color-warning)"
                          filled
                        />
                      </div>
                      {a.notes && (
                        <p className="mt-1.5 text-meta leading-relaxed">
                          {a.notes}
                        </p>
                      )}
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setEditingAchId(a.id);
                        setAchForm({ title: a.title, issuer: a.issuer, notes: a.notes });
                        setAchSheet(true);
                      }}
                    >
                      Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        if (!confirmDelete(a.title || "achievement")) return;
                        void ipc
                          .profileDeleteAchievement(a.id)
                          .then(() => showToast("Achievement deleted", "success"))
                          .catch((err) => showToast(formatIpcError(err), "error"));
                      }}
                    >
                      Delete
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </AppCard>
        </div>
      )}

      {view === "portfolio" && (
        <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3 pt-1">
          <div className="grid gap-2.5 sm:grid-cols-3">
            <MetricTile
              label="Profile completeness"
              value={`${Math.round(profileCompleteness.ratio * 100)}%`}
              accent="var(--color-primary)"
            />
            <MetricTile label="Experiences" value={experiences.length} />
            <MetricTile label="Achievements" value={achievements.length} accent="var(--color-warning)" />
          </div>
          <AppCard title="Portfolio snapshot">
            <div className="flex flex-wrap items-center gap-4">
              <ProgressRing ratio={profileCompleteness.ratio} label={`${profileCompleteness.filled}/${profileCompleteness.total}`} />
              <div className="min-w-0 flex-1">
                <p className="text-section-title text-[var(--color-text-main)]">
                  {identity?.fullName || "Your portfolio"}
                </p>
                <p className="mt-1 text-meta">
                  {identity?.major || "Add your major"} ·{" "}
                  {identity?.universityName || "Add your university"}
                </p>
                <ProgressBar value={profileCompleteness.ratio} className="mt-3" height={8} />
              </div>
            </div>
          </AppCard>
          <div className="grid gap-3 lg:grid-cols-2">
            <AppCard title="Portfolio projects">
              <div className="mb-3 flex justify-end">
                <Button
                  size="sm"
                  onClick={() => {
                    setEditingProjectId(null);
                    setProjectForm({ title: "", role: "", tech: "", summary: "", url: "" });
                    setProjectSheet(true);
                  }}
                >
                  Add project
                </Button>
              </div>
              {projects.length === 0 ? (
                <EmptyState
                  title="No projects"
                  body="Showcase coursework, research, or side projects on your portfolio."
                />
              ) : (
                <ul className="space-y-2">
                  {projects.map((p) => (
                    <li
                      key={p.id}
                      className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="text-section-title">{p.title}</div>
                          {p.role ? (
                            <div className="mt-0.5 text-caption">
                              {p.role}
                            </div>
                          ) : null}
                          {p.tech ? (
                            <StatusChip title={p.tech} filled className="mt-1" />
                          ) : null}
                        </div>
                        <div className="flex shrink-0 gap-1">
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => {
                              setEditingProjectId(p.id);
                              setProjectForm({
                                title: p.title,
                                role: p.role,
                                tech: p.tech,
                                summary: p.summary,
                                url: p.url,
                              });
                              setProjectSheet(true);
                            }}
                          >
                            Edit
                          </Button>
                          <Button
                            size="sm"
                            variant="danger"
                            onClick={async () => {
                              if (!confirmDelete(p.title)) return;
                              const next = projects.filter((x) => x.id !== p.id);
                              await ipc.settingsSet(
                                "profile.portfolio.projects.v1",
                                JSON.stringify(next),
                              );
                              setProjects(next);
                            }}
                          >
                            Delete
                          </Button>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
            <AppCard title="Experiences">
              {experiences.length === 0 ? (
                <EmptyState title="No experiences" body="Add roles under Experiences in the sidebar." />
              ) : (
                <ul className="space-y-2">
                  {experiences.slice(0, 4).map((e) => (
                    <li
                      key={e.id}
                      className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                    >
                      <div className="text-section-title">{e.title}</div>
                      <StatusChip title={e.organization} filled className="mt-1" />
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
            <AppCard title="Achievements">
              {achievements.length === 0 ? (
                <EmptyState title="No achievements" body="Add awards under Achievements in the sidebar." />
              ) : (
                <ul className="space-y-2">
                  {achievements.slice(0, 4).map((a) => (
                    <li
                      key={a.id}
                      className="rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2"
                    >
                      <div className="text-section-title">{a.title}</div>
                      {a.issuer ? (
                        <StatusChip title={a.issuer} tint="var(--color-warning)" filled className="mt-1" />
                      ) : null}
                    </li>
                  ))}
                </ul>
              )}
            </AppCard>
          </div>
        </div>
      )}

      {view === "advisor" && (
        <div className="min-h-0 flex-1 space-y-3 overflow-auto p-3 pt-1">
          <AppCard title="Meeting checklist">
            <p className="mb-3 text-meta">
              Track what to bring and discuss before your next advisor meeting. Progress is saved
              locally.
            </p>
            <ul className="space-y-2">
              {ADVISOR_CHECKLIST_KEYS.map((key) => (
                <li key={key}>
                  <label className="flex cursor-pointer items-start gap-2.5 rounded-[10px] border border-[var(--color-chrome-stroke)] px-3 py-2.5 hover:bg-[var(--color-row-hover)]">
                    <input
                      type="checkbox"
                      checked={Boolean(advisorChecks[key])}
                      onChange={() => void toggleAdvisorCheck(key)}
                      className="mt-0.5"
                    />
                    <span
                      className={`text-body ${
                        advisorChecks[key]
                          ? "text-[var(--color-text-light)] line-through"
                          : "text-[var(--color-text-main)]"
                      }`}
                    >
                      {ADVISOR_CHECKLIST_LABELS[key]}
                    </span>
                  </label>
                </li>
              ))}
            </ul>
          </AppCard>
          <AppCard title="Quick context">
            <dl className="space-y-2 text-body">
              <Row label="Major" value={identity?.major || "—"} />
              <Row
                label="Graduation"
                value={identity?.graduationYear != null ? String(identity.graduationYear) : "—"}
              />
              <Row label="Experiences logged" value={String(experiences.length)} />
              <Row label="Achievements logged" value={String(achievements.length)} />
            </dl>
          </AppCard>
        </div>
      )}

      <ModalSheet open={sheetOpen} onOpenChange={setSheetOpen} title="Edit identity">
        <div className="space-y-3">
          {(
            [
              ["Full name", "fullName"],
              ["Email", "email"],
              ["University", "universityName"],
              ["Major", "major"],
            ] as const
          ).map(([label, key]) => (
            <FormField key={key} label={label}>
              <input
                className={fieldControlClass}
                value={form[key]}
                onChange={(e) => setForm({ ...form, [key]: e.target.value })}
              />
            </FormField>
          ))}
          <FormField label="Graduation year">
            <input
              className={fieldControlClass}
              type="number"
              value={form.graduationYear}
              onChange={(e) => setForm({ ...form, graduationYear: Number(e.target.value) })}
            />
          </FormField>
          <Button
            disabled={!form.fullName.trim()}
            onClick={async () => {
              await ipc.profileUpsertIdentity({
                fullName: form.fullName.trim(),
                email: form.email.trim() || undefined,
                universityName: form.universityName.trim() || undefined,
                major: form.major.trim() || undefined,
                graduationYear: form.graduationYear,
              });
              setSheetOpen(false);
            }}
          >
            Save
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={expSheet}
        onOpenChange={setExpSheet}
        title={editingExpId ? "Edit experience" : "Add experience"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={expForm.title}
              onChange={(e) => setExpForm({ ...expForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Organization">
            <input
              className={fieldControlClass}
              value={expForm.organization}
              onChange={(e) => setExpForm({ ...expForm, organization: e.target.value })}
            />
          </FormField>
          <FormField label="Summary">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={expForm.summary}
              onChange={(e) => setExpForm({ ...expForm, summary: e.target.value })}
            />
          </FormField>
          <div className="grid gap-3 sm:grid-cols-2">
            <FormField label="Start date">
              <input
                type="date"
                className={fieldControlClass}
                value={expForm.startDate}
                onChange={(e) => setExpForm({ ...expForm, startDate: e.target.value })}
              />
            </FormField>
            <FormField label="End date">
              <input
                type="date"
                className={fieldControlClass}
                value={expForm.endDate}
                onChange={(e) => setExpForm({ ...expForm, endDate: e.target.value })}
              />
            </FormField>
          </div>
          <Button
            disabled={!expForm.title.trim() || !expForm.organization.trim()}
            onClick={async () => {
              try {
                await ipc.profileUpsertExperience({
                  id: editingExpId ?? undefined,
                  title: expForm.title.trim(),
                  organization: expForm.organization.trim(),
                  summary: expForm.summary.trim() || undefined,
                  startDate: expForm.startDate.trim() || undefined,
                  endDate: expForm.endDate.trim() || undefined,
                });
                setExpSheet(false);
                setEditingExpId(null);
                setExpForm({ title: "", organization: "", summary: "", startDate: "", endDate: "" });
                showToast(editingExpId ? "Experience updated" : "Experience saved", "success");
              } catch (err) {
                showToast(formatIpcError(err), "error");
              }
            }}
          >
            {editingExpId ? "Save changes" : "Save experience"}
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={achSheet}
        onOpenChange={setAchSheet}
        title={editingAchId ? "Edit achievement" : "Add achievement"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={achForm.title}
              onChange={(e) => setAchForm({ ...achForm, title: e.target.value })}
            />
          </FormField>
          <FormField label="Issuer">
            <input
              className={fieldControlClass}
              value={achForm.issuer}
              onChange={(e) => setAchForm({ ...achForm, issuer: e.target.value })}
            />
          </FormField>
          <FormField label="Notes">
            <NotesEditor
              value={achForm.notes}
              onChange={(notes) => setAchForm({ ...achForm, notes })}
              minRows={3}
            />
          </FormField>
          <Button
            disabled={!achForm.title.trim()}
            onClick={async () => {
              try {
                await ipc.profileUpsertAchievement({
                  id: editingAchId ?? undefined,
                  title: achForm.title.trim(),
                  issuer: achForm.issuer.trim() || undefined,
                  notes: achForm.notes.trim() || undefined,
                });
                setAchSheet(false);
                setEditingAchId(null);
                setAchForm({ title: "", issuer: "", notes: "" });
                showToast(editingAchId ? "Achievement updated" : "Achievement saved", "success");
              } catch (err) {
                showToast(formatIpcError(err), "error");
              }
            }}
          >
            {editingAchId ? "Save changes" : "Save achievement"}
          </Button>
        </div>
      </ModalSheet>

      <ModalSheet
        open={projectSheet}
        onOpenChange={setProjectSheet}
        title={editingProjectId ? "Edit project" : "Add project"}
      >
        <div className="space-y-3">
          <FormField label="Title">
            <input
              className={fieldControlClass}
              value={projectForm.title}
              onChange={(e) => setProjectForm((f) => ({ ...f, title: e.target.value }))}
            />
          </FormField>
          <FormField label="Role">
            <input
              className={fieldControlClass}
              value={projectForm.role}
              onChange={(e) => setProjectForm((f) => ({ ...f, role: e.target.value }))}
            />
          </FormField>
          <FormField label="Tech stack">
            <input
              className={fieldControlClass}
              value={projectForm.tech}
              onChange={(e) => setProjectForm((f) => ({ ...f, tech: e.target.value }))}
            />
          </FormField>
          <FormField label="Summary">
            <textarea
              className={fieldControlClass}
              rows={3}
              value={projectForm.summary}
              onChange={(e) => setProjectForm((f) => ({ ...f, summary: e.target.value }))}
            />
          </FormField>
          <FormField label="URL">
            <input
              className={fieldControlClass}
              value={projectForm.url}
              onChange={(e) => setProjectForm((f) => ({ ...f, url: e.target.value }))}
            />
          </FormField>
          <Button
            onClick={async () => {
              const row: PortfolioProject = {
                id: editingProjectId ?? crypto.randomUUID(),
                title: projectForm.title.trim(),
                role: projectForm.role.trim(),
                tech: projectForm.tech.trim(),
                summary: projectForm.summary.trim(),
                url: projectForm.url.trim(),
              };
              if (!row.title) {
                showToast("Title is required", "error");
                return;
              }
              const next = editingProjectId
                ? projects.map((p) => (p.id === editingProjectId ? row : p))
                : [...projects, row];
              try {
                await ipc.settingsSet("profile.portfolio.projects.v1", JSON.stringify(next));
                setProjects(next);
                setProjectSheet(false);
                showToast(editingProjectId ? "Project updated" : "Project added", "success");
              } catch (err) {
                showToast(formatIpcError(err), "error");
              }
            }}
          >
            Save project
          </Button>
        </div>
      </ModalSheet>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-[var(--color-text-light)]">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </div>
  );
}

function ProgressRing({ ratio, label }: { ratio: number; label: string }) {
  const pct = Math.round(Math.min(1, Math.max(0, ratio)) * 100);
  const r = 36;
  const c = 2 * Math.PI * r;
  const offset = c * (1 - pct / 100);
  return (
    <div className="relative flex h-[88px] w-[88px] shrink-0 items-center justify-center">
      <svg width={88} height={88} viewBox="0 0 88 88" aria-hidden>
        <circle
          cx={44}
          cy={44}
          r={r}
          fill="none"
          stroke="var(--color-chrome-stroke)"
          strokeWidth={6}
        />
        <circle
          cx={44}
          cy={44}
          r={r}
          fill="none"
          stroke="var(--color-primary)"
          strokeWidth={6}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={offset}
          transform="rotate(-90 44 44)"
        />
      </svg>
      <div className="absolute text-center">
        <div
          className="text-section-title font-semibold tabular-nums text-[var(--color-text-main)]"
          style={{ fontSize: 15 }}
        >
          {pct}%
        </div>
        <div className="text-caption">{label}</div>
      </div>
    </div>
  );
}
