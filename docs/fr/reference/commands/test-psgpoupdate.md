# Test-PSGPOUpdate

Tells whether a newer version of HGPM is published on the PowerShell Gallery.

_L'aide de la commande, telle que `Get-Help Test-PSGPOUpdate -Full` la donne (en anglais)._

## Syntaxe

```powershell
Test-PSGPOUpdate [[-Repository] <string>] [-Prerelease] [-Quiet] [<CommonParameters>]
```

## Description

Compares the version of HGPM loaded in the session with the latest one of the PowerShell Gallery (Find-PSResource), as semantic versions: a prerelease comes before its release (0.1.4-alpha before 0.1.4), and the prereleases sort by their label (alpha, beta, rc).

The prereleases of the Gallery count when the version loaded is one, or with -Prerelease; a stable version is otherwise only compared with the stable ones. The result gives the command that updates the module: Update-PSResource when it was installed from the Gallery, Install-PSResource otherwise (a copy of the repository, for instance).

Nothing is installed: the command only reads the Gallery.

## Paramètres

### -Prerelease

Takes the prereleases of the Gallery into account, even when the version loaded is stable.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Quiet

Returns $true when a newer version is published, $false otherwise, instead of the details.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `SwitchParameter` | Non | Nommé | Aucune | Non |

### -Repository

Repository of PSResourceGet to look in (Get-PSResourceRepository); PSGallery by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | `PSGallery` | Non |

## Exemples

### Exemple 1

```powershell
Test-PSGPOUpdate
```

### Exemple 2

```powershell
if (Test-PSGPOUpdate -Quiet) { Update-PSResource -Name HGPM -Prerelease }
```

## Sorties

- `PSGPOTools.Update`

## Voir aussi

- [Toutes les commandes](../commands.md)
