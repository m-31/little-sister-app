# Changelog

All notable changes to the Little Sister Apple client. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) and are independent
of the little-sister library's version line — when the JSON API contract
matters, an entry states the minimum library version required.

## [Unreleased]

## [0.2.0] - 2026-07-15

First release. A macOS menu-bar client for the
[little-sister](https://github.com/m-31/little-sister) status server:

- polls the read-only JSON status API (bearer token, kept in the macOS
  Keychain) and shows the overall status — or a chosen subtree — as a
  menu-bar icon;
- notifies on status transitions and repeats an **alarm** for unacknowledged
  errors: sound, blinking icon, modal dialog — each independently switchable,
  acknowledgment stops the sound only;
- Settings for base URL, subtree path, poll interval and alert behaviour,
  plus an in-app debug log.

Requires a little-sister server serving JSON API **contract 1.1.0** (envelope
`schema_version: 1`) — every little-sister release from its first (v0.2.0) on.
