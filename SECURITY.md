# Security — Vulkan Polaris llama.cpp

> Practical safety notes for the server-mini HTTP server.
> This is a local development tool, not a production service.

## Intended Use

`llama-server-mini` is designed for **trusted LAN environments only**.
It provides an OpenAI-compatible API endpoint for local AI development —
coding assistants, experimentation, and personal tooling.

## Current Implementation

- Binds to `0.0.0.0` (all network interfaces) by default
- Permissive CORS (`Access-Control-Allow-Origin: *`)
- **No authentication by default**
- No TLS/HTTPS
- No rate limiting
- No input sanitization beyond minimal JSON parsing

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Unauthenticated access from external networks | High | Do not expose to the internet |
| Model weight extraction | Medium | LAN-only deployment limits reach |
| Resource exhaustion (context fill, memory) | Low | Fixed context size, single-threaded |
| Injection via malformed request | Low | Minimal parsing surface, no shell execution |

## Safe Deployment

1. **Private LAN only.** Do not forward port 8080 on your router.
2. **Restrict with Windows Firewall.** Allow inbound only from trusted
   development machines:
   ```cmd
   netsh advfirewall firewall add rule name="llama-server-mini" ^
     dir=in action=allow protocol=TCP localport=8080 ^
     remoteip=192.168.0.0/24
   ```
3. **Optional authentication.** If you enable `--api-key`, clients must
   provide `Authorization: Bearer <key>` headers. Without this flag,
   the server has no auth.
4. **Stop when not in use.** Close the server window or kill the process
   when you're done for the day.
5. **Do not expose to the public internet.** No TLS, no auth by default,
   no WAF — this server will be compromised within minutes on the open web.

## If You Need Remote Access

Do not expose server-mini directly. Instead:

- Use a VPN (Tailscale, WireGuard, OpenVPN) and access the server over
  the VPN IP.
- Or tunnel through SSH: `ssh -L 8080:localhost:8080 user@windows-pc`

## Reporting Issues

This is a personal enablement project. Security issues can be reported
via GitHub issues.
