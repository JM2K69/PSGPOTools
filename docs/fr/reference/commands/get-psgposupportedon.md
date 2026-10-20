# Get-PSGPOSupportedOn

The platforms the policies of the loaded administrative templates support.

_L'aide de la commande, telle que `Get-Help Get-PSGPOSupportedOn -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOSupportedOn [<CommonParameters>]
```

## Description

Each supportedOn definition of the ADMX files loaded (Initialize-PSGPOAdmx), with its text in the language of the ADML files ("At least Windows 10"...): what the Details tab of a policy shows, and what the policy editor filters on.

## Exemples

### Exemple 1

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
Get-PSGPOSupportedOn | Where-Object DisplayName -Like '*Windows 11*'
```

## Sorties

- `GPOToolsSupportedOn`

## Voir aussi

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [Toutes les commandes](../commands.md)
