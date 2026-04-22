# Taylor Claw

A native macOS chat client for large language models — bring your own API keys, talk to five providers from one window.

Taylor Claw v0.1 is the chat-only foundation of a larger agentic harness. Future versions (v0.2+) will add MCP tool servers, the MemPalace memory system, and OAuth connectors. This release focuses on making the core chat experience fast, native, and private.

## Screenshots

_Screenshots coming soon. The app uses a standard Mac `NavigationSplitView` layout: conversations on the left, chat on the right, model picker in the top trailing toolbar, and Settings (`⌘,`) in its own tabbed window._

## Status

- **Version:** 0.1.0
- **Platform:** macOS 14 Sonoma or later
- **Language:** Swift 6, SwiftUI, strict concurrency enabled
- **License:** MIT

## Supported providers

| Provider | Models shipped | Connection | Notes |
|----------|----------------|------------|-------|
| Anthropic | `claude-opus-4-7` (default), `claude-sonnet-4-6`, `claude-haiku-4-5-20251001` | BYO key | Messages API, SSE streaming |
| OpenAI | `gpt-5`, `gpt-5-mini`, `gpt-4.1` | BYO key | Chat Completions API |
| Google Gemini | `gemini-2.5-pro`, `gemini-2.5-flash` | BYO key | `streamGenerateContent` with `alt=sse` |
| Ollama | Auto-detected from `ollama list` | Local, no key | Connects to `http://localhost:11434` |
| OpenRouter | Any model — paste IDs in Settings | BYO key | Unified endpoint, one key for many models |

You can switch providers or models mid-conversation. Each message remembers which model produced it.

## Setup

### Prerequisites

- macOS 14 Sonoma or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build

```bash
git clone https://github.com/catinahat85/taylorclaw.git
cd taylorclaw
xcodegen generate
open TaylorClaw.xcodeproj
```

Then hit Run (`⌘R`) in Xcode. The first build will resolve the `MarkdownUI` Swift package; subsequent builds should be fast.

### Tests

```bash
xcodebuild test -project TaylorClaw.xcodeproj -scheme TaylorClaw -destination 'platform=macOS'
```

## How to add an API key

1. Open Settings (`⌘,`).
2. Pick the tab for your provider (Anthropic, OpenAI, Gemini, or OpenRouter).
3. Paste your key into the secure field and click **Save**.
4. Click **Test connection** to confirm it works.

Keys live in the macOS Keychain (`com.catinahat85.taylorclaw.apikeys`, accessibility `WhenUnlockedThisDevice`). They are never written to disk or sent anywhere except the provider you are talking to.

Ollama doesn't need a key — just make sure `ollama serve` is running locally. The **Refresh models** button in the Ollama tab rescans `/api/tags` for anything you've pulled.

## Where data lives

- **API keys:** macOS Keychain, service `com.catinahat85.taylorclaw.apikeys`.
- **Conversations:** `~/Library/Application Support/TaylorClaw/conversations.json`, written atomically on every message.
- **Preferences:** standard `UserDefaults` (default model, appearance override, onboarding flag, OpenRouter model IDs).
- **MemPalace runtime trace:** `~/Library/Application Support/TaylorClaw/mcp-mempalace.log` (append-only lifecycle + stderr lines from the MCP subprocess).

### Debugging a MemPalace startup hang

1. Open **Settings → Diagnostics** and click **Refresh**.
2. In **Runtime & MemPalace**, copy:
   - **MemPalace log** (the full on-disk path),
   - **Log tail** (durable trace from the log file, including previous runs),
   - **Live stderr** (current process stderr, if running).
3. You can also inspect the file directly from Terminal:
   ```bash
   tail -n 200 ~/Library/Application\ Support/TaylorClaw/mcp-mempalace.log
   ```

## Keyboard shortcuts

| Shortcut | Action |
|---------|--------|
| `⌘N` | New chat |
| `⌘⇧K` | Clear current conversation |
| `⌘,` | Settings |
| `⌘↩` | Send message |
| `⌘.` | Stop streaming |
| `Shift ↩` | Newline in composer |

## Known limitations (v0.1)

- No tool calling. Chat-only. (Landing in v0.2 as the MCP tool runtime.)
- No file attachments. The paperclip button is there but disabled.
- No image input, vision, or audio.
- No voice/speech-to-text.
- No global hotkey or menu bar extra.
- No auto-updater (Sparkle) and no code signing. Builds are unsigned by default; run from Xcode.
- Conversations are stored in a single JSON file. Fine for hundreds of chats; we'll shard in v0.2 once we start attaching artifacts.
- OpenRouter model list is user-maintained in the OpenRouter settings tab (one model ID per line). We do not auto-fetch the full catalog.

## Security and privacy

Taylor Claw talks directly to the provider you select — no Taylor Claw server, no telemetry, no analytics. The app sandbox allows outbound network only; there are no background services. API keys are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Logs never contain keys.

## Roadmap

### v0.2 (next)
- MCP server runtime: launch, supervise, and route tool calls to local MCP processes.
- File attachments: drag files into the composer; vision-capable models receive images, text-capable models receive extracted text.
- Tool-call rendering: inline, collapsible blocks that show the tool, input, and output.
- MemPalace: long-term, structured memory integrated as a first-class MCP server.

### v0.3 and beyond
- OAuth connectors (Google, Notion, Linear, Slack) surfaced as MCP servers with a single auth consent flow.
- Multi-file conversation sharding so attachments don't bloat the main JSON.
- Voice input via macOS dictation.
- Global hotkey for a quick-ask panel.
- Sparkle-based auto-updates and a notarized, signed build.

## Contributing

This is a personal project for now. Issues and small PRs are welcome — please open an issue before starting large changes.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Jake Pineda.
