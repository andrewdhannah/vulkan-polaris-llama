Running llama.cpp Server on Windows
====================================

Start the server by double-clicking `start_server.bat` in `G:\llama.cpp\`.
A command prompt window will open, the model will load (~12s), and the server
will listen on port 8080.

Once running, you can access it from other devices on your network.

From Any Device on Your Network
-------------------------------

Using curl:

```bash
curl http://192.168.0.158:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write hello world in Python"}],"stream":false}'
```

Using Python:

```python
import requests
r = requests.post("http://192.168.0.158:8080/v1/chat/completions", json={
    "messages": [{"role": "user", "content": "Write hello world in Python"}]
})
print(r.json()["choices"][0]["message"]["content"])
```

Using OpenWork / OpenCode on Another Machine
--------------------------------------------

1. Open Settings → AI Providers
2. Add Provider → Custom (OpenAI-compatible)
3. Set:
   - **Name**: Qwen Vulkan
   - **Base URL**: `http://192.168.0.158:8080/v1`
   - **API Key**: (any value, or leave blank)
4. Save
5. Select it from the model picker in any session

Command-Line Options
--------------------

```
llama-server-mini -m model.gguf [-p port] [-c context_size] [-ngl gpu_layers] [-n max_tokens]
```

| Flag | Default | Description |
|------|---------|-------------|
| `-m`  | (required) | Path to GGUF model file |
| `-p`  | 8080       | HTTP port to listen on |
| `-c`  | 32768      | Context size (tokens) |
| `-ngl` | 99        | Number of layers to offload to GPU |
| `-n`  | 512        | Maximum tokens to generate per request |

Build Instructions
------------------

1. Clone llama.cpp and apply the Polaris fix patch:

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
git apply /path/to/vulkan-polaris-fix.patch
```

2. Build with Vulkan support:

```bash
mkdir build && cd build
cmake .. -DGGML_VULKAN=ON -DSPIRV-Headers_DIR=/path/to/VulkanSDK/Lib/cmake
cmake --build . --config Release
```

3. Copy the server-mini example:

```bash
cp /path/to/server-mini/ examples/server-mini/
# Re-run cmake and build the llama-server-mini target
```
