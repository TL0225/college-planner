import { openPath, revealItemInDir } from "@tauri-apps/plugin-opener";
import { Button } from "@/design-system";
import { CareerPageHeader } from "./CareerPageHeader";
import { ipc, formatIpcError } from "@/lib/ipc";
import { CareerStatsView } from "./views/CareerStatsView";
import { CareerApplyView } from "./views/CareerApplyView";
import { CareerBragView } from "./views/CareerBragView";
import { CareerNetworkingView } from "./views/CareerNetworkingView";
import { CareerInterviewView } from "./views/CareerInterviewView";
import { CareerPipelineView } from "./views/CareerPipelineView";
import { CareerOpeningsView } from "./views/CareerOpeningsView";
import { CareerResumesView } from "./views/CareerResumesView";
import { CareerPathingView } from "./views/CareerPathingView";
import { confirmDelete } from "@/lib/confirm";
import { showToast } from "@/lib/toast";
import { openResumePopOutWindow } from "./openResumePopOut";
import { CareerModals } from "./CareerModals";
import { useCareerModule } from "./useCareerModule";

export function CareerModule({ page = "applications" }: { page?: string }) {
  const m = useCareerModule(page);

  return (
    <div className="relative flex h-full flex-col">
      <CareerPageHeader
        shellView={m.shellView}
        layout={m.layout}
        onLayoutChange={m.setLayout}
        onRefresh={() => void m.refresh()}
        actions={
          <>
            {m.shellView === "openings" ? (
              <>
                <Button size="sm" variant="secondary" onClick={() => m.openSmartBoardEditor()}>
                  Smart board
                </Button>
                <Button size="sm" variant="secondary" onClick={() => m.setSyncBoardsSheet(true)}>
                  Find new jobs
                </Button>
                <Button size="sm" variant="secondary" onClick={() => m.setImportUrlSheet(true)}>
                  Import from URL
                </Button>
                <Button size="sm" onClick={() => m.setPostingSheet(true)}>
                  Add opening
                </Button>
              </>
            ) : m.shellView === "pathing" ? (
              <Button
                size="sm"
                onClick={() => {
                  m.setEditingPathId(null);
                  m.setPathForm({
                    organization: "",
                    roleTitle: "",
                    startDate: "",
                    endDate: "",
                    summary: "",
                  });
                  m.setPathSheet(true);
                }}
              >
                Add path entry
              </Button>
            ) : m.shellView === "brag" ? (
              <Button size="sm" onClick={() => m.openBragEditor()}>
                Add win
              </Button>
            ) : m.shellView === "networking" ? (
              <Button size="sm" onClick={() => m.openContactEditor()}>
                Add contact
              </Button>
            ) : m.shellView === "interview" ? (
              <Button size="sm" onClick={() => m.openInterviewEditor()}>
                Add prep
              </Button>
            ) : m.shellView === "resumes" ? (
              <>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => void openResumePopOutWindow()}
                >
                  Pop out
                </Button>
                <Button
                  size="sm"
                  disabled={m.draftBusy}
                  onClick={() => void m.generateResumeDraft(false)}
                >
                  {m.draftBusy ? "Loading…" : "New draft"}
                </Button>
              </>
            ) : m.shellView === "stats" || m.shellView === "apply" ? null : (
              <Button
                size="sm"
                onClick={() => {
                  m.setEditingAppId(null);
                  m.setForm({ company: "", roleTitle: "", status: "interested", location: "", url: "" });
                  m.setSheetOpen(true);
                }}
              >
                Add application
              </Button>
            )}
          </>
        }
      />
      {m.error && <p className="px-3 text-meta text-[var(--color-error)]">{m.error}</p>}

      {m.shellView === "openings" && (
        <CareerOpeningsView
          openingsScope={m.openingsScope}
          companyBoards={m.companyBoards}
          smartBoards={m.smartBoards}
          visiblePostings={m.visiblePostings}
          smartBoardPostingsBusy={m.smartBoardPostingsBusy}
          selectedPostingId={m.selectedPostingId}
          selectedPosting={m.selectedPosting}
          lastApplyPostingId={m.lastApplyPostingId}
          onScopeAll={() => {
            m.setOpeningsScope({ kind: "all" });
            m.setSelectedPostingId(null);
          }}
          onScopeCompany={(id, name) => {
            m.setOpeningsScope({ kind: "company", id, name });
            m.setSelectedPostingId(null);
          }}
          onScopeSmartBoard={(id, name) => {
            m.setOpeningsScope({ kind: "smartBoard", id, name });
            m.setSelectedPostingId(null);
          }}
          onOpenSmartBoardEditor={(board) => {
            const full = board ? m.smartBoards.find((b) => b.id === board.id) : undefined;
            m.openSmartBoardEditor(full);
          }}
          onSelectPosting={m.setSelectedPostingId}
          onClearPostingSelection={() => m.setSelectedPostingId(null)}
          onTrackPosting={async (postingId) => {
            try {
              await ipc.careerTrackJobPosting(postingId);
              showToast("Added to pipeline", "success");
            } catch (err) {
              showToast(formatIpcError(err), "error");
            }
          }}
          onApplyInCollege={(posting) => void m.openApplyForPosting(posting)}
          onMarkApplied={(posting) => void m.markPostingApplyComplete(posting)}
          onOpenInBrowser={(url) => void m.openPostingInBrowser(url)}
          onDeletePosting={async (posting) => {
            if (!confirmDelete(posting.title || "opening")) return;
            try {
              await ipc.careerDeleteJobPosting(posting.id);
              m.setSelectedPostingId(null);
              showToast("Opening deleted", "success");
            } catch (err) {
              showToast(formatIpcError(err), "error");
            }
          }}
        />
      )}

      {m.shellView === "resumes" && (
        <CareerResumesView
          resumeMetrics={m.resumeMetrics}
          resumeLibrary={m.resumeLibrary}
          resumeProfileByVaultId={m.resumeProfileByVaultId}
          builderLoadNonce={m.builderLoadNonce}
          includeBragInDraft={m.includeBragInDraft}
          builderTailoring={m.builderTailoring}
          selectedResumeId={m.selectedResumeId}
          selectedResume={m.selectedResume}
          selectedResumeProfile={m.selectedResumeProfile}
          tailoringForm={m.tailoringForm}
          tailoringBusy={m.tailoringBusy}
          resumeText={m.resumeText}
          jobText={m.jobText}
          matchBusy={m.matchBusy}
          matchResult={m.matchResult}
          onIncludeBragBookChange={m.setIncludeBragInDraft}
          onDraftOutputsChange={({ markdown, typst }) => {
            m.setDraftMarkdown(markdown);
            m.setDraftTypst(typst);
          }}
          onOpenSourceSheet={() => {
            m.setDraftPane("preview");
            m.setDraftPreviewAs("markdown");
            m.setDraftSheet(true);
          }}
          onSelectResume={m.setSelectedResumeId}
          onClearResumeSelection={() => m.setSelectedResumeId(null)}
          onTailoringFormChange={m.setTailoringForm}
          onSaveTailoringNotes={async () => {
            if (!m.selectedResume) return;
            m.setTailoringBusy(true);
            try {
              await ipc.careerUpsertResumeProfile({
                vaultDocId: m.selectedResume.id,
                targetRole: m.tailoringForm.targetRole.trim(),
                targetCompany: m.tailoringForm.targetCompany.trim(),
                notes: m.tailoringForm.notes.trim(),
              });
              const [profiles, rMetrics] = await Promise.all([
                ipc.careerListResumeProfiles(),
                ipc.careerResumeMetrics(),
              ]);
              m.setResumeProfiles(profiles);
              m.setResumeMetrics(rMetrics);
              showToast("Tailoring notes saved", "success");
            } catch (e) {
              showToast(formatIpcError(e), "error");
            } finally {
              m.setTailoringBusy(false);
            }
          }}
          onOpenResume={async () => {
            if (!m.selectedResume?.hasFile) return;
            const resolved = await ipc.documentsResolvePath(m.selectedResume.id);
            if (!resolved) return;
            await openPath(resolved);
          }}
          onRevealResume={async () => {
            if (!m.selectedResume?.hasFile) return;
            const resolved = await ipc.documentsResolvePath(m.selectedResume.id);
            if (!resolved) return;
            await revealItemInDir(resolved);
          }}
          onResumeTextChange={m.setResumeText}
          onJobTextChange={m.setJobText}
          onMatchKeywords={async () => {
            m.setMatchBusy(true);
            try {
              const res = await ipc.careerResumeKeywordMatch({
                resumeText: m.resumeText,
                jobText: m.jobText,
              });
              m.setMatchResult(res);
              const rMetrics = await ipc.careerResumeMetrics();
              m.setResumeMetrics(rMetrics);
            } finally {
              m.setMatchBusy(false);
            }
          }}
        />
      )}

      {(m.shellView === "applications" || m.shellView === "board") && (
        <CareerPipelineView
          metrics={m.metrics}
          apps={m.apps}
          effectiveLayout={m.effectiveLayout}
          byStatus={m.byStatus}
          selected={m.selected}
          selectedApp={m.selectedApp}
          dropTargetStatus={m.dropTargetStatus}
          lastApplySessionId={m.lastApplySessionId}
          interviewTimeline={m.interviewTimeline}
          onSelectApp={m.setSelected}
          onClearSelection={() => m.setSelected(null)}
          onLaneDragOver={m.handleLaneDragOver}
          onLaneDragLeave={(status) =>
            m.setDropTargetStatus((prev) => (prev === status ? null : prev))
          }
          onLaneDrop={m.handleLaneDrop}
          onStatusChange={async (appId, status) => {
            try {
              await ipc.careerMoveApplication(appId, status);
            } catch (err) {
              showToast(formatIpcError(err), "error");
            }
          }}
          onApplyInCollege={(app) => void m.openApplyForApp(app)}
          onMarkApplied={(appId) => void m.markApplyComplete(appId)}
          onOpenInBrowser={(url) => void m.openPostingInBrowser(url)}
          onEditApp={(app) => {
            m.setEditingAppId(app.id);
            m.setForm({
              company: app.company,
              roleTitle: app.roleTitle,
              status: app.status,
              location: app.location || "",
              url: app.url || "",
            });
            m.setSheetOpen(true);
          }}
          onDeleteApp={async (app) => {
            if (!confirmDelete(`${app.roleTitle} @ ${app.company}`)) return;
            try {
              await ipc.careerDeleteApplication(app.id);
              m.setSelected(null);
              showToast("Application deleted", "success");
            } catch (e) {
              showToast(formatIpcError(e), "error");
            }
          }}
        />
      )}

      {m.shellView === "pathing" && (
        <CareerPathingView
          pathByOrg={m.pathByOrg}
          byOrg={m.byOrg}
          selectedPathId={m.selectedPathId}
          selectedPath={m.selectedPath}
          selectedAppId={m.selected}
          pathInspectorTab={m.pathInspectorTab}
          pathPipeline={m.pathPipeline}
          pathDocuments={m.pathDocuments}
          vaultDocs={m.vaultDocs}
          relatedPathApplications={m.relatedPathApplications}
          pathMilestones={m.pathMilestones}
          pathMilestoneProgress={m.pathMilestoneProgress}
          milestonesByLane={m.milestonesByLane}
          pathJournalEntries={m.pathJournalEntries}
          pathPromotions={m.pathPromotions}
          pathPeople={m.pathPeople}
          skillNameDraft={m.skillNameDraft}
          careerSkills={m.careerSkills}
          bragEntries={m.bragEntries}
          pathBenefits={m.pathBenefits}
          pathCompensation={m.pathCompensation}
          employmentTerms={m.employmentTerms}
          decisionJournal={m.decisionJournal}
          employmentBusy={m.employmentBusy}
          decisionBusy={m.decisionBusy}
          pathEntries={m.pathEntries}
          onSelectPathId={m.setSelectedPathId}
          onClearPathSelection={() => m.setSelectedPathId(null)}
          onSelectAppId={m.setSelected}
          onPathInspectorTabChange={m.setPathInspectorTab}
          onOpenPathDocLink={() => m.setPathDocLinkSheet(true)}
          onPathDocumentsChange={m.setPathDocuments}
          onPathBenefitsChange={m.setPathBenefits}
          onPathPipelineChange={m.setPathPipeline}
          onCareerSkillsChange={m.setCareerSkills}
          onSkillNameDraftChange={m.setSkillNameDraft}
          onPathCompensationChange={m.setPathCompensation}
          onEmploymentTermsChange={m.setEmploymentTerms}
          onEmploymentBusyChange={m.setEmploymentBusy}
          onDecisionJournalChange={m.setDecisionJournal}
          onDecisionBusyChange={m.setDecisionBusy}
          onOpenMilestoneEditor={m.openMilestoneEditor}
          onOpenJournalEditor={m.openJournalEditor}
          onOpenPromotionEditor={m.openPromotionEditor}
          onOpenPersonEditor={m.openPersonEditor}
          onOpenCompensationEditor={m.openCompensationEditor}
          onOpenPathEditor={m.openPathEditor}
          onDeletePathEntry={async (entry) => {
            if (
              !confirmDelete(
                `${entry.roleTitle.trim() || "entry"} @ ${entry.organization.trim() || "org"}`,
              )
            )
              return;
            try {
              await ipc.careerDeletePathEntry(entry.id);
              m.setSelectedPathId(null);
              showToast("Path entry deleted", "success");
            } catch (e) {
              showToast(formatIpcError(e), "error");
            }
          }}
          onOpenBragBook={m.openBragBook}
          onPathMerged={(targetId, entries) => {
            m.setPathEntries(entries);
            m.setSelectedPathId(targetId);
            m.setPathInspectorTab("overview");
          }}
          onResumeDocumentSaved={(entryId, resumeDocumentId) => {
            m.setPathEntries((prev) =>
              prev.map((e) => (e.id === entryId ? { ...e, resumeDocumentId } : e)),
            );
          }}
        />
      )}

      {m.shellView === "stats" && (
        <CareerStatsView metrics={m.metrics} appCount={m.apps.length} />
      )}

      {m.shellView === "apply" && <CareerApplyView />}

      {m.shellView === "brag" && (
        <CareerBragView entries={m.bragEntries} onOpenEntry={m.openBragEditor} />
      )}

      {m.shellView === "networking" && (
        <CareerNetworkingView
          contacts={m.networkContacts}
          selectedContact={m.selectedContact}
          onSelectContact={m.setSelectedContactId}
          onCloseContact={() => m.setSelectedContactId(null)}
          onEditContact={m.openContactEditor}
          onDeleteContact={async (contact) => {
            if (!confirmDelete(contact.name || "contact")) return;
            try {
              await ipc.careerDeleteNetworkContact(contact.id);
              m.setSelectedContactId(null);
              showToast("Contact deleted", "success");
            } catch (e) {
              showToast(formatIpcError(e), "error");
            }
          }}
        />
      )}

      {m.shellView === "interview" && (
        <CareerInterviewView
          prepRows={m.interviewPrep}
          apps={m.apps}
          onOpenPrep={m.openInterviewEditor}
        />
      )}

      <CareerModals
        sheetOpen={m.sheetOpen}
        setSheetOpen={m.setSheetOpen}
        editingAppId={m.editingAppId}
        setEditingAppId={m.setEditingAppId}
        form={m.form}
        setForm={m.setForm}
        pathSheet={m.pathSheet}
        setPathSheet={m.setPathSheet}
        editingPathId={m.editingPathId}
        setEditingPathId={m.setEditingPathId}
        pathForm={m.pathForm}
        setPathForm={m.setPathForm}
        setSelectedPathId={m.setSelectedPathId}
        postingSheet={m.postingSheet}
        setPostingSheet={m.setPostingSheet}
        postingForm={m.postingForm}
        setPostingForm={m.setPostingForm}
        importUrlSheet={m.importUrlSheet}
        setImportUrlSheet={m.setImportUrlSheet}
        importUrl={m.importUrl}
        setImportUrl={m.setImportUrl}
        importUrlBusy={m.importUrlBusy}
        setImportUrlBusy={m.setImportUrlBusy}
        setSelectedPostingId={m.setSelectedPostingId}
        refresh={m.refresh}
        smartBoardSheet={m.smartBoardSheet}
        setSmartBoardSheet={m.setSmartBoardSheet}
        editingSmartBoardId={m.editingSmartBoardId}
        setEditingSmartBoardId={m.setEditingSmartBoardId}
        smartBoardBusy={m.smartBoardBusy}
        setSmartBoardBusy={m.setSmartBoardBusy}
        smartBoardForm={m.smartBoardForm}
        setSmartBoardForm={m.setSmartBoardForm}
        companyBoards={m.companyBoards}
        setCompanyBoards={m.setCompanyBoards}
        setSmartBoards={m.setSmartBoards}
        openingsScope={m.openingsScope}
        setOpeningsScope={m.setOpeningsScope}
        syncBoardsSheet={m.syncBoardsSheet}
        setSyncBoardsSheet={m.setSyncBoardsSheet}
        syncBoardResult={m.syncBoardResult}
        setSyncBoardResult={m.setSyncBoardResult}
        syncBoardsBusy={m.syncBoardsBusy}
        setSyncBoardsBusy={m.setSyncBoardsBusy}
        syncBoardSources={m.syncBoardSources}
        setSyncBoardSources={m.setSyncBoardSources}
        syncCompaniesBusy={m.syncCompaniesBusy}
        setSyncCompaniesBusy={m.setSyncCompaniesBusy}
        companyBoardForm={m.companyBoardForm}
        setCompanyBoardForm={m.setCompanyBoardForm}
        companyBoardBusy={m.companyBoardBusy}
        setCompanyBoardBusy={m.setCompanyBoardBusy}
        eventSheet={m.eventSheet}
        setEventSheet={m.setEventSheet}
        editingEventId={m.editingEventId}
        setEditingEventId={m.setEditingEventId}
        eventForm={m.eventForm}
        setEventForm={m.setEventForm}
        selectedApp={m.selectedApp}
        reloadCareerEvents={m.reloadCareerEvents}
        bragSheet={m.bragSheet}
        setBragSheet={m.setBragSheet}
        editingBragId={m.editingBragId}
        setEditingBragId={m.setEditingBragId}
        bragForm={m.bragForm}
        setBragForm={m.setBragForm}
        contactSheet={m.contactSheet}
        setContactSheet={m.setContactSheet}
        editingContactId={m.editingContactId}
        setEditingContactId={m.setEditingContactId}
        contactForm={m.contactForm}
        setContactForm={m.setContactForm}
        setSelectedContactId={m.setSelectedContactId}
        milestoneSheet={m.milestoneSheet}
        setMilestoneSheet={m.setMilestoneSheet}
        editingMilestoneId={m.editingMilestoneId}
        setEditingMilestoneId={m.setEditingMilestoneId}
        milestoneForm={m.milestoneForm}
        setMilestoneForm={m.setMilestoneForm}
        selectedPath={m.selectedPath}
        setPathMilestones={m.setPathMilestones}
        setPathPipeline={m.setPathPipeline}
        compensationSheet={m.compensationSheet}
        setCompensationSheet={m.setCompensationSheet}
        editingCompensationId={m.editingCompensationId}
        setEditingCompensationId={m.setEditingCompensationId}
        compensationForm={m.compensationForm}
        setCompensationForm={m.setCompensationForm}
        setPathCompensation={m.setPathCompensation}
        journalSheet={m.journalSheet}
        setJournalSheet={m.setJournalSheet}
        editingJournalId={m.editingJournalId}
        setEditingJournalId={m.setEditingJournalId}
        journalForm={m.journalForm}
        setJournalForm={m.setJournalForm}
        setPathJournalEntries={m.setPathJournalEntries}
        promotionSheet={m.promotionSheet}
        setPromotionSheet={m.setPromotionSheet}
        editingPromotionId={m.editingPromotionId}
        setEditingPromotionId={m.setEditingPromotionId}
        promotionForm={m.promotionForm}
        setPromotionForm={m.setPromotionForm}
        setPathPromotions={m.setPathPromotions}
        personSheet={m.personSheet}
        setPersonSheet={m.setPersonSheet}
        editingPersonId={m.editingPersonId}
        setEditingPersonId={m.setEditingPersonId}
        personForm={m.personForm}
        setPersonForm={m.setPersonForm}
        setPathPeople={m.setPathPeople}
        pathDocLinkSheet={m.pathDocLinkSheet}
        setPathDocLinkSheet={m.setPathDocLinkSheet}
        linkableVaultDocs={m.linkableVaultDocs}
        vaultDocs={m.vaultDocs}
        setPathDocuments={m.setPathDocuments}
        interviewSheet={m.interviewSheet}
        setInterviewSheet={m.setInterviewSheet}
        editingInterviewId={m.editingInterviewId}
        setEditingInterviewId={m.setEditingInterviewId}
        interviewForm={m.interviewForm}
        setInterviewForm={m.setInterviewForm}
        apps={m.apps}
        draftSheet={m.draftSheet}
        setDraftSheet={m.setDraftSheet}
        draftPane={m.draftPane}
        setDraftPane={m.setDraftPane}
        draftPreviewAs={m.draftPreviewAs}
        setDraftPreviewAs={m.setDraftPreviewAs}
        includeBragInDraft={m.includeBragInDraft}
        setIncludeBragInDraft={m.setIncludeBragInDraft}
        draftBusy={m.draftBusy}
        draftMarkdown={m.draftMarkdown}
        draftTypst={m.draftTypst}
        draftCompileBusy={m.draftCompileBusy}
        setDraftCompileBusy={m.setDraftCompileBusy}
        generateResumeDraft={m.generateResumeDraft}
      />
    </div>
  );
}
