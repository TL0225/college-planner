//! CLI: copy Swift College GRDB workspace into the Tauri CollegeDesktop store.
//!
//! Usage:
//!   cargo run --bin import_swift_workspace -- [--force]

use college_lib::db::AppDb;
use college_lib::paths::AppPaths;
use college_lib::swift_seed;

fn main() {
    let force = std::env::args().any(|a| a == "--force");

    let paths = match AppPaths::resolve() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("resolve paths: {e}");
            std::process::exit(1);
        }
    };
    if let Err(e) = paths.ensure_dirs() {
        eprintln!("ensure dirs: {e}");
        std::process::exit(1);
    }

    let db = match AppDb::open(&paths.college_db_path) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("open db: {e}");
            std::process::exit(1);
        }
    };
    if let Err(e) = db.migrate() {
        eprintln!("migrate: {e}");
        std::process::exit(1);
    }

    let result = if force {
        swift_seed::copy_swift_workspace_now(&db, &paths)
    } else {
        match swift_seed::seed_from_swift_if_needed(&db, &paths) {
            Ok(Some(report)) => Ok(report),
            Ok(None) => {
                println!(
                    "{{\"status\":\"skipped\",\"collegeDb\":\"{}\"}}",
                    paths.college_db_path.display()
                );
                return;
            }
            Err(e) => Err(e),
        }
    };

    match result {
        Ok(report) => {
            println!("{}", serde_json::to_string_pretty(&report).unwrap_or_default());
            println!(
                "Tauri store: {}",
                paths.college_db_path.display()
            );
        }
        Err(e) => {
            eprintln!("copy failed: {e}");
            std::process::exit(1);
        }
    }
}
