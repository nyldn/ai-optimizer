# Contributing

Thanks for helping make macOS AI coding environments easier to trust.

## Before opening a pull request

1. Open or reference an issue for behavior changes.
2. Preserve the safety invariants in `AGENTS.md`.
3. Add a failing regression test before changing behavior.
4. Run:

```sh
/usr/bin/ruby test/test_all.rb
scripts/check-syntax.sh
gitleaks git --redact --exit-code 1 .
```

For installer or scheduler changes, also run the applicable full round trip.
Do not include real credentials, MCP endpoints, private workspace names, or
machine-specific paths in fixtures.

## Pull requests

Keep changes focused. Explain the user-visible behavior, mutation boundary,
tests, and rollback. New integrations should remain optional and
feature-detected unless the project explicitly changes its support contract.
