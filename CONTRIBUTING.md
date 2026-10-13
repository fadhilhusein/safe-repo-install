# Contributing

Thanks for helping make installs safer.

## Ground rules

- The audit must stay **read-only**: `ls`, `find`, `grep`, `cat`, `head`, `od`, `readlink`.
  Never add a line that runs git, a package manager, or any file from the audited repo.
- Fixtures are **inert text**. No real payloads, real domains, or working exploits.
  Use `example.invalid` for URLs.
- Keep `SKILL.md` instructions and `README` tables in sync with the script.

## Add a detection pattern

1. Add a `scan` (or `emit`) line to the right section of `scripts/audit_repo.sh`.
   Use `BLOCK` only for things that execute without user action.
2. Add a folder under `tests/fixtures/<case>/` with the smallest inert sample.
   If it needs a `.git` folder, create it at runtime in a `setup_<case>` function
   inside `tests/run-tests.sh` (a nested `.git` cannot be committed).
3. Add a `check` line in `tests/run-tests.sh` with the expected exit code
   (`1` WARN, `2` BLOCK) and the label the output must contain.
4. Run:

   ```bash
   bash tests/run-tests.sh
   shellcheck scripts/audit_repo.sh install.sh tests/run-tests.sh
   ```

5. Add a line to `CHANGELOG.md` under *Unreleased*.

## Reduce a false positive

Open a *False positive* issue with the file path and the matching line. Prefer
narrowing the regex or using `code` mode (skips `*.md`, `*.txt`, `*.rst`) over
deleting a check.

## Pull requests

- One topic per PR.
- CI must be green (shellcheck + fixture tests).
- Explain the real-world attack the change covers, with a link if one exists.
