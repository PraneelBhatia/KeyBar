# Contributing

Keep KeyBar small. Prefer a clear failure state over guessed success. Never include a real credential in an issue, screenshot, fixture, or log.

Run `./scripts/test.sh` and `./scripts/build-app.sh` before submitting changes. The test script supports both Xcode and Command Line Tools installations. For UI work, inspect the empty state, populated state (`--demo`), add form, keyboard navigation, and menu-bar panel. Test Keychain changes with a separate temporary service, never someone else's stored keys.

To add a provider, extend `Provider`, add a fixed HTTPS endpoint and authentication header in `ProviderChecker`, and test request construction and response mapping with synthetic fixtures. Use a documented, non-generating authentication endpoint. Do not expose arbitrary URLs, redirects, or raw provider errors. Document what the check does and cannot establish.
