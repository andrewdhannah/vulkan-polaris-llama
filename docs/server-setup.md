# Server Setup — llama-server-mini

> Usage, build, and troubleshooting guide for the llama-server-mini HTTP server
> with the Vulkan Polaris fix.

## Prerequisites

- llama.cpp built with `-DGGML_VULKAN=ON` and the Polaris fix patch applied
- A GGUF model file (known-good: `qwen2.5-coder-1.5b-q8_0.gguf`)
- Vulkan SDK installed and working (`vulkaninfo` succeeds)
- AMD Polaris GPU with up-to-date drivers

See [REBUILD-STEPS.md](../REBUILD-STEPS.md) for the full build procedure.

## Starting the Server

### Using start_server.bat

If you cloned this repo alongside llama.cpp, double-click `start_server.bat`.
Edit the `LLAMA_DIR` and `MODEL` paths at the top of the script to match your
setup.

### Manual start

```cmd
llama-server-mini -m G:\llama.cpp\models\qwen2.5-coder-1.5b-q8_0.gguf ^
  -p 8080 -c 32768 -ngl 99 -n 512
```

Wait ~12 seconds for the model to load. You'll see:

```
[server] Loading model...
[server] Model loaded. Starting HTTP on port 8080...
[server] Listening on http://0.0.0.0:8080
[server] Model: G:\llama.cpp\models\qwen2.5-coder-1.5b-q8_0.gguf
[server] Context: 32768 tokens, GPU layers: 99, Auth: disabled
```

## Command-Line Options

```
llama-server-mini -m model.gguf [-p port] [-c context_size] [-ngl gpu_layers] [-n max_tokens] [--host address] [--api-key key]
```

| Flag | Default | Description |
|------|---------|-------------|
| `-m`  | (required) | Path to GGUF model file |
| `-p`  | 8080       | HTTP port to listen on |
| `-c`  | 32768      | Context size (tokens) |
| `-ngl`| 99         | Number of layers to offload to GPU |
| `-n`  | 512        | Maximum tokens to generate per request |
| `--host` | `0.0.0.0` | Bind address. Use `127.0.0.1` for local-only access |
| `--api-key` | (none) | Enable Bearer token authentication |

## Security Note

The server binds to `0.0.0.0` by default (all interfaces). This makes it
reachable from other machines on the same network, but also means anyone on
your LAN can access it if no API key is set.

**Recommended:**
- Set `--host 127.0.0.1` if you only need local access
- Set `--api-key <secret>` and configure clients to send `Authorization: Bearer <key>`
- Use a Windows Firewall rule to restrict access to trusted IPs
- See [SECURITY.md](../SECURITY.md) for details

## Windows Firewall

If clients on other machines cannot reach the server, create a firewall rule:

```cmd
netsh advfirewall firewall add rule name="llama-server-mini" ^
  dir=in action=allow protocol=TCP localport=8080 ^
  remoteip=192.168.0.0/24
```

## Health Checks

### Local health check

```bash
curl http://localhost:8080/health
```

Expected response:
```json
{
  "status": "ok",
  "model": "qwen2.5-coder-1.5b-q8_0",
  "n_ctx": 32768,
  "n_gpu_layers": 99,
  "auth_required": false
}
```

### LAN health check

```bash
curl http://<BIG_PICKLE_LAN_IP>:8080/health
```

Replace `<BIG_PICKLE_LAN_IP>` with the Windows PC's LAN IP (found via `ipconfig`).

### List models

```bash
curl http://localhost:8080/v1/models
```

## API Usage

### Non-streaming chat completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write hello world in Python"}],"stream":false}'
```

### With API key

If the server was started with `--api-key mysecret`:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer mysecret" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"stream":false}'
```

### Python client

```python
import requests
r = requests.post("http://192.168.0.158:8080/v1/chat/completions", json={
    "messages": [{"role": "user", "content": "Write hello world in Python"}]
})
print(r.json()["choices"][0]["message"]["content"])
```

## OpenWork / OpenCode Integration

1. Open Settings → AI Providers
2. Add Provider → Custom (OpenAI-compatible)
3. Set:
   - **Name**: Qwen Vulkan
   - **Base URL**: `http://192.168.0.158:8080/v1`
   - **API Key**: (leave blank unless `--api-key` is set)
4. Save
5. Select it from the model picker in any session

You can also add the provider directly to `opencode.jsonc`:

```jsonc
"qwen-vulkan": {
  "name": "Qwen Vulkan (Windows)",
  "npm": "@ai-sdk/openai-compatible",
  "options": {
    "baseURL": "http://192.168.0.158:8080/v1",
    "apiKey": "sk-vulkan-local"
  },
  "models": {
    "qwen2.5-coder-1.5b-q8_0": {
      "name": "Qwen 2.5 Coder 1.5B"
    }
  }
}
```

## Troubleshooting

### Model fails to load

- Check the model file path is correct.
- Verify the model file is not truncated (compare file size to the Hugging Face listing).
- Run `llama-cli` or `llama-perplex` directly to test model loading outside the server.

### Vulkan device lost

- This was the original bug. Confirm the patch was applied (`git diff --stat` in llama.cpp should show changes in `ggml-vulkan.cpp`).
- Run the diagnostic tests in `tests/` to verify queue-family and pNext handling:
  ```cmd
  cl tests/test_vk_queues.cpp /I "%VULKAN_SDK%\Include" /link "%VULKAN_SDK%\Lib\vulkan-1.lib"
  ```
- If the patch is applied and tests pass, try a full driver reinstall (DDU + clean install).

### Port already in use

```cmd
netstat -ano | findstr :8080
```

Find the PID and kill it:
```cmd
taskkill /PID <PID> /F
```

Or use a different port with `-p`.

### Cannot reach from another machine

1. Verify the server is running and bound to `0.0.0.0` (check the startup log).
2. Test locally first: `curl http://localhost:8080/health`.
3. On the Windows PC, check `ipconfig` for the correct LAN IP.
4. From the other machine, ping the Windows PC.
5. If ping works but curl doesn't, add a firewall rule (see above).
6. If ping doesn't work, both machines may not be on the same network segment.

### Slow CPU fallback

Check the startup log for the number of layers offloaded. If it says "0 layers
offloaded to GPU" or CPU-only benchmarks, the Vulkan backend may not be
loading. Verify:
- llama.cpp was built with `-DGGML_VULKAN=ON`.
- The Vulkan SDK is installed and `vulkaninfo` shows the Polaris GPU.
- The patch applied cleanly.

### Context full

The server keeps conversation history. If you send many long messages, the
context fills up and the model returns `[context full]`. Restart the server
to clear history, or reduce the context size with `-c`.

## Build Instructions

See [REBUILD-STEPS.md](../REBUILD-STEPS.md) for a complete walkthrough.
