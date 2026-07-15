# ADR-0005 — Bearer token in Keychain only, never UserDefaults

- **Status:** Accepted
- **Date:** 2026-07-01
- **Related:** [ADR-0004 — Settings apply on OK](0004-settings-apply-on-ok.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
The client needs to hold one secret long-term: the bearer token used to
authenticate against the server's JSON API
([`docs/architecture.md`](https://github.com/m-31/little-sister/blob/main/docs/architecture.md) §5.2). Every
other setting (base URL, node path, poll interval) is fine sitting in plain
`UserDefaults`.

## Decision
The token is stored **only** in the macOS Keychain, behind a small
`TokenStoring` protocol (`loadToken() -> String?`, `save(token:)`,
`deleteToken()`), with `KeychainTokenStore` as the real implementation
(`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock` so the
background polling loop can read it while the screen is locked). It is never
written to `UserDefaults`, `Info.plist`, source, git, or logs — including the
Debug Log, whose settings-committed entry deliberately omits it.

## Rationale
- `UserDefaults` is an unencrypted plist on disk — fine for non-secret
  configuration, wrong for a credential.
- Keychain is the standard, OS-provided mechanism for exactly this, with no
  new dependency.
- `kSecAttrAccessibleAfterFirstUnlock` (rather than a stricter
  `WhenUnlocked` variant) is required because the polling loop runs
  continuously in the background, including while the screen is locked — a
  stricter accessibility class would silently break polling every time the
  Mac locks.

## Consequences
- A dedicated protocol (`TokenStoring`) exists purely so tests can inject an
  in-memory fake instead of touching the real Keychain (avoiding
  Keychain-access flakiness or OS prompts inside the unit test target) — the
  same injection pattern already used for `StatusAPIClient` and
  `NotificationSending`.
- Deleting/rotating the token means clearing the Settings token field and
  saving — there's no separate "revoke" UI, matching the server's current
  token model (a static named token from `.env`; self-service token rotation
  is a planned server capability, not built yet).

## Alternatives considered
- **`UserDefaults` with the value obscured somehow** (base64, a fixed XOR).
  Rejected outright — obscuring is not security, and this is exactly the
  kind of pattern the project's rules explicitly forbid.
- **App Sandbox + Keychain access group sharing** for a future multi-app
  scenario. Not needed today — App Sandbox is currently off for this app
  entirely (a separate, unrelated build setting), so this is deferred until
  there's an actual second app to share a token with.
