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
quand ce que HGPM demande à un add-on, ou lui donne, change : un add-on fait pour un autre contrat
est refusé avec un message qui dit quel paquet installer, jamais avec une erreur dans une console.

## Les points d'accroche du contrat 1

Chaque point d'accroche est un scriptblock, appelé dans un try : une erreur, ou rien de renvoyé,
laisse ce que fait HGPM tel quel.

| Point d'accroche | Appelé avec | Renvoie | Où |
|---|---|---|---|
| `WindowLogo` | `Icon` ou `Header` | le chemin d'une image | `Icon` : l'icône de chaque fenêtre (barre de titre, barre des tâches) ; `Header` : l'image de l'en-tête des consoles, affichée en 44 x 44 |
| `ReportHtml` | le HTML d'un rapport | le HTML modifié | les rapports HTML (`Get-PSGPOReport -ReportType Html`, **Enregistrer le rapport...**) |

Un rapport HTML contient trois repères où un add-on ajoute ce qu'il donne, sans lire le reste de
la page : `<!-- hgpm:head -->` avant `</head>`, `<!-- hgpm:body-start -->` après `<body>`,
`<!-- hgpm:body-end -->` avant `</body>`. Un rapport reste un seul fichier : ce qu'ajoute un
add-on est dans la page.

## Versions

Un add-on est testé avec une version de HGPM, et l'exige : son paquet contient les deux, dans les
versions testées ensemble, et une nouvelle version de HGPM amène un nouveau paquet de l'add-on. Sa
version est celle de HGPM avec un quatrième nombre à lui : `HGPM.Contoso` `0.3.0.1` est fait pour
HGPM `0.3.0`. Avec un add-on chargé, les consoles montrent les deux versions
(`HGPM 0.3.0 + Contoso 0.3.0.1`) et ne proposent pas les mises à jour de la PowerShell Gallery :
HGPM se met à jour avec le paquet de l'add-on.
