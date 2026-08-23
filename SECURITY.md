# Security policy

## Reporting a vulnerability

Please use GitHub private vulnerability reporting for this repository. Do not
open a public issue for a suspected credential leak, path-traversal bug,
unsafe uninstall, or command-injection issue.

Include the affected version, macOS version and architecture, reproduction, and
the smallest safe diagnostic output. Remove tokens, endpoints, usernames, and
workspace names.

## Support window

Security fixes target the current minor release. Release artifacts include
SHA-256 checksums and GitHub build provenance.

The direct-install runtime supports macOS's system Ruby 2.6 so it can start
without bootstrapping another language runtime. Ruby 2.6 is upstream end-of-life;
AI Environment Optimizer therefore uses only the operating-system Ruby standard library,
does not open a listening service, does not parse untrusted network responses in
normal doctor runs, and also tests under Homebrew's maintained Ruby. This
tradeoff will be revisited if macOS removes the system runtime.
