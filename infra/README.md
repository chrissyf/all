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

A permissions boundary, `agent-session-boundary`, is attached to
`christianAdmin`, and it changes how rollback works. Re attaching
`AdministratorAccess` no longer restores administrative access, because
effective permissions are the intersection of the identity policy and the
boundary, and the boundary does not allow those actions. The user cannot run
the command either: `iam:AttachUserPolicy` against its own user evaluates to
`implicitDeny`.

The lever is the role, not the user. The role holds `AdministratorAccess`, is
not subject to the user's boundary, and the boundary explicitly permits
assuming it, so this path stays reachable even when the user can do nothing
else:

```sh
aws iam delete-user-permissions-boundary \
  --user-name christianAdmin \
  --profile agent

aws iam attach-user-policy \
  --user-name christianAdmin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile agent
```

Removing the boundary is the step that matters. Without it the second command
is inert.

If the role is unusable as well, the account root user is the recovery route.
Root is unaffected by any of this, because these are IAM user permissions and
root is not an IAM user. Confirm root sign in actually works before relying on
it. A root password nobody has used in months is not a break glass path, and
past this point there is no other way back.

### After the swap

Console work needs a role switch rather than a direct sign in. The stack output
`ConsoleSwitchRoleUrl` is the link. For the CLI, the `[profile agent]` block
above refreshes sessions automatically.

Permissions boundary
--------------------

`christianAdmin` carries a permissions boundary, `agent-session-boundary`. A
boundary caps what a user can do regardless of which policies are attached:
effective permissions are the intersection of the two. Attaching
`AdministratorAccess` on top of it grants nothing the boundary does not already
allow, which is why the rollback above has to remove the boundary first.

Version `v2` allows four things and nothing else:

- `sts:AssumeRole`, on `agent-session-admin` only
- management of the caller's own sign in credentials, scoped to
  `${aws:username}`
- reading account context, `iam:GetAccountPasswordPolicy` and
  `iam:ListAccountAliases`
- `signin:AuthorizeOAuth2Access` and `signin:CreateOAuth2Token`

That last pair is load bearing. It is what lets `aws login` work for this user;
without it the browser sign in fails and the user has no way to obtain
credentials at all.

The scoping is easy to misread when testing. `sts:AssumeRole` simulated against
`*` comes back denied, because the boundary grants it only on the one role ARN.
Simulate against the role ARN itself to get a truthful answer.

**The boundary is not created by `agent-session-role.yaml`.** It was applied out
of band, so the account carries a control this stack neither manages nor would
recreate. Deleting and redeploying the stack leaves the boundary untouched, and
an account built from this template alone would not have one. Folding it into
the template is the obvious next change.

Retiring the christian user
---------------------------

`christian` is a second IAM user holding standing `s3:*` on `*` through
`iampolicys3full`, plus `IAMReadOnlyAccess` through membership of the
`iamreadonly` group. Note that the group is a second source of permission and
does not appear in `list-attached-user-policies`. It has a console password and
a virtual MFA device, and no access keys. None of this is reachable through the
agent session role, and none of it carries a permissions boundary.

Retiring it removes the last standing grant of real power in the account.
`christianAdmin` has its own console password and MFA device, so console access
survives the deletion.

**CloudFormation cannot do this.** The user, `iampolicys3full`, the
`iamreadonly` group and `agent-session-boundary` were all created out of band,
and a stack deletes only the resources it owns. Retirement is manual, in the
order below, because IAM refuses to delete a user that still has dependents
attached.

Run every command here with `--profile agent`. `christianAdmin` cannot perform
them directly: the boundary is an allow list, and IAM writes against another
user are not on it.

### 1. Confirm nothing depends on it

```sh
aws iam list-access-keys --user-name christian --profile agent
```

Expect an empty list. A key here means something may be authenticating as this
user, and that should be tracked down before continuing.

### 2. Remove the console path

```sh
SERIAL=$(aws iam list-mfa-devices --user-name christian \
  --query 'MFADevices[0].SerialNumber' --output text --profile agent)

aws iam delete-login-profile --user-name christian --profile agent
aws iam deactivate-mfa-device --user-name christian \
  --serial-number "$SERIAL" --profile agent
aws iam delete-virtual-mfa-device --serial-number "$SERIAL" --profile agent
```

### 3. Detach permissions

```sh
aws iam remove-user-from-group --user-name christian \
  --group-name iamreadonly --profile agent

for P in \
  arn:aws:iam::aws:policy/IAMUserChangePassword \
  arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess \
  arn:aws:iam::<account-id>:policy/iampolicys3full
do
  aws iam detach-user-policy --user-name christian \
    --policy-arn "$P" --profile agent
done
```

### 4. Delete the user

```sh
aws iam delete-user --user-name christian --profile agent
```

### 5. Confirm

```sh
aws iam get-user --user-name christian --profile agent
```

`NoSuchEntity` is the expected result.

`iampolicys3full` and the `iamreadonly` group outlive the user. The group has no
other members, so both can be deleted separately once nothing else references
them.

What still is not closed
------------------------

Nothing prevents a new access key being minted on the user, since
`agent-session-assume-only` permits self service key management by design, and
`agent-session-boundary` allows `iam:CreateAccessKey` on the caller's own user
for the same reason. Such a key is far less useful than it once was, because
the boundary caps it to assuming the role rather than acting directly, but it
is still a permanent credential.

This is not hypothetical. An access key was minted on `christianAdmin` on
2026-07-29. Because the boundary permits assuming the agent session role, such a
key pair reaches `AdministratorAccess` in a single hop, and `RequireMFA` defaults
to `false`, so nothing else stands in the way. It is weaker than the credential
this template was written to remove, since it can only assume the role rather
than act directly, but it is still permanent and still ends at administrator.

CloudTrail shows that key used in one session only, on the day it was created:
34 read only calls enumerating the account, and no `AssumeRole` at any point. Most
of those reads would be refused by the boundary in force today, which dates the
boundary to after that session. The key has been dormant since and is now
`Inactive`. Deactivating rather than deleting keeps the change reversible; delete
it once a stretch of silence confirms nothing depended on it.

The shape of that episode is worth noting on its own. A key was minted, used once
to survey the account, and abandoned. The key injected into the agent container
was a different one again, already deleted by the time it was found there. Keys
being created per environment and left behind is the pattern this role exists to
end, and deleting any single key does not end it.

An SCP is the durable control there, and it is not in this template. Neither is
the boundary, as noted above.

The stronger end state is IAM Identity Center, where no permanent key exists at
all and sessions are established through a browser login. This template is the
step that does not require that migration first.
