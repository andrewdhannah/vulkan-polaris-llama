/**
 * llama-server-mini - Minimal HTTP server using llama.cpp directly.
 *
 * Keeps the model loaded, listens on a TCP socket, and serves an
 * OpenAI-compatible chat completions API.
 *
 * Build:
 *     MSBuild: should be part of the solution once cmake is configured
 *
 * Usage:
 *   llama-server-mini -m model.gguf [-p 8080] [-c 32768] [-ngl 99]
 *
 *   Then from anywhere on the network:
 *     curl http://192.168.0.158:8080/v1/chat/completions \
 *       -H "Content-Type: application/json" \
 *       -d '{"messages":[{"role":"user","content":"Hello"}],"stream":false}'
 */

#include "llama.h"
#include "ggml.h"

#include <clocale>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <sstream>
#include <thread>
#include <mutex>
#include <atomic>
#include <algorithm>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>
#endif

// -----------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------
static std::string g_model_path;
static int g_port = 8080;
static int g_n_ctx = 32768;
static int g_ngl = 99;
static int g_n_predict = 512;
static std::string g_type_k = "f16";
static std::string g_type_v = "f16";
static std::string g_alias;

// -----------------------------------------------------------------------
// global model & context (protected by a mutex — one request at a time)
// -----------------------------------------------------------------------
static std::mutex g_mutex;
static llama_model * g_model = nullptr;
static llama_context * g_ctx = nullptr;
static llama_sampler * g_smpl = nullptr;
static const llama_vocab * g_vocab = nullptr;
static std::vector<llama_chat_message> g_messages;
static int g_prev_len = 0;
static std::vector<char> g_formatted;

static std::atomic<bool> g_running{true};

// -----------------------------------------------------------------------
// helpers
// -----------------------------------------------------------------------
static void print_usage(const char * prog) {
    fprintf(stderr, "\nUsage: %s -m model.gguf [-p port] [-c ctx] [-ngl ngl] [-n predict] [--alias name]\n\n", prog);
}

static std::string url_decode(const std::string & src) {
    std::string res;
    for (size_t i = 0; i < src.size(); i++) {
        if (src[i] == '%' && i + 2 < src.size()) {
            int hi, lo;
            sscanf(src.c_str() + i + 1, "%2x", &hi);
            res += (char)hi;
            i += 2;
        } else if (src[i] == '+') {
            res += ' ';
        } else {
            res += src[i];
        }
    }
    return res;
}

static std::string trim(const std::string & s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    size_t end   = s.find_last_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    return s.substr(start, end - start + 1);
}

// Simple JSON string escape
static std::string json_escape(const std::string & s) {
    std::string out;
    out.reserve(s.size() + 2);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;
        }
    }
    return out;
}

// -----------------------------------------------------------------------
// LLM generation (adapted from simple-chat)
// -----------------------------------------------------------------------
static std::string generate(const std::string & prompt) {
    std::string response;

    const bool is_first = llama_memory_seq_pos_max(llama_get_memory(g_ctx), 0) == -1;

    int n_prompt_tokens = -llama_tokenize(g_vocab, prompt.c_str(), prompt.size(), NULL, 0, is_first, true);
    std::vector<llama_token> prompt_tokens(n_prompt_tokens);
    if (llama_tokenize(g_vocab, prompt.c_str(), prompt.size(), prompt_tokens.data(), prompt_tokens.size(), is_first, true) < 0) {
        return "ERROR: failed to tokenize prompt";
    }

    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());

    int n_decoded = 0;
    while (n_decoded < g_n_predict) {
        int n_ctx = llama_n_ctx(g_ctx);
        int n_ctx_used = llama_memory_seq_pos_max(llama_get_memory(g_ctx), 0) + 1;
        if (n_ctx_used + batch.n_tokens > n_ctx) {
            return "[context full]";
        }

        if (llama_decode(g_ctx, batch) != 0) {
            return "ERROR: llama_decode failed";
        }

        llama_token new_token_id = llama_sampler_sample(g_smpl, g_ctx, -1);

        if (llama_vocab_is_eog(g_vocab, new_token_id)) {
            break;
        }

        char buf[256];
        int n = llama_token_to_piece(g_vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n < 0) {
            buf[0] = '?';
            n = 1;
        }
        response.append(buf, n);

        batch = llama_batch_get_one(&new_token_id, 1);
        n_decoded++;
    }

    return response;
}

// -----------------------------------------------------------------------
// Chat handler (preserves conversation history)
// -----------------------------------------------------------------------
static std::string chat_completion(const std::string & user_input) {
    std::lock_guard<std::mutex> lock(g_mutex);

    const char * tmpl = llama_model_chat_template(g_model, nullptr);

    // Add user message
    g_messages.push_back({"user", strdup(user_input.c_str())});

    int new_len = llama_chat_apply_template(tmpl, g_messages.data(), g_messages.size(), true,
                                            g_formatted.data(), (int)g_formatted.size());
    if (new_len > (int)g_formatted.size()) {
        g_formatted.resize(new_len);
        new_len = llama_chat_apply_template(tmpl, g_messages.data(), g_messages.size(), true,
                                            g_formatted.data(), (int)g_formatted.size());
    }
    if (new_len < 0) {
        return "ERROR: failed to apply chat template";
    }

    // Extract the new part of the prompt (only the latest user message)
    std::string prompt(g_formatted.begin() + g_prev_len, g_formatted.begin() + new_len);

    // Generate
    std::string response = generate(prompt);

    // Add assistant response to message history
    g_messages.push_back({"assistant", strdup(response.c_str())});

    g_prev_len = llama_chat_apply_template(tmpl, g_messages.data(), g_messages.size(), false, nullptr, 0);
    if (g_prev_len < 0) {
        g_prev_len = new_len; // fallback
    }

    return response;
}

// -----------------------------------------------------------------------
// HTTP helpers
// -----------------------------------------------------------------------
static void send_response(int client_fd, int status, const std::string & content_type,
                          const std::string & body) {
    std::ostringstream resp;
    resp << "HTTP/1.1 " << status << " ";
    switch (status) {
        case 200: resp << "OK"; break;
        case 400: resp << "Bad Request"; break;
        case 404: resp << "Not Found"; break;
        case 500: resp << "Internal Server Error"; break;
        default:  resp << "Unknown";
    }
    resp << "\r\n"
         << "Content-Type: " << content_type << "\r\n"
         << "Content-Length: " << body.size() << "\r\n"
         << "Access-Control-Allow-Origin: *\r\n"
         << "Connection: close\r\n"
         << "\r\n"
         << body;

    std::string resp_str = resp.str();
#ifdef _WIN32
    send(client_fd, resp_str.c_str(), (int)resp_str.size(), 0);
#else
    write(client_fd, resp_str.c_str(), resp_str.size());
#endif
}

static void send_json(int client_fd, int status, const std::string & json_body) {
    send_response(client_fd, status, "application/json; charset=utf-8", json_body);
}

// -----------------------------------------------------------------------
// Request parser (minimal — just enough for our endpoints)
// -----------------------------------------------------------------------
struct HttpRequest {
    std::string method;
    std::string path;
    std::string body;
};

static bool parse_http(int client_fd, HttpRequest & req) {
    char buf[65536];
#ifdef _WIN32
    int n = recv(client_fd, buf, sizeof(buf) - 1, 0);
#else
    int n = read(client_fd, buf, sizeof(buf) - 1);
#endif
    if (n <= 0) return false;
    buf[n] = '\0';

    std::string raw(buf, n);
    size_t header_end = raw.find("\r\n\r\n");
    if (header_end == std::string::npos) return false;

    std::string header_part = raw.substr(0, header_end);

    // Parse first line: METHOD /path HTTP/1.1
    size_t first_space = header_part.find(' ');
    if (first_space == std::string::npos) return false;
    req.method = header_part.substr(0, first_space);

    size_t second_space = header_part.find(' ', first_space + 1);
    if (second_space == std::string::npos) return false;
    req.path = header_part.substr(first_space + 1, second_space - first_space - 1);

    // Determine Content-Length
    size_t cl_pos = header_part.find("Content-Length: ");
    size_t content_length = 0;
    if (cl_pos != std::string::npos) {
        content_length = (size_t)std::stoll(header_part.substr(cl_pos + 16));
    }

    // Read body: use what we already have, then read more if needed
    size_t body_start = header_end + 4;
    size_t already_have = raw.size() - body_start;

    if (content_length > 0 && already_have < content_length) {
        // Need to read more
        req.body = raw.substr(body_start);
        size_t remaining = content_length - already_have;
        while (remaining > 0) {
            char chunk[4096];
#ifdef _WIN32
            int r = recv(client_fd, chunk, (int)(remaining < sizeof(chunk) ? remaining : sizeof(chunk)), 0);
#else
            int r = read(client_fd, chunk, std::min(remaining, sizeof(chunk)));
#endif
            if (r <= 0) break;
            req.body.append(chunk, r);
            remaining -= (size_t)r;
        }
    } else {
        req.body = raw.substr(body_start);
    }

    return true;
}

// -----------------------------------------------------------------------
// JSON field extractor (basic, no nesting)
// -----------------------------------------------------------------------
static std::string extract_json_string(const std::string & json, const std::string & key) {
    // Find "key":
    std::string search = "\"" + key + "\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return "";

    size_t colon = json.find(':', pos + search.size());
    if (colon == std::string::npos) return "";

    // Skip whitespace
    size_t val_start = json.find_first_not_of(" \t\r\n", colon + 1);
    if (val_start == std::string::npos) return "";

    if (json[val_start] == '"') {
        // String value
        val_start++;
        size_t val_end = val_start;
        while (val_end < json.size()) {
            if (json[val_end] == '\\') {
                val_end += 2;
                continue;
            }
            if (json[val_end] == '"') break;
            val_end++;
        }
        std::string val = json.substr(val_start, val_end - val_start);
        // Unescape
        std::string out;
        for (size_t i = 0; i < val.size(); i++) {
            if (val[i] == '\\' && i + 1 < val.size()) {
                switch (val[i + 1]) {
                    case 'n': out += '\n'; i++; break;
                    case 'r': out += '\r'; i++; break;
                    case 't': out += '\t'; i++; break;
                    default:  out += val[i + 1]; i++; break;
                }
            } else {
                out += val[i];
            }
        }
        return out;
    } else if (json[val_start] == 't' || json[val_start] == 'f' || json[val_start] == 'n') {
        // true / false / null
        size_t val_end = json.find_first_of(",}\n", val_start);
        return json.substr(val_start, val_end - val_start);
    } else {
        // Number
        size_t val_end = json.find_first_of(",}\n", val_start);
        return json.substr(val_start, val_end - val_start);
    }
}

static bool extract_json_bool(const std::string & json, const std::string & key, bool def) {
    std::string val = extract_json_string(json, key);
    if (val.empty()) return def;
    return val == "true";
}

// -----------------------------------------------------------------------
// Handle a single client connection
// -----------------------------------------------------------------------
static void handle_client(int client_fd) {
    HttpRequest req;
    if (!parse_http(client_fd, req)) {
        send_json(client_fd, 400, R"({"error":"bad request"})");
#ifdef _WIN32
        closesocket(client_fd);
#else
        close(client_fd);
#endif
        return;
    }

    // CORS preflight
    if (req.method == "OPTIONS") {
        std::string resp = "HTTP/1.1 204 No Content\r\n"
                           "Access-Control-Allow-Origin: *\r\n"
                           "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
                           "Access-Control-Allow-Headers: Content-Type\r\n"
                           "Connection: close\r\n"
                           "\r\n";
#ifdef _WIN32
        send(client_fd, resp.c_str(), (int)resp.size(), 0);
#else
        write(client_fd, resp.c_str(), resp.size());
#endif
#ifdef _WIN32
        closesocket(client_fd);
#else
        close(client_fd);
#endif
        return;
    }

    // GET /v1/models
    if (req.method == "GET" && req.path == "/v1/models") {
        send_json(client_fd, 200,
            R"({"object":"list","data":[{"id":")" + g_alias + R"(","object":"model","owned_by":"local"}]})");
#ifdef _WIN32
        closesocket(client_fd);
#else
        close(client_fd);
#endif
        return;
    }

    // GET /health or /
    if (req.method == "GET" && (req.path == "/health" || req.path == "/")) {
        send_json(client_fd, 200,
            R"({"status":"ok","model":")" + g_alias + R"("})");
#ifdef _WIN32
        closesocket(client_fd);
#else
        close(client_fd);
#endif
        return;
    }

    // POST /v1/chat/completions
    if (req.method == "POST" && req.path == "/v1/chat/completions") {
        // Extract prompt from messages
        std::string body = req.body;

        // Need to find the last user message content
        // Simple approach: find "role":"user" then find the next "content":"..."
        std::string user_content;
        size_t search_pos = 0;
        while (true) {
            size_t role_pos = body.find("\"role\"", search_pos);
            if (role_pos == std::string::npos) break;

            size_t colon = body.find(':', role_pos + 6);
            if (colon == std::string::npos) break;

            size_t val_start = body.find_first_not_of(" \t\"", colon + 1);
            if (val_start == std::string::npos) break;

            size_t val_end = body.find('"', val_start);
            if (val_end == std::string::npos) break;

            std::string role = body.substr(val_start, val_end - val_start);

            if (role == "user") {
                // Find the content of this message
                size_t content_pos = body.find("\"content\"", val_end);
                if (content_pos == std::string::npos) break;

                size_t content_colon = body.find(':', content_pos + 9);
                if (content_colon == std::string::npos) break;

                size_t cstart = body.find_first_not_of(" \t\"", content_colon + 1);
                if (cstart == std::string::npos) break;

                size_t cend = cstart;
                while (cend < body.size()) {
                    if (body[cend] == '\\') { cend += 2; continue; }
                    if (body[cend] == '"') break;
                    cend++;
                }

                user_content = body.substr(cstart, cend - cstart);
                // Unescape
                std::string unescaped;
                for (size_t i = 0; i < user_content.size(); i++) {
                    if (user_content[i] == '\\' && i + 1 < user_content.size()) {
                        switch (user_content[i + 1]) {
                            case 'n': unescaped += '\n'; i++; break;
                            case 'r': unescaped += '\r'; i++; break;
                            case 't': unescaped += '\t'; i++; break;
                            case '"': unescaped += '"'; i++; break;
                            case '\\': unescaped += '\\'; i++; break;
                            default: unescaped += user_content[i + 1]; i++; break;
                        }
                    } else {
                        unescaped += user_content[i];
                    }
                }
                user_content = unescaped;
            }

            search_pos = val_end + 1;
        }

        // Also check for "messages" array directly
        // If the above didn't find user_content, try the last message content directly
        if (user_content.empty()) {
            // Fallback: try to find "content":" directly
            size_t last_content = body.rfind("\"content\"");
            if (last_content != std::string::npos) {
                size_t content_colon = body.find(':', last_content + 9);
                if (content_colon != std::string::npos) {
                    size_t cstart = body.find_first_not_of(" \t\"", content_colon + 1);
                    if (cstart != std::string::npos) {
                        size_t cend = cstart;
                        while (cend < body.size()) {
                            if (body[cend] == '\\') { cend += 2; continue; }
                            if (body[cend] == '"') break;
                            cend++;
                        }
                        user_content = body.substr(cstart, cend - cstart);
                    }
                }
            }
        }

        if (user_content.empty()) {
            send_json(client_fd, 400, R"({"error":"no user message found"})");
#ifdef _WIN32
            closesocket(client_fd);
#else
            close(client_fd);
#endif
            return;
        }

        // Check for stream parameter
        bool stream = extract_json_bool(body, "stream", false);

        if (stream) {
            // Streaming not fully supported in this minimal server — send non-streaming
            // But we wrap it in SSE format
            std::string response;
            try {
                response = chat_completion(user_content);
            } catch (std::exception & e) {
                response = std::string("ERROR: ") + e.what();
            }

            std::string sse;
            // Send as a single SSE chunk
            std::string data = R"({"choices":[{"delta":{"content":")" + json_escape(response) + R"("},"finish_reason":null}]})";
            sse += "data: " + data + "\n\n";
            sse += "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n";
            sse += "data: [DONE]\n\n";

            send_response(client_fd, 200, "text/event-stream; charset=utf-8", sse);
        } else {
            std::string response;
            try {
                response = chat_completion(user_content);
            } catch (std::exception & e) {
                response = std::string("ERROR: ") + e.what();
            }

            std::string json = R"({"id":"chat-)" + std::to_string(time(nullptr)) + R"(","object":"chat.completion",)"
                               R"("created":)" + std::to_string(time(nullptr)) + R"(,"model":")" + g_alias + R"(",)"
                               R"("choices":[{"index":0,"message":{"role":"assistant","content":")"
                               + json_escape(response) + R"("},"finish_reason":"stop"}])"
                               R"(})";
            send_json(client_fd, 200, json);
        }

#ifdef _WIN32
        closesocket(client_fd);
#else
        close(client_fd);
#endif
        return;
    }

    // Fallback: 404
    send_json(client_fd, 404, R"({"error":"not found"})");
#ifdef _WIN32
    closesocket(client_fd);
#else
    close(client_fd);
#endif
}

// -----------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------
int main(int argc, char ** argv) {
    std::setlocale(LC_NUMERIC, "C");

    // Parse args
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            g_model_path = argv[++i];
        } else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            g_port = std::stoi(argv[++i]);
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            g_n_ctx = std::stoi(argv[++i]);
        } else if (strcmp(argv[i], "-ngl") == 0 && i + 1 < argc) {
            g_ngl = std::stoi(argv[++i]);
        } else if (strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
            g_n_predict = std::stoi(argv[++i]);
        } else if (strcmp(argv[i], "--alias") == 0 && i + 1 < argc) {
            g_alias = argv[++i];
        } else {
            print_usage(argv[0]);
            return 1;
        }
    }

    if (g_model_path.empty()) {
        print_usage(argv[0]);
        return 1;
    }

    if (g_alias.empty()) {
        // Derive alias from model filename (strip path and extension)
        size_t last_slash = g_model_path.find_last_of("/\\");
        std::string filename = (last_slash == std::string::npos) ? g_model_path : g_model_path.substr(last_slash + 1);
        size_t dot = filename.find_last_of('.');
        g_alias = (dot == std::string::npos) ? filename : filename.substr(0, dot);
    }

    fprintf(stderr, "[server] Starting (alias: %s)...\n", g_alias.c_str());

    // -------------------------------------------------------------------
    // Initialize LLM
    // -------------------------------------------------------------------
    llama_log_set([](enum ggml_log_level level, const char * text, void *) {
        if (level <= GGML_LOG_LEVEL_INFO) {
            fprintf(stderr, "%s", text);
        }
    }, nullptr);

    ggml_backend_load_all();

    fprintf(stderr, "[server] Loading model...\n");
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = g_ngl;

    g_model = llama_model_load_from_file(g_model_path.c_str(), model_params);
    if (!g_model) {
        fprintf(stderr, "[server] Failed to load model\n");
        return 1;
    }

    g_vocab = llama_model_get_vocab(g_model);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = g_n_ctx;
    ctx_params.n_batch = g_n_ctx;

    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (!g_ctx) {
        fprintf(stderr, "[server] Failed to create context\n");
        llama_model_free(g_model);
        return 1;
    }

    g_smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(g_smpl, llama_sampler_init_min_p(0.05f, 1));
    llama_sampler_chain_add(g_smpl, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add(g_smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    g_formatted.resize(llama_n_ctx(g_ctx));

    fprintf(stderr, "[server] Model loaded. Starting HTTP on port %d...\n", g_port);

    // -------------------------------------------------------------------
    // Network init
    // -------------------------------------------------------------------
#ifdef _WIN32
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        fprintf(stderr, "[server] WSAStartup failed\n");
        return 1;
    }
#endif

    int server_fd;
#ifdef _WIN32
    server_fd = (int)socket(AF_INET, SOCK_STREAM, 0);
#else
    server_fd = socket(AF_INET, SOCK_STREAM, 0);
#endif
    if (server_fd < 0) {
        fprintf(stderr, "[server] Failed to create socket\n");
        return 1;
    }

    int opt = 1;
#ifdef _WIN32
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, (const char *)&opt, sizeof(opt));
#else
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(g_port);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "[server] Failed to bind port %d\n", g_port);
#ifdef _WIN32
        closesocket(server_fd);
        WSACleanup();
#else
        close(server_fd);
#endif
        return 1;
    }

    if (listen(server_fd, 5) < 0) {
        fprintf(stderr, "[server] Failed to listen\n");
#ifdef _WIN32
        closesocket(server_fd);
        WSACleanup();
#else
        close(server_fd);
#endif
        return 1;
    }

    fprintf(stderr, "[server] Listening on http://0.0.0.0:%d\n", g_port);
    fprintf(stderr, "[server] From your Mac:\n");
    fprintf(stderr, "  curl http://<WINDOWS_IP>:%d/v1/chat/completions \\\n", g_port);
    fprintf(stderr, "    -H \"Content-Type: application/json\" \\\n");
    fprintf(stderr, "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'\n");

    // Accept loop
    while (g_running) {
        struct sockaddr_in client_addr;
#ifdef _WIN32
        int addr_len = sizeof(client_addr);
#else
        socklen_t addr_len = sizeof(client_addr);
#endif
        int client_fd = (int)accept(server_fd, (struct sockaddr *)&client_addr, &addr_len);
        if (client_fd < 0) {
            if (g_running) {
                fprintf(stderr, "[server] Accept failed\n");
            }
            break;
        }

        char client_ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, sizeof(client_ip));
        fprintf(stderr, "[server] Connection from %s\n", client_ip);

        // Handle in a separate thread so we can accept other connections
        std::thread(handle_client, client_fd).detach();
    }

    // Cleanup
#ifdef _WIN32
    closesocket(server_fd);
    WSACleanup();
#else
    close(server_fd);
#endif

    // Free messages
    for (auto & msg : g_messages) {
        free(const_cast<char *>(msg.content));
    }
    llama_sampler_free(g_smpl);
    llama_free(g_ctx);
    llama_model_free(g_model);

    return 0;
}
