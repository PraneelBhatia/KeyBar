# Using KeyBar

## Use it

Requires macOS 14 or later and Swift 6 (Xcode or Command Line Tools).

```sh
./scripts/build-app.sh
open dist/KeyBar.app
```

Move the app to Applications or keep it in this folder. Drag it to the Dock for quick access; it also has a menu-bar icon. **Move it before sharing instructions:** the note includes the app's current executable path.

1. Click **Add a key**, paste a credential, give it a friendly name and an uppercase environment variable.
2. Choose the provider. Recognizable prefixes suggest OpenRouter, Anthropic, or OpenAI. For Gemini, select Gemini explicitly: Google keys also serve other APIs. Any other API key works with **Other service**.
3. Save with or without a provider check. The form names the destination before sending a request.
4. Drag a key row or its agent card into a chat or `AGENTS.md`, or click **Copy instructions**. Only instructions are copied.

The agent receives a command like:

```sh
'/path/to/KeyBar.app/Contents/MacOS/KeyBar' exec --key OPENROUTER_API_KEY -- python3 script.py
```

Keychain mode reads only the selected key and launches the command with the variable in its environment. This mode writes no secret file. The shared note never contains a secret. Multiple `--key` options are supported. To start a new terminal agent with access, use the same wrapper with its executable as the command. An existing session can use the wrapper to run a child command; dropping the note alone does not modify its environment.

Use a program or SDK that reads the variable itself. Avoid interpolating a key into command-line arguments or using verbose HTTP/debug output.

## Agent access

Choose **Agent chooses**, **Keychain**, **.env**, or **.zshrc** before dragging or copying instructions. The menu-bar panel uses the same choice. Agent chooses includes commands for all three methods.

- **Keychain:** runs a child command with only the selected stored keys added to its environment.
- **.env:** writes one selected key to a project file. **Load key… → Load into .env…** opens a project-folder picker and asks before writing. Existing values for that variable are replaced after confirmation; unrelated entries are preserved. Files are written atomically with owner-only permissions (`0600`). The CLI requires `--replace` to overwrite an existing variable.
- **.zshrc:** **Load key… → Enable in .zshrc…** adds a marked block that fetches the selected value from Keychain using `/usr/bin/security`. The profile contains a reference, not the secret. New interactive zsh sessions and their children receive the key; existing shells and desktop agent sessions do not. `ZDOTDIR` is honored when inherited by KeyBar; otherwise the app uses `~/.zshrc`. The CLI can target a custom `.zshrc` explicitly.

```sh
'/path/to/KeyBar.app/Contents/MacOS/KeyBar' env --key SERVICE_TOKEN --file .env
'/path/to/KeyBar.app/Contents/MacOS/KeyBar' shell --key SERVICE_TOKEN --file "${ZDOTDIR:-$HOME}/.zshrc"
```

The `.env` export appends an ignore rule in the same directory and refuses already tracked files. Git must be available when exporting inside a repository. Symlinks, hard links, oversized files, duplicate target assignments, and ambiguous target multiline values are refused. Unrelated complete multiline values are preserved. Values with interpolation or escaping that varies across dotenv readers remain available through Keychain instead of being exported. Use your application's dotenv loader to load the resulting file.

`.zshrc` setup is idempotent and preserves existing settings. It refuses an existing unmanaged assignment for the selected name or a syntactically invalid profile. Keychain may ask permission when the shell reads a key. Removing a stored key does not erase exported files, remove the shell reference, or clear running processes. Rotate at the provider if a value is exposed.

## What a check means

| Provider | Request | Result |
| --- | --- | --- |
| Gemini | `GET /v1beta/models` | Access accepted or failure status |
| OpenRouter | `GET /api/v1/key` | Access and key-specific remaining limit, when reported |
| Anthropic | `GET /v1/models` | Access accepted or failure status |
| OpenAI | `GET /v1/models` | Access accepted or failure status |
| Other service | No request | Stored, unchecked |

These checks do not generate tokens. A valid result confirms access to that endpoint at the time checked; it does not prove sufficient billing, every model permission, or future validity. Restricted access, rate limiting, and unavailable checks are distinct from invalid credentials. OpenRouter's key limit is not the account balance. **Added** is when this value was saved in KeyBar, not when the provider created it. Replacing a key resets that date and its check result.

Provider references: [Gemini models](https://ai.google.dev/api/models), [Gemini authentication](https://ai.google.dev/gemini-api/docs/api-key), [OpenRouter current key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key), [Anthropic models](https://platform.claude.com/docs/en/api/models/list), [OpenAI models](https://developers.openai.com/api/reference/resources/models/methods/list).

## Safety and limits

- Keys and metadata are stored in local, non-syncing macOS Keychain items under service `app.keybar.vault.v1`. The UI lists metadata without reading secret values. No analytics or server.
- Known providers receive a key only on an enabled save check or **Check again**. HTTPS headers carry credentials; URLs do not. Checks use ephemeral sessions, no cookies/cache, a timeout, and reject redirects. Raw provider responses and errors are never displayed or logged.
- The wrapper supplies only selected stored keys. It preserves your existing environment and gives the selected keys to the command **and all its children**. A process or agent with access can reveal or transmit a secret. This reduces accidental exposure; it is not a sandbox or a security boundary against a hostile agent or other software running as you.
- Keychain may ask permission to read credentials. Locked or denied access fails visibly. Ad-hoc development signing can cause prompts again after rebuilding; a stable signing identity is preferable for daily use.
- Your system clipboard still holds the original key after you paste it. KeyBar clears its input when dismissed, but Swift strings are not guaranteed to be zeroized in memory. No reveal/copy-secret function is provided.
- Variables use uppercase shell identifier syntax. Environment variables that control process loading, shell startup, or common runtime configuration are reserved. Rename one to a credential-oriented name if needed.
- Removing a key deletes only the local Keychain item. Revoke compromised keys with the provider.
