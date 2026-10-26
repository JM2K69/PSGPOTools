# Start-HGPM

Opens the launcher of HGPM: a tile for each graphical console of the module.

_L'aide de la commande, telle que `Get-Help Start-HGPM -Full` la donne (en anglais)._

## Syntaxe

```powershell
Start-HGPM [[-Language] <string>] [<CommonParameters>]
```

## Description

A window with a tile for each console of HGPM: Group Policy Management (Show-GPOManagerAvalonia), the fine-grained password policies (Show-PSOManagerAvalonia) and the WMI filter creator (Show-WmiFilterCreatorAvalonia), Policy Analyzer (Show-PolicyAnalyzerAvalonia) and the audit log (Show-AuditLogAvalonia). A click on a tile opens the console with its default parameters, in the language of the launcher, chosen in its list of languages and kept for the next time; several consoles can be open at once, and the tile of an open console is disabled until its window is closed. To give a console parameters (-Server, -Credential, -PolicyDefinitions...), run its command instead.

Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until the launcher and the consoles opened from it are closed.

## Paramètres

### -Language

Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the one last chosen in the launcher, else the language of the session, English when the module has no translation for it.

| Type | Obligatoire | Position | Valeur par défaut | Accepte le pipeline |
|---|---|---|---|---|
| `String` | Non | 1 | Aucune | Non |

## Exemples

### Exemple 1

```powershell
Start-HGPM
```

### Exemple 2

```powershell
Start-HGPM -Language fr-FR
```

## Voir aussi

- [Show-GPOManagerAvalonia](show-gpomanageravalonia.md)
- [Show-PSOManagerAvalonia](show-psomanageravalonia.md)
- [Show-WmiFilterCreatorAvalonia](show-wmifiltercreatoravalonia.md)
- [Show-PolicyAnalyzerAvalonia](show-policyanalyzeravalonia.md)
- [Show-AuditLogAvalonia](show-auditlogavalonia.md)
- [Toutes les commandes](../commands.md)
