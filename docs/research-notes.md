# Design patterns from current adjacent projects

Observed on 2026-08-22. Recommendations used sources freshly served or changed
since 2026-05-22. These are independently implemented design patterns; no
project code was copied.

| Pattern | Recent evidence | AI Environment Optimizer decision |
|---|---|---|
| Structured findings and JSON | [Homebrew Finding objects, 2026-07-24](https://github.com/Homebrew/brew/commit/a05f49aa85a885a9c524616085a5ee1abdd87803) | One stable finding model renders human and JSON output. |
| Text/JSON parity | [mise doctor fix and test, 2026-08-22](https://github.com/jdx/mise/commit/6f52dcdf99e282ef7a7db68c81301fa4618d0f79) | Regression tests ensure warnings appear in both formats. |
| Manifest ownership | [ECC lifecycle fix, 2026-08-13](https://github.com/affaan-m/ECC/commit/01335551a3ebd16af6f8d69aacc26fb122faedea) | Never replace or remove an unowned path. |
| Explicit repair boundary | [agent-browser doctor modules, current head 2026-08-22](https://github.com/vercel-labs/agent-browser/tree/f9a6cc34212340dad62b114559f7a306c4be0707/cli/src/doctor) | Doctor remains read-only; repairs require a separate contract. |
| Required and optional health | [Claude-Mem doctor, current head 2026-08-22](https://github.com/thedotmack/claude-mem/blob/e2d1df569a8f04075d40e92461128ece7cf04c82/src/npx-cli/commands/doctor.ts) | Missing companions warn; product corruption fails. |
| Scoped uninstall | [Graphify regression, 2026-07-27](https://github.com/Graphify-Labs/graphify/commit/bdb678858b61183c3cf820fd6f82eec9748b7134) | Isolated round trips prove global and unrelated state is untouched. |
| Visible background failure | [gstack crash sentinel, 2026-08-15](https://github.com/garrytan/gstack/commit/008dd65b1fc3df8af618408f5aea37a24dcea411) | Silence cannot mean success; every scheduled run has a receipt. |
| Validate before replace | [cc-switch backup source, current head 2026-08-22](https://github.com/farion1231/cc-switch/blob/5ca9459d50ea4beea6a81bbc509de6ec5b6b09ca/src-tauri/src/database/backup.rs) | Stage and validate before changing last known-good state. |
| One recommended install path | [Matt Pocock skills, current head 2026-08-22](https://github.com/mattpocock/skills/blob/5b15a47f2d7150f545fbcacbfe381787fc0230dc/README.md) | Homebrew is primary; direct install is a clearly labeled fallback. |
| Native service lifecycle | [Homebrew service DSL public API, 2026-07-26](https://github.com/Homebrew/brew/commit/29cb5e338a49290d813aa063312b7b79c5d10732) and [Formula Cookbook](https://docs.brew.sh/Formula-Cookbook#service-files) | Homebrew installs use `brew services` with a stable `opt` command and an explicit 19:30 cron expression; no user crontab is created. |
| Precise linked-skill failures | [fx linked-skill diagnostic, 2026-08-22](https://github.com/vercel-labs/fx/commit/c6d210b1fe47808e1a3553b17a022bfb82831a89) | Broken linked skill directories warn separately from invalid frontmatter, without leaking paths. |

The resulting product boundary is intentional: AI Environment Optimizer is a macOS
observer and owner of its own maintenance state. It is not another package
manager, provider proxy, memory system, or autonomous workspace repair agent.
