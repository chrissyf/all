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

Identity Center is enabled but not usable. Instance
`ssoins-7223d6dd9f48d37c`, identity store `d-90667864e1`, in `us-east-1`. It
holds one user, `cfq`, and one group, `hogpimple`, and **zero permission sets**,
so nothing is assigned to any account and nobody can sign in through it yet.

Access today runs entirely on IAM users:

| User | Console | MFA | Permissions | Keys |
|------|---------|-----|-------------|------|
| `christian` | yes | yes | `IAMReadOnlyAccess` via `iamreadonly`, plus `iampolicys3full`, `IAMUserChangePassword`, `SignInLocalDevelopmentAccess` | none |
| `christian2` | yes | **no** | `iampolicys3full` via `2ndGroup` | none |
| `christianAdmin` | yes | yes | `agent-session-assume-only`, capped by `agent-session-boundary` | one, inactive |

`iampolicys3full` is `s3:*` on `*`. It reaches two of the three users by
different routes, directly on `christian` and through a group on `christian2`.

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

Identity Center is regional. This instance lives in `us-east-1` while the account
default region is `eu-central-1`, so sign in acquires a hard dependency on a
region nothing else here uses.

Deleting an Identity Center instance is disruptive and not a routine operation,
so enabling it in earnest is closer to a commitment than the current stack is.

Session duration is set per permission set, default one hour, maximum twelve. The
current role is fixed at one hour by `MaxSessionSeconds`, so this is equivalent
rather than better.

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

Whether `cfq` and `hogpimple` are intended identities or leftovers from enabling
the instance. Nothing can be assigned until that is settled.

Whether one permission set or two. The current setup separates a near powerless
default from an elevated role, and that separation is worth preserving rather
than collapsing into a single administrator set.

Whether `s3:*` on `*` is still the intent for whoever inherits `iampolicys3full`,
or an artifact worth narrowing while it is being rewritten anyway.

Unrelated to the migration, and worth handling regardless of the outcome:
`christian2` has console access with no MFA device and `s3:*` through its group,
and has been dormant since 2026-07-15. It is the weakest identity in the account
under either design.
