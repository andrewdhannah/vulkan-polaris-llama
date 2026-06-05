# Rebuild Steps — Vulkan Polaris llama.cpp

> Complete procedure to rebuild the known-good llama.cpp Vulkan inference
> setup from scratch on a Windows machine with an AMD Polaris GPU.

## Prerequisites

- Windows 10 or 11
- AMD Polaris GPU (RX 400/500 series)
- Administrator access (for driver install, firewall rules)
- ~15 GB free disk space

## 1. Install AMD Driver

Download and install the latest AMD Adrenalin driver for your GPU from
[https://www.amd.com/en/support](https://www.amd.com/en/support).

**Known-good version:** Adrenalin 26.5.2 (Vega/Polaris driver).
Later versions may also work but are untested.

After install, reboot and verify the GPU appears in Device Manager.

## 2. Install Vulkan SDK

1. Download from [https://vulkan.lunarg.com/](https://vulkan.lunarg.com/)
2. Run the installer (default options are fine).
3. **Known-good version:** 1.3.296.0

Verify installation:

```cmd
vulkaninfo
```

Confirm your Polaris GPU appears in the output.

## 3. Clone llama.cpp

```cmd
cd G:\
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
```

> Record the commit you're building from. This helps if a future version
> changes the Vulkan backend and the patch needs updating.
>
> ```cmd
> git rev-parse HEAD > COMMIT.txt
> ```

## 4. Apply the Polaris Fix Patch

```cmd
git apply G:\vulkan-polaris-llama\patches\ggml-vulkan-polaris-fix.patch
```

If the patch applies cleanly, `git diff --stat` will show changes in
`ggml/src/ggml-vulkan/ggml-vulkan.cpp`.

**Expected:** the patch changes device creation in the Vulkan backend to:
- Fall back to graphics-capable queue family 0
- Use a minimal Vk11 + Vk12 pNext chain for device creation
- Use the C API (`vkCreateDevice`) instead of the C++ wrapper

## 5. Add server-mini to the Build

```cmd
mkdir examples\server-mini
copy G:\vulkan-polaris-llama\server\server-mini.cpp examples\server-mini\
copy G:\vulkan-polaris-llama\server\CMakeLists.txt examples\server-mini\
```

Then add `add_subdirectory(examples/server-mini)` to the root `CMakeLists.txt`
inside the `add_subdirectory(examples)` block.

## 6. Configure CMake

```cmd
mkdir build
cd build
cmake .. -DGGML_VULKAN=ON ^
  -DSPIRV-Headers_DIR="C:\VulkanSDK\1.3.296.0\Lib\cmake\SPIRV-Headers"
```

> **Note:** The `SPIRV-Headers_DIR` path depends on your Vulkan SDK version.
> Adjust the version number or omit the flag if CMake finds it automatically.

## 7. Build Release

```cmd
cmake --build . --config Release
```

The server-mini binary will be at one of:

- `build\bin\Release\llama-server-mini.exe`
- `build\examples\server-mini\Release\llama-server-mini.exe`

## 8. Place the GGUF Model

Download `qwen2.5-coder-1.5b-q8_0.gguf` (or your preferred model) from
Hugging Face. Place it in `G:\llama.cpp\models\`.

Verify the file is not truncated:

```cmd
dir G:\llama.cpp\models\qwen2.5-coder-1.5b-q8_0.gguf
```

## 9. Local Smoke Test

Start the server:

```cmd
build\bin\Release\llama-server-mini.exe ^
  -m G:\llama.cpp\models\qwen2.5-coder-1.5b-q8_0.gguf ^
  -p 8080 -c 32768 -ngl 99 -n 512
```

Wait ~12 seconds for the model to load.

In a second terminal (or from another machine), verify:

```cmd
curl http://localhost:8080/health
```

Expected response:
```json
{"status":"ok","model":"qwen2.5-coder-1.5b-q8_0","n_ctx":32768,"n_gpu_layers":99,"auth_required":false}
```

List models:

```cmd
curl http://localhost:8080/v1/models
```

Send a chat request:

```cmd
curl http://localhost:8080/v1/chat/completions ^
  -H "Content-Type: application/json" ^
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello in 5 words\"}],\"stream\":false}"
```

Expected: a JSON response with the assistant's reply and `"finish_reason":"stop"`.

## 10. LAN Smoke Test

Find your Windows PC's LAN IP:

```cmd
ipconfig
```

Look for the IPv4 address under your active network adapter (e.g., `192.168.0.158`).

From another machine on the same network:

```bash
curl http://192.168.0.158:8080/health
```

If this fails, check:
- Windows Firewall allows inbound connections on port 8080 (see note below)
- Both machines are on the same subnet
- The server is binding to `0.0.0.0` (default) not `127.0.0.1`

## 11. Windows Firewall Note

If the LAN test fails, create a firewall rule to allow inbound TCP on port 8080:

```cmd
netsh advfirewall firewall add rule name="llama-server-mini" ^
  dir=in action=allow protocol=TCP localport=8080
```

For better security, restrict the rule to your trusted subnet:

```cmd
netsh advfirewall firewall add rule name="llama-server-mini" ^
  dir=in action=allow protocol=TCP localport=8080 ^
  remoteip=192.168.0.0/24
```

## 12. Record the Results

After a successful rebuild, update [KNOWN-GOOD-STATE.md](KNOWN-GOOD-STATE.md):

| Field | Action |
|-------|--------|
| **llama.cpp commit** | Run `git rev-parse HEAD` in the checkout |
| **GPU layers** | Check server log for actual layers offloaded |
| **Generation speed** | Time a known-length response and calculate tok/s |
| **All other fields** | Confirm they match, or update if changed |
