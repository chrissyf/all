all
===

[![CI](https://github.com/chrissyf/all/actions/workflows/ci.yml/badge.svg)](https://github.com/chrissyf/all/actions/workflows/ci.yml)

Each language lives in its own subspace with its own toolchain configuration.
Open the repository root in VS Code; `.vscode/settings.json` wires all three up.

| Subspace  | Stack                        | Checks                                            |
| --------- | ---------------------------- | ------------------------------------------------- |
| `rust/`   | Cargo workspace, edition 2024 | `cargo fmt`, `cargo clippy`, `cargo test`         |
| `python/` | PEP 621, `src/` layout        | `ruff check`, `ruff format`, `mypy`, `pytest`     |
| `csharp/` | WPF app + xUnit tests         | `dotnet build`, `dotnet test` (Windows only)      |

CI runs all three on every pull request; the C# job runs on a Windows runner
because WPF cannot be built elsewhere.
