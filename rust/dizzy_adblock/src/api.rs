//! Ad/tracker matching for the in-app embed webview.
//!
//! The engine is Brave's `adblock-rust` over DATA (open-source filter lists +
//! a shipped supplemental list). Blocking decisions never live in Dart/UI code:
//! this module is the single place that answers "should this request be
//! blocked?".
//!
//! The observable Dart API (via flutter_rust_bridge) is:
//!   newEngine(rules: List<String>) -> DizzyEngine
//!   engineMatch(engine, url, sourceHost, resourceType) -> bool
//!
//! ## Why a worker thread
//!
//! `adblock::Engine` is deliberately single-threaded internally (`Rc` /
//! `RefCell`), so it is neither `Send` nor `Sync` — and flutter_rust_bridge's
//! opaque handles require both. Instead of asserting thread-safety with
//! `unsafe impl` (which would be a lie the moment two webview callbacks race),
//! the engine lives on ONE owned thread and every query is a channel
//! round-trip. Access is therefore genuinely serialized, and the expensive
//! filter-list compilation happens off the caller's thread.
//!
//! Dropping the last handle closes the channel and the worker exits.

use std::sync::mpsc::{channel, Sender};
use std::thread;

use adblock::lists::ParseOptions;
use adblock::request::Request;
use adblock::Engine;

enum Query {
    Match {
        url: String,
        source_host: String,
        resource_type: String,
        reply: Sender<bool>,
    },
}

/// One compiled matcher, owned by a dedicated worker thread.
pub struct DizzyEngine {
    tx: Sender<Query>,
}

impl DizzyEngine {
    /// Compile a rule set on a worker thread. Invalid/unsupported rules are
    /// skipped by the underlying parser; one bad line must never take the
    /// engine (or the app) down. If the thread cannot start, every query
    /// answers "allow" — an ad blocker must never be the reason playback fails.
    pub fn from_rules(rules: Vec<String>) -> Self {
        let (tx, rx) = channel::<Query>();
        let spawned = thread::Builder::new()
            .name("dizzy-adblock".to_string())
            .spawn(move || {
                // adblock-rust 0.8 takes an iterator of rules.
                let engine = Engine::from_rules(rules, ParseOptions::default());
                while let Ok(query) = rx.recv() {
                    match query {
                        Query::Match {
                            url,
                            source_host,
                            resource_type,
                            reply,
                        } => {
                            let block = match Request::new(&url, &source_host, &resource_type) {
                                Ok(req) => engine.check_network_request(&req).matched,
                                // Never block on a parse error.
                                Err(_) => false,
                            };
                            let _ = reply.send(block);
                        }
                    }
                }
            });
        if spawned.is_err() {
            // Keep the receiver alive in a dropped thread-free way: closing
            // both ends is fine because every send then fails → allow.
            return Self { tx };
        }
        Self { tx }
    }

    /// True = block this request.
    ///
    /// [source_host] is the page the request came from (e.g. `vidfast.vc`);
    /// [resource_type] follows the webview vocabulary (`document`, `xhr`,
    /// `script`, `image`, `media`, `xmlhttprequest`, …).
    pub fn match_request(&self, url: &str, source_host: &str, resource_type: &str) -> bool {
        let (reply, rx) = channel::<bool>();
        let sent = self.tx.send(Query::Match {
            url: url.to_string(),
            source_host: source_host.to_string(),
            resource_type: resource_type.to_string(),
            reply,
        });
        if sent.is_err() {
            return false;
        }
        // The worker answers immediately after the (one-off) compile.
        rx.recv().unwrap_or(false)
    }
}

// ── flutter_rust_bridge surface ────────────────────────────────────────────

/// Build the matcher. Dart: `newEngine(rules: [...])`.
pub fn new_engine(rules: Vec<String>) -> DizzyEngine {
    DizzyEngine::from_rules(rules)
}

/// Dart: `engineMatch(engine, url, sourceHost, resourceType)`.
pub fn engine_match(
    engine: &DizzyEngine,
    url: String,
    source_host: String,
    resource_type: String,
) -> bool {
    engine.match_request(&url, &source_host, &resource_type)
}
