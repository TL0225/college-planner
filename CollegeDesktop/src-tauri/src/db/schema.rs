//! Schema migrations mirroring CollegeGRDB domain tables.
//! Full parity tables for core domains used by the cross-platform shell.

use anyhow::Result;
use rusqlite::Connection;

const MIGRATIONS: &[(&str, &str)] = &[
    (
        "001_core_metadata",
        r#"
        CREATE TABLE IF NOT EXISTS college_metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY NOT NULL,
            applied_at TEXT NOT NULL
        );
        "#,
    ),
    (
        "002_planner_profile",
        r#"
        CREATE TABLE IF NOT EXISTS profile (
            id TEXT PRIMARY KEY NOT NULL,
            full_name TEXT NOT NULL DEFAULT '',
            email TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            university_name TEXT NOT NULL DEFAULT '',
            major TEXT NOT NULL DEFAULT '',
            graduation_year INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS experience (
            id TEXT PRIMARY KEY NOT NULL,
            profile_id TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            organization TEXT NOT NULL DEFAULT '',
            start_date TEXT,
            end_date TEXT,
            summary TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(profile_id) REFERENCES profile(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS achievement (
            id TEXT PRIMARY KEY NOT NULL,
            profile_id TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            issuer TEXT NOT NULL DEFAULT '',
            date_received TEXT,
            notes TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(profile_id) REFERENCES profile(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS planner_plan (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL DEFAULT 'Default Plan',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS academic_profile (
            id TEXT PRIMARY KEY NOT NULL,
            profile_id TEXT,
            plan_id TEXT,
            degree_level TEXT NOT NULL DEFAULT 'bachelor',
            is_primary INTEGER NOT NULL DEFAULT 1,
            is_active INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS planner_semester (
            id TEXT PRIMARY KEY NOT NULL,
            plan_id TEXT,
            year INTEGER NOT NULL,
            season TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            is_current INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS planner_course (
            id TEXT PRIMARY KEY NOT NULL,
            semester_id TEXT NOT NULL,
            catalog_course_id TEXT,
            code TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            credits REAL NOT NULL DEFAULT 0,
            grade TEXT,
            status TEXT NOT NULL DEFAULT 'planned',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS graduation_plan_term (
            id TEXT PRIMARY KEY NOT NULL,
            profile_id TEXT NOT NULL,
            year INTEGER NOT NULL,
            season TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS planner_task (
            id TEXT PRIMARY KEY NOT NULL,
            semester_id TEXT,
            course_id TEXT,
            title TEXT NOT NULL,
            due_at TEXT,
            is_complete INTEGER NOT NULL DEFAULT 0,
            notes TEXT NOT NULL DEFAULT '',
            lms_item_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_planner_semester_year ON planner_semester(year, season);
        CREATE INDEX IF NOT EXISTS idx_planner_course_semester ON planner_course(semester_id, sort_order);
        "#,
    ),
    (
        "003_calendar",
        r#"
        CREATE TABLE IF NOT EXISTS calendar_event (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            start_at TEXT NOT NULL,
            end_at TEXT,
            all_day INTEGER NOT NULL DEFAULT 0,
            location TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            provider TEXT NOT NULL DEFAULT 'local',
            provider_event_id TEXT,
            semester_id TEXT,
            course_id TEXT,
            color_hex TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_calendar_event_start ON calendar_event(start_at);
        CREATE INDEX IF NOT EXISTS idx_calendar_event_provider ON calendar_event(provider);
        "#,
    ),
    (
        "004_career",
        r#"
        CREATE TABLE IF NOT EXISTS job_application (
            id TEXT PRIMARY KEY NOT NULL,
            company TEXT NOT NULL DEFAULT '',
            role_title TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'interested',
            location TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            applied_at TEXT,
            notes TEXT NOT NULL DEFAULT '',
            salary_text TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS recruiter_contact (
            id TEXT PRIMARY KEY NOT NULL,
            application_id TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            email TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(application_id) REFERENCES job_application(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workday_job_posting (
            id TEXT PRIMARY KEY NOT NULL,
            company TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            location TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            posted_at TEXT,
            tracked_application_id TEXT,
            raw_json TEXT NOT NULL DEFAULT '{}'
        );
        CREATE TABLE IF NOT EXISTS career_event (
            id TEXT PRIMARY KEY NOT NULL,
            application_id TEXT,
            title TEXT NOT NULL,
            occurs_at TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'interview',
            notes TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(application_id) REFERENCES job_application(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS career_path_entry (
            id TEXT PRIMARY KEY NOT NULL,
            profile_id TEXT,
            organization TEXT NOT NULL DEFAULT '',
            role_title TEXT NOT NULL DEFAULT '',
            start_date TEXT,
            end_date TEXT,
            summary TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_job_application_status ON job_application(status, sort_order);
        "#,
    ),
    (
        "005_catalog",
        r#"
        CREATE TABLE IF NOT EXISTS university (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            short_name TEXT NOT NULL DEFAULT '',
            domain TEXT NOT NULL DEFAULT '',
            catalog_base_url TEXT NOT NULL DEFAULT '',
            is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS department (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL,
            name TEXT NOT NULL,
            code TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(university_id) REFERENCES university(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS course_catalog (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL,
            department_id TEXT,
            code TEXT NOT NULL,
            title TEXT NOT NULL,
            credits REAL,
            description TEXT NOT NULL DEFAULT '',
            prerequisites TEXT NOT NULL DEFAULT '',
            is_archived INTEGER NOT NULL DEFAULT 0,
            stable_id TEXT,
            FOREIGN KEY(university_id) REFERENCES university(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS major (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL,
            name TEXT NOT NULL,
            degree_type TEXT NOT NULL DEFAULT '',
            program_url TEXT NOT NULL DEFAULT '',
            stable_id TEXT,
            FOREIGN KEY(university_id) REFERENCES university(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS catalog_degree_requirement (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL,
            major_id TEXT,
            section_title TEXT NOT NULL DEFAULT '',
            rule_json TEXT NOT NULL DEFAULT '{}',
            credits_required REAL,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_course_catalog_code ON course_catalog(university_id, code);
        CREATE VIRTUAL TABLE IF NOT EXISTS course_catalog_fts USING fts5(
            code, title, description, content='course_catalog', content_rowid='rowid'
        );
        "#,
    ),
    (
        "006_vault",
        r#"
        CREATE TABLE IF NOT EXISTS vault_document (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            relative_path TEXT NOT NULL DEFAULT '',
            mime_type TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'general',
            parent_folder_id TEXT,
            course_id TEXT,
            tags_json TEXT NOT NULL DEFAULT '[]',
            file_size INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS watched_folder (
            id TEXT PRIMARY KEY NOT NULL,
            path TEXT NOT NULL,
            bookmark_data BLOB,
            added_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_vault_category ON vault_document(category, sort_order);
        "#,
    ),
    (
        "007_finance",
        r#"
        CREATE TABLE IF NOT EXISTS finance_account (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            institution TEXT NOT NULL DEFAULT '',
            account_type TEXT NOT NULL DEFAULT 'checking',
            currency TEXT NOT NULL DEFAULT 'USD',
            balance REAL NOT NULL DEFAULT 0,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS finance_transaction (
            id TEXT PRIMARY KEY NOT NULL,
            account_id TEXT NOT NULL,
            posted_at TEXT NOT NULL,
            amount REAL NOT NULL,
            payee TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT '',
            memo TEXT NOT NULL DEFAULT '',
            external_id TEXT,
            FOREIGN KEY(account_id) REFERENCES finance_account(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS finance_budget (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT '',
            amount REAL NOT NULL DEFAULT 0,
            period TEXT NOT NULL DEFAULT 'monthly'
        );
        CREATE TABLE IF NOT EXISTS finance_recurring (
            id TEXT PRIMARY KEY NOT NULL,
            account_id TEXT,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            cadence TEXT NOT NULL DEFAULT 'monthly',
            next_due TEXT,
            category TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_finance_tx_posted ON finance_transaction(posted_at);
        "#,
    ),
    (
        "008_discovery_transfer",
        r#"
        CREATE TABLE IF NOT EXISTS transfer_equivalency (
            id TEXT PRIMARY KEY NOT NULL,
            source_school TEXT NOT NULL DEFAULT '',
            source_code TEXT NOT NULL DEFAULT '',
            target_code TEXT NOT NULL DEFAULT '',
            credits REAL,
            notes TEXT NOT NULL DEFAULT '',
            dedupe_key TEXT UNIQUE,
            proof_document_id TEXT
        );
        CREATE TABLE IF NOT EXISTS discovery_institution_identity (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            unit_id TEXT,
            state TEXT NOT NULL DEFAULT '',
            city TEXT NOT NULL DEFAULT '',
            website TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS discovery_cds_snapshot (
            id TEXT PRIMARY KEY NOT NULL,
            unit_id TEXT NOT NULL,
            year INTEGER NOT NULL,
            payload_json TEXT NOT NULL DEFAULT '{}',
            UNIQUE(unit_id, year)
        );
        "#,
    ),
    (
        "009_seed_defaults",
        r#"
        INSERT OR IGNORE INTO app_settings (key, value, updated_at)
        VALUES ('ui.theme', 'system', datetime('now'));
        INSERT OR IGNORE INTO app_settings (key, value, updated_at)
        VALUES ('ui.reduceMotion', 'false', datetime('now'));
        INSERT OR IGNORE INTO app_settings (key, value, updated_at)
        VALUES ('ai.provider', 'local', datetime('now'));
        "#,
    ),
    (
        "010_lms_portal",
        r#"
        CREATE TABLE IF NOT EXISTS lms_portal (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_lms_portal_sort ON lms_portal(sort_order, name);
        "#,
    ),
    (
        "011_finance_goal",
        r#"
        CREATE TABLE IF NOT EXISTS finance_goal (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            target_amount REAL NOT NULL,
            current_amount REAL NOT NULL DEFAULT 0,
            deadline TEXT,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_finance_goal_sort ON finance_goal(sort_order, name);
        "#,
    ),
    (
        "012_calendar_color_recurrence",
        r#"
        ALTER TABLE calendar_event ADD COLUMN color TEXT NOT NULL DEFAULT '';
        ALTER TABLE calendar_event ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none';
        UPDATE calendar_event SET color = color_hex
        WHERE color_hex IS NOT NULL AND color_hex != '' AND color = '';
        "#,
    ),
    (
        "013_finance_inventory_receipt",
        r#"
        CREATE TABLE IF NOT EXISTS finance_inventory_item (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT '',
            purchase_date TEXT,
            value REAL NOT NULL DEFAULT 0,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS finance_receipt (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            merchant TEXT NOT NULL DEFAULT '',
            amount REAL NOT NULL DEFAULT 0,
            purchased_at TEXT,
            category TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            vault_doc_id TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_finance_inventory_sort ON finance_inventory_item(sort_order, name);
        CREATE INDEX IF NOT EXISTS idx_finance_receipt_sort ON finance_receipt(sort_order, purchased_at);
        "#,
    ),
    (
        "014_career_resume_profile",
        r#"
        CREATE TABLE IF NOT EXISTS career_resume_profile (
            id TEXT PRIMARY KEY NOT NULL,
            vault_doc_id TEXT NOT NULL UNIQUE,
            target_role TEXT NOT NULL DEFAULT '',
            target_company TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL,
            FOREIGN KEY(vault_doc_id) REFERENCES vault_document(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_resume_profile_vault ON career_resume_profile(vault_doc_id);
        "#,
    ),
    (
        "015_career_submodules",
        r#"
        CREATE TABLE IF NOT EXISTS career_brag_entry (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            occurred_at TEXT,
            summary TEXT NOT NULL DEFAULT '',
            evidence_note TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS career_network_contact (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            organization TEXT NOT NULL DEFAULT '',
            role_title TEXT NOT NULL DEFAULT '',
            email TEXT NOT NULL DEFAULT '',
            last_contact_at TEXT,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS career_interview_prep (
            id TEXT PRIMARY KEY NOT NULL,
            application_id TEXT,
            company TEXT NOT NULL DEFAULT '',
            role_title TEXT NOT NULL DEFAULT '',
            scheduled_at TEXT,
            status TEXT NOT NULL DEFAULT 'upcoming',
            notes TEXT NOT NULL DEFAULT '',
            questions TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(application_id) REFERENCES job_application(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_career_brag_sort ON career_brag_entry(sort_order, occurred_at);
        CREATE INDEX IF NOT EXISTS idx_career_network_sort ON career_network_contact(sort_order, name);
        CREATE INDEX IF NOT EXISTS idx_career_interview_status ON career_interview_prep(status, scheduled_at);
        "#,
    ),
    (
        "016_career_path_milestone",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_milestone (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            title TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'planned',
            due_at TEXT,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_milestone_entry
            ON career_path_milestone(path_entry_id, sort_order);
        "#,
    ),
    (
        "017_career_path_document",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_document (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            vault_doc_id TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            UNIQUE(path_entry_id, vault_doc_id),
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE,
            FOREIGN KEY(vault_doc_id) REFERENCES vault_document(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_document_entry
            ON career_path_document(path_entry_id);
        "#,
    ),
    (
        "018_career_path_journal",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_journal_entry (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',
            mood TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_journal_entry
            ON career_path_journal_entry(path_entry_id, occurred_at DESC, sort_order);
        "#,
    ),
    (
        "019_calendar_source",
        r#"
        CREATE TABLE IF NOT EXISTS calendar_source (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT '',
            ics_url TEXT NOT NULL DEFAULT '',
            last_synced_at TEXT,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        ALTER TABLE calendar_event ADD COLUMN source_id TEXT;
        CREATE INDEX IF NOT EXISTS idx_calendar_event_source ON calendar_event(source_id);
        CREATE INDEX IF NOT EXISTS idx_calendar_source_sort ON calendar_source(sort_order, name);
        INSERT OR IGNORE INTO calendar_source (id, name, color, ics_url, is_enabled, sort_order)
        VALUES ('cal-src-personal', 'Personal', 'blue', '', 1, 0);
        UPDATE calendar_event SET source_id = 'cal-src-personal' WHERE source_id IS NULL;
        "#,
    ),
    (
        "020_calendar_oauth",
        r#"
        CREATE TABLE IF NOT EXISTS calendar_oauth_account (
            id TEXT PRIMARY KEY NOT NULL,
            provider TEXT NOT NULL,
            account_email TEXT NOT NULL DEFAULT '',
            access_token_enc TEXT NOT NULL DEFAULT '',
            refresh_token_enc TEXT NOT NULL DEFAULT '',
            expires_at TEXT,
            scopes TEXT NOT NULL DEFAULT '',
            source_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_calendar_oauth_provider ON calendar_oauth_account(provider);
        ALTER TABLE calendar_source ADD COLUMN provider TEXT NOT NULL DEFAULT 'local';
        "#,
    ),
    (
        "021_vault_starred",
        r#"
        ALTER TABLE vault_document ADD COLUMN is_starred INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX IF NOT EXISTS idx_vault_starred ON vault_document(is_starred, updated_at DESC);
        "#,
    ),
    (
        "022_discovery_saved",
        r#"
        ALTER TABLE discovery_institution_identity ADD COLUMN is_saved INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX IF NOT EXISTS idx_discovery_saved ON discovery_institution_identity(is_saved, name);
        "#,
    ),
    (
        "023_pathing_phase_c",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_promotion (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            title TEXT NOT NULL,
            effective_at TEXT,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_promotion_entry
            ON career_path_promotion(path_entry_id, sort_order, effective_at);

        CREATE TABLE IF NOT EXISTS career_path_person (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            name TEXT NOT NULL,
            role_title TEXT NOT NULL DEFAULT '',
            relationship TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_person_entry
            ON career_path_person(path_entry_id, sort_order, name);
        "#,
    ),
    (
        "024_pathing_phase_c_depth",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_decision_journal (
            path_entry_id TEXT PRIMARY KEY NOT NULL,
            why_accepted TEXT NOT NULL DEFAULT '',
            alternatives TEXT NOT NULL DEFAULT '',
            expected_benefits TEXT NOT NULL DEFAULT '',
            concerns TEXT NOT NULL DEFAULT '',
            success_criteria TEXT NOT NULL DEFAULT '',
            why_left TEXT NOT NULL DEFAULT '',
            lessons TEXT NOT NULL DEFAULT '',
            would_do_differently TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS career_path_benefit (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            title TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 0,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_benefit_entry
            ON career_path_benefit(path_entry_id, sort_order, title);

        CREATE TABLE IF NOT EXISTS career_skill (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL UNIQUE,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS career_skill_evidence (
            id TEXT PRIMARY KEY NOT NULL,
            skill_id TEXT NOT NULL,
            path_entry_id TEXT,
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY(skill_id) REFERENCES career_skill(id) ON DELETE CASCADE,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_career_skill_evidence_skill
            ON career_skill_evidence(skill_id, created_at DESC);
        "#,
    ),
    (
        "025_pathing_phase_b",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_compensation (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'base_salary',
            title TEXT NOT NULL,
            amount REAL,
            currency TEXT NOT NULL DEFAULT 'USD',
            cadence TEXT NOT NULL DEFAULT 'yearly',
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_compensation_entry
            ON career_path_compensation(path_entry_id, sort_order, kind);

        CREATE TABLE IF NOT EXISTS career_path_employment_terms (
            path_entry_id TEXT PRIMARY KEY NOT NULL,
            employment_type TEXT NOT NULL DEFAULT '',
            work_location TEXT NOT NULL DEFAULT '',
            schedule_notes TEXT NOT NULL DEFAULT '',
            notice_period TEXT NOT NULL DEFAULT '',
            other_terms TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );

        ALTER TABLE career_path_milestone ADD COLUMN lane TEXT NOT NULL DEFAULT 'general';
        CREATE INDEX IF NOT EXISTS idx_career_path_milestone_lane
            ON career_path_milestone(path_entry_id, lane, sort_order);
        "#,
    ),
    (
        "026_discovery_cds_seed",
        r#"
        INSERT OR IGNORE INTO discovery_cds_snapshot (id, unit_id, year, payload_json)
        SELECT lower(hex(randomblob(16))), '100001', 2024, '{"academicYear":2024,"sourceURL":"https://www.stateu.edu/common-data-set.html","c1":{"applicants":28450,"admits":18210,"enrolled":3920,"admitRate":0.64,"yield":0.215},"c7":{"gpa":"Very Important","rigor":"Very Important","tests":"Considered","essay":"Important","recommendations":"Important","interview":"Not Considered","extracurriculars":"Important"},"c8":{"testPolicyNote":"SAT/ACT optional for most first-year applicants."},"c9":{"satEBRW25":560,"satEBRW75":640,"satMath25":570,"satMath75":660,"actComposite25":24,"actComposite75":29,"percentSubmittingSAT":0.68,"percentSubmittingACT":0.31},"c11":{"hsGPAAverage":3.65,"distribution":{"4.0":0.18,"3.75-3.99":0.36,"3.50-3.74":0.26,"3.25-3.49":0.13,"below_3.25":0.07}}}';
        INSERT OR IGNORE INTO discovery_cds_snapshot (id, unit_id, year, payload_json)
        SELECT lower(hex(randomblob(16))), '100002', 2024, '{"academicYear":2024,"sourceURL":"https://www.coastaltech.edu/admissions/cds","c1":{"applicants":41200,"admits":12480,"enrolled":2680,"admitRate":0.303,"yield":0.215},"c7":{"gpa":"Very Important","rigor":"Very Important","tests":"Important","essay":"Considered","recommendations":"Considered","interview":"Not Considered","extracurriculars":"Considered"},"c8":{"testPolicyNote":"Test scores required for most applicants; see site for exceptions."},"c9":{"satEBRW25":610,"satEBRW75":690,"satMath25":620,"satMath75":710,"actComposite25":27,"actComposite75":32,"percentSubmittingSAT":0.81,"percentSubmittingACT":0.42},"c11":{"hsGPAAverage":3.82,"distribution":{"4.0":0.28,"3.75-3.99":0.41,"3.50-3.74":0.2,"3.25-3.49":0.08,"below_3.25":0.03}},"c21":{"earlyDecisionApplicants":4200,"earlyDecisionAdmits":1680}}';
        "#,
    ),
    (
        "027_vault_folders",
        r#"
        ALTER TABLE vault_document ADD COLUMN is_folder INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX IF NOT EXISTS idx_vault_parent ON vault_document(parent_folder_id, is_folder, sort_order);
        "#,
    ),
    (
        "028_finance_holdings",
        r#"
        CREATE TABLE IF NOT EXISTS finance_holding (
            id TEXT PRIMARY KEY NOT NULL,
            asset_type TEXT NOT NULL DEFAULT 'stock',
            symbol TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL DEFAULT '',
            quantity REAL NOT NULL DEFAULT 0,
            price_per_unit REAL NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_finance_holding_type ON finance_holding(asset_type, symbol);
        "#,
    ),
    (
        "029_focus_blocks",
        r#"
        CREATE TABLE IF NOT EXISTS focus_block (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            duration_minutes INTEGER NOT NULL DEFAULT 45,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_focus_block_sort ON focus_block(sort_order, title);
        "#,
    ),
    (
        "030_job_board_company",
        r#"
        CREATE TABLE IF NOT EXISTS job_board_company (
            id TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL DEFAULT '',
            careers_url TEXT NOT NULL DEFAULT '',
            platform TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            last_synced_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_job_board_company_enabled
            ON job_board_company(enabled, sort_order, display_name);
        "#,
    ),
    (
        "031_swift_parity_tables",
        r#"
        CREATE TABLE IF NOT EXISTS course_grading_category (
            id TEXT PRIMARY KEY NOT NULL,
            course_id TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            weight REAL NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS requirement_fulfillment (
            id TEXT PRIMARY KEY NOT NULL,
            requirement_id TEXT NOT NULL,
            course_code TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS course_override (
            id TEXT PRIMARY KEY NOT NULL,
            catalog_course_id TEXT,
            code TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            credits REAL NOT NULL DEFAULT 0,
            notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS transfer_proof_record (
            id TEXT PRIMARY KEY NOT NULL,
            equivalency_id TEXT NOT NULL,
            vault_document_id TEXT,
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS catalog_scrape_state (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL DEFAULT '',
            last_scraped_at TEXT,
            status TEXT NOT NULL DEFAULT 'idle',
            raw_json TEXT NOT NULL DEFAULT '{}'
        );
        CREATE TABLE IF NOT EXISTS catalog_edition (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL DEFAULT '',
            year INTEGER NOT NULL DEFAULT 0,
            label TEXT NOT NULL DEFAULT '',
            source_url TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS catalog_policy_document (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'general'
        );
        CREATE TABLE IF NOT EXISTS catalog_college (
            id TEXT PRIMARY KEY NOT NULL,
            university_id TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS career_application_preferences (
            id TEXT PRIMARY KEY NOT NULL,
            payload_json TEXT NOT NULL DEFAULT '{}',
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS career_resume_job_match (
            id TEXT PRIMARY KEY NOT NULL,
            application_id TEXT,
            resume_document_id TEXT,
            score REAL NOT NULL DEFAULT 0,
            summary TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS career_resume_job_match_snapshot (
            id TEXT PRIMARY KEY NOT NULL,
            match_id TEXT NOT NULL,
            payload_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS finance_category (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'expense',
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS finance_due (
            id TEXT PRIMARY KEY NOT NULL,
            person TEXT NOT NULL DEFAULT '',
            amount REAL NOT NULL DEFAULT 0,
            due_at TEXT NOT NULL,
            is_paid INTEGER NOT NULL DEFAULT 0,
            notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS finance_net_worth_snapshot (
            id TEXT PRIMARY KEY NOT NULL,
            captured_at TEXT NOT NULL,
            net_worth REAL NOT NULL DEFAULT 0,
            payload_json TEXT NOT NULL DEFAULT '{}'
        );
        "#,
    ),
    (
        "032_job_board_smart_board",
        r#"
        CREATE TABLE IF NOT EXISTS job_board_smart_board (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            company_ids_json TEXT NOT NULL DEFAULT '[]',
            filter_json TEXT NOT NULL DEFAULT '{}',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_job_board_smart_board_sort
            ON job_board_smart_board(sort_order, name);
        "#,
    ),
    (
        "033_pathing_phase_c_depth",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_role_expectation (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL UNIQUE,
            summary TEXT NOT NULL DEFAULT '',
            boxes_json TEXT NOT NULL DEFAULT '[]',
            updated_at TEXT NOT NULL,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS career_path_relationship (
            id TEXT PRIMARY KEY NOT NULL,
            from_entry_id TEXT NOT NULL,
            to_entry_id TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'related',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            UNIQUE(from_entry_id, to_entry_id, kind)
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_relationship_from
            ON career_path_relationship(from_entry_id, kind);
        CREATE INDEX IF NOT EXISTS idx_career_path_relationship_to
            ON career_path_relationship(to_entry_id, kind);

        ALTER TABLE career_path_entry ADD COLUMN resume_document_id TEXT;
        "#,
    ),
    (
        "034_catalog_vector_index",
        r#"
        CREATE TABLE IF NOT EXISTS catalog_course_embedding (
            course_id TEXT PRIMARY KEY NOT NULL,
            model_tag TEXT NOT NULL,
            vector_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_catalog_course_embedding_model
            ON catalog_course_embedding(model_tag, updated_at);
        "#,
    ),
    (
        "035_pathing_goals_scenarios",
        r#"
        CREATE TABLE IF NOT EXISTS career_path_goal (
            id TEXT PRIMARY KEY NOT NULL,
            path_entry_id TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'custom',
            cadence TEXT NOT NULL DEFAULT 'yearly',
            target_date TEXT,
            notes TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_career_path_goal_entry
            ON career_path_goal(path_entry_id, sort_order);

        CREATE TABLE IF NOT EXISTS career_path_scenario (
            path_entry_id TEXT PRIMARY KEY NOT NULL,
            current_json TEXT NOT NULL DEFAULT '{}',
            alternate_json TEXT NOT NULL DEFAULT '{}',
            updated_at TEXT NOT NULL,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS career_path_disclosure (
            path_entry_id TEXT PRIMARY KEY NOT NULL,
            comp INTEGER NOT NULL DEFAULT 0,
            benefits INTEGER NOT NULL DEFAULT 0,
            equity INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(path_entry_id) REFERENCES career_path_entry(id) ON DELETE CASCADE
        );
        "#,
    ),
    (
        "036_portable_ai_cache",
        r#"
        CREATE TABLE IF NOT EXISTS ai_embed_cache (
            content_hash TEXT PRIMARY KEY NOT NULL,
            model_tag TEXT NOT NULL,
            dims INTEGER NOT NULL,
            vector_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_ai_embed_cache_model
            ON ai_embed_cache(model_tag, updated_at);

        CREATE TABLE IF NOT EXISTS app_ui_prefs (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL DEFAULT ''
        );
        "#,
    ),
    (
        "037_career_brag_path_entry",
        r#"
        ALTER TABLE career_brag_entry ADD COLUMN path_entry_id TEXT;
        CREATE INDEX IF NOT EXISTS idx_career_brag_path_entry
            ON career_brag_entry(path_entry_id);
        "#,
    ),
];

pub fn run_migrations(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY NOT NULL,
            applied_at TEXT NOT NULL
        );",
    )?;

    for (version, sql) in MIGRATIONS {
        let already: bool = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = ?1)",
            [version],
            |r| r.get(0),
        )?;
        if already {
            continue;
        }
        conn.execute_batch(sql)?;
        conn.execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (?1, datetime('now'))",
            [version],
        )?;
        tracing::info!(version, "applied database migration");
    }
    Ok(())
}
