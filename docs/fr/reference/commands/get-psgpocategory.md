# Get-PSGPOCategory

The categories of the administrative templates loaded by Initialize-PSGPOAdmx.

_L'aide de la commande, telle que `Get-Help Get-PSGPOCategory -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOCategory [<CommonParameters>]
```

## Description

Each category of the ADMX files loaded (Initialize-PSGPOAdmx), with its name in the language of the ADML files and its parent category: the tree of Administrative Templates in the policy editor.

## Exemples

### Exemple 1

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
Get-PSGPOCategory | Where-Object DisplayName -Like '*Windows Update*'
```

## Sorties

- `GPOToolsCategory`

## Voir aussi

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [Toutes les commandes](../commands.md)
