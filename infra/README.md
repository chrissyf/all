infra
=====

Account level pieces that support development in this repository: the
CloudFormation below, and the developer machine setup scripts.

Region
------

`eu-central-1` is the primary Region for this account. The stacks here, the
resources they manage, and the default the setup scripts write into the shared
config are all `eu-central-1`.

Pass it explicitly on every `aws cloudformation` call. IAM is global and
Identity Center is reached per instance, but the stacks that own those
resources are regional, so deploying into the wrong Region creates a second
stack rather than updating the first. `agent-session-role.yaml` below spells
out what that failure looks like, because it is confusing when it happens.

Two things sit in `us-east-1` deliberately, and neither is a mistake to
correct:

- The Agent Toolkit control plane resolves nowhere else, so
  `aws configure agent-toolkit` and `aws agent-toolkit` always take
  `--region us-east-1`.
- The Identity Center instance was enabled there. Its Region is fixed for the
  life of the instance and can only be changed by deleting and recreating it,
  so anything addressing that instance, including the `identity-center` stack,
  uses `us-east-1` too. See `identity-center.yaml` below.

Nothing else here should name another Region.

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
step that does not require that migration first. `identity-center.yaml` below
is that migration.

identity-center.yaml
--------------------

Permission sets and account assignments for IAM Identity Center. Deploying it
is the last step of a longer procedure, most of which cannot be automated.

### What this template does not do

It does not enable Identity Center. AWS documents enabling an organization
instance as a console action, performed in the Organizations management
account while signed in as an administrative user or the root user, and no
CloudFormation resource type creates an instance. `AWS::SSO::PermissionSet`
and `AWS::SSO::Assignment` operate on an instance that already exists.

So the split is: enable by hand once, then keep every grant in git.

### 1. Enable Identity Center

Already done. An organization instance exists in `us-east-1`, enabled in
August 2026, using the default Identity Center directory. The account is the
management account of its organization.

The Region is the surprising part, since everything else here is
`eu-central-1`. It stays as it is on purpose. A Region is fixed for the life
of an instance, and switching means deleting the instance and recreating
users, groups, permission sets, applications and assignments, which also
changes the access portal URL. Replicating to an additional Region does not
help, because replication adds a Region without moving the primary one. Since
the instance grants access to the whole account regardless of where it runs,
the only thing gained by moving would be holding identity data in the EU, and
that did not justify a teardown here.

Read the instance ARN and identity store id from the Identity Center console
under Settings.

### 2. Create a group and a user

In the Identity Center directory, create a group, create your user, and put
the user in the group. The template assigns access to a group by default so
that adding or removing an administrator is a directory change rather than a
stack update.

Name the group for the access it receives, `administrators` rather than
`developers`. The permission set this stack creates is `AdministratorAccess`,
so everyone in the group named here is a full account administrator. A group
named after a job title stops being true the first time someone joins it who
should not hold admin, and nothing in the directory flags that drift.

A user can belong to several groups, so keeping a separate `developers` group
costs nothing now and is where a narrower permission set goes when there is
one. That narrowing is the same deferred work `agent-session-role.yaml`
describes: remove the standing credential first, reduce what a session can do
once there is a record of what it actually calls.

### 3. Collect the two identifiers

```sh
aws sso-admin list-instances --region us-east-1
aws identitystore list-groups \
  --identity-store-id <IdentityStoreId from the call above> \
  --region us-east-1
```

The first gives `InstanceArn` and `IdentityStoreId`, the second the group's
`GroupId`. That GroupId is the `PrincipalId` parameter, and it is a directory
id unrelated to any IAM user name.

It comes in one of two shapes. A store migrated off legacy AWS SSO issues a
bare GUID; a store created new prefixes the store id, as
`1234567890-<guid>`. This instance is the second kind. Pass whatever
`list-groups` prints, in full.

### 4. Deploy

```sh
aws cloudformation deploy \
  --template-file infra/identity-center.yaml \
  --stack-name identity-center \
  --region us-east-1 \
  --parameter-overrides \
      InstanceArn=arn:aws:sso:::instance/ssoins-0123456789abcdef \
      PrincipalId=00000000-0000-0000-0000-000000000000
```

Pass `--region us-east-1`, not the primary Region. The stack has to live in
the Region its Identity Center instance was enabled in, and this is the one
stack here where that is not `eu-central-1`.

### 5. Point the CLI at it

```sh
aws configure sso
```

It asks for the start URL, which the Identity Center console shows under
Settings as `https://d-xxxxxxxxxx.awsapps.com/start`, then for a Region, then
for the account and permission set. The permission set name is
`AdministratorAccess`, the `PermissionSetName` output of the stack.

It asks for a Region twice, and here the two answers differ. The SSO session
Region is where the instance lives, `us-east-1`. The profile's own default
Region is where you work, `eu-central-1`. Answering `eu-central-1` to the
first fails to find the instance, and answering `us-east-1` to the second
quietly points every later command at the wrong Region.

### 6. Point VS Code at it

The AWS Toolkit supports IAM Identity Center natively. Add the connection
through the Toolkit rather than through a profile, and the
`credential_process` shim described under "Visual Studio Code" above becomes
unnecessary. Delete the `vscode` profile once the SSO connection works, so
there is one credential path rather than two.

### What this closes, and what it does not

It removes the standing key as a *requirement*: administrative access now
comes from a browser login that expires. It does not delete anything on its
own. The IAM users and any keys they still hold remain until they are removed
by hand, and until then they are an alternative path to the same access. That
removal is deliberately not in this template, for the same reason the detach
in `agent-session-role.yaml` is manual: it is the step that actually takes
privilege away, and it should fail loudly rather than as a side effect of a
stack update.

Verify the new path works before removing the old one. The recovery route if
both are broken is the account root user, which none of this affects.
