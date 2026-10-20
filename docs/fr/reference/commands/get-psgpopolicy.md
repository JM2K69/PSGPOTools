# Get-PSGPOPolicy

The policies of the administrative templates loaded by Initialize-PSGPOAdmx.

_L'aide de la commande, telle que `Get-Help Get-PSGPOPolicy -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOPolicy [[-Scope] <string>] [<CommonParameters>]
```

## Description

Each policy of the ADMX files loaded (Initialize-PSGPOAdmx): its name and explanation in the language of the ADML files, its category, its supported platforms, the registry values it writes when enabled or disabled, and its options (elements). A policy of both scopes in the ADMX is listed once for each.

## Paramètres

### -Scope

Machine (Computer Configuration) or User (User Configuration); both by default.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture fr-FR
Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biom*' | Select-Object DisplayName, Registry
```

## Sorties

- `GPOToolsPolicy`

## Voir aussi

- [Initialize-PSGPOAdmx](initialize-psgpoadmx.md)
- [Toutes les commandes](../commands.md)
