# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.0.0] - 2026-10-13

### Added
- `SKILL.md` workflow: validate source, quarantine clone, audit, review, report, decide, install.
- `scripts/audit_repo.sh` read-only static audit with AMAN / WASPADA / BLOKIR exit codes (0 / 1 / 2).
- `references/manual-checks.md` fallback commands when bash is unavailable.
- `install.sh` and `install.ps1` for Claude Code, Codex, and `~/.agents/skills`.
- Fixture tests and GitHub Actions CI (shellcheck + fixtures on Linux and Windows).
- English and Indonesian README.
