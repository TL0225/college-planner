use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

/// Host-level rate limiter mirroring CatalogFetchPoliteness.
pub struct FetchPoliteness {
    last_hit: Mutex<HashMap<String, Instant>>,
    min_interval: Duration,
}

impl FetchPoliteness {
    pub fn new(min_interval: Duration) -> Self {
        Self {
            last_hit: Mutex::new(HashMap::new()),
            min_interval,
        }
    }

    pub fn global() -> &'static Self {
        use std::sync::OnceLock;
        static INSTANCE: OnceLock<FetchPoliteness> = OnceLock::new();
        INSTANCE.get_or_init(|| FetchPoliteness::new(Duration::from_millis(400)))
    }

    pub async fn await_slot(&self, raw_url: &str) {
        let host = parse_host(raw_url).unwrap_or_else(|| "unknown".into());

        loop {
            let sleep_for = {
                let mut map = self.last_hit.lock().await;
                if let Some(last) = map.get(&host) {
                    let elapsed = last.elapsed();
                    if elapsed < self.min_interval {
                        Some(self.min_interval - elapsed)
                    } else {
                        map.insert(host.clone(), Instant::now());
                        None
                    }
                } else {
                    map.insert(host.clone(), Instant::now());
                    None
                }
            };
            if let Some(d) = sleep_for {
                tokio::time::sleep(d).await;
            } else {
                break;
            }
        }
    }
}

fn parse_host(s: &str) -> Option<String> {
    let rest = s
        .strip_prefix("https://")
        .or_else(|| s.strip_prefix("http://"))?;
    rest.split('/').next().map(|h| h.to_string())
}

#[allow(dead_code)]
fn _arc_hint() -> Arc<()> {
    Arc::new(())
}
