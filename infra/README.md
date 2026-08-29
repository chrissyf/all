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

### winget can be installed and still missing

The Windows script warns when `winget` is not callable. Nothing it installs
comes from winget, the AWS CLI is fetched straight from `awscli.amazonaws.com`,
so this reports on the machine rather than on a missing dependency and the
script carries on either way.

It earns a line of output because the usual cause is not a missing install.
`winget` ships inside the App Installer package and is reached through an app
execution alias, and that alias is per user and survives reinstalls. Switched
off, the package is still listed, every reinstall reports success, and the
command stays gone. Turn it back on under Settings > Apps > Advanced app
settings > App execution aliases, or re-register the package:

```powershell
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
```

When the package really is absent, install App Installer from the Microsoft
Store or from <https://aka.ms/getwinget>. Windows Server 2019 has neither and
does not support winget at all.

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

Visual Studio Code
------------------

Two extensions are worth having alongside the setup script: Claude Code, and
the AWS Toolkit.

### Install in this order

1. **Claude Code.** Extensions view, search `Claude Code`, install. Running
   `claude` in the integrated terminal also offers to install it.
2. **`setup-aws-local.ps1`.** Not before step 1.
3. **AWS Toolkit.** Extensions view, search `AWS Toolkit`, install, restart.

Step 2 must follow step 1. The toolkit installer detects which agents are
already present on the machine and writes into each one it finds; run it first
and it reports every agent as not found, installs no skills anywhere useful,
and configures no MCP server. The output names the agents it wrote to, which is
the thing to read rather than the exit code.

Agent configuration is user level rather than per project, at
`~/.claude/skills` and `~/.claude.json` (`%USERPROFILE%` on Windows), and is
shared between the CLI and the editor extension. Running the setup script once
covers both.

### Pointing the Toolkit at the right credentials

Set the Toolkit's region to `eu-central-1` after connecting. It does not
inherit the CLI default.

**The Toolkit cannot use an `aws login` profile.** Every profile reports
session expired and no authentication is attempted. The status bar is
misleading here: the Toolkit lists profile *names* out of the shared config,
so `default` appears there and looks connected, while `login_session` is not
among the credential types it actually resolves. Its documented methods are
IAM Identity Center, IAM credentials, AWS Builder ID, and an external
credential process.

The external credential process is the way through, and the AWS CLI can serve
as its own provider. Write the path to `aws` in full:

```ini
[profile vscode]
credential_process = "C:\Program Files\Amazon\AWSCLIV2\aws.exe" configure export-credentials --profile default --format process
region = eu-central-1
```

Select `vscode` in the Toolkit. `export-credentials` reads the login session
and emits the `credential_process` contract, short term `ASIA` credentials
carrying a session token and an expiry, which the Toolkit does understand. It
is re-run whenever credentials are needed, so a session renewed with
`aws login` is picked up without touching this profile again.

**The absolute path is required, not a fallback.** Written as bare `aws` the
profile works perfectly from a terminal and fails inside the Toolkit, which
reports the same "Unable to authenticate connection" as a profile with no
credentials at all. The extension host spawns the process without a shell and
does not inherit the PATH your terminal has. Because `aws sts
get-caller-identity --profile vscode` passes either way, that check cannot
tell the two apart, and the identical symptom makes this look like the
Toolkit rejecting `credential_process` outright when it is only failing to
launch the command. Confirm the path with `(Get-Command aws).Source` and quote
it, since it contains a space.

Two smaller traps. The profile must not be named `default`, because a profile
whose `credential_process` exports that same profile recurses. And VS Code
must be fully quit and reopened after editing the config: the connection list
survives a window reload, so a corrected profile can still show as expired.

For reference, `aws login` caches short term credentials under
`~/.aws/login/cache` (`%USERPROFILE%\.aws\login\cache` on Windows) and marks
the profile with `login_session`. The credentials last 15 minutes and refresh
automatically for up to 12 hours.

IAM Identity Center remains the better end state, and the Toolkit supports it
natively with no shim at all — see "What still is not closed" below. An IAM
access key would also work and should still be the last resort, since a
standing `AKIA` credential is what `agent-session-role.yaml` exists to remove.

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
long as the trusted user has `AdministratorAccess` attached directly, its access
key is an admin credential in its own right and the role is only an alternative
path to the same power.

The trusted user is `christian`, the identity signed in to day to day.
`christianAdmin` was the original one and is on its way out; "Moving the entry
point between users" below covers that handover.

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
  --user-name christian \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 4. Confirm the new shape

```sh
aws iam list-attached-user-policies --user-name christian
```

`agent-session-assume-only` should be the only entry. A direct call such as
`aws s3 ls` should now fail with `AccessDenied`, while the same call made with
credentials from step 2 should succeed. That difference is the whole point of
the change.

### Rollback

```sh
aws iam attach-user-policy \
  --user-name christian \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

If the user is somehow left with no working administrative path, the account
root user is the recovery route. Root is unaffected by any of this, because
these are IAM user permissions and root is not an IAM user.

### Moving the entry point between users

The role trusts `TrustedUserName`, and optionally a second user named by
`AdditionalTrustedUserName`. The second exists so the entry point can change
hands without a gap in which nobody can elevate. Trust both, verify the new
user, then drop the old one.

```sh
# 1. Trust both. The new user gains the assume grant, the old one keeps it.
aws cloudformation deploy \
  --template-file infra/agent-session-role.yaml \
  --stack-name agent-session-role \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1 \
  --parameter-overrides TrustedUserName=christian AdditionalTrustedUserName=christianAdmin

# 2. Verify, signed in as the new user.
aws sts assume-role \
  --role-arn "arn:aws:iam::<account-id>:role/agent-session-admin" \
  --role-session-name preflight --query 'AssumedRoleUser.Arn'

# 3. Drop the old one.
aws cloudformation deploy \
  --template-file infra/agent-session-role.yaml \
  --stack-name agent-session-role \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1 \
  --parameter-overrides TrustedUserName=christian AdditionalTrustedUserName=""
```

Step 3 is what actually retires the old user: it removes that user from the
trust policy and from `agent-session-assume-only`. If that user also carries
the boundary, those two were the whole of its access, so it is left inert.
Revoking its keys and console password is a separate step, and deleting the
user should wait until the new path has carried real work.

Do not run step 3 before step 2 passes. Between the two both users can elevate,
which is the point: there is no moment where nobody can.

### After the swap

Console work needs a role switch rather than a direct sign in. The stack output
`ConsoleSwitchRoleUrl` is the link. For the CLI, the `[profile agent]` block
above refreshes sessions automatically.

### If the profile uses `aws login`

The CLI's browser based sign in needs `signin:AuthorizeOAuth2Access` and
`signin:CreateOAuth2Token`. `AdministratorAccess` covered those implicitly, so
detaching it breaks credential refresh for a profile configured that way, with

```
Unable to create or refresh login credentials due to insufficient permissions.
You may be missing permission for the 'signin:CreateOAuth2Token' action.
```

Both policies here grant those actions, so the path keeps working. The failure
mode is worth knowing anyway, because it is delayed: existing credentials keep
working until they expire, and only the refresh fails. A profile that looks
healthy immediately after the detach can stop working hours later.

This is the general hazard of the boundary, in concrete form. Anything the user
relied on that was covered only by `AdministratorAccess` has to be named
explicitly in **both** documents, since the boundary caps whatever the identity
policy grants. Granting it in one and not the other achieves nothing.

Changing which user holds the entry point
-----------------------------------------

The identity signed in to day to day should be the low privilege one, elevating
through the role when it needs to. A user named for administration holding the
entry point invites the opposite habit.

`TrustedUserName` is that identity; `AdditionalTrustedUserName` exists so the
switch can happen without a gap. Trust both, confirm the new one works, then
empty the second parameter.

**Renaming the entry point does not by itself reduce anything.** Whatever the
new user already has, it keeps. If it holds `AdministratorAccess` directly, the
switch has to be paired with the same detach documented above, or the result is
a low privilege role sitting next to a user that never needed it. Check first:

```sh
aws iam list-attached-user-policies --user-name <new-user>
aws iam list-groups-for-user --user-name <new-user>
```

Group membership matters as much as attached policies, and is the easier of the
two to overlook.

Order:

1. deploy with both users named, so neither loses access
2. verify the new user can assume the role
3. detach `AdministratorAccess` from the new user if it has it, following the
   same sequence as above
4. redeploy with `AdditionalTrustedUserName=""` to drop the old user
5. retire the old user's access key once nothing depends on it

### A boundary on an interactive identity

Applying `agent-session-boundary` to a user that signs in to the console is a
larger step than applying it to a programmatic one, and is best left until last.

A boundary denies everything it does not name, and what an interactive session
needs is harder to enumerate than it looks. Detaching `AdministratorAccess` from
this account's user silently removed the sign in actions the CLI's browser login
depends on, and the failure did not appear until the cached credential expired
some time later. A boundary would have blocked the repair as well as the
original permission.

Attach the assume only policy first, work normally for a while, and read
CloudTrail for denied calls before adding the ceiling.

Making the reduction durable
----------------------------

Detaching `AdministratorAccess` removes today's standing privilege, but it does
not stop the policy being reattached, and a new access key minted on the user
inherits whatever is attached at the time. `agent-session-assume-only` permits
self service key management by design, so that path stays open.

`agent-session-boundary` is the ceiling. Effective permissions are the
intersection of a principal's attached policies and its boundary, and a boundary
grants nothing by itself, so with it in place reattaching `AdministratorAccess`
to the user would confer nothing beyond assuming the role and managing its own
credentials.

Apply it after the swap is complete and verified, to a user whose only job is
to elevate:

```sh
aws iam put-user-permissions-boundary \
  --user-name christian \
  --permissions-boundary arn:aws:iam::<account-id>:policy/agent-session-boundary \
  --region eu-central-1
```

Confirm:

```sh
aws iam get-user --user-name christian --query "User.PermissionsBoundary"
```

To remove it, `aws iam delete-user-permissions-boundary --user-name christian`.

**Check what else the user holds before attaching it.** A boundary caps
everything, not only administrative access. Applied to a user that also carries
day to day permissions, it leaves those policies attached and ineffective, and
the resulting `AccessDenied` points at the call rather than at the boundary.
`christian` currently holds S3 and Lambda policies for ordinary development, so
the boundary as written would take those away. Either leave that user unbounded
and let `agent-session-assume-only` carry the intent, or widen the boundary to
cover what the user is meant to keep.

On a user that holds only `agent-session-assume-only`, the boundary mirrors it
and applying it changes nothing about what works today. That is the intent: a
ceiling, not a further reduction.

**Keep the two documents in step.** A boundary narrower than the attached policy
silently breaks whatever falls outside it. If `agent-session-assume-only` gains
a permission, the boundary needs it too.

What a boundary on the user does not cover
------------------------------------------

The boundary constrains the user, not the role. `agent-session-admin` still has
`AdministratorAccess`, so anything holding a session from it can create a fresh
IAM user with `AdministratorAccess` and a permanent key, reproducing exactly the
arrangement this stack exists to remove.

Closing that requires constraining the role itself, either with a `Deny` on
`iam:CreateUser` and `iam:CreateRole` unless the request carries a permissions
boundary, or with a service control policy. An SCP is the stronger of the two
because it cannot be edited from inside the account it governs.

SCPs require AWS Organizations, and that prerequisite is met: this account is
the management account of an organization created with `FeatureSet: ALL`, and
`SERVICE_CONTROL_POLICY` is listed as an enabled policy type. Confirm with
`aws organizations describe-organization`.

Neither control is in this template. The `Deny` variant is a small addition;
the SCP route is now a matter of writing one rather than of restructuring the
account first.

IAM Identity Center
-------------------

The end state where no permanent key exists at all. Access is established
through a browser login (`aws sso login`), credentials are short lived by
construction, and there is no `AKIA` key anywhere to leak or rotate.

Identity Center offers two instance types, and the distinction decides what is
possible:

- an **account instance** can be created in a standalone account, but does not
  support AWS account access or permission sets, so it cannot replace the IAM
  user for this purpose
- an **organization instance** does support permission sets and account access,
  and requires AWS Organizations

The organization prerequisite is met, and an Identity Center instance has
existed in `us-east-1` since 2026-08-04, with its identity store alongside it.
Neither of those is visible to a principal without `sso:ListInstances`, so read
them from an elevated session:

```sh
aws sso-admin list-instances --region us-east-1
```

Enabling Identity Center from the console does not tell you which instance type
you got, and only an organization instance supports the permission sets this
would need. Confirm the type before depending on it, by listing permission sets
against the instance: an account instance rejects that call.

What remains is the permission sets and account assignments themselves. Until
those exist, the role plus boundary arrangement in this stack is what removes
the standing credential.
