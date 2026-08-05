Identity Center migration: what it displaces
============================================

An assessment, not a plan of record. `infra/README.md` names IAM Identity Center
as "the stronger end state, where no permanent key exists at all" and positions
the agent session role as the step that does not require migrating first. An
Identity Center instance now exists in this account, so the migration is
available and the tradeoff is worth stating explicitly.

Scope is the single account `275956877229`, which is also the management account
of organisation `o-5yw9xjw0it`.

Current state
-------------

Instance `ssoins-7223d6dd9f48d37c`, identity store `d-90667864e1`, in
`us-east-1`. It holds one user, `cfruehling`, one permission set,
`AdministratorAccess` at `PT4H`, and an assignment of that set to this account.
The portal is `https://d-90667864e1.awsapps.com/start`, verified by an OIDC
device authorization rather than assumed from the identity store ID.

The instance was initially empty, holding only `cfq` and a group `hogpimple`
left over from an Amazon Q attempt. Both were removed once the permission set
proved out. Amazon Q's free tier signs in with a personal Builder ID and needs
no Identity Center at all, so nothing depended on them.

Both paths are live at once. Nothing has been cut over, and the IAM users below
still work exactly as before:

| User | Console | MFA | Permissions | Keys |
|------|---------|-----|-------------|------|
| `christian` | yes | yes | `IAMReadOnlyAccess` via `iamreadonly`, plus `iampolicys3full`, `IAMUserChangePassword`, `SignInLocalDevelopmentAccess` | none |
| `christian2` | no | no | none | none |
| `christianAdmin` | yes | yes | `agent-session-assume-only`, capped by `agent-session-boundary` | one, inactive |

`christian2` was stripped of its console login profile and removed from
`2ndGroup`, leaving an empty user object. It previously had console access with
no MFA device and `s3:*` through that group. The user itself remains only so the
change stays reversible.

`iampolicys3full` is `s3:*` on `*`, and still reaches `christian` directly.
`2ndGroup` still exists and still references the policy, but has no members.

What the migration displaces
----------------------------

| Component | Fate under Identity Center |
|-----------|---------------------------|
| `christian`, `christian2`, `christianAdmin` | Deleted. Replaced by identity store users. |
| Per user MFA devices (`authy`, `ip17admin`) | Deleted. MFA moves to the portal, enforced once. |
| `iamreadonly`, `2ndGroup` | Deleted. Grouping moves to the identity store. |
| `iampolicys3full` | Folded into a permission set. |
| `agent-session-admin` role | Deleted. Permission sets provision their own roles. |
| `agent-session-assume-only` | Deleted. No IAM user remains to grant assume rights to. |
| `agent-session-boundary` | Deleted. It exists to cap an IAM user that would no longer exist. |
| `SignInLocalDevelopmentAccess` | Deleted. It exists so IAM users can run `aws login`. |
| Access keys, present and future | Structurally impossible. This is the point. |
| `agent-session-role.yaml` and its stack | Obsolete. |
| `[profile agent]` | Rewritten as an `sso_session` profile. |

The role does not disappear so much as change owner. A permission set provisions
an IAM role named `AWSReservedSSO_<name>_<hash>` into each assigned account, so
there is still a role granting `AdministratorAccess` and still a session that
expires. What goes away is the standing user that assumes it, the trust policy
naming that user, the boundary capping it, and the key it could mint.

Three quarters of `infra/` is displaced by this. That is the honest cost: the
template, the assume only policy, the boundary, and most of the README document
a mechanism whose purpose is to make an IAM user safe to keep. Identity Center
removes the user.

What it does not displace
-------------------------

**The root user.** Root is not an IAM identity and is unaffected. It still needs
its own MFA, and it remains the final break glass path. Root MFA is currently
enabled and root holds no access keys, which is the correct shape.

**The break glass problem.** Today a boundary caps `christianAdmin` and the role
is the way back. Afterwards, if the Identity Center instance is misconfigured or
the region is unreachable, root is the only way back. The dependency does not
disappear, it concentrates.

**The headless container problem.** Identity Center sign in is browser based, as
`aws login` already is. An agent session in a container without a browser still
needs a human to complete a cross device flow. This migration does not fix that,
and should not be chosen for that reason. Non interactive access wants IAM Roles
Anywhere or OIDC federation, neither of which is in scope here.

**The Agent Toolkit setup.** Skills and the AWS MCP server read whatever
credentials resolve, so they are indifferent. Only the login command changes,
from `aws login` to `aws sso login`, and the two should not be mixed.

New costs
---------

Identity Center is regional, and this instance lives in `us-east-1` while the
account default region is `eu-central-1`. That is less of an outlier than it
first appears: `us-east-1` also holds the Agent Toolkit service, which is pinned
there and cannot be moved, three S3 buckets, and two `AWS-QuickSetup-SSM-*`
stacks. Only the `agent-session-role` and `cloudtrail-audit` stacks and one
bucket are in `eu-central-1`.

Relocating the instance to `eu-central-1` is possible but not from the CLI. The
`CreateInstance` API refuses to run in an Organizations management account, which
this is, and rejects the call with `Organization management account is not
allowed to perform the operation`. Organization instances can only be enabled
from the console, so a move means deleting the instance and re-enabling it there,
with a window in between where the account has no instance at all. Deleting the
organization to lift that restriction would be a bad trade: an instance in a
standalone account cannot grant sign in to AWS accounts, only to applications.

Session duration is set per permission set, one hour by default and twelve at
most; this one is `PT4H`. The agent session role is fixed at one hour by
`MaxSessionSeconds`, so the permission set is the longer lived of the two.

Sequencing
----------

The same discipline `infra/README.md` applies to the AdministratorAccess detach
holds here: additive first, destructive last, and never remove the old path
before the new one is proven.

1. Create permission sets and assign them to the account. Nothing is displaced
   yet; both paths work.
2. Configure `aws configure sso` and verify sign in end to end, including a
   privileged call.
3. Only then delete the IAM users, groups, policies, boundary and stack, in the
   order the retirement runbook uses, since IAM refuses to delete a user with
   dependents.

Steps 1 and 2 are reversible. Step 3 is not, and should wait until the portal has
been used for real work rather than a smoke test.

Decisions needed first
----------------------

`cfruehling` has no password yet. The Identity Store API exposes no password
operations, so the first sign in has to be set up from the console, under Users,
Reset password. Until that is done the portal path is untested and the IAM users
must stay.

Whether one permission set or two. The IAM arrangement separates a near powerless
default from an elevated role that expires. A single `AdministratorAccess` set
collapses that: every portal session is an administrator session. A second,
narrower set restores the distinction, and is cheap to add.

Whether `s3:*` on `*` is still the intent for whoever inherits `iampolicys3full`,
or an artifact worth narrowing while it is being rewritten anyway.

Retirement order, once the portal is proven, is `christian2` first since it is
already inert, then `christian`, then `christianAdmin` last because it is the one
currently holding the fort. Retiring any of them before a successful portal sign
in would leave root as the only way in.
