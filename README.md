all
===

[![CI](https://github.com/chrissyf/all/actions/workflows/ci.yml/badge.svg)](https://github.com/chrissyf/all/actions/workflows/ci.yml)

Each language lives in its own subspace with its own toolchain configuration.
Open the repository root in VS Code; `.vscode/settings.json` wires the language
subspaces up.

| Subspace  | Stack                        | Checks                                            |
| --------- | ---------------------------- | ------------------------------------------------- |
| `rust/`   | Cargo workspace, edition 2024 | `cargo fmt`, `cargo clippy`, `cargo test`         |
| `python/` | PEP 621, `src/` layout        | `ruff check`, `ruff format`, `mypy`, `pytest`     |
| `csharp/` | WPF app + xUnit tests         | `dotnet build`, `dotnet test` (Windows only)      |
| `robot/`  | Robot Framework, Browser + Requests | `robocop check`, `robocop format`, `robot tests` |
| `infra/`  | CloudFormation                | `cfn-lint`                                        |

CI runs every subspace on each pull request; the C# job runs on a Windows runner
because WPF cannot be built elsewhere. The Robot suites ship with a bundled
fixture server, so they pass without a deployed application - see
[`robot/README.md`](robot/README.md). Nothing in CI deploys the `infra/`
templates, so linting is all that guards them - see
[`infra/README.md`](infra/README.md).
