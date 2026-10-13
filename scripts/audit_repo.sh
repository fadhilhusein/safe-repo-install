#!/usr/bin/env bash
# audit_repo.sh - static, read-only audit of a freshly cloned public repo.
#
# Usage: audit_repo.sh <path-to-cloned-repo>
# Exit code: 0 = no findings, 1 = WARN findings, 2 = BLOCK findings, 3 = usage error
#
# Safety: this script only reads files (ls, find, grep, cat, od, readlink).
# It never runs git inside the repo and never executes anything from the repo,
# because git can run fsmonitor/pager/hook commands defined in .git/config.

set -u
export LC_ALL=C

REPO="${1:-}"
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  echo "Usage: $0 <path-to-cloned-repo>" >&2
  exit 3
fi
cd "$REPO" || exit 3

BLOCK=0
WARN=0
MAXLINES=12

emit() { # level check detail
  case "$1" in
    BLOCK) BLOCK=$((BLOCK + 1)) ;;
    WARN) WARN=$((WARN + 1)) ;;
  esac
  printf '[%s] %s | %s\n' "$1" "$2" "$3"
}

section() { printf '\n== %s ==\n' "$1"; }

# Directories and files that add noise without adding signal.
EXCL=(--exclude-dir=.git --exclude=package-lock.json --exclude=yarn.lock
  --exclude=pnpm-lock.yaml --exclude=Cargo.lock --exclude=poetry.lock
  --exclude=Pipfile.lock --exclude=go.sum --exclude=composer.lock)
DOCS=(--exclude=*.md --exclude=*.txt --exclude=*.rst --exclude=*.adoc)

# scan LEVEL LABEL REGEX [all|code] [grep flags and --include globs]
# "code" mode skips prose files, where words like curl are usually just documentation.
scan() {
  local level="$1" label="$2" re="$3" mode="${4:-all}" out n
  local -a flags=(-E)
  [ $# -ge 5 ] && flags=("${@:5}")
  if [ "$mode" = code ]; then
    out=$(grep -rIn "${flags[@]}" "${EXCL[@]}" "${DOCS[@]}" -e "$re" . 2>/dev/null)
  else
    out=$(grep -rIn "${flags[@]}" "${EXCL[@]}" -e "$re" . 2>/dev/null)
  fi
  [ -z "$out" ] && return 0
  n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  emit "$level" "$label" "$n match(es)"
  printf '%s\n' "$out" | cut -c1-200 | head -n "$MAXLINES" | sed 's/^/    /'
  [ "$n" -gt "$MAXLINES" ] && echo "    ... $((n - MAXLINES)) more"
  return 0
}

WL='(^|[^A-Za-z0-9_])'
WR='([^A-Za-z0-9_]|$)'

echo "Audit target: $(pwd)"
FILECOUNT=$(find . -path ./.git -prune -o -type f -print | wc -l | tr -d ' ')
echo "Files (excluding .git): $FILECOUNT"

# ---------------------------------------------------------------- 1
section "1. Folder structure (hook folders and unusual folders)"
echo "Top level:"
ls -la .
echo
while IFS= read -r d; do
  base=$(basename "$d")
  case "$base" in
    .git) emit BLOCK structure "$d : nested .git folder (embedded repo, can carry its own hooks and config)" ;;
    .github) emit INFO structure "$d : GitHub-side workflows, they do not run on this computer" ;;
    hooks | .husky | .githooks) emit WARN structure "$d : hook folder, can run on git events" ;;
    .devcontainer | .vscode | .claude | .cursor | .gemini | .codex | .windsurf | .continue | .zed)
      emit WARN structure "$d : tool configuration folder, review contents (section 5)" ;;
    node_modules | vendor | bower_components)
      emit WARN structure "$d : committed dependencies cannot be audited and may hide modified code" ;;
    .*) emit WARN structure "$d : hidden folder" ;;
  esac
done < <(find . -path ./.git -prune -o -type d -name .git -print -prune -o -type d ! -name . -print)

# ---------------------------------------------------------------- 2
section "2. .git/hooks (anything without .sample can run by itself)"
if [ -f .git ]; then
  emit WARN git-hooks ".git is a file pointing elsewhere: $(head -c 200 .git)"
elif [ -d .git/hooks ]; then
  ls -la .git/hooks
  hookfound=0
  while IFS= read -r f; do
    emit BLOCK git-hooks "$f is not a .sample file"
    hookfound=1
  done < <(find .git/hooks \( -type f -o -type l \) ! -name '*.sample')
  [ "$hookfound" -eq 0 ] && echo "OK: only .sample files in .git/hooks"
elif [ -d .git ]; then
  echo "OK: .git/hooks does not exist (clone used an empty template)"
else
  emit INFO git-hooks "no .git folder (not a git clone), skipping rules 2 and 3"
fi

# ---------------------------------------------------------------- 3
section "3. .git/config (hooksPath, fsmonitor, pager, shell commands)"
if [ -f .git/config ]; then
  cat .git/config
  echo
  # Dangerous keys: each can make git run a command.
  while IFS= read -r line; do
    emit BLOCK git-config "$line"
  done < <(grep -inE '^[[:space:]]*(hookspath|fsmonitor|pager|sshcommand|editor|askpass|gitproxy|textconv|smudge|clean|process|helper|cmd|command|program|external|tool|trustexitcode)[[:space:]]*=' .git/config)
  # Values that look like shell: alias "!cmd", sh -c, curl, wget.
  while IFS= read -r line; do
    emit BLOCK git-config "shell-like value: $line"
  done < <(grep -inE "=[[:space:]]*!|(^|[[:space:]=])(sh|bash|zsh|cmd|powershell|pwsh)([[:space:]]|\$)|curl|wget" .git/config)
  # Unexpected sections: a plain clone only has core, remote and branch.
  while IFS= read -r sec; do
    name=$(printf '%s' "$sec" | sed -E 's/^\[([A-Za-z0-9.-]+).*/\1/' | tr '[:upper:]' '[:lower:]')
    case "$name" in
      core | remote | branch) ;;
      *) emit WARN git-config "unexpected section $sec" ;;
    esac
  done < <(grep -E '^\[' .git/config)
  echo "Remote URL(s):"
  grep -iE '^[[:space:]]*url[[:space:]]*=' .git/config | sed 's/^/    /'
else
  [ -d .git ] && emit WARN git-config ".git/config missing"
fi

# ---------------------------------------------------------------- 4
section "4. Download and execute commands in every file"
echo "-- 4a. Pipe-to-shell, encoded payloads, reverse shells, exfil endpoints (all files)"
scan BLOCK pipe-to-shell "(curl|wget|iwr|Invoke-WebRequest|Invoke-RestMethod|fetch)[^|;#]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh${WR}|(curl|wget)[^|;#]*\|[[:space:]]*(python3?|node|perl|ruby|iex)"
scan BLOCK powershell-download "iex[[:space:]]*[(\"' ].*(DownloadString|Invoke-WebRequest|iwr|WebClient)|(DownloadString|DownloadFile)[[:space:]]*\("
scan BLOCK encoded-payload "powershell[^#]*-(enc|encodedcommand)${WR}|base64[[:space:]]+(-d|--decode|-D)|certutil[^#]*-urlcache|bitsadmin[[:space:]]+/transfer|mshta[[:space:]]|rundll32[[:space:]]"
scan BLOCK reverse-shell "/dev/tcp/|nc[[:space:]]+(-[a-z]*e|.*-e[[:space:]])|ncat[[:space:]].*-e|socat[[:space:]].*exec|bash[[:space:]]+-i[[:space:]]*>&"
scan BLOCK exfil-endpoint "discord(app)?\.com/api/webhooks|api\.telegram\.org/bot|pastebin\.com|transfer\.sh|webhook\.site|requestbin|interact\.sh|oast\.(fun|live|pro|site)|ngrok\.(io|app|dev)|pipedream\.net"

echo "-- 4b. Download commands (code files only, prose files are summarized)"
scan WARN download-cmd "${WL}(curl|wget)${WR}|Invoke-WebRequest|Start-BitsTransfer|urllib\.request|requests\.(get|post)\(|http\.get\(|https\.get\(|XMLHttpRequest|axios\.(get|post)\(|fetch\(['\"]https?://" code
dl_docs=$(grep -rIlE "${WL}(curl|wget)${WR}" "${EXCL[@]}" --include='*.md' --include='*.txt' --include='*.rst' . 2>/dev/null | wc -l | tr -d ' ')
[ "$dl_docs" -gt 0 ] && emit INFO download-cmd "$dl_docs documentation file(s) mention curl/wget (read them: install steps live here)"

echo "-- 4c. Command execution and dynamic code (code files only)"
scan WARN exec-cmd "${WL}eval[[:space:]]*\(|${WL}exec[[:space:]]*\(|os\.system|subprocess\.|child_process|execSync|spawnSync|Runtime\.getRuntime|popen\(|new Function\(|pickle\.loads|marshal\.loads|__import__\(|importlib\.import_module|ShellExecute|Process\.Start|system\(" code

echo "-- 4d. Persistence, privilege and destructive commands"
scan WARN persistence "crontab|launchctl|LaunchAgents|LaunchDaemons|systemctl[[:space:]]+(--user[[:space:]]+)?enable|schtasks|HKEY_|reg[[:space:]]+add|authorized_keys|/etc/profile|\.bashrc|\.zshrc|\.bash_profile|\.zprofile|\.profile${WR}" code
scan WARN privilege-destructive "sudo[[:space:]]|chmod[[:space:]]+(-R[[:space:]]+)?(777|\+s)|chown[[:space:]]+root|rm[[:space:]]+-[a-z]*r[a-z]*f?[[:space:]]+(/|~|\\\$HOME|\\\$\{HOME\})|mkfs|dd[[:space:]]+if=|:\(\)\{" code

echo "-- 4e. Secrets and credential locations"
scan WARN secret-access "\.ssh/|id_rsa|id_ed25519|\.aws/credentials|\.npmrc|\.netrc|\.gnupg|\.kube/config|\.docker/config|Login Data|Cookies|keychain|wallet\.dat|ANTHROPIC_API_KEY|OPENAI_API_KEY|GITHUB_TOKEN|GH_TOKEN|AWS_SECRET_ACCESS_KEY|\.claude/(settings|\.credentials)|\.env${WR}" code

# ---------------------------------------------------------------- 5
section "5. Extra checks: install scripts, Claude Code config, submodules, filters"
echo "-- 5a. Files that execute at install or build time"
while IFS= read -r f; do
  emit WARN install-script "$f : may run during install/build, read it before running any install"
done < <(find . -path ./.git -prune -o -type f \( -name setup.py -o -name Makefile -o -name makefile -o -name GNUmakefile \
  -o -name 'install*.sh' -o -name 'setup*.sh' -o -name 'bootstrap*' -o -name '*.ps1' -o -name '*.bat' -o -name '*.cmd' \
  -o -name build.rs -o -name extconf.rb -o -name '*.gemspec' -o -name Dockerfile -o -name 'docker-compose*.y*ml' \
  -o -name conftest.py -o -name tox.ini -o -name justfile -o -name Taskfile.yml \) -print | head -n 40)
while IFS= read -r f; do
  emit BLOCK python-pth "$f : .pth files can execute code at every Python start"
done < <(find . -path ./.git -prune -o -type f -name '*.pth' -print)
scan WARN npm-lifecycle "\"(preinstall|install|postinstall|prepare|prepack|prepublish|prepublishOnly|postpack)\"[[:space:]]*:" all -E --include=package.json
scan WARN remote-dependency "\"[^\"]+\"[[:space:]]*:[[:space:]]*\"(git\+|git://|github:|https?://)|^[[:space:]]*(git\+|-e[[:space:]]+git|--(extra-)?index-url)|cmdclass|build-backend[[:space:]]*=[[:space:]]*\"[^\"]*\.[^\"]*\"" all -E --include=package.json --include=requirements*.txt --include=pyproject.toml --include=setup.cfg --include=setup.py

echo "-- 5b. Claude Code and editor configuration"
for f in CLAUDE.md AGENTS.md .cursorrules .mcp.json .claude/settings.json .claude/settings.local.json .vscode/tasks.json .devcontainer/devcontainer.json; do
  [ -e "$f" ] && emit WARN agent-config "$f present, read it fully"
done
if [ -d .claude ]; then
  find .claude -type f | head -n 40 | sed 's/^/    /'
fi
scan BLOCK claude-hooks "\"(hooks|statusLine|apiKeyHelper|awsAuthRefresh|awsCredentialExport|otelHeadersHelper)\"[[:space:]]*:|enableAllProjectMcpServers|bypassPermissions|dangerously-?skip|\"defaultMode\"[[:space:]]*:[[:space:]]*\"(acceptEdits|bypass)" all -E --include=settings*.json --include=*.json
scan BLOCK skill-frontmatter-hooks "^hooks:[[:space:]]*$|^allowed-tools:.*Bash\(\*\)|^allowed-tools:[[:space:]]*\*" all -E --include=SKILL.md --include=*.md
scan WARN vscode-autorun "runOn[\"[:space:]]*:[[:space:]]*\"folderOpen\"" all -E --include=tasks.json
scan WARN mcp-servers "\"(command|args|url)\"[[:space:]]*:" all -E --include=.mcp.json --include=mcp*.json

echo "-- 5c. Prompt injection phrases (text the AI would read and obey)"
scan WARN prompt-injection "ignore[[:space:]]+(all[[:space:]]+)?(the[[:space:]]+)?(previous|prior|above|earlier)[[:space:]]+(instructions|rules|messages)|disregard[[:space:]]+(the[[:space:]]+|all[[:space:]]+)?(previous|prior|above|system|safety)|(do[[:space:]]+not|don'?t|never)[[:space:]]+(tell|inform|mention|reveal|show|notify)[[:space:]]+(the[[:space:]]+)?user|without[[:space:]]+(telling|informing|asking|notifying)[[:space:]]+(the[[:space:]]+)?user|hidden[[:space:]]+from[[:space:]]+the[[:space:]]+user|silently[[:space:]]+(run|execute|install|download|send)|secretly|bypass[[:space:]]+(the[[:space:]]+)?(permission|approval|safety|security|audit|sandbox)|skip[[:space:]]+(the[[:space:]]+)?(audit|security|verification|confirmation|safety)|disable[[:space:]]+(the[[:space:]]+)?(security|sandbox|safety|audit)|you[[:space:]]+are[[:space:]]+now[[:space:]]+(in|a|an)[[:space:]]|new[[:space:]]+system[[:space:]]+prompt" all -Ei

echo "-- 5d. Submodules, filters, symlinks"
if [ -f .gitmodules ]; then
  emit WARN submodule ".gitmodules present: submodules pull code from other repos and were NOT fetched"
  grep -iE 'url[[:space:]]*=' .gitmodules | sed 's/^/    /'
fi
if [ -f .gitattributes ] || find . -path ./.git -prune -o -name .gitattributes -print | grep -q .; then
  scan WARN gitattributes-filter "(filter|diff|merge)=[A-Za-z0-9_-]+|textconv" all -E --include=.gitattributes
fi
while IFS= read -r l; do
  tgt=$(readlink "$l" 2>/dev/null)
  case "$tgt" in
    /* | ~* | *..*) emit BLOCK symlink "$l -> $tgt : points outside the repo" ;;
    *) emit INFO symlink "$l -> $tgt" ;;
  esac
done < <(find . -path ./.git -prune -o -type l -print | head -n 40)

# ---------------------------------------------------------------- 6
section "6. Binaries, obfuscation, hidden characters"
echo "-- 6a. Precompiled binaries (cannot be audited statically)"
if [ "$FILECOUNT" -le 20000 ]; then
  while IFS= read -r f; do
    magic=$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$magic" in
      7f454c46) emit WARN binary "$f : ELF executable/library" ;;
      4d5a*) emit WARN binary "$f : Windows PE executable/library" ;;
      cffaedfe | cefaedfe | feedface | feedfacf | cafebabe) emit WARN binary "$f : Mach-O or Java class binary" ;;
      504b0304) case "$f" in *.jar | *.apk | *.exe | *.msi) emit WARN binary "$f : zip-based executable package" ;; esac ;;
    esac
  done < <(find . -path ./.git -prune -o -type f -size -50000k -print)
  while IFS= read -r f; do
    emit WARN binary "$f : extension of a compiled or auto-run artifact"
  done < <(find . -path ./.git -prune -o -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.so' -o -name '*.dylib' \
    -o -name '*.node' -o -name '*.jar' -o -name '*.class' -o -name '*.pyc' -o -name '*.wasm' -o -name '*.msi' \
    -o -name '*.scr' -o -name '*.vbs' -o -name '*.jse' -o -name '*.wsf' -o -name '*.lnk' -o -name '*.app' -o -name '*.pkg' \) -print | head -n 30)
else
  emit INFO binary "repo has more than 20000 files, magic-byte scan skipped"
fi
echo "-- 6b. Executable-bit files (first 25)"
find . -path ./.git -prune -o -type f -perm -u+x -print | head -n 25 | sed 's/^/    /'

echo "-- 6c. Obfuscation signals"
scan WARN long-line ".{1500,}" code
scan WARN base64-blob "[A-Za-z0-9+/]{300,}={0,2}" code
scan WARN charcode-obfuscation "String\.fromCharCode|(\\\\x[0-9a-fA-F]{2}){10,}|chr\([0-9]+\)[[:space:]]*\+[[:space:]]*chr|atob\(|Buffer\.from\([^)]*base64" code
echo "-- 6d. Hidden Unicode (zero-width and bidi override characters)"
hidden=$(grep -rIlE $'\xe2\x80[\x8b-\x8f\xaa-\xae]|\xe2\x81[\xa0-\xa9]' "${EXCL[@]}" . 2>/dev/null | head -n 20)
if [ -n "$hidden" ]; then
  emit WARN hidden-unicode "invisible characters found in:"
  printf '%s\n' "$hidden" | sed 's/^/    /'
fi

# ---------------------------------------------------------------- summary
section "SUMMARY"
echo "BLOCK findings: $BLOCK"
echo "WARN findings : $WARN"
if [ "$BLOCK" -gt 0 ]; then
  echo "SUGGESTED VERDICT: BLOKIR (review every BLOCK item, recommend aborting)"
  exit 2
elif [ "$WARN" -gt 0 ]; then
  echo "SUGGESTED VERDICT: WASPADA (review every WARN item in context)"
  exit 1
else
  echo "SUGGESTED VERDICT: AMAN (no automatic findings, still read the install instructions)"
  exit 0
fi
