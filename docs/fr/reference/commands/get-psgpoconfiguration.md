# Get-PSGPOConfiguration

Shows the configuration of PSGPOTools for the domain, and where it comes from.

_L'aide de la commande, telle que `Get-Help Get-PSGPOConfiguration -Full` la donne (en anglais)._

## Syntaxe

```powershell
Get-PSGPOConfiguration [[-Directory] <GPOToolsDirectory>] [[-Server] <string>] [<CommonParameters>]
```

## Description

The configuration is the Resources/Configuration.psd1 of the module (every setting with its default, commented), with over it the configuration of the domain: Configuration.psd1 in SYSVOL\<domain>\PSGPOTools on the domain controller, which holds only the settings it changes. It is the same for every console of the domain, and only the administrators of the domain can write it (SYSVOL: Authenticated Users read it); there is no configuration of the user. It is read as data, never run; one that cannot be read or holds a wrong value is reported and left out.

The configuration in use is the one of the last domain read (Get-PSGPODirectory, the window, or a command given -Directory); -Directory or -Server reads another one. The Settings window of the console changes it.

It sets what the window proposes for a new GPO (name, status, security filtering groups), and the labels of the approved versions and of the templates.

## Paramètres

### -Directory

Directory of the domain (Get-PSGPODirectory).

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `GPOToolsDirectory` | Non | 1 | Aucune | Non |

### -Server

Domain controller to read the domain from, without -Directory.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 2 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Get-PSGPOConfiguration -Server dc1.contoso.com
```

### Exemple 2

```powershell
# An administrator of the domain: the groups of the new GPOs in OU=GPO,OU=Groups
$Path = (Get-PSGPOConfiguration).DomainPath
Set-Content -Path $Path -Value "@{ NewGpo = @{ SecurityFilteringGroups = @{ Create = `$true; Container = 'OU=GPO,OU=Groups' } } }"
```

## Sorties

- `System.Management.Automation.PSObject`

## Voir aussi

- [Toutes les commandes](../commands.md)
