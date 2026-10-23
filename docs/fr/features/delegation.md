# Délégation : ce que le compte gère

Chaque compte voit tout le domaine, comme dans GPMC ; la console ne propose à chacun que ce qu'il
gère, d'après les **délégations du domaine** et le ticket Kerberos qu'il utilise : un contrôle
d'accès par rôle bâti sur les droits qui existent déjà, sans rien à configurer dans la console.

## Comment les droits sont lus

L'annuaire les calcule pour le compte connecté :

| Droit | Lu dans | Donne |
|---|---|---|
| Lier des GPO à un domaine ou une OU | `allowedAttributesEffective` du domaine / de l'OU contient `gPLink` | l'OU n'est pas grisée ; créer et lier, lier, supprimer un lien, bloquer l'héritage |
| Modifier une GPO | `allowedAttributesEffective` de son conteneur contient `versionNumber` | la GPO n'est pas grisée ; Edit, Apply, restaurer, supprimer |
| Créer des GPO | `allowedChildClassesEffective` de `CN=Policies` contient `groupPolicyContainer` | New GPO |
| Créer des filtres WMI | `allowedChildClassesEffective` de `CN=SOM,CN=WMIPolicy,CN=System` contient `msWMI-Som` | Nouveau filtre WMI |
| Modifier un filtre WMI | `allowedAttributesEffective` du filtre contient `msWMI-Parm2` | Modifier le filtre WMI, Supprimer le filtre WMI |

Le compte est celui que l'annuaire répond à « Who am I? » (RFC 4532) : la console le montre dans
son titre, les détails du domaine et la barre d'état.

## Ce que voit un technicien

![La console du technicien Tier 1](../assets/screenshots/14-tier1-view.fr.png)

- toutes les OU, tous les liens et toutes les GPO du domaine, comme GPMC les montre ;
- les OU où il lie des GPO et les GPO qu'il modifie comme d'habitude, **les autres grisées** : il les
  lit (détails, liens, paramètres, délégation, historique) et n'y change rien ;
- seulement les actions qu'il peut faire, dans le menu contextuel.

Les détails du domaine disent si la délégation est **complète** (le compte gère toutes les OU et
GPO), **limitée** ou **aucune**.

```bash
# La même console, avec le technicien Tier 1
kinit tiers1@HARDENBOX.LABO
pwsh -c 'Show-GPOManagerAvalonia -Server dc.hardenbox.labo'
```

!!! note "Plusieurs tickets"
    `kinit` remplace le ticket du cache par défaut. Pour garder celui du Tier 0 dans un autre
    terminal, donnez à chaque terminal son propre cache : `export KRB5CCNAME=FILE:/tmp/krb5cc_tier1`
    avant `kinit`.

## Un compte sans délégation

Un compte à qui le domaine ne donne aucune délégation, un utilisateur de Domain Users par exemple,
lit tout le domaine : tout est grisé, les menus contextuels ne proposent rien, **Paramètres** est
grisé, et la barre d'état dit **(lecture seule)**. Les détails du domaine disent
**Délégation : Aucune**.

![La console d'un compte sans délégation](../assets/screenshots/42-read-only-view.fr.png)

## Ne montrer que ce que le compte gère

Les administrateurs du domaine le choisissent dans la [configuration du domaine](configuration.md) :
avec **`View.ShowUnmanaged`** à `$false` (**Paramètres**, ou `Configuration.psd1`), chaque compte ne
voit que ce qu'il gère : les OU où il lie des GPO, **leurs parents grisés** comme chemin d'accès,
sans leurs liens, et les GPO qu'il modifie ou qui sont liées à ses OU. Un compte sans délégation ne
voit alors rien ; les détails du domaine et la barre d'état le disent. La valeur par défaut, `$true`,
est la vue ci-dessus. La console reconstruit son arbre une fois le réglage enregistré.

![Le technicien Tier 1, View.ShowUnmanaged à $false](../assets/screenshots/44-filtered-view.fr.png)

```powershell
@{ View = @{ ShowUnmanaged = $false } }
```

## Les droits sont ceux du domaine

La console ne décide jamais seule : une modification que le compte n'a pas le droit de faire est
refusée par le contrôleur de domaine, et la console le dit. Les menus évitent seulement à un
technicien les actions qui lui seraient refusées. Le [workflow d'approbation](../workflows/approval.md)
repose sur le même principe.
