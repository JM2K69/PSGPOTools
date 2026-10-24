# The launcher

`Start-HGPM` opens the launcher of HGPM: a tile for each of its tools. A click on a tile opens the
tool, in the language of the launcher; several tools can be open at once, and the tile of an open
tool is disabled until its window is closed.

```powershell
Import-Module HGPM
Start-HGPM
Start-HGPM -Language fr-FR      # the launcher and the tools in French
```

![The launcher](../assets/screenshots/56-launcher.png)

## The tools

| | Tool | Command | What it does |
|---|---|---|---|
| ![](../assets/screenshots/57-tile-group-policy.png){ width="150" } | [Group Policy Management](console.md) | `Show-GPOManagerAvalonia` | The GPOs of the domain, their links, settings, delegation and backups, as GPMC |
| ![](../assets/screenshots/58-tile-password-settings.png){ width="150" } | [Password Settings](password-policies.md) | `Show-PSOManagerAvalonia` | The fine-grained password policies (PSO), and the one a user or a group gets |
| ![](../assets/screenshots/59-tile-wmi-filter-creator.png){ width="150" } | [WMI Filter Creator](wmi-filter-creator.md) | `Show-WmiFilterCreatorAvalonia` | WMI filters built from ready-made queries, checked, tested, exported to `.mof` |
| ![](../assets/screenshots/60-tile-policy-analyzer.png){ width="150" } | [Policy Analyzer](policy-analyzer.md) | `Show-PolicyAnalyzerAvalonia` | GPOs and the security baselines of Microsoft compared setting by setting |

A tile opens its tool with its default parameters: the domain of the computer, the ADMX files last
chosen. To give a tool parameters (`-Server`, `-Credential`, `-PolicyDefinitions`...), run its
command instead. When a tool cannot open, the launcher says why under its tiles.

## Language and theme

- **The list of languages** (English, Français) changes the language of the launcher at once, and
  of the tools opened after. The choice is kept in the settings of the user: `Start-HGPM` starts on
  it the next time; `Start-HGPM -Language` still chooses another one.
- **Dark mode / Light mode** changes the theme of every window of HGPM: the launcher, the tools open
  and those opened after, and the windows they open (ADMX files, configuration...).
