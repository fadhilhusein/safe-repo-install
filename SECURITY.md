# Security policy

## What this project is

`safe-repo-install` is a **static, read-only pattern scanner** plus agent
instructions. It lowers the chance of installing something that runs code
behind your back. It does not prove a repo is safe.

## Reporting

Please report privately, not in a public issue, when you find:

- a **bypass**: a malicious repo that hides a hook, config command, or
  download-and-execute path and still gets an AMAN verdict;
- a way for the audit script itself to **execute** repo content;
- a flaw in `install.sh` or `install.ps1` (path traversal, overwriting files
  outside the skill folder).

Use GitHub's **Report a vulnerability** button on the *Security* tab
(private advisories). Include a minimal inert fixture that reproduces it.

Ordinary false positives and false negatives that are not a bypass of a
documented rule are fine as normal issues.

## In scope

- `scripts/audit_repo.sh`
- `install.sh`, `install.ps1`
- Instructions in `SKILL.md` that weaken the quarantine or approval flow

## Out of scope

- Malware in third-party repos you audited (report to the repo host)
- Findings that need you to ignore a WASPADA or BLOKIR verdict

## Known limits

- Pattern matching cannot see logic bugs, novel obfuscation, or code fetched
  at runtime after install.
- The scan covers the cloned commit only. Submodules are not fetched.
- A clean report is a snapshot of one commit SHA, not a guarantee for later commits.
