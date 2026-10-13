# Manual checks (fallback when audit_repo.sh cannot run)

Run these inside the quarantine clone. They are read-only. Do not run `git` commands there until check 3 is clean.

## Rule 1: no hook folders or strange folders

```bash
ls -la
find . -path ./.git -prune -o -type d -print
find . -path ./.git -prune -o -type d \( -name hooks -o -name .husky -o -name .githooks -o -name .devcontainer -o -name .vscode -o -name .claude -o -name .cursor -o -name node_modules \) -print
find . -mindepth 2 -name .git
```

Anything besides ordinary source and docs folders needs an explanation. A nested `.git` is a red flag.

## Rule 2: git hooks

```bash
ls -la .git/hooks
find .git/hooks \( -type f -o -type l \) ! -name '*.sample'
```

The second command must print nothing. A missing `.git/hooks` folder is fine (empty template clone). Any file without `.sample` can run automatically on git events.

## Rule 3: git config

```bash
cat .git/config
grep -inE '^[[:space:]]*(hookspath|fsmonitor|pager|sshcommand|editor|askpass|gitproxy|textconv|smudge|clean|process|helper|cmd|command|program)[[:space:]]*=' .git/config
grep -inE "=[[:space:]]*!|(^|[[:space:]=])(sh|bash|zsh|powershell)([[:space:]]|$)|curl|wget" .git/config
```

A normal clone config has only `[core]`, `[remote "origin"]`, and `[branch ...]`. Check that the remote URL matches what the user asked for.

## Rule 4: download and execute commands

```bash
grep -rInE '(curl|wget)[^|;#]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh' . --exclude-dir=.git
grep -rInE '(^|[^A-Za-z0-9_])(curl|wget)([^A-Za-z0-9_]|$)|Invoke-WebRequest|DownloadString|DownloadFile' . --exclude-dir=.git
grep -rInE 'eval[[:space:]]*\(|exec[[:space:]]*\(|os\.system|subprocess|child_process|base64[[:space:]]+(-d|--decode)|/dev/tcp/' . --exclude-dir=.git
```

## Extra checks

```bash
# install-time scripts
find . -path ./.git -prune -o -type f \( -name setup.py -o -name Makefile -o -name 'install*.sh' -o -name '*.ps1' -o -name '*.pth' \) -print
grep -rnE '"(preinstall|install|postinstall|prepare)"[[:space:]]*:' . --include=package.json --exclude-dir=.git

# Claude Code and editor config
ls -la .claude .mcp.json CLAUDE.md AGENTS.md .vscode/tasks.json 2>/dev/null
grep -rnE '"(hooks|statusLine|apiKeyHelper)"[[:space:]]*:|enableAllProjectMcpServers|bypassPermissions' . --include='*.json' --exclude-dir=.git

# submodules, filters, symlinks
cat .gitmodules .gitattributes 2>/dev/null
find . -path ./.git -prune -o -type l -exec ls -l {} \;

# prompt injection phrases
grep -rniE "ignore (all )?(previous|prior|above) instructions|do not (tell|inform) the user|without (telling|asking) the user|secretly" . --exclude-dir=.git
```

## Judging results

- Matches in documentation or tests are usually benign; matches in files the install executes, in hooks, in `.claude/settings.json`, or in anything obfuscated are not.
- A clean result means no known pattern matched. It is not a guarantee, so record the commit SHA in the report.
