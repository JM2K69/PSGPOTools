# SYSVOL

Les fichiers d'une GPO sont dans son dossier SYSVOL, `gPCFileSysPath`
(`\\domaine\SysVol\domaine\Policies\{GUID}`), lus et écrits **sur le contrôleur de domaine depuis
lequel l'annuaire a été lu** : Samba ne réplique pas SYSVOL entre contrôleurs de domaine.

## Fichiers

| | Windows | Linux |
|---|---|---|
| Lire un fichier | `\\<dc>\<partage>\<chemin>` | `smbclient //<dc>/<partage> --use-kerberos=required -c 'get ...'` |
| Lire un dossier (sauvegardes) | `Get-ChildItem -Recurse` sur le chemin UNC | `smbclient ... 'recurse ON; mget *'` dans un dossier temporaire |
| Écrire un fichier | `[IO.File]::WriteAllBytes` | `smbclient ... 'mkdir ...; put ...'`, un niveau de dossier à la fois |

`smbclient` ne demande jamais de mot de passe : pas d'entrée standard, Kerberos seulement (pas
`--no-pass`, avec lequel il n'utiliserait pas le ticket). Ses erreurs `NT_STATUS_*` sont rapportées
telles quelles ; un fichier absent n'est pas une erreur là où il peut manquer.

## Enregistrer un paramètre

Écrire `Registry.pol`, `GptTmpl.inf` ou un fichier de préférences fait aussi :

1. augmenter la version de l'étendue dans `GPT.INI` (`Version=`, version utilisateur dans le mot
   haut, version ordinateur dans le mot bas) ;
2. augmenter `versionNumber` dans l'annuaire, à partir de la valeur qu'il contient, refusé si elle
   a changé entre-temps ;
3. déclarer l'extension côté client et son outil dans `gPCMachineExtensionNames` /
   `gPCUserExtensionNames` (paires de GUID triées, comme GPMC les écrit).

Sans 1 et 2 les ordinateurs n'appliqueraient pas la modification ; sans 3 ils ignoreraient le
fichier.

## Droits

L'ACL du dossier d'une GPO est dérivée de la DACL de son conteneur, comme le font Samba
(`dsacl2fsacl`) et GPMC : les ACE d'autorisation, héritées par les fichiers et dossiers, les droits
de l'annuaire traduits en droits de fichiers.

| | Windows | Linux |
|---|---|---|
| Lire un descripteur | `GetAccessControl(...).GetSecurityDescriptorBinaryForm()` | Python : `libsmb.Conn.get_acl` (propriétaire, groupe, DACL) |
| L'écrire | `SetSecurityDescriptorBinaryForm` + `SetAccessControl` | Python : `libsmb.Conn.set_acl` avec ses drapeaux `SECINFO_*` |
| Le contenu d'un dossier | Windows propage l'ACL du dossier | la console donne à chaque fichier et dossier l'ACL du dossier, comme `samba-tool ntacl sysvolreset` |

Les ACE de droits étendus (« Appliquer la stratégie de groupe ») ne veulent rien dire pour un
fichier : Windows les écarte, comme GPMC ; Samba les garde comme `samba-tool` les écrit. `smbcacls`
n'est pas utilisé : il trie les ACE et retire les doublons, et `samba-tool gpo aclcheck` compare
les ACL telles qu'écrites.

!!! warning "Samba vérifie deux ACL"
    Avec `vfs objects = acl_xattr`, Samba vérifie l'ACL NT d'un fichier (un attribut étendu)
    **et** son ACL POSIX, et ne modifie l'ACL POSIX d'un fichier que pour son propriétaire. Un
    administrateur qui change l'ACL d'un fichier dont il n'est pas propriétaire ne change que son
    ACL NT. Le [workflow d'approbation](../workflows/approval.md) pose les droits des créateurs
    tant qu'ils sont propriétaires des fichiers, pour que les deux ACL les leur donnent.

## La configuration du domaine

`SYSVOL\<domaine>\PSGPOTools\Configuration.psd1`, lu et écrit de la même façon, par son chemin depuis
la racine du partage ([configuration](../features/configuration.md)).
