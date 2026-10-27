# Formats de fichiers

## Le dossier d'une GPO

```text
{GUID}/
  GPT.INI                                      [General] Version=<utilisateur << 16 | ordinateur>
  Machine/
    Registry.pol                               modèles d'administration de l'ordinateur
    Microsoft/Windows NT/SecEdit/GptTmpl.inf   paramètres de sécurité
    Preferences/<Type>/<Type>.xml              préférences de stratégie de groupe
    Scripts/...
  User/
    Registry.pol
    Preferences/<Type>/<Type>.xml
```

## Registry.pol

`GPOToolsRegistryPol`, [MS-GPREG] 2.1 : la signature `PReg`, version 1, puis des entrées
`[clé;valeur;type;taille;donnée]` en UTF-16LE, les crochets et points-virgules étant des caractères
UTF-16. La console le lit et l'écrit octet par octet : un fichier lu puis réécrit est le même
fichier.

| Nom de valeur | Signification |
|---|---|
| un nom | pose la valeur |
| `**del.<nom>` | supprime la valeur |
| `**delvals.` | supprime toutes les valeurs de la clé, avant les autres |
| `**DeleteValues` / `**DeleteKeys` | suppriment les valeurs / sous-clés listées dans la donnée |

L'état d'une stratégie vient de son ADMX : son `enabledValue` / `disabledValue`, les valeurs de
ses éléments, les suppressions qu'elle écrit quand elle est désactivée. Une stratégie dont toutes
les valeurs sont présentes est activée, une dont les valeurs de désactivation sont présentes est
désactivée ; ce qu'aucune stratégie n'explique est une valeur de registre en plus.

## GptTmpl.inf

`GPOToolsSecurityTemplate` : un fichier INF en UTF-16LE avec indicateur d'ordre des octets,
`[Unicode] Unicode=yes` et `[Version] signature="$CHICAGO$"`, puis ses sections (`[System Access]`,
`[Kerberos Policy]`, `[Event Audit]`, `[Privilege Rights]`, `[Registry Values]`, les journaux
d'événements). `[Registry Values]` contient `MACHINE\...\Nom=<type>,<donnée>` ; `[Privilege Rights]`
liste les comptes sous la forme `*SID`. Un fichier écrit par `samba-tool gpo manage security` (sans
`[Unicode]` ni `[Version]`) est lu aussi.

## scripts.ini et psscripts.ini

`GPOToolsScriptsFile` ([MS-GPSCR] 2.2.2) : `Machine\Scripts\scripts.ini` (démarrage, arrêt) et
`User\Scripts\scripts.ini` (ouverture, fermeture de session), `psscripts.ini` à côté pour les
scripts Windows PowerShell ; des fichiers INI en UTF-16LE avec indicateur d'ordre des octets, une
ligne vide en premier, comme l'éditeur de stratégie de groupe les écrit :

```ini
[Startup]
0CmdLine=Install-Agent.cmd
0Parameters=/quiet
```

Un script est `<n>CmdLine` et `<n>Parameters`, numérotés depuis 0 dans l'ordre d'exécution ; une
ligne de commande sans racine est un fichier de `Machine\Scripts\Startup` (`Shutdown`,
`User\Scripts\Logon`, `Logoff`). `[ScriptsConfig]` de `psscripts.ini` dit si les scripts PowerShell
s'exécutent en premier : `StartExecutePSFirst` (démarrage, ouverture de session),
`EndExecutePSFirst` (arrêt, fermeture de session), `true` ou `false`. Les autres sections et clés
sont gardées. L'extension des scripts est `{42B5FAAE-6536-11D2-AE5A-0000F87571E3}`, avec l'outil
`{40B6664F-4972-11D1-A7CA-0000F87571E3}` pour l'ordinateur et
`{40B66650-4972-11D1-A7CA-0000F87571E3}` pour l'utilisateur.

## Le rapport d'une GPO

`Get-PSGPOReport -ReportType Xml` écrit un document XML de HGPM, en anglais (pas le schéma des
rapports de GPMC), dans l'espace de noms `https://jm2k69.github.io/PSGPOTools/schemas/gpo-report/1` :

```xml
<GpoReports generated="..." generatedBy="HGPM 0.1.16-alpha">
  <Gpo id="{...}" name="T1 - Servers - Proxy" domain="contoso.com">
    <Details owner="..." status="Enabled" approval="Pending" computerVersion="3" userVersion="0"/>
    <Links><Link name="Servers" container="OU=Servers,..." enabled="true" enforced="false" order="1"/></Links>
    <SecurityFiltering><Trustee>Authenticated Users</Trustee></SecurityFiltering>
    <Permissions><Permission trustee="..." permission="GpoEdit" inherited="false" denied="false"/></Permissions>
    <Extensions><Extension scope="Machine" guid="{...}" name="Scripts" interpreted="true"/></Extensions>
    <Computer><Setting path="Policies > ..." name="..." state="...">options</Setting></Computer>
    <User/>
    <NotInterpreted><Setting path="Client-side extensions" name="Folder Redirection" state="User">...</Setting></NotInterpreted>
  </Gpo>
</GpoReports>
```

`-ReportType Html` écrit une page en un seul fichier, dans la langue de l'interface, lisible dans
tout navigateur ; `-ReportType Object` donne des objets `PSGPOTools.GpoReport` avec les mêmes
parties.

## Préférences de stratégie de groupe

`GPOToolsPreferenceFile` : le XML d'un type de préférences, lu et écrit avec `System.Xml`.
`Resources/Preferences.json` décrit les 21 types ([MS-GPPREF] 1.9, 2.2.1) : leur fichier,
l'extension côté client et son outil, les éléments et leurs CLSID, les attributs de leurs
`Properties` et leurs natures.

```xml
<RegistrySettings clsid="{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}">
  <Registry clsid="{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}" name="Baseline" status="Baseline"
            image="7" changed="2026-10-15 08:45:12" uid="{...}" desc="Version of the Tier 1 baseline"
            bypassErrors="1">
    <Properties action="U" hive="HKEY_LOCAL_MACHINE" key="SOFTWARE\HardenBox\Tier1" name="Baseline" type="REG_SZ" value="2026.10"/>
  </Registry>
</RegistrySettings>
```

## Sauvegardes

```text
<racine>/<nom de la GPO> {<GUID>}/<yyyy-MM-dd_HH-mm-ss>/manifest.json
```

```json
{
  "Format": "PSGPOTools.Backup/1",
  "BackedUp": "2026-10-16T09:47:04.0000000Z",
  "Domain": "hardenbox.labo",
  "Server": "dc.hardenbox.labo",
  "Account": "HARDENBOX\\Administrator",
  "Gpo": {
    "Id": "f1726771-92f6-4598-9775-a26d8b33a1c8",
    "DistinguishedName": "CN={F1726771-...},CN=Policies,CN=System,DC=hardenbox,DC=labo",
    "FileSysPath": "\\\\hardenbox.labo\\SysVol\\hardenbox.labo\\Policies\\{F1726771-...}",
    "Modified": "2026-10-16T09:46:58.0000000Z",
    "DisplayName": "T1 - Workflow test",
    "Version": 65537, "ComputerVersion": 1, "UserVersion": 1,
    "Flags": 0, "Status": "Enabled",
    "SecurityFiltering": ["Authenticated Users"], "DeniedTo": [],
    "MachineExtensionNames": "[{35378EAC-...}{D02B1F72-...}]", "UserExtensionNames": null,
    "Links": [{ "Container": "OU=Tier 1,DC=hardenbox,DC=labo", "Enabled": true, "Enforced": false, "Order": 1 }]
  },
  "Files": [{ "Path": "Machine\\Registry.pol", "Size": 98, "Sha256": "..." }]
}
```

`notes.json`, à côté, quand la sauvegarde a des notes :

```json
{
  "Format": "PSGPOTools.BackupNotes/1",
  "Comment": "Approved by HARDENBOX\\Administrator, created by TIERS1: the creators read it; applied by Authenticated Users.",
  "Labels": ["Approved"],
  "Updated": "2026-10-16T09:47:05.0000000Z",
  "UpdatedBy": "HARDENBOX\\Administrator",
  "RestoredAs": null
}
```

`RestoredAs` est le GUID de la GPO recréée à partir de cette sauvegarde d'une GPO supprimée : il
fait sortir la GPO supprimée de la corbeille.

## La configuration du domaine

Un fichier de données PowerShell (`.psd1`) avec les clés qu'il change, lu avec
`Import-PowerShellDataFile` ([référence de la configuration](../reference/configuration.md)).
