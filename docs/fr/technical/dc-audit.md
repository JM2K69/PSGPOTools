# L'audit sur les contrôleurs de domaine

HGPM écrit chaque modification qu'il fait dans son [journal d'audit](../features/audit-log.md), et
dans le journal du système pour un SIEM. Une modification faite avec un autre outil (GPMC,
`samba-tool`, un script, un client LDAP) n'y est pas : l'[écart](../workflows/drift.md) montre ce
qui a changé dans une GPO, pas qui l'a changé. Les contrôleurs de domaine le savent : configurez-les
pour qu'ils le disent.

| Ce qui change | Où | Windows | Samba |
|---|---|---|---|
| Une GPO créée, modifiée (sa version, ses extensions, son dossier, son filtre WMI, ses permissions) ou supprimée | son conteneur dans `CN=Policies,CN=System` | événements 5137, 5136, 5141 | `dsdb_json_audit` |
| Un lien, un blocage de l'héritage | `gPLink` et `gPOptions` du domaine, d'une OU, d'un site | événement 5136 | `dsdb_json_audit` |
| Les fichiers d'une GPO, leurs permissions | son dossier dans `SYSVOL\<domaine>\Policies` | événement 4663 | `vfs_full_audit` |

Envoyez-les au SIEM avec les événements de HGPM : une modification d'une GPO sans son événement de
HGPM a été faite avec un autre outil.

## Windows (Active Directory)

### 1. La stratégie d'audit des contrôleurs de domaine

Dans la **Default Domain Controllers Policy** (l'éditeur de HGPM l'a, [stratégie d'audit
avancée](../features/policy-editor.md)) : **Configuration ordinateur > Stratégies > Paramètres
Windows > Paramètres de sécurité > Configuration avancée de la stratégie d'audit > Stratégies
d'audit** :

| Sous-catégorie | Valeur |
|---|---|
| Accès DS > **Auditer les modifications du service d'annuaire** | Succès |
| Accès à l'objet > **Auditer le système de fichiers** | Succès |

Sur un contrôleur de domaine, une fois appliquée :

```powershell
auditpol /get /subcategory:"Directory Service Changes","File System"
```

### 2. Ce que l'annuaire audite : les SACL

Un événement n'est écrit que pour les objets dont la SACL audite la modification. En Domain Admin,
avec le module ActiveDirectory (RSAT), les GPO et leurs liens :

```powershell
Import-Module ActiveDirectory
$domain = (Get-ADDomain).DistinguishedName
$everyone = [System.Security.Principal.SecurityIdentifier]'S-1-1-0'
$all = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All

# Les GPO : créées, modifiées, supprimées, leurs permissions et leur propriétaire.
$path = "AD:\CN=Policies,CN=System,$domain"
$acl = Get-Acl -Path $path -Audit
$rights = [System.DirectoryServices.ActiveDirectoryRights]'WriteProperty, CreateChild, DeleteChild, Delete, DeleteTree, WriteDacl, WriteOwner'
$acl.AddAuditRule([System.DirectoryServices.ActiveDirectoryAuditRule]::new($everyone, $rights, 'Success', $all))
Set-Acl -Path $path -AclObject $acl

# Les liens (gPLink) et le blocage de l'héritage (gPOptions) du domaine et de chaque OU.
$path = "AD:\$domain"
$acl = Get-Acl -Path $path -Audit
foreach ($attribute in 'f30e3bbe-9ff0-11d1-b603-0000f80367c1', 'f30e3bbf-9ff0-11d1-b603-0000f80367c1') {
    $acl.AddAuditRule([System.DirectoryServices.ActiveDirectoryAuditRule]::new($everyone, 'WriteProperty', 'Success', [guid]$attribute, $all))
}
Set-Acl -Path $path -AclObject $acl
```

Les liens des sites sont dans la configuration de la forêt : la même règle pour `gPLink` sur
`CN=Sites,CN=Configuration,<forêt>`, en Enterprise Admin.

### 3. Ce que SYSVOL audite

La SACL du dossier `Policies`, sur chaque contrôleur de domaine (SYSVOL est local à chacun) :

```powershell
$path = "$env:SystemRoot\SYSVOL\domain\Policies"
$acl = Get-Acl -Path $path -Audit
$rights = [System.Security.AccessControl.FileSystemRights]'CreateFiles, AppendData, WriteAttributes, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
$acl.AddAuditRule([System.Security.AccessControl.FileSystemAuditRule]::new('Everyone', $rights, 'ContainerInherit, ObjectInherit', 'None', 'Success'))
Set-Acl -Path $path -AclObject $acl
```

### Les événements

Dans le journal **Sécurité** du contrôleur de domaine où la modification a été faite :

| Événement | Dit |
|---|---|
| 5137 | un objet a été créé : une GPO (`groupPolicyContainer`) et ses conteneurs `User` et `Machine` |
| 5136 | un objet a été modifié : le compte, l'objet, l'attribut (`versionNumber`, `gPLink`, `nTSecurityDescriptor`...) et sa valeur ajoutée ou retirée |
| 5141 | un objet a été supprimé |
| 5139 | un objet a été déplacé |
| 4663 | un fichier ou un dossier de SYSVOL écrit, supprimé, ou ses permissions modifiées (`WRITE_DAC`), par qui |

```powershell
Get-WinEvent -ComputerName dc1 -FilterHashtable @{ LogName = 'Security'; Id = 5136, 5137, 5141 } -MaxEvents 20 |
    Format-List TimeCreated, Id, Message
```

## Samba AD

Samba n'a pas de SACL : il journalise ce qui change, pour chaque objet, en JSON, quand la classe
`dsdb_json_audit` est au niveau 5 ; et les fichiers d'un partage avec le module `vfs_full_audit`.
Les deux se règlent dans `/etc/samba/smb.conf` de chaque contrôleur de domaine, puis Samba est
redémarré.

### 1. Les modifications de l'annuaire

Dans `[global]` :

```ini
[global]
    log level = 0 dsdb_json_audit:5@/var/log/samba/dsdb_json_audit.log
```

| Partie | Fait |
|---|---|
| `log level = 0` | le niveau des autres classes, dans `log file` : gardez le vôtre (`1`, `2`...) si la ligne en avait déjà un |
| `dsdb_json_audit:5` | chaque modification de la base (ajout, modification, suppression), en une ligne de JSON : qui (`userSid`), d'où (`remoteAddress`), quoi (`operation`, `dn`, `attributes` avec leurs valeurs) |
| `@/var/log/samba/dsdb_json_audit.log` | dans un fichier à part, pas dans `log.samba` |

```bash
sudo systemctl restart samba-ad-dc
```

`smbcontrol ... debug` à chaud ne l'active pas : les processus de LDAP le lisent à leur démarrage.
D'autres classes, sur la même ligne : `dsdb_group_json_audit:5` (les membres des groupes : les
groupes du filtrage de sécurité), `auth_json_audit:3` (les ouvertures de session).

Une GPO retirée d'une OU (sur une ligne, raccourcie ici) : la valeur de `gPLink` avant (`delete`) et
après (`add`), comme la console l'écrit en une seule requête.

```json
{"timestamp": "2026-10-30T12:51:48.701369+0100", "type": "dsdbChange", "dsdbChange": {
  "status": "Success", "operation": "Modify", "remoteAddress": "ipv4:10.0.0.51:47044",
  "userSid": "S-1-5-21-99285962-3314789183-2679996994-500", "dn": "OU=Test,DC=hardenbox,DC=labo",
  "attributes": {"gPLink": {"actions": [
    {"action": "delete", "values": [{"value": "[LDAP://CN={5D5A49E5-...},CN=Policies,...;0][LDAP://CN={04CF011D-...},...;0]"}]},
    {"action": "add", "values": [{"value": "[LDAP://CN={04CF011D-...},CN=Policies,...;0]"}]}]}}}}
```

Le fichier grossit à chaque modification du domaine (ouvertures de session et ordinateurs aussi) :
`max log size` (en Ko) le fait tourner en `.old`, ou une règle de `logrotate` ; le SIEM le lit en
JSON.

### 2. Les fichiers de SYSVOL

Dans `[sysvol]` (et `[netlogon]`), le module `full_audit` après les deux modules dont SYSVOL a
besoin :

```ini
[sysvol]
    vfs objects = dfs_samba4 acl_xattr full_audit
    full_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S
    full_audit:success = mkdirat renameat unlinkat pwrite pwrite_send fset_nt_acl
    full_audit:failure = none
    full_audit:facility = local7
    full_audit:priority = NOTICE
```

| Ligne | Fait |
|---|---|
| `vfs objects = dfs_samba4 acl_xattr full_audit` | ajoute l'audit ; ne retirez jamais `dfs_samba4` et `acl_xattr` (les ACL de SYSVOL sont dans `acl_xattr`) |
| `full_audit:prefix` | le début de chaque ligne : l'adresse, le compte, l'ordinateur, le partage |
| `full_audit:success` | les opérations journalisées : un dossier créé (`mkdirat`), renommé (`renameat`, Samba crée un dossier sous un nom temporaire), un fichier ou un dossier supprimé (`unlinkat`), écrit (`pwrite` ; `pwrite_send` en SMB2, comme `GPT.INI`), ses permissions (`fset_nt_acl`) |
| `full_audit:failure = none` | les opérations refusées ne sont pas journalisées |
| `full_audit:facility`, `full_audit:priority` | où syslog les range : `journalctl -t smbd_audit` |

Sans `pwrite_send`, `unlinkat` et `fset_nt_acl`, les écritures en SMB2, les suppressions et les
permissions ne sont pas journalisées : seuls les dossiers renommés le sont.

## Testé

Sur hardenbox.labo (Samba 4.22), les deux réglages ci-dessus dans `smb.conf`, Samba redémarré,
puis une GPO créée avec la console, liée à une OU, déliée, une permission modifiée, et supprimée :

| Quoi | `dsdb_json_audit` | `full_audit` |
|---|---|---|
| La GPO créée | `Add` de la GPO, de ses `User` et `Machine` | `mkdirat`, `renameat` de ses dossiers, `pwrite_send` de `GPT.INI`, `fset_nt_acl` |
| Liée, déliée | `Modify` de l'OU, deux fois | (rien : l'annuaire seulement) |
| Une permission modifiée | `Modify` de la GPO | `fset_nt_acl` de son dossier et de ses fichiers |
| Supprimée | `Delete` de `User`, `Machine`, puis de la GPO | `unlinkat` de `GPT.INI`, de ses dossiers, du dossier |
| Qui | `userSid` du compte (Administrator, RID 500) | `USER=HARDENBOX\Administrator`, son adresse |

`smbcontrol samba debug` et `smbcontrol ldap_server debug` à chaud : rien de journalisé. Avec
seulement `full_audit:success = pwrite write renameat` : seuls les dossiers renommés.

La partie Windows donne les réglages et les événements de Windows Server ; elle n'a pas été
exécutée sur powershell.labo.
