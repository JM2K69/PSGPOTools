# Délégation : ce que le compte gère

La console montre à chaque technicien ce qu'il gère, d'après les **délégations du domaine** et le
ticket Kerberos qu'il utilise : un contrôle d'accès par rôle bâti sur les droits qui existent déjà,
sans rien à configurer dans la console.

## Comment les droits sont lus

L'annuaire les calcule pour le compte connecté :

| Droit | Lu dans | Donne |
|---|---|---|
| Lier des GPO à un domaine ou une OU | `allowedAttributesEffective` du domaine / de l'OU contient `gPLink` | l'OU est montrée avec ses liens ; créer et lier, lier, supprimer un lien |
| Modifier une GPO | `allowedAttributesEffective` de son conteneur contient `versionNumber` | Edit, Apply, restaurer, supprimer |
| Créer des GPO | `allowedChildClassesEffective` de `CN=Policies` contient `groupPolicyContainer` | New GPO |

Le compte est celui que l'annuaire répond à « Who am I? » (RFC 4532) : la console le montre dans
son titre, les détails du domaine et la barre d'état.

## Ce que voit un technicien

![La console du technicien Tier 1](../assets/screenshots/14-tier1-view.png)

- les OU où il lie des GPO, et **leurs parents grisés** comme chemin d'accès, sans leurs liens ;
- les GPO qu'il modifie, ou qui sont liées à ses OU ;
- seulement les actions qu'il peut faire, dans le menu contextuel.

Les détails du domaine disent si la délégation est **complète** (le compte gère toutes les OU et
GPO) ou **limitée**.

```bash
# La même console, avec le technicien Tier 1
kinit tiers1@HARDENBOX.LABO
pwsh -c 'Show-GPOManagerAvalonia -Server dc.hardenbox.labo'
```

!!! note "Plusieurs tickets"
    `kinit` remplace le ticket du cache par défaut. Pour garder celui du Tier 0 dans un autre
    terminal, donnez à chaque terminal son propre cache : `export KRB5CCNAME=FILE:/tmp/krb5cc_tier1`
    avant `kinit`.

## Les droits sont ceux du domaine

La console ne décide jamais seule : une modification que le compte n'a pas le droit de faire est
refusée par le contrôleur de domaine, et la console le dit. Les menus évitent seulement à un
technicien les actions qui lui seraient refusées. Le [workflow d'approbation](../workflows/approval.md)
repose sur le même principe.
