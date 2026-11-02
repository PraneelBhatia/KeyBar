# KeyBar design

A menu-bar panel lists keys and copies or drags agent instructions. A desktop window adds, checks, replaces, and removes keys. Use native NavigationSplitView, List, Form, and toolbar controls with system typography and appearance. Keep the visible copy to labels and actions; put explanations in help tooltips and accessibility hints. Liquid Glass is used for actions on macOS 26+, with standard controls and materials on macOS 14–25. Status always has a text label as well as color.

## Data flow

The form owns a transient secure input. Save creates a generic-password Keychain item whose account is the unique environment variable. The item's generic attribute contains Codable metadata: stable UUID, friendly name, provider, optional custom-provider ID and label, added/check timestamps, status, and an optional remaining key limit. The password data contains the secret. Reusable custom-provider names and stable IDs are stored separately in UserDefaults. Renaming one updates the live display through its stable ID. Before removal, saved key metadata retains the latest provider label as a snapshot; secrets are unchanged. Older key metadata decodes with the optional fields absent. There is no application database. Explicit .env exports create a plaintext copy outside Keychain. Metadata edits preserve the UUID, secret, added date, and check result. Variable renames change the Keychain account and metadata together using SecItemUpdate. Provider changes reset the check result; secret rotation resets the added date and check result. Optional revision IDs prevent older checks from overwriting edited metadata. Duplicate variables are rejected rather than overwritten.

KeyStore is main-actor observable state containing metadata only. It coordinates vault mutations and asynchronous provider checks, prevents simultaneous checks, and verifies the item is still the same revision before recording a result. The add form explicitly names the provider host and permits saving without checking. Ambiguous keys are custom by default.

ProviderChecker builds requests to a fixed set of HTTPS endpoints. Each check uses a short-lived ephemeral URLSession with redirects refused, credentials in headers, and timeouts. It maps responses to a finite, non-sensitive status set. Only OpenRouter's numeric remaining key limit is retained; no response messages or labels reach the UI.

The same signed executable handles UI launch and `exec`. The command parser accepts explicit `--key` selections and a required `--` separator. It reads only those values, sets their environment variables, then uses `execvp` without shell evaluation, preserving terminal behavior and exit status. Secrets never appear in the wrapper's argv. The command controls its own behavior once given access. The environment inherited from the invoking shell is preserved.

Drag and copy encode metadata into a plain-text note with a shell-quoted absolute executable path and an instruction not to reveal the variable. The selected handoff mode controls whether the note provides Keychain, .env, .zshrc, or all three commands. The note never contains a secret. Explicit load actions use a confirmation before writing a selected key to .env or adding a Keychain reference to .zshrc. The app does not edit repository instructions or live agent environments.

## Scope

Any single-line API key and a custom uppercase variable name. Known providers get an optional authentication check. No sync, accounts, graphing, auto-rotation, telemetry, or launch-at-login setup. Shell export is explicit and applies only to selected keys in new interactive sessions. No reveal or secret-copy actions. No claim that an arbitrary agent can use a credential without having the technical ability to read it.

## Validation

Core tests cover variable validation, provider detection, secret input limits, request destinations and header placement, response classification, metadata serialization, handoff quoting, and command parsing. No test accesses existing user credentials. An in-memory demo provides visual fixtures and metadata editing without loading secrets or writing to Keychain. Keychain permissions and live provider success must be checked on the target Mac with deliberately supplied test keys before a public release.

EnvironmentFiles preserves unrelated entries, uses bounded UTF-8 reads and atomic writes, refuses linked or foreign-owned files, and sets .env permissions to 0600 and clears inherited ACLs. It checks Git tracking and adds an ignore rule before export. Profile edits contain Keychain references only and are syntax-checked with zsh without executing the profile. CLI errors never include file contents or secret values.
