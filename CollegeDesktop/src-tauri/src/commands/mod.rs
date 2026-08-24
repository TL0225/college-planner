pub mod academics;
pub mod ai;
pub mod assistant;
pub mod assistant_tool_registry;
pub mod assistant_tools_extended;
pub mod assistant_tools_parity;
pub mod assistant_write_tools;
pub mod backup;
pub mod background;
pub mod calendar;
pub mod calendar_oauth;
pub mod career;
pub mod career_apply;
pub mod catalog;
pub mod discovery;
pub mod documents;
pub mod focus_blocks;
pub mod finance;
pub mod finance_connections;
pub mod lms;
pub mod platform;
pub mod platform_import;
pub mod profile;
pub mod scrapers;
pub mod security;
pub mod settings;
pub mod syllabus;
pub mod transfer;
pub mod writes;

use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandError {
    pub message: String,
}

impl From<anyhow::Error> for CommandError {
    fn from(value: anyhow::Error) -> Self {
        Self {
            message: value.to_string(),
        }
    }
}

pub type CmdResult<T> = Result<T, CommandError>;
