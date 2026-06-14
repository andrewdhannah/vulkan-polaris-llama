//! llama-router — Rust sidecar for llama.cpp
//!
//! Routes multiple logical sessions through a single llama.cpp instance.
//! Owns session state outside VRAM, packs bounded context, returns receipts.

use axum::{
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use dashmap::DashMap;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{error, info, warn};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const LLAMA_CPP_ADDR: &str = "http://127.0.0.1:9120";
const ROUTER_BIND: &str = "0.0.0.0:8080";
const MAX_TURNS: usize = 8; // keep last N turns per session
const SYSTEM_RULES: &str = "You are a helpful assistant. Be concise and accurate.";

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------
#[derive(Clone)]
struct AppState {
    sessions: Arc<DashMap<String, Session>>,
    http: Arc<Client>,
    /// Mutex to serialize requests to llama.cpp (single-slot server)
    llama_lock: Arc<Mutex<()>>,
}

#[derive(Debug, Clone)]
struct Session {
    id: String,
    created_at: chrono::DateTime<Utc>,
    messages: Vec<ChatMessage>,
    total_tokens_estimate: usize,
}

impl Session {
    fn new(id: String) -> Self {
        Self {
            id,
            created_at: Utc::now(),
            messages: Vec::new(),
            total_tokens_estimate: 0,
        }
    }

    /// Pack messages for forwarding: system rules + recent turns + new message
    fn pack(&self, new_user_message: &str) -> Vec<ChatMessage> {
        let mut packed = Vec::new();

        // Always include system rules
        packed.push(ChatMessage {
            role: "system".into(),
            content: SYSTEM_RULES.into(),
        });

        // Keep last MAX_TURNS turns (each turn = user + assistant)
        let recent = self
            .messages
            .iter()
            .rev()
            .take(MAX_TURNS * 2)
            .cloned()
            .collect::<Vec<_>>();
        let mut recent: Vec<_> = recent.into_iter().rev().collect();

        packed.append(&mut recent);

        // Add the new user message
        packed.push(ChatMessage {
            role: "user".into(),
            content: new_user_message.into(),
        });

        packed
    }

    fn append_user(&mut self, content: &str) {
        self.messages.push(ChatMessage {
            role: "user".into(),
            content: content.into(),
        });
    }

    fn append_assistant(&mut self, content: &str) {
        self.messages.push(ChatMessage {
            role: "assistant".into(),
            content: content.into(),
        });
    }

    fn reset(&mut self) {
        self.messages.clear();
        self.total_tokens_estimate = 0;
    }
}

// ---------------------------------------------------------------------------
// OpenAI-compatible types
// ---------------------------------------------------------------------------
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatRequest {
    model: Option<String>,
    messages: Vec<ChatMessage>,
    max_tokens: Option<usize>,
    temperature: Option<f32>,
    stream: Option<bool>,
    #[serde(default)]
    metadata: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct ChatResponse {
    id: String,
    object: String,
    created: i64,
    model: String,
    choices: Vec<Choice>,
}

#[derive(Debug, Serialize)]
struct Choice {
    index: usize,
    message: ChatMessage,
    finish_reason: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    router: String,
    llama_cpp: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct SessionInfo {
    id: String,
    created_at: chrono::DateTime<Utc>,
    message_count: usize,
    total_tokens_estimate: usize,
}

#[derive(Debug, Serialize)]
struct SessionReceipt {
    id: String,
    created_at: chrono::DateTime<Utc>,
    messages: Vec<ChatMessage>,
    total_tokens_estimate: usize,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------
async fn health(State(state): State<AppState>) -> Response {
    let llama_health = match state.http.get(format!("{}/health", LLAMA_CPP_ADDR)).send().await {
        Ok(resp) => {
            if resp.status().is_success() {
                match resp.json::<serde_json::Value>().await {
                    Ok(v) => v,
                    Err(e) => serde_json::json!({"error": format!("parse error: {}", e)}),
                }
            } else {
                serde_json::json!({"error": format!("status {}", resp.status())})
            }
        }
        Err(e) => serde_json::json!({"error": format!("unreachable: {}", e)}),
    };

    let status = if llama_health.get("error").is_none() {
        "ok"
    } else {
        "degraded"
    };

    let body = HealthResponse {
        status: status.into(),
        router: "ok".into(),
        llama_cpp: llama_health,
    };

    (StatusCode::OK, Json(body)).into_response()
}

async fn list_sessions(State(state): State<AppState>) -> Response {
    let sessions: Vec<SessionInfo> = state
        .sessions
        .iter()
        .map(|entry| {
            let s = entry.value();
            SessionInfo {
                id: s.id.clone(),
                created_at: s.created_at,
                message_count: s.messages.len(),
                total_tokens_estimate: s.total_tokens_estimate,
            }
        })
        .collect();
    Json(sessions).into_response()
}

async fn get_session(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Response {
    match state.sessions.get(&id) {
        Some(entry) => {
            let s = entry.value();
            (StatusCode::OK, Json(SessionReceipt {
                id: s.id.clone(),
                created_at: s.created_at,
                messages: s.messages.clone(),
                total_tokens_estimate: s.total_tokens_estimate,
            })).into_response()
        }
        None => (
            StatusCode::NOT_FOUND,
            Json(SessionReceipt {
                id,
                created_at: Utc::now(),
                messages: vec![],
                total_tokens_estimate: 0,
            }),
        ).into_response(),
    }
}

async fn reset_session(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Response {
    match state.sessions.get_mut(&id) {
        Some(mut entry) => {
            entry.value_mut().reset();
            info!(session_id = %id, "session reset");
            (
                StatusCode::OK,
                Json(serde_json::json!({"status": "ok", "session_id": id})),
            ).into_response()
        }
        None => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "session not found"})),
        ).into_response(),
    }
}

async fn chat_completions(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ChatRequest>,
) -> Response {
    let request_id = Uuid::new_v4().to_string();

    // Extract or create session ID
    let session_id = if let Some(header_val) = headers.get("X-Librarian-Session") {
        header_val.to_str().unwrap_or("").to_string()
    } else if let Some(meta) = &req.metadata {
        meta.get("session_id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string()
    } else {
        String::new()
    };

    let session_id = if session_id.is_empty() {
        let new_id = format!("session-{}", Uuid::new_v4().simple());
        info!(request_id = %request_id, session_id = %new_id, "created new session");
        new_id
    } else {
        session_id
    };

    // Extract the last user message from the request
    let last_user_message = req
        .messages
        .iter()
        .rev()
        .find(|m| m.role == "user")
        .map(|m| m.content.as_str())
        .unwrap_or("");

    if last_user_message.is_empty() {
        warn!(request_id = %request_id, "no user message found");
        let mut resp_headers = HeaderMap::new();
        resp_headers.insert("X-Librarian-Session", HeaderValue::from_str(&session_id).unwrap());
        return (
            StatusCode::BAD_REQUEST,
            resp_headers,
            Json(ChatResponse {
                id: request_id,
                object: "chat.completion".into(),
                created: Utc::now().timestamp(),
                model: req.model.unwrap_or_else(|| "local-rx570".into()),
                choices: vec![Choice {
                    index: 0,
                    message: ChatMessage {
                        role: "assistant".into(),
                        content: "ERROR: no user message found".into(),
                    },
                    finish_reason: "stop".into(),
                }],
            }),
        ).into_response();
    }

    // Get or create session
    let session = state
        .sessions
        .entry(session_id.clone())
        .or_insert_with(|| Session::new(session_id.clone()));

    let is_new_session = session.value().messages.is_empty();

    // Check if we need to reset (session switch or context pressure)
    let needs_reset = if is_new_session {
        false
    } else {
        // Check if this is a different conversation flow
        let last_role = session.value().messages.last().map(|m| m.role.as_str());
        matches!(last_role, Some("assistant") | None)
    };

    // Pack the request
    let packed_messages = session.value().pack(last_user_message);

    // Serialize to llama.cpp
    let llama_request = serde_json::json!({
        "model": req.model.as_deref().unwrap_or("local-rx570"),
        "messages": packed_messages,
        "max_tokens": req.max_tokens.unwrap_or(512),
        "temperature": req.temperature.unwrap_or(0.8),
        "stream": false,
    });

    info!(
        request_id = %request_id,
        session_id = %session_id,
        messages_in_session = session.value().messages.len(),
        packed_messages = packed_messages.len(),
        "forwarding to llama.cpp"
    );

    // Acquire lock to serialize access to llama.cpp
    let _lock = state.llama_lock.lock().await;

    // If switching sessions or context is full, reset llama.cpp first
    if needs_reset {
        info!(session_id = %session_id, "resetting llama.cpp context for session switch");
        let _ = state
            .http
            .post(format!("{}/reset", LLAMA_CPP_ADDR))
            .send()
            .await;
    }

    // Forward to llama.cpp
    let resp = match state
        .http
        .post(format!("{}/v1/chat/completions", LLAMA_CPP_ADDR))
        .json(&llama_request)
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            error!(request_id = %request_id, error = %e, "llama.cpp request failed");
            let mut resp_headers = HeaderMap::new();
            resp_headers.insert("X-Librarian-Session", HeaderValue::from_str(&session_id).unwrap());
            return (
                StatusCode::BAD_GATEWAY,
                resp_headers,
                Json(ChatResponse {
                    id: request_id,
                    object: "chat.completion".into(),
                    created: Utc::now().timestamp(),
                    model: req.model.unwrap_or_else(|| "local-rx570".into()),
                    choices: vec![Choice {
                        index: 0,
                        message: ChatMessage {
                            role: "assistant".into(),
                            content: format!("ERROR: llama.cpp unreachable: {}", e),
                        },
                        finish_reason: "stop".into(),
                    }],
                }),
            ).into_response();
        }
    };

    let status = resp.status();
    if !status.is_success() {
        error!(request_id = %request_id, status = %status, "llama.cpp returned error");
        let mut resp_headers = HeaderMap::new();
        resp_headers.insert("X-Librarian-Session", HeaderValue::from_str(&session_id).unwrap());
        return (
            StatusCode::BAD_GATEWAY,
            resp_headers,
            Json(ChatResponse {
                id: request_id,
                object: "chat.completion".into(),
                created: Utc::now().timestamp(),
                model: req.model.unwrap_or_else(|| "local-rx570".into()),
                choices: vec![Choice {
                    index: 0,
                    message: ChatMessage {
                        role: "assistant".into(),
                        content: format!("ERROR: llama.cpp returned status {}", status),
                    },
                    finish_reason: "stop".into(),
                }],
            }),
        ).into_response();
    }

    let llama_body: serde_json::Value = match resp.json().await {
        Ok(b) => b,
        Err(e) => {
            error!(request_id = %request_id, error = %e, "failed to parse llama.cpp response");
            let mut resp_headers = HeaderMap::new();
            resp_headers.insert("X-Librarian-Session", HeaderValue::from_str(&session_id).unwrap());
            return (
                StatusCode::BAD_GATEWAY,
                resp_headers,
                Json(ChatResponse {
                    id: request_id,
                    object: "chat.completion".into(),
                    created: Utc::now().timestamp(),
                    model: req.model.unwrap_or_else(|| "local-rx570".into()),
                    choices: vec![Choice {
                        index: 0,
                        message: ChatMessage {
                            role: "assistant".into(),
                            content: "ERROR: failed to parse llama.cpp response".into(),
                        },
                        finish_reason: "stop".into(),
                    }],
                }),
            ).into_response();
        }
    };

    // Extract assistant response
    let assistant_content = llama_body
        .get("choices")
        .and_then(|c| c.get(0))
        .and_then(|c| c.get("message"))
        .and_then(|m| m.get("content"))
        .and_then(|c| c.as_str())
        .unwrap_or("");

    // Save to session state
    {
        let mut session = state.sessions.get_mut(&session_id).unwrap();
        session.append_user(last_user_message);
        session.append_assistant(assistant_content);
        // Rough token estimate: ~1.3 tokens per word
        session.total_tokens_estimate +=
            (last_user_message.len() as f64 / 4.0).ceil() as usize
                + (assistant_content.len() as f64 / 4.0).ceil() as usize;
    }

    info!(
        request_id = %request_id,
        session_id = %session_id,
        response_len = assistant_content.len(),
        "response complete"
    );

    // Build OpenAI-compatible response
    let response = ChatResponse {
        id: request_id,
        object: "chat.completion".into(),
        created: Utc::now().timestamp(),
        model: req.model.unwrap_or_else(|| "local-rx570".into()),
        choices: vec![Choice {
            index: 0,
            message: ChatMessage {
                role: "assistant".into(),
                content: assistant_content.into(),
            },
            finish_reason: llama_body
                .get("choices")
                .and_then(|c| c.get(0))
                .and_then(|c| c.get("finish_reason"))
                .and_then(|f| f.as_str())
                .unwrap_or("stop")
                .into(),
        }],
    };

    let mut resp_headers = HeaderMap::new();
    resp_headers.insert("X-Librarian-Session", HeaderValue::from_str(&session_id).unwrap());

    (StatusCode::OK, resp_headers, Json(response)).into_response()
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "llama_router=info,tower_http=info".into()),
        )
        .init();

    info!("llama-router starting");
    info!("llama.cpp backend: {}", LLAMA_CPP_ADDR);
    info!("router bind address: {}", ROUTER_BIND);

    let state = AppState {
        sessions: Arc::new(DashMap::new()),
        http: Arc::new(
            Client::builder()
                .timeout(std::time::Duration::from_secs(120))
                .build()
                .expect("failed to create HTTP client"),
        ),
        llama_lock: Arc::new(Mutex::new(())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/chat/completions", post(chat_completions))
        .route("/sessions", get(list_sessions))
        .route("/sessions/{id}", get(get_session))
        .route("/sessions/{id}/reset", post(reset_session))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(ROUTER_BIND)
        .await
        .expect("failed to bind");

    info!("router listening on {}", ROUTER_BIND);

    axum::serve(listener, app).await.expect("server failed");
}
