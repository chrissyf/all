# robot/

Robot Framework end-to-end tests: browser UI via the Playwright-backed
[`Browser`](https://marketplace.visualstudio.com/items?itemName=MarketSquare.robotframework-browser)
library, HTTP APIs via
[`RequestsLibrary`](https://github.com/MarketSquare/robotframework-requests).

Robot's runtime is Python, so every custom keyword that needs real logic lives in
a `.py` file under `libraries/` and is imported into a `.resource` file.

## Layout

```
robot/
├── libraries/          Python keyword libraries
│   ├── DataFactory.py     test-data generation (module library)
│   └── FixtureServer.py   the bundled system under test (class library)
├── resources/          shared keywords and selectors
│   ├── common.resource    fixture lifecycle, ${BASE_URL} resolution
│   ├── web.resource       Browser setup, selectors, page keywords
│   └── api.resource       session handling, request keywords
├── tests/
│   ├── api/               HTTP suites  (__init__.robot owns the session)
│   └── web/               UI suites    (__init__.robot owns the browser)
├── results/            output.xml, log.html, report.html, screenshots
└── pyproject.toml      Robocop lint + format configuration
```

The split matters: **suites contain intent, resources contain mechanics.** A test
says `Sign In As    ${USERNAME}    ${PASSWORD}`; which selector that fills in is
`web.resource`'s problem. When the markup changes you edit one variable, not
every suite.

## Setup

```bash
cd robot
python -m venv .venv
. .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
rfbrowser init                # downloads the Playwright browsers, ~300 MB
```

`rfbrowser init` is separate because the Browser library drives a real
Playwright/Node runtime; `pip install` alone gets you the Python side only.

## Running

```bash
robot --outputdir results tests            # everything
robot --outputdir results tests/api        # one directory
robot --outputdir results tests/web/login.robot
robot --outputdir results --include smoke tests
robot --outputdir results --test "Wrong Password Is Rejected" tests
```

Open `results/log.html` afterwards. For a failing web test, the Browser library
has already attached a screenshot of the page at the moment it failed.

Useful overrides:

| Variable              | Default              | Purpose                                    |
| --------------------- | -------------------- | ------------------------------------------ |
| `TARGET_URL`          | *(empty)*            | Test a real deployment instead of the fixture |
| `API_TOKEN`           | *(from fixture)*     | Bearer token for the API suites             |
| `USERNAME` `PASSWORD` | `demo` / `s3cret`    | Login credentials                           |
| `BROWSER`             | `chromium`           | `chromium`, `firefox` or `webkit`           |
| `HEADLESS`            | `${True}`            | `--variable HEADLESS:${False}` to watch it run |
| `BROWSER_EXECUTABLE`  | *(empty)*            | Use a browser binary already on the machine |

```bash
robot --variable HEADLESS:${False} --outputdir results tests/web
robot --variable TARGET_URL:https://staging.example.com \
      --variable API_TOKEN:xxx --outputdir results tests/api
```

## The bundled fixture

`libraries/FixtureServer.py` serves a login form, a dashboard and a small JSON
user API from an ephemeral localhost port. It exists so `robot tests` passes on a
clean checkout with no network and no application to deploy, which makes the
scaffold verifiable on its own.

It is scaffolding, not something to build on. Point `TARGET_URL` at your
application, rewrite the selectors in `web.resource` and the endpoints in
`api.resource`, and delete `FixtureServer.py` along with the `Start Test
Fixtures` / `Stop Test Fixtures` calls in the two `__init__.robot` files.

## Lint and format

```bash
robocop check      # lint
robocop format     # rewrite in place
robocop format --check --diff
```

Robocop 6 absorbed Robotidy, so `robocop format` replaces the old `robotidy`
command. Configuration is in `pyproject.toml`; both run in CI.

## VS Code

Install the [RobotCode](https://marketplace.visualstudio.com/items?itemName=d-biehl.robotcode)
extension (`d-biehl.robotcode`) - VS Code offers it from `.vscode/extensions.json`
when you open the repository root. It provides syntax highlighting, go-to-definition
across `.robot`/`.resource`/`.py`, keyword completion with documentation, inline
Robocop diagnostics, formatting on save, and a Test Explorer that runs and debugs
individual test cases with breakpoints.

The repository root `.vscode/settings.json` already points it at `robot/tests` and
`robot/results` and wires up the shared Robocop config. One thing is left to you,
because it differs per platform: tell RobotCode which interpreter to use.
RobotCode takes it from the Python extension, so either run
**Python: Select Interpreter** and pick `robot/.venv`, or uncomment the
`python.defaultInterpreterPath` line for your OS in `.vscode/settings.json`.

Do not reach for the `robotcode.python` setting. It is deprecated, and RobotCode
passes its value to `spawn()` without expanding `${workspaceFolder}`, so a path
written that way never starts and you get *"Invalid python version for workspace
folder"* instead. Only an absolute path works there, which is what
`python.defaultInterpreterPath` saves you from hardcoding.

This repository keeps a separate virtualenv per subspace - `robot/.venv` here,
whatever `python/` uses there. A single-folder window still has just one active
interpreter, so selecting `robot/.venv` at the repository root applies to `python/`
as well. To keep them genuinely independent, open `robot/robot.code-workspace`
(it carries this folder's RobotCode settings, interpreter included) or add the
subspaces as folders in a multi-root workspace, where the Python extension
resolves an interpreter per folder.
