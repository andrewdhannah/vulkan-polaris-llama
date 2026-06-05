# Changelog

## 2026-06-05 — Hardware receipt and safety hardening pass

- **Docs added:**
  - `HARDWARE-RECEIPT.md` — Known-good hardware enablement record for Big Pickle
  - `KNOWN-GOOD-STATE.md` — Verified configuration table
  - `REBUILD-STEPS.md` — Complete Windows rebuild procedure
  - `SECURITY.md` — LAN-only deployment guidance
  - `PATCH-REPORT.md` — Summary of this change set
  - `CHANGELOG.md` — This file
- **README.md updated:** Framed as a Polaris compatibility patch and rebuild record, with status block and cross-references
- **docs/server-setup.md updated:** Complete prerequisites, firewall notes, health checks, troubleshooting
- **docs/root-cause.md updated:** Improved structure with confirmed environment, hardware scope, unknowns section, and clear scope statement
- **Server hardening (additive, no behavioral change to defaults):**
  - `--host` flag to control bind address (default: `0.0.0.0` to preserve LAN access)
  - `--api-key` flag for optional Bearer token authentication (default: disabled)
  - Maximum request body size enforcement (reject >1 MB with HTTP 413)
  - Enhanced startup logging (model path, context size, GPU layers, bind host, port, auth status)
  - Extended `/health` endpoint with `n_ctx`, `n_gpu_layers`, `auth_required` fields
- **No change to Vulkan patch behavior.**
