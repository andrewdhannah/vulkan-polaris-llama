# Windows Rust Router (llama-router)

> **Date:** 2026-06-13  
> **Binary:** `router/target/release/llama-router.exe` (4.8 MB)  
> **Purpose:** Route multiple logical sessions through a single llama.cpp instance

---

## Architecture

```
Mac Librarian / OpenWork
        ↓
  http://windows-pc:8080
        ↓
  Rust Router (llama-router.exe)
        ↓
  http://127.0.0.1:9120
        ↓
  llama-server-mini.exe
        ↓
  RX 570 model (phi-4)
```

**Security boundary:**
- `llama-server-mini.exe` binds to `127.0.0.1` only (localhost)
- Router binds to `0.0.0.0:8080` (LAN-facing)
- Router is the only network-exposed service

---

## Why Rust

| Requirement | Why Rust fits |
|---|---|
| Lightweight | 4.8 MB binary, ~10 MB RAM |
| Long-running | No GC pauses, no runtime dependency |
| Low-memory | Minimal overhead on VRAM-constrained system |
| Single .exe | Easy to ship, no Python/Node install needed |
| Memory safe | Safe around file/process/network boundaries |
| Async HTTP | Good at proxying requests |
| Structured logging | Built-in tracing with request receipts |

---

## What It Does

### Stage 1 (POC) — Implemented

1. **Listen on port 8080** — OpenAI-compatible API
2. **Proxy `/v1/chat/completions`** — Forward to llama.cpp on `127.0.0.1:9120`
3. **Maintain sessions** — Keyed by `X-Librarian-Session` header or `metadata.session_id`
4. **Store transcripts in RAM** — Per-session message history
5. **Pack prompts** — System rules + recent turns + current user message
6. **Forward to llama.cpp** — Single serialized request (mutex-protected)
7. **Save responses** — Append assistant reply to session state
8. **Reset on session switch** — Calls `POST /reset` on llama.cpp when switching sessions
9. **Health endpoint** — Checks both router and llama.cpp health
10. **No shell execution** — Never exposes arbitrary commands

### What It Does NOT Do (Forbidden)

- Decide task priority
- Promote outputs
- Commit code
- Run arbitrary shell commands
- Expose raw model server publicly
- Act as full project authority

---

## API Surface

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Router + llama.cpp health check |
| `POST` | `/v1/chat/completions` | OpenAI-compatible chat completion |
| `GET` | `/sessions` | List all active sessions |
| `GET` | `/sessions/{id}` | Get session transcript |
| `POST` | `/sessions/{id}/reset` | Clear session memory |

### Session Identification

The router accepts session ID via:
1. **Header:** `X-Librarian-Session: my-session-id`
2. **Metadata:** `{"metadata": {"session_id": "my-session-id"}}`
3. **Auto-generated:** If neither provided, creates `session-<uuid>`

The session ID is returned in the `X-Librarian-Session` response header.

### Example: Chat Completion

```bash
curl http://windows-pc:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Librarian-Session: research-task-001" \
  -d '{
    "model": "local-rx570",
    "messages": [{"role": "user", "content": "What is the capital of France?"}]
  }'
```

### Example: Health

```bash
curl http://windows-pc:8080/health
# → {"status":"ok","router":"ok","llama_cpp":{"status":"ok","model":"phi-4"}}
```

### Example: Reset Session

```bash
curl -X POST http://windows-pc:8080/sessions/research-task-001/reset
# → {"status":"ok","session_id":"research-task-001"}
```

---

## Context Strategy

### Deterministic Packing (Stage 1)

1. **Always keep** system rules
2. **Always keep** current user message
3. **Keep last N turns** (default: 8 turns = 16 messages)
4. **If too large**, drop oldest turns
5. **Later:** replace dropped turns with rolling summary

### Session Behavior

| Scenario | Router Action |
|---|---|
| Same session, continuing | Forward with accumulated history |
| Session switch | Reset llama.cpp context, repack new session |
| Context near full | Summarize/truncate, reset, repack |

**Note:** The router does NOT reset before every message. It resets only on session switch or context pressure.

---

## Build Instructions

```powershell
# Requires Rust toolchain (rustup)
cd G:\llama.cpp\router
cargo build --release
```

Output: `G:\llama.cpp\router\target\release\llama-router.exe` (4.8 MB)

### Dependencies

| Crate | Purpose |
|---|---|
| `axum` | HTTP server |
| `tokio` | Async runtime |
| `reqwest` | HTTP client to llama.cpp |
| `serde` / `serde_json` | JSON handling |
| `uuid` | Session ID generation |
| `tracing` / `tracing-subscriber` | Structured logging |
| `dashmap` | Concurrent session storage |
| `chrono` | Timestamps |

---

## Running

```powershell
# Ensure llama-server-mini is running on port 9120
.\model_manager.ps1 start phi-4

# Start router
.\router\target\release\llama-router.exe
```

Router logs to stdout. Set `RUST_LOG=debug` for verbose output.

---

## Topology Comparison

| Approach | VRAM Usage | Sessions | Speed |
|---|---|---|---|
| 1 mini server (no router) | ~3.3 GB | 1 (context fills) | Fast |
| 2 mini servers | ~6.6 GB (impossible on 4GB) | 2 | Slow (CPU fallback) |
| Full llama.cpp server | ~3.4 GB+ | 4 slots (shared VRAM) | Slower (partial GPU) |
| **Router + 1 mini server** | **~3.3 GB** | **Unlimited** | **Fast (full GPU)** |

---

## Related

- [HANDOFF-WINDOWS-LLAMA-POC.md](HANDOFF-WINDOWS-LLAMA-POC.md) — Clean handoff
- [LLAMA-SERVER-MINI-ALIAS-PATCH.md](LLAMA-SERVER-MINI-ALIAS-PATCH.md) --alias + /reset endpoint
- [LIBRARIAN-RUNTIME-CONTRACT.md](LIBRARIAN-RUNTIME-CONTRACT.md) — Substrate-agnostic contract
