# CLAUDE.md — Project Instructions for Claude Code

## Git Workflow

Commit and push all changes **directly to `main`**. Do not create feature branches or pull requests unless explicitly asked by the user.

## Branch

Always work on `main`. The active development branch is `main`.

## Commit Style

- Use conventional commit prefixes: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`
- Keep commit messages concise and descriptive

## Code Style

- Swift 5.10, iOS 17.0+, SwiftUI + `@Observable` view models
- All view models are `@MainActor`
- No third-party package dependencies (SPM/CocoaPods/Carthage)
- All user-facing strings use `String(localized:)` with keys in `Resources/Localizable.strings`
