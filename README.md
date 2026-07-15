# Little Sister — client apps

Native client apps for the [little-sister](https://github.com/m-31/little-sister)
monitoring server. Each is a small, platform-native **status indicator**: it polls the
server's read-only JSON API and alerts when the watched status tree (or a subtree) changes
materially — it is **not** a copy of the web dashboard.

The apps depend on little-sister **one-way** — they consume its JSON API; the server knows
nothing about them. Each carries its own copy of the API contract, synced one-way from
little-sister's `docs/api/`.

## Apps

- **[`apple/`](apple/README.md)** — a macOS menu-bar app (Swift / Xcode).

More platforms may follow; each gets its own top-level directory with its own build, docs
and rulebook.

## Layout

One directory per platform, each **self-contained** (its own `README.md`, `docs/`, build
and tests) so it can be built and worked on alone.

## Contributing

Development happens on a private working branch; `main` carries releases only —
one squashed commit per version, on this repository's own version line
(independent of the little-sister library's). Bug reports and feature requests
go through
[GitHub issues](https://github.com/m-31/little-sister-app/issues). Pull
requests are welcome too: an accepted PR is absorbed into the working branch
and lands in the next release, credited with `Co-authored-by`.
