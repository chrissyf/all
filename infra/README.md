infra
=====

Account level pieces that support development in this repository: the
CloudFormation below, and the developer machine setup scripts.

setup-aws-local.sh / setup-aws-local.ps1
----------------------------------------

Sets up the [Agent Toolkit for AWS](https://github.com/aws/agent-toolkit-for-aws)
on a developer machine: installs the AWS CLI v2, signs in with `aws login`,
installs the toolkit (the AWS skills plus the `aws-mcp` server), and writes the
AWS rules file into a project that does not already carry one.

```sh
infra/setup-aws-local.sh                 # macOS, Linux, or WSL
```

```powershell
.\infra\setup-aws-local.ps1              # Windows, from PowerShell
```

Both default to `eu-central-1` and take the region as an argument. Both are
idempotent: a valid session is not thrown away, and an existing `CLAUDE.md`
that differs from upstream is reported rather than overwritten.

### PowerShell or bash on Windows

Use PowerShell. The toolkit writes skills to `~/.claude/skills` and the MCP
server entry to `~/.claude.json`, and those have to land in the same home
directory the coding agent reads from. Installing under WSL while the agent
runs on Windows produces a clean install in a home directory the agent never
looks at.

`aws login` also opens a browser. From PowerShell that is the normal Windows
browser; from WSL it usually prints a localhost URL that resolves inside the
WSL network namespace and cannot complete.

Run the `.sh` script under WSL only when the agent itself runs under WSL.

### us-east-1 is not a mistake

Step 4 of both scripts passes `--region us-east-1` while everything else uses
your region. The Agent Toolkit control plane is only reachable there. Swapping
it for `eu-central-1` fails to resolve the endpoint.

### uv is a real dependency

The `aws-mcp` server is launched as `uvx mcp-proxy-for-aws@latest`. Without
[uv](https://docs.astral.sh/uv/) on PATH the server entry is written to
`~/.claude.json` but never starts, and the failure is quiet. Both scripts warn
when `uvx` is missing rather than failing, since the skills install regardless.

### Headless machines

`aws login` opens a browser and waits on a loopback callback. Over SSH, or in a
container, that callback is unreachable from the browser you would use. Pass
`--remote` for the cross device flow, which prints a URL and reads back an
authorization code:

```sh
aws login --region eu-central-1 --remote
```

The code is bound to the PKCE verifier held by that specific process, so the
command has to stay running while you complete sign in. Backgrounding it and
returning later invalidates the code.

### Placeholder credentials in agent containers

Some agent environments inject `AWS_ACCESS_KEY_ID=proxy-injected` and a
matching secret. Environment credentials outrank the profile, so `aws login`
reports success while every subsequent call fails with `InvalidClientTokenId`.
Unset both; leave `AWS_CA_BUNDLE` alone, since the proxy needs it.

agent-session-role.yaml
-----------------------

Creates `agent-session-admin`, a role that agent sessions assume instead of
carrying a permanent IAM access key.

### Why

A long lived access key (`AKIA...`) placed in an agent environment never
expires, is readable by anything running in that container, and is not covered
by MFA even when the owning user has an MFA device registered. A role session
produces temporary credentials (`ASIA...`) that expire on their own.

The role keeps `AdministratorAccess` deliberately: the goal here is to remove
the *standing* credential, not to narrow what a session can do. Narrowing comes
later, once there is a record of which API calls sessions actually make.

### Deploy

```sh
aws cloudformation deploy \
  --template-file infra/agent-session-role.yaml \
  --stack-name agent-session-role \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1
```

`CAPABILITY_NAMED_IAM` is required because the role is created with an explicit
name.

**Always pass `--region eu-central-1`.** IAM is a global service but
CloudFormation stacks are regional, and this stack is the one that owns the
role. Deploying without the flag targets whatever the caller's default region
is; if that is not `eu-central-1` CloudFormation sees no stack there, tries to
create the role a second time, and fails with

```
Resource of type 'AWS::IAM::Role' with identifier 'agent-session-admin'
already exists. (HandlerErrorCode: AlreadyExists)
```

That failure is harmless, since the pre existing role is never adopted and so
is never deleted by the rollback, but the failed stack lands in
`ROLLBACK_COMPLETE` and must be deleted before the region can be retried.

### Use

```sh
aws sts assume-role \
  --role-arn "$(aws cloudformation describe-stacks \
      --stack-name agent-session-role \
      --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
      --output text)" \
  --role-session-name agent \
  --duration-seconds 3600
```

Export the returned `AccessKeyId`, `SecretAccessKey`, and `SessionToken`. A
session credential is recognisable by its `ASIA` prefix, against `AKIA` for a
permanent key.

Equivalently, as a profile in `~/.aws/config`, which refreshes the session
automatically as it expires:

```ini
[profile agent]
role_arn = arn:aws:iam::<account-id>:role/agent-session-admin
source_profile = default
duration_seconds = 3600
```

Taking the user off AdministratorAccess
--------------------------------------

Creating the role does not by itself remove standing administrative access. As
long as `christianAdmin` has `AdministratorAccess` attached directly, its access
key is an admin credential in its own right and the role is only an alternative
path to the same power.

The template ships `agent-session-assume-only` as the intended replacement: it
grants `sts:AssumeRole` on the agent session role, plus management of the
caller's own sign in credentials, and nothing else.

**The detach is the one step that actually removes privilege, and it is
deliberately manual.** Run the sequence below in order. Steps 1 and 2 are
additive and reversible; do not run step 3 until step 2 has succeeded.

### 1. Attach the replacement policy

```sh
aws cloudformation deploy \
  --template-file infra/agent-session-role.yaml \
  --stack-name agent-session-role \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1
```

This is safe to run while `AdministratorAccess` is still attached. IAM takes the
union of allows, so the user gains the assume grant and loses nothing.

Pass `--region eu-central-1`, for the reason given above. Deploying into any other
region fails on the role name rather than updating this stack.

### 2. Verify role assumption works

```sh
aws sts assume-role \
  --role-arn "arn:aws:iam::<account-id>:role/agent-session-admin" \
  --role-session-name preflight \
  --query 'Credentials.[AccessKeyId,Expiration]'
```

The returned key must begin with `ASIA`. If this command fails, stop. Detaching
admin at this point would leave the user with no administrative path at all.

### 3. Detach AdministratorAccess

```sh
aws iam detach-user-policy \
  --user-name christianAdmin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 4. Confirm the new shape

```sh
aws iam list-attached-user-policies --user-name christianAdmin
```

`agent-session-assume-only` should be the only entry. A direct call such as
`aws s3 ls` should now fail with `AccessDenied`, while the same call made with
credentials from step 2 should succeed. That difference is the whole point of
the change.

### Rollback

```sh
aws iam attach-user-policy \
  --user-name christianAdmin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

If the user is somehow left with no working administrative path, the account
root user is the recovery route. Root is unaffected by any of this, because
these are IAM user permissions and root is not an IAM user.

### After the swap

Console work needs a role switch rather than a direct sign in. The stack output
`ConsoleSwitchRoleUrl` is the link. For the CLI, the `[profile agent]` block
above refreshes sessions automatically.

What still is not closed
------------------------

Nothing prevents a new access key being minted on the user, since
`agent-session-assume-only` permits self service key management by design. A
permissions boundary or an SCP is the durable control there, and neither is in
this template.

The stronger end state is IAM Identity Center, where no permanent key exists at
all and sessions are established through a browser login. This template is the
step that does not require that migration first.
