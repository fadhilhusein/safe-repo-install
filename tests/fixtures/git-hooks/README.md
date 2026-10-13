# Git hooks fixture

run-tests.sh adds a `.git/hooks/post-checkout` file at runtime.
The audit must report a BLOCK for any hook that is not a `.sample` file.
