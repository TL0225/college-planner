//! College Tauri v2 core — unified single-codebase backend.

pub mod ai;
pub mod background;
pub mod commands;
pub mod db;
pub mod paths;
pub mod scrapers;
pub mod security;
pub mod swift_mirror;
pub mod swift_seed;

use db::AppDb;
use paths::AppPaths;
use security::SecurityService;
use std::sync::Arc;
use tauri::Manager;

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<AppDb>,
    pub paths: Arc<AppPaths>,
    pub security: Arc<SecurityService>,
    pub ai: Arc<ai::AiRuntime>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let paths = Arc::new(AppPaths::resolve()?);
            paths.ensure_dirs()?;

            let restored = commands::backup::apply_pending_restore_if_any(
                &paths.college_db_path,
                &paths.backups_dir,
            )?;
            if restored {
                tracing::info!("Applied pending database restore before open");
            }

            let db = Arc::new(AppDb::open(&paths.college_db_path)?);
            db.migrate()?;
            match swift_seed::seed_from_swift_if_needed(&db, &paths) {
                Ok(Some(report)) => {
                    tracing::info!(
                        total_rows = report.total_rows,
                        path = %report.swift_db_path,
                        "Seeded Tauri DB from Swift workspace copy"
                    );
                }
                Ok(None) => {}
                Err(e) => tracing::warn!("Swift workspace seed skipped: {e}"),
            }

            let security = Arc::new(SecurityService::new(paths.clone())?);
            let ai = Arc::new(ai::AiRuntime::new(paths.clone(), db.clone())?);

            app.manage(AppState {
                db,
                paths,
                security,
                ai,
            });

            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                background::start_all(handle).await;
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::platform::get_platform_info,
            commands::platform::get_storage_paths,
            commands::platform::platform_typst_available,
            commands::platform::platform_fetch_weather,
            commands::platform_import::platform_import_swift_workspace,
            commands::platform_import::platform_sync_published_calendar_feed,
            commands::academics::academics_get_audit_summary,
            commands::academics::academics_list_semesters,
            commands::academics::academics_get_requirement_audit,
            commands::academics::academics_get_gpa_summary,
            commands::academics::academics_list_programs,
            commands::academics::academics_get_program_detail,
            commands::academics::academics_set_active_program,
            commands::academics::academics_list_grading_categories,
            commands::academics::academics_evaluate_prerequisites,
            commands::calendar::calendar_list_events,
            commands::calendar::calendar_list_tasks,
            commands::calendar::calendar_list_sources,
            commands::calendar::calendar_upsert_source,
            commands::calendar::calendar_delete_source,
            commands::calendar::calendar_sync_ics_url,
            commands::calendar::calendar_import_ics,
            commands::calendar::calendar_import_ics_path,
            commands::calendar::calendar_export_ics,
            commands::calendar::calendar_export_ics_path,
            commands::calendar::calendar_publish_subscribe_feed,
            commands::calendar::calendar_open_apple_calendar_feed,
            commands::focus_blocks::calendar_list_focus_blocks,
            commands::focus_blocks::calendar_upsert_focus_block,
            commands::focus_blocks::calendar_delete_focus_block,
            commands::calendar::calendar_geocode_location,
            commands::calendar_oauth::calendar_oauth_begin,
            commands::calendar_oauth::calendar_oauth_complete,
            commands::calendar_oauth::calendar_oauth_status,
            commands::calendar_oauth::calendar_oauth_sync,
            commands::calendar_oauth::calendar_oauth_sync_all,
            commands::calendar_oauth::calendar_oauth_disconnect,
            commands::calendar_oauth::calendar_oauth_push_local,
            commands::career::career_list_applications,
            commands::career::career_pipeline_metrics,
            commands::career::career_list_job_postings,
            commands::career::career_upsert_job_posting,
            commands::career::career_delete_job_posting,
            commands::career::career_track_job_posting,
            commands::career::career_import_job_from_url,
            commands::career::career_sync_job_boards,
            commands::career::career_list_job_board_companies,
            commands::career::career_upsert_job_board_company,
            commands::career::career_delete_job_board_company,
            commands::career::career_sync_job_board_companies,
            commands::career::career_list_smart_boards,
            commands::career::career_upsert_smart_board,
            commands::career::career_delete_smart_board,
            commands::career::career_query_smart_board_postings,
            commands::career_apply::career_apply_build_payload,
            commands::career_apply::career_apply_run_autofill,
            commands::career_apply::career_apply_install_bridge,
            commands::career::career_list_path_entries,
            commands::career::career_upsert_path_entry,
            commands::career::career_delete_path_entry,
            commands::career::career_list_path_milestones,
            commands::career::career_upsert_path_milestone,
            commands::career::career_delete_path_milestone,
            commands::career::career_list_path_journal_entries,
            commands::career::career_upsert_path_journal_entry,
            commands::career::career_delete_path_journal_entry,
            commands::career::career_list_path_promotions,
            commands::career::career_upsert_path_promotion,
            commands::career::career_delete_path_promotion,
            commands::career::career_list_path_people,
            commands::career::career_upsert_path_person,
            commands::career::career_delete_path_person,
            commands::career::career_get_path_decision_journal,
            commands::career::career_upsert_path_decision_journal,
            commands::career::career_list_path_benefits,
            commands::career::career_upsert_path_benefit,
            commands::career::career_delete_path_benefit,
            commands::career::career_list_path_compensation,
            commands::career::career_upsert_path_compensation,
            commands::career::career_delete_path_compensation,
            commands::career::career_get_path_employment_terms,
            commands::career::career_upsert_path_employment_terms,
            commands::career::career_list_skills,
            commands::career::career_upsert_skill,
            commands::career::career_delete_skill,
            commands::career::career_add_skill_evidence,
            commands::career::career_path_achievement_pipeline,
            commands::career::career_list_path_documents,
            commands::career::career_link_path_document,
            commands::career::career_unlink_path_document,
            commands::career::career_get_role_expectation,
            commands::career::career_save_role_expectation,
            commands::career::career_list_path_relationships,
            commands::career::career_upsert_path_relationship,
            commands::career::career_delete_path_relationship,
            commands::career::career_set_path_resume,
            commands::career::career_merge_path_entries,
            commands::career::career_list_events,
            commands::career::career_upsert_event,
            commands::career::career_delete_event,
            commands::career::career_list_resume_profiles,
            commands::career::career_upsert_resume_profile,
            commands::career::career_resume_metrics,
            commands::career::career_list_brag_entries,
            commands::career::career_upsert_brag_entry,
            commands::career::career_delete_brag_entry,
            commands::career::career_list_network_contacts,
            commands::career::career_upsert_network_contact,
            commands::career::career_delete_network_contact,
            commands::career::career_list_interview_prep,
            commands::career::career_upsert_interview_prep,
            commands::career::career_delete_interview_prep,
            commands::career::career_compile_typst_pdf,
            commands::catalog::catalog_search_courses,
            commands::catalog::catalog_list_universities,
            commands::catalog::catalog_list_departments,
            commands::catalog::catalog_list_department_courses,
            commands::catalog::catalog_ingest_url,
            commands::catalog::catalog_get_sync_diagnostics,
            commands::catalog::catalog_sync_university,
            commands::catalog::catalog_embedding_stats,
            commands::catalog::catalog_reindex_embeddings,
            commands::catalog::catalog_semantic_search,
            commands::discovery::discovery_list_institutions,
            commands::discovery::discovery_get_profile,
            commands::discovery::discovery_get_cds,
            commands::discovery::discovery_upsert_institution,
            commands::discovery::discovery_update_institution,
            commands::discovery::discovery_delete_institution,
            commands::discovery::discovery_sync_federal_data,
            commands::transfer::transfer_list_equivalencies,
            commands::transfer::transfer_upsert_equivalency,
            commands::transfer::transfer_import_equivalencies,
            commands::transfer::transfer_delete_equivalency,
            commands::transfer::transfer_link_proof_document,
            commands::transfer::transfer_import_community_json,
            commands::transfer::transfer_import_assist,
            commands::documents::documents_list_vault,
            commands::documents::documents_import_file,
            commands::documents::documents_create_folder,
            commands::documents::documents_move_vault_item,
            commands::documents::documents_rename_vault_item,
            commands::documents::documents_quick_look,
            commands::documents::documents_quick_look_preview,
            commands::documents::documents_resolve_path,
            commands::documents::documents_update_vault_doc,
            commands::documents::documents_list_watched_folders,
            commands::documents::documents_upsert_watched_folder,
            commands::documents::documents_delete_watched_folder,
            commands::background::documents_watchdog_status,
            commands::background::background_weekly_digest_preview,
            commands::finance::finance_dashboard_summary,
            commands::finance::finance_list_accounts,
            commands::finance::finance_list_transactions,
            commands::finance::finance_list_budgets,
            commands::finance::finance_list_goals,
            commands::finance::finance_list_inventory_items,
            commands::finance::finance_list_receipts,
            commands::finance::finance_list_holdings,
            commands::finance::finance_list_categories,
            commands::finance::finance_list_due,
            commands::finance::finance_list_recurring,
            commands::finance::finance_export_transactions_csv,
            commands::finance::finance_export_transactions_csv_path,
            commands::finance_connections::finance_sync_coinbase,
            commands::lms::lms_list_portals,
            commands::lms::lms_upsert_portal,
            commands::lms::lms_delete_portal,
            commands::lms::lms_import_items,
            commands::lms::lms_extract_portal_page,
            commands::lms::lms_portal_navigate,
            commands::lms::lms_portal_find,
            commands::lms::lms_portal_credentials_get,
            commands::lms::lms_portal_credentials_set,
            commands::lms::lms_portal_credentials_clear,
            commands::lms::lms_portal_autofill_login,
            commands::lms::lms_portal_install_bridge,
            commands::profile::profile_get_identity,
            commands::profile::profile_list_experiences,
            commands::profile::profile_list_achievements,
            commands::settings::settings_get,
            commands::settings::settings_set,
            commands::security::security_is_locked,
            commands::security::security_unlock,
            commands::security::security_lock,
            commands::security::security_biometric_available,
            commands::assistant::assistant_turn,
            commands::assistant::assistant_cancel_turn,
            commands::assistant::assistant_list_tools,
            commands::ai::ai_embed_texts,
            commands::ai::ai_chat_completion,
            commands::ai::ai_runtime_status,
            commands::ai::ai_ping,
            commands::ai::ai_semantic_search_catalog,
            commands::ai::ai_semantic_search_vault,
            commands::backup::backup_create,
            commands::backup::backup_list,
            commands::backup::backup_restore,
            commands::scrapers::scraper_fetch_html_preview,
            commands::syllabus::syllabus_extract_assignments,
            commands::syllabus::syllabus_analyze_text,
            commands::syllabus::syllabus_analyze_pdf_path,
            commands::syllabus::syllabus_resolve_pdf_path,
            commands::writes::academics_upsert_semester,
            commands::writes::academics_upsert_course,
            commands::writes::academics_add_requirement_course,
            commands::writes::academics_assign_fulfillment,
            commands::writes::academics_update_course_status,
            commands::writes::academics_update_course_grade,
            commands::writes::academics_delete_course,
            commands::writes::academics_delete_semester,
            commands::writes::academics_list_courses,
            commands::writes::calendar_upsert_event,
            commands::writes::calendar_upsert_task,
            commands::writes::calendar_toggle_task_complete,
            commands::writes::calendar_delete_event,
            commands::writes::calendar_delete_task,
            commands::writes::career_upsert_application,
            commands::writes::career_update_application_status,
            commands::writes::career_move_application,
            commands::writes::career_apply_complete,
            commands::writes::career_delete_application,
            commands::writes::career_resume_keyword_match,
            commands::writes::finance_upsert_account,
            commands::writes::finance_upsert_transaction,
            commands::writes::finance_upsert_budget,
            commands::writes::finance_upsert_goal,
            commands::writes::finance_upsert_inventory_item,
            commands::writes::finance_upsert_receipt,
            commands::writes::finance_import_transactions_csv,
            commands::writes::finance_import_transactions_csv_path,
            commands::writes::finance_delete_transaction,
            commands::writes::finance_delete_account,
            commands::writes::finance_delete_budget,
            commands::writes::finance_delete_goal,
            commands::writes::finance_delete_inventory_item,
            commands::writes::finance_delete_receipt,
            commands::writes::finance_upsert_holding,
            commands::writes::finance_delete_holding,
            commands::writes::finance_upsert_recurring,
            commands::writes::finance_run_recurring_due,
            commands::writes::finance_mark_due_paid,
            commands::writes::documents_upsert_vault_doc,
            commands::writes::documents_delete_vault_doc,
            commands::writes::documents_delete_folder_cascade,
            commands::writes::profile_upsert_identity,
            commands::writes::profile_upsert_experience,
            commands::writes::profile_upsert_achievement,
            commands::writes::profile_delete_experience,
            commands::writes::profile_delete_achievement,
            commands::writes::demo_seed_sample_data,
        ])
        .run(tauri::generate_context!())
        .expect("error while running College");
}
