# AGENTS.md

## Project Overview

`Codex Usage Menubar` is a small macOS menu bar app that shows Codex 5h and 7d availability, reset times, credits, and launch-at-login state.

## Working Principles

- Keep changes small, readable, and easy to review.
- Prefer the simplest implementation that solves the problem.
- Do not add abstractions unless they clearly reduce complexity.
- Match existing repo style and file layout.
- Use English for code comments, commit messages, and PR titles/descriptions.

## Versioning

- The app version lives in the root `VERSION` file.
- The version is shown in the popover and embedded into the app bundle at build time.
- Every new feature branch or PR must bump the version before merging.
- Use semantic versioning:
  - `patch` for bug fixes, documentation updates, build fixes, and small internal refactors
  - `minor` for new user-visible features that remain backward compatible
  - `major` for breaking changes or incompatible behavior
- If the right bump is unclear, ask before changing it.

## Build and Validation

- Use `./start.command` for local builds and launches.
- Use `BUILD_ONLY=1 ./start.command` when you only need a build and verification.
- After changing app logic, UI, signing, or release behavior, run the relevant build command before finishing.

## Release and Distribution

- Keep the DMG release path working.
- Preserve the `latest` release flow unless there is a clear reason to change it.
- If release packaging changes, verify the DMG still opens and contains the app bundle correctly.

## Repo Hygiene

- Keep generated build output out of git.
- Keep public-facing docs short, accurate, and consistent with the current app behavior.
- Update the README when installation, launch, or versioning behavior changes.
