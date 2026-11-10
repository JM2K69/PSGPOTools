# Add-ons

Un add-on est un module installé à côté de HGPM qui le complète. HGPM n'en a jamais besoin : un
add-on absent, ou qui ne peut pas être chargé, laisse les consoles telles qu'elles sont.

On parle d'add-ons, pas d'extensions : une GPO a déjà des extensions côté client.

## Ce qui fait d'un module un add-on

- Son nom est `HGPM.<nom>` (`HGPM.Contoso`).
- Son manifeste le marque `HGPMAddOn` (`PrivateData.PSData.Tags`).
- Il exige la version de HGPM avec laquelle il a été testé (`RequiredModules`).
- Quand il est importé, il s'enregistre avec
  [`Register-PSGPOAddOn`](../reference/commands/register-psgpoaddon.md), en donnant le
  **contrat** des points d'extension pour lequel il a été fait, et ses points d'accroche.

```powershell
# HGPM.Contoso.psd1
@{
    RootModule      = 'HGPM.Contoso.psm1'
    ModuleVersion   = '0.3.0.1'
    RequiredModules = @(@{ ModuleName = 'HGPM'; RequiredVersion = '0.3.0' })
    PrivateData     = @{ PSData = @{ Tags = @('HGPMAddOn') } }
}
```

```powershell
# HGPM.Contoso.psm1 : sa version est lue dans son manifeste
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -Edition 'Contoso' -WindowLogo {
    param($Kind)
    Join-Path $PSScriptRoot "$Kind.png"
}
```

## Comment HGPM les charge

HGPM cherche les add-ons installés (`Get-Module -ListAvailable HGPM.*`, la version la plus récente
de chacun de ceux marqués `HGPMAddOn`) la première fois que quelque chose en a besoin : une
fenêtre, un rapport, la barre d'état. Il le fait dans chaque processus, puisque chaque console de
`Start-HGPM` tourne dans le sien, et les importe dans la session.

| État | Pourquoi | Ce que font les consoles |
|---|---|---|
| Loaded | il s'est enregistré avec le contrat de ce HGPM | elles appellent ses points d'accroche et montrent sa version |
| Refused | fait pour un autre contrat | elles s'ouvrent sans lui |
| Failed | il ne peut pas être importé (la version de HGPM qu'il exige, une erreur), ou ne s'est pas enregistré | elles s'ouvrent sans lui |

Un add-on laissé de côté est signalé dans le journal technique et dans **À propos** du lanceur,
avec la raison. `PSGPOTOOLS_NO_ADDON=1` n'en charge aucun (les tests le posent).

Le premier contrat, celui de HGPM 0.3.0, qui apporte les add-ons, est le **1**. Il change
quand un point d'accroche change ou disparaît, de sorte qu'un add-on fait pour lui ne marcherait
plus : un add-on fait pour un autre contrat est refusé avec un message qui dit quel paquet
installer, jamais avec une erreur dans une console. Un point d'accroche **ajouté** garde le
contrat : les add-ons faits avant lui marchent comme avant, et celui qui l'utilise exige la
version de HGPM qui l'a.

## Les points d'accroche du contrat 1

Chaque point d'accroche est un scriptblock, appelé dans un try : une erreur, ou rien de renvoyé,
laisse ce que fait HGPM tel quel.

| Point d'accroche | Appelé avec | Renvoie | Où |
|---|---|---|---|
| `WindowLogo` | `Icon` ou `Header` | le chemin d'une image | `Icon` : l'icône de chaque fenêtre (barre de titre, barre des tâches) ; `Header` : l'image de l'en-tête des consoles, affichée en 44 x 44 |
| `ReportHtml` | le HTML d'un rapport | le HTML modifié | les rapports HTML (`Get-PSGPOReport -ReportType Html`, **Enregistrer le rapport...**) |
| `ReportFormat` (HGPM 0.4.0) | son `Save` : le HTML d'un rapport (`ReportHtml` appliqué) et un chemin | le fichier écrit | les types de fichier de **Enregistrer le rapport...**, après HTML et XML ; `Get-PSGPOReport -ReportType Html -Path` avec son extension |
| `BeforeChange` (HGPM 0.4.0) | l'annuaire du domaine | rien ; **une erreur refuse la modification** | avant chaque modification du domaine : GPO, liens, filtres WMI, permissions, paramètres, configuration |
| `AuditEntry` (HGPM 0.4.0) | la ligne du journal d'audit, avant son écriture | rien : il ajoute à `$Entry.Details` | chaque ligne du [journal d'audit](../features/audit-log.md), et du journal du système |
| `ConsoleField` (HGPM 0.4.0) | son `Get` et son `Set` | la valeur, gardée par l'add-on | un champ de la barre d'outils de la console GPO |

Un rapport HTML contient trois repères où un add-on ajoute ce qu'il donne, sans lire le reste de
la page : `<!-- hgpm:head -->` avant `</head>`, `<!-- hgpm:body-start -->` après `<body>`,
`<!-- hgpm:body-end -->` avant `</body>`. Un rapport reste un seul fichier : ce qu'ajoute un
add-on est dans la page.

### Formats de rapport

`ReportFormat` donne les formats de fichier dans lesquels un add-on écrit les rapports, en plus de
la page HTML et du document XML de HGPM. Chacun est une table de hachage :

| Clé | Quoi |
|---|---|
| `Name` | son nom (`Text`), dans le journal technique |
| `Extension` | son extension, lettres et chiffres (`txt`) ; ni `html`, ni `htm`, ni `xml`, celles de HGPM |
| `TypeName` | le type de fichier de la boîte d'enregistrement : un texte, ou un texte par langue (`@{ 'en-US' = 'Text file'; 'fr-FR' = 'Fichier texte' }`, l'anglais quand la langue de l'interface n'en a pas) |
| `Save` | `param($Html, $Path)` : écrit le rapport HTML dans `$Path` dans ce format |

```powershell
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ReportFormat @{
    Name      = 'Text'
    Extension = 'txt'
    TypeName  = @{ 'en-US' = 'Text file'; 'fr-FR' = 'Fichier texte' }
    Save      = { param($Html, $Path) Set-Content -LiteralPath $Path -Value ($Html -replace '<[^>]+>', '') }
}
```

**Enregistrer le rapport...** propose chaque type, et le rapport est écrit selon l'extension du
fichier choisi ; `Get-PSGPOReport -ReportType Html -Path ./gpo.txt` fait de même. Contrairement
aux autres points d'accroche, l'erreur de `Save` est celle de l'enregistrement : la console dit
que le rapport n'est pas enregistré, avec elle, et un `Save` qui n'écrit aucun fichier est aussi
une erreur. Un format qui ne convient pas (une extension de HGPM, pas de `Save`...) arrête
l'enregistrement : l'add-on n'est pas chargé, et le journal technique dit pourquoi.

### Une valeur de la console, avant chaque modification

Un add-on peut demander une valeur dans la console GPO (`ConsoleField`), l'écrire dans chaque ligne
du journal d'audit (`AuditEntry`) et refuser une modification sans elle (`BeforeChange`) : un
ticket de changement, par exemple. Un champ est une table de hachage :

| Clé | Quoi |
|---|---|
| `Name` | son nom, lettres et chiffres |
| `Label`, `ToolTip`, `Placeholder` | ses textes : un texte, ou un texte par langue |
| `Width` | sa largeur, de 80 à 400 pixels (160) |
| `Get` | sa valeur, telle que l'add-on la garde |
| `Set` | `param($Value)` : la valeur saisie (Entrée, ou le champ quitté) ; son erreur est dite dans la console, en rouge, et le champ montre la valeur que l'add-on garde |

```powershell
Register-PSGPOAddOn -Name 'HGPM.Contoso' -Contract 1 -ConsoleField @{
    Name  = 'Ticket'
    Label = @{ 'en-US' = 'Ticket'; 'fr-FR' = 'Ticket' }
    Get   = { $env:CONTOSO_TICKET }
    Set   = { param($Value) $env:CONTOSO_TICKET = $Value }
} -BeforeChange {
    param($Directory)
    if (-not $env:CONTOSO_TICKET) { throw 'Saisissez d''abord le ticket du changement.' }
} -AuditEntry {
    param($Entry)
    $Entry.Details['Ticket'] = $env:CONTOSO_TICKET
}
```

`BeforeChange` n'est appelé que pour le domaine, pas pour un annuaire en mémoire (un exemple, un
fichier lu). Contrairement aux autres points d'accroche, son erreur est le refus : la modification
n'est pas faite, et son message est celui que le compte lit. Une console fait ses longues
opérations dans un runspace à elle : une valeur que l'add-on garde pour le processus (une variable
d'environnement du processus) est vue des deux.

### Réglages pour le domaine

Un add-on garde ses réglages pour le domaine dans la configuration du domaine, `AddOns.<nom>`
([configuration](../reference/configuration.md#addons)) : toutes les consoles du domaine les
lisent, seul un administrateur du domaine les écrit. Dans le module de HGPM :
`Get-PSGPOAddOnConfiguration -Name Contoso` les donne, et
`Save-PSGPOAddOnConfiguration -Directory $Directory -Name Contoso -Settings @{ ... }` les écrit
(`$null` les retire), les autres réglages tels que le domaine les a, dans le journal d'audit comme
toute configuration enregistrée.

## Versions

Un add-on est testé avec une version de HGPM, et l'exige : son paquet contient les deux, dans les
versions testées ensemble, et une nouvelle version de HGPM amène un nouveau paquet de l'add-on. Sa
version est celle de HGPM avec un quatrième nombre à lui : `HGPM.Contoso` `0.3.0.1` est fait pour
HGPM `0.3.0`. Avec un add-on chargé, les consoles montrent les deux versions
(`HGPM 0.3.0 + Contoso 0.3.0.1`) et ne proposent pas les mises à jour de la PowerShell Gallery :
HGPM se met à jour avec le paquet de l'add-on.
