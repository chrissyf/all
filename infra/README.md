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

### What this does not fix

Deploying this template does not by itself eliminate standing administrative
access. Two gaps remain, both requiring a decision that is out of scope for the
template:

1. `christianAdmin` still has `AdministratorAccess` attached directly, so its
   remaining access key is an admin credential in its own right and the role is
   merely an alternative path to the same power. Closing this means replacing
   that user's attached policy with a single `sts:AssumeRole` grant scoped to
   this role, so the key alone can do nothing but start a time boxed session.
2. Nothing prevents a future key from being minted on that user. An SCP or a
   permissions boundary is the durable control.

The stronger end state is IAM Identity Center, where no permanent key exists at
all and sessions are established through a browser login. This template is the
step that does not require that migration first.
