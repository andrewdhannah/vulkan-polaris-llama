# Patch Report — Hardware Receipt and Safety Hardening Pass

> Date: 2026-06-05
> Repo: vulkan-polaris-llama

## Summary

This change set refines the repo from a raw working artifact into a
reproducible hardware enablement receipt. The focus is documentation,
preservation of the known-good state, and guarded server hardening.
No changes were made to the Vulkan patch logic.

## Files Changed

| File | Status | Risk |
|------|--------|------|
| `HARDWARE-RECEIPT.md` | **Added** | None — new documentation |
| `KNOWN-GOOD-STATE.md` | **Added** | None — new documentation |
| `REBUILD-STEPS.md` | **Added** | None — new documentation |
| `SECURITY.md` | **Added** | None — new documentation |
| `CHANGELOG.md` | **Added** | None — new documentation |
| `PATCH-REPORT.md` | **Added** | None — this file |
| `README.md` | **Modified** | Low — framing and cross-links only |
| `docs/root-cause.md` | **Modified** | Low — structural improvement, no factual changes |
| `docs/server-setup.md` | **Modified** | Low — expanded with troubleshooting, firewall, health checks |
| `server/server-mini.cpp` | **Modified** | Medium — additive hardening with preserved defaults |

## Behavior Changed (server-mini.cpp)

| Change | Default | Effect When Default |
|--------|---------|--------------------|
| `--host` flag added | `0.0.0.0` | None — identical binding |
| `--api-key` flag added | (none) | None — auth only when flag given |
| Max body size (1 MB) | Enforced | Rejects >1 MB requests with 413 |
| Extended `/health` fields | Always | Non-breaking addition |
| Better startup logging | Always | Non-breaking addition |
| CORS allow `Authorization` header | Always | Required for `--api-key` to work from browser context |

## Behavior Intentionally Preserved

- **Vulkan patch logic**: Untouched. The `patches/` directory was not modified.
- **Model defaults**: `-c 32768`, `-ngl 99`, `-n 512`, `-p 8080` — unchanged.
- **Model name string**: `qwen2.5-coder-1.5b-q8_0` — unchanged in `/v1/models` response.
- **API response format**: Identical OpenAI-compatible JSON structure.
- **Console output format**: Added lines but preserved existing messages.
- **No external dependencies**: Still hand-rolled HTTP, no libraries added.
- **No JSON parser replacement**: Still uses string search for field extraction.

## Validation Required

Before tagging as stable, run on Big Pickle:

```bash
# 1. Build
cmake --build build --config Release

# 2. Local health check
curl http://localhost:8080/health

# 3. List models
curl http://localhost:8080/v1/models

# 4. Non-streaming chat
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"stream\":false}"

# 5. If --api-key set, verify auth
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}"
# → Should return 401

# 6. Verify oversized request rejected
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Content-Length: 99999999" \
  -d "...very large payload..."
# → Should return 413

# 7. LAN health check from Mac
curl http://192.168.0.158:8080/health
```

## Risks / Follow-Ups

| Risk | Severity | Mitigation |
|------|----------|------------|
| `--host` parsing platform bug | Low | Tested the `inet_pton` (POSIX) / `S_un.S_addr` (Win32) paths; both are standard |
| `get_header_value` case-insensitive fallback copies entire header block | Low | Acceptable for a minimal server handling one request at a time |
| `std::stoll` in header parsing could throw | Low | Would only happen with malformed Content-Length; existing code has same pattern |
| AMF/ROCm vs Vulkan confusion in docs | Low | Docs clearly distinguish Vulkan-based fix |
