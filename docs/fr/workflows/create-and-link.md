# Créer et lier une GPO

Objectif : une GPO pour les serveurs du Tier 1, qui ne s'applique qu'aux membres d'un groupe, liée
à l'OU `Tier 1`.

## Dans la fenêtre

1. Clic droit sur **Tier 1** > **Create a GPO in this domain, and Link it here...**
2. Nommez-la `T1 - Servers - Proxy`, choisissez son **GPO status** (ici *Computer settings only*),
   et **Start from** une GPO vide ou un modèle.
3. Cochez **Create the security filtering groups** : `APPLY_T1 - Servers - Proxy` et
   `DENY_T1 - Servers - Proxy`, dans le conteneur proposé par la configuration.
4. **Create**.

![Le formulaire New GPO](../assets/screenshots/05-new-gpo.png)

Sous les détails, la console dit ce qu'elle a fait : la GPO créée, son statut, ses groupes, son
lien. Si les groupes n'ont pas pu être créés, la GPO **n'est pas liée**, et la console dit
pourquoi : sans son filtrage de sécurité, elle s'appliquerait à tous les ordinateurs de l'OU.

5. Ajoutez les serveurs à `APPLY_T1 - Servers - Proxy`.
6. Clic droit sur la GPO > **Edit**, configurez ses paramètres, **Apply** sur chacun.

## En ligne de commande

```powershell
$Directory = Get-PSGPODirectory -Server dc.hardenbox.labo
$Gpo = New-PSGPO -Directory $Directory -Name 'T1 - Servers - Proxy' -Status ComputerOnly
$Groups = $Directory.NewFilteringGroups($Gpo, '')          # le conteneur de la configuration
$Link = $Directory.NewLink($Directory.FindSom('OU=Tier 1,DC=hardenbox,DC=labo'), $Gpo)
```

## Lier une GPO existante ailleurs

Clic droit sur le domaine ou une OU > **Link an Existing GPO...**, cherchez-la par son nom,
**Link**. Le lien prend la plus faible priorité ; pour changer l'ordre, utilisez GPMC ou
`samba-tool gpo setlink` pour l'instant.

## Vérifier

- Les détails de la GPO : son statut, **Security filtering** `APPLY_T1 - Servers - Proxy`,
  **Denied to** `DENY_T1 - Servers - Proxy`, son lien à `Tier 1`.
- Sur un serveur du groupe : `gpupdate /force`, puis `gpresult /r` liste la GPO.
