# Git config fixture

run-tests.sh writes a `.git/config` with a `core.fsmonitor` command at runtime.
The audit must report a BLOCK because git would run that command.
