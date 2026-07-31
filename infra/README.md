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

Apply it after the swap is complete and verified:

```sh
aws iam put-user-permissions-boundary \
  --user-name christianAdmin \
  --permissions-boundary arn:aws:iam::<account-id>:policy/agent-session-boundary \
  --region eu-central-1
```

Confirm:

```sh
aws iam get-user --user-name christianAdmin --query "User.PermissionsBoundary"
```

To remove it, `aws iam delete-user-permissions-boundary --user-name
christianAdmin`. The boundary mirrors `agent-session-assume-only`, so applying
it changes nothing about what works today. That is the intent: it is a ceiling,
not a further reduction.

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
because it cannot be edited from inside the account it governs, but SCPs require
AWS Organizations, which this account is not part of.

Neither is in this template. The `Deny` variant is a small addition; the SCP
route depends on the Organizations decision described below.

IAM Identity Center
-------------------

The end state where no permanent key exists at all. Access is established
through a browser login (`aws sso login`), credentials are short lived by
construction, and there is no `AKIA` key anywhere to leak or rotate.

Reaching it from a standalone account is not a small change. Identity Center
offers two instance types, and the distinction decides the work:

- an **account instance** can be created in a standalone account, but does not
  support AWS account access or permission sets, so it cannot replace the IAM
  user for this purpose
- an **organization instance** does support permission sets and account access,
  and requires AWS Organizations

So adopting Identity Center here means first creating an organization with this
account as its management account. That is a structural change to the account,
awkward to reverse, and it brings its own surface. It also unlocks SCPs, which
is the durable control missing above, so the two open items resolve together or
not at all.

Worth doing when the account grows past one person or one workload. For a single
operator on a single account, the role plus boundary arrangement in this stack
already removes the standing credential, and the remaining gain is narrower than
the migration cost.
