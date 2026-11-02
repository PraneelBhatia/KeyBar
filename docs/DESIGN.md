# KeyBar v0.1 design

A menu-bar panel lists keys and copies or drags agent instructions. A desktop window adds, checks, replaces, and removes keys. Use native NavigationSplitView, List, Form, and toolbar controls with system typography and appearance. Keep the visible copy to labels and actions; put explanations in help tooltips and accessibility hints. Liquid Glass is used for actions on macOS 26+, with standard controls and materials on macOS 14–25. Status always has a text label as well as color.

## Data flow

The form owns a transient secure input. Save creates a generic-password Keychain item whose account is the unique environment variable. The item's generic attribute contains Codable metadata: stable UUID, friendly name, provider, added/check timestamps, status, and an optional remaining key limit. The password data contains the secret. There is no application database or secret file. Updates preserve the UUID; rotation resets dates and status. Duplicate variables are rejected rather than overwritten.

KeyStore is main-actor observable state containing metadata only. It coordinates vault mutations and asynchronous provider checks, prevents simultaneous checks, and verifies the item is still the same revision before recording a result. The add form explicitly names the provider host and permits saving without checking. Ambiguous keys are custom by default.

ProviderChecker builds requests to a fixed set of HTTPS endpoints. Each check uses a short-lived ephemeral URLSession with redirects refused, credentials in headers, and timeouts. It maps responses to a finite, non-sensitive status set. Only OpenRouter's numeric remaining key limit is retained; no response messages or labels reach the UI.

The same signed executable handles UI launch and `exec`. The command parser accepts explicit `--key` selections and a required `--` separator. It reads only those values, sets their environment variables, then uses `execvp` without shell evaluation, preserving terminal behavior and exit status. Secrets never appear in the wrapper's argv. The command controls its own behavior once given access. The environment inherited from the invoking shell is preserved.

Drag and copy encode metadata into a plain-text note with a shell-quoted absolute executable path and an instruction not to reveal the variable. The app does not edit shell profiles, repository instructions, or live agent sessions.

## Scope

Any single-line API key and a custom uppercase variable name. Known providers get an optional authentication check. No sync, accounts, graphing, auto-rotation, telemetry, launch-at-login setup, or global shell export. No reveal or secret-copy actions. No claim that an arbitrary agent can use a credential without having the technical ability to read it.

## Validation

Core tests cover variable validation, provider detection, secret input limits, request destinations and header placement, response classification, metadata serialization, handoff quoting, and command parsing. No test accesses existing user credentials. A read-only demo provides visual fixtures without fake secrets. Keychain permissions and live provider success must be checked on the target Mac with deliberately supplied test keys before a public release.
