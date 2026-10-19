# Importer une GPO avec une table de migration

Une GPO construite dans un domaine de test, ou sauvegardée dans une autre forêt, est amenée dans
le domaine avec ses paramètres, ses comptes et ses chemins UNC transposés vers ceux du domaine :
comme **Importer des paramètres** de GPMC, avec une **table de migration**, et comme l'import
d'AGPM dans une GPO existante, dont les paramètres sont remplacés.

## Les sauvegardes

`Import-PSGPO` et **Importer des paramètres...** lisent deux sortes de sauvegardes :

- **GPMC** : `Backup-GPO`, ou **Sauvegarder...** dans GPMC. Un dossier contient un dossier par
  sauvegarde, nommé par son ID, avec `bkupInfo.xml` (la GPO, son domaine, la date), `Backup.xml`
  (ses comptes avec leur SID, nom, type et domaine, et ses extensions côté client) et
  `DomainSysvol\GPO` (ses fichiers).
- **PSGPOTools** : `Backup-PSGPO` ou l'onglet Historique ; la sauvegarde la plus récente de chaque
  GPO.

```powershell
Get-PSGPOGpmcBackup -Path C:\backupGPO
```

## La table de migration

Une table de migration (`.migtable`) est le fichier XML qu'écrit l'**éditeur de tables de
migration** de GPMC : une entrée par compte ou chemin UNC de la source, et ce qu'il devient dans
le domaine de l'import.

| Destination | Dans l'éditeur | Ce que fait l'import |
|---|---|---|
| `<DestinationSameAsSource/>` | Same As Source | la référence est gardée |
| `<DestinationByRelativeName/>` | Map by Relative Name | le compte du même nom dans ce domaine (`Domain Admins@test.contoso.com` devient Domain Admins de ce domaine) |
| `<DestinationNone/>` | No Destination | le compte est retiré du paramètre |
| `<Destination>CONTOSO\Groupe</Destination>` | un nom, ou un chemin | ce compte de ce domaine, ou ce chemin |

Les types d'entrées sont ceux de GPMC : `User`, `Computer`, `LocalGroup`, `GlobalGroup`,
`UniversalGroup`, `UNCPath`, et `Unknown` pour le texte libre et les SID (les comptes intégrés,
comme Administrateurs ou Opérateurs de sauvegarde). Comme GPMC le vérifie, un chemin UNC est gardé
ou transposé vers un autre chemin (jamais retiré ni transposé par nom relatif), un texte libre ou
un SID n'est pas transposé par nom relatif, et une destination est un nom, pas un SID. Une table de
GPMC s'utilise telle quelle ; une table écrite par la console s'ouvre dans l'éditeur de GPMC.

```powershell
# Comme « Remplir à partir de la sauvegarde » de l'éditeur : une entrée par référence, à modifier avant l'import.
New-PSGPOMigrationTable -Path C:\backupGPO\production.migtable -BackupPath C:\backupGPO -MapByRelativeName
Get-PSGPOMigrationEntry -Path C:\backupGPO | Format-Table Type, Source, Gpos
Get-PSGPOMigrationTable -Path C:\backupGPO\production.migtable
```

## Ce qui est migré

- Les **paramètres de sécurité** (`GptTmpl.inf`) : les comptes des attributions de droits et des
  groupes restreints (`*SID` ou un nom ; le groupe restreint d'un compte retiré part avec lui), et
  les comptes des autorisations de fichiers, clés de registre et services (SDDL).
- Les **préférences** : les membres des groupes locaux, les comptes des filtres de ciblage, des
  services et des tâches (leur `sid` et leur nom), et chaque chemin UNC (lecteurs mappés,
  raccourcis, fichiers...).
- Les **scripts** et la **redirection de dossiers** : leurs chemins UNC et leurs comptes.
- Les **modèles d'administration** (`Registry.pol`) sont copiés tels quels, comme le fait GPMC :
  GPMC ne les migre pas non plus.

Un compte ou un chemin que la table ne nomme pas est copié tel quel ; avec **-Exclusive**
(« Utiliser exclusivement la table de migration » de GPMC), l'import s'arrête à la place. Une
destination introuvable dans le domaine arrête l'import avant toute modification, comme dans
GPMC ; les destinations sont cherchées dans le domaine de l'import (un nom d'un autre domaine est
refusé).

## Importer

Dans la console, **Importer des paramètres...** dans le menu contextuel d'une GPO : le dossier des
sauvegardes, la sauvegarde à importer, la table de migration, et si elle est utilisée
exclusivement. Le résultat dit ce qu'est devenue chaque référence.

![Importer des paramètres](../assets/screenshots/26-import-settings.png)

```powershell
Import-PSGPO -Path C:\backupGPO -SourceName 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline' `
    -MigrationTable C:\backupGPO\production.migtable
Import-PSGPO -Path C:\backupGPO -SourceName TEST -TargetName 'C - Test' -CreateIfNeeded -WhatIf
```

La GPO est d'abord sauvegardée, dans le dossier de l'onglet Historique (`-BackupPath`, ou aucune
sauvegarde avec `-NoBackup`) : ses paramètres d'avant l'import peuvent être restaurés. Ses
paramètres sont remplacés, comme AGPM le fait pour une GPO existante ; ses liens, autorisations,
état et filtre WMI ne changent pas, sa version augmente pour que les ordinateurs l'appliquent à
nouveau, et les extensions côté client sont celles de la sauvegarde (celles de ses fichiers quand
la sauvegarde n'en déclare pas). L'import va dans le [journal d'audit](../features/backup-history.md),
avec ce qui a été migré.

## Sources

- [Creating Migration Tables](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc757141(v=ws.10)) et
  [Migration tables](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc739066(v=ws.10)) (GPMC, Microsoft Learn)
- [The Migration Table Editor](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc779961(v=ws.10)) (Microsoft Learn)
- [IGPMMigrationTable::AddEntry](https://learn.microsoft.com/en-us/windows/win32/api/gpmgmt/nf-gpmgmt-igpmmigrationtable-addentry) : les types d'entrées (Microsoft Learn)
- [Import a GPO from a File](https://learn.microsoft.com/en-us/microsoft-desktop-optimization-pack/agpm/import-a-gpo-from-a-file-agpmadmin) (AGPM, Microsoft Learn)
- Les sauvegardes et la table des tests viennent de GPMC sous Windows : `CI/tests/Fixtures/GpmcBackup`.
