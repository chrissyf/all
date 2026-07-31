infra
=====

CloudFormation for account level pieces that support development in this
repository.

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
  --capabilities CAPABILITY_NAMED_IAM
```

`CAPABILITY_NAMED_IAM` is required because the role is created with an explicit
name.

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
  --capabilities CAPABILITY_NAMED_IAM
```

This is safe to run while `AdministratorAccess` is still attached. IAM takes the
union of allows, so the user gains the assume grant and loses nothing.

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
