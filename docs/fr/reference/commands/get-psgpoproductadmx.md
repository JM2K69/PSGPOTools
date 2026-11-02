# Get-PSGPOProductAdmx

Lists the products whose ADMX files Install-PSGPOProductAdmx installs: their publisher, the version pinned, their languages.

_L'aide de la commande, telle que `Get-Help Get-PSGPOProductAdmx -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOProductAdmx [[-Name] <string[]>] [<CommonParameters>]
```

## Description

The module pins one package of each product (Resources/AdmxProducts.json): its address on the site of its publisher, its size and SHA-256, and the SHA-256 of each of its .admx and of its .adml files. Install-PSGPOProductAdmx installs only that package, those files. A newer version of a product than the one pinned is installed from its folder with -SourcePath.

## Paramètres

### -Name

The products to show (Office, Firefox...); all of them by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String[]` | Non | 1 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOProductAdmx | Format-Table Name, Publisher, Version, Languages
```

### Exemple 2

```powershell
(Get-PSGPOProductAdmx -Name Firefox).Languages
```

## Sorties

- `PSGPOTools.AdmxProduct`

## Voir aussi

- [Install-PSGPOProductAdmx](install-psgpoproductadmx.md)
- [Toutes les commandes](../commands.md)
