# Delegation: what the account manages

The console shows each technician what it manages, from the **delegations of the domain** and
the Kerberos ticket it uses: role-based access built on the permissions that already exist, with
nothing to configure in the console.

## How the rights are read

The directory computes them for the account connected:

| Right | Read from | Gives |
|---|---|---|
| Link GPOs to a domain or an OU | `allowedAttributesEffective` of the domain / OU holds `gPLink` | the OU is shown with its links; create and link, link, delete a link |
| Edit a GPO | `allowedAttributesEffective` of its container holds `versionNumber` | Edit, Apply, restore, delete |
| Create GPOs | `allowedChildClassesEffective` of `CN=Policies` holds `groupPolicyContainer` | New GPO |

The account is the one the directory answers to "Who am I?" (RFC 4532): the console shows it in
its title, the details of the domain and the status bar.

## What a technician sees

![The console of the Tier 1 technician](../assets/screenshots/14-tier1-view.png)

- the OUs where it links GPOs, and **their parents greyed** as the path to them, without their links;
- the GPOs it edits, or that are linked to its OUs;
- only the actions it may take, in the context menu.

The details of the domain say whether the delegation is **full** (the account manages every OU and
GPO) or **limited**.

```bash
# The same console, as the Tier 1 technician
kinit tiers1@HARDENBOX.LABO
pwsh -c 'Show-GPOManagerAvalonia -Server dc.hardenbox.labo'
```

!!! note "Several tickets"
    `kinit` replaces the ticket of the default cache. To keep the Tier 0 one in another terminal,
    give each terminal its own cache: `export KRB5CCNAME=FILE:/tmp/krb5cc_tier1` before `kinit`.

## The rights are those of the domain

The console never decides alone: a change the account may not make is refused by the domain
controller, and the console says so. The menus only spare a technician the actions it would be
refused. The [approval workflow](../workflows/approval.md) builds on the same principle.
