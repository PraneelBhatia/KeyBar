# KeyBar

A macOS menu-bar app for API keys. Store them in Keychain, check whether they work, and drag usage instructions into an agent chat.

Supports any API key. Built-in checks for Gemini, OpenRouter, Anthropic, and OpenAI. Shows when you added a key; OpenRouter also reports its remaining key limit when available.

<img src="docs/screenshots/app.jpg" alt="KeyBar app showing sample API keys, validation status, and agent access instructions" width="800">

## Install

Download the Apple silicon DMG from [Releases](https://github.com/PraneelBhatia/KeyBar/releases), open it, and drag KeyBar to Applications. Requires macOS 14 or later. The current download is not Apple-notarized, so macOS may block opening it.

## Use

1. Add a key and its environment variable name.
2. Check access, or save without checking.
3. Drag a key into an agent chat, or copy its instructions.

The note contains a command that loads the selected key from Keychain into a child process. It contains no secret. It does not change an existing agent session's environment.

Keys stay in local Keychain storage. No analytics or sync. An agent given access can still read the key; use agents you trust. Checks confirm endpoint access, not billing or every model permission.

## Build

Requires Swift 6. No external dependencies.

```sh
./scripts/test.sh
./scripts/build-app.sh
open dist/KeyBar.app
```

Run `./scripts/build-dmg.sh` to package a DMG for your Mac's architecture.

[Usage and security details](docs/USAGE.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)
