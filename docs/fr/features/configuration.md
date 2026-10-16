# Configuration du domaine

La configuration de PSGPOTools est **celle du domaine**, la même pour toutes les consoles du
domaine :

```text
\\<contrôleur de domaine>\SYSVOL\<domaine>\PSGPOTools\Configuration.psd1
```

- Seuls les **administrateurs du domaine** peuvent l'écrire : SYSVOL laisse Authenticated Users la
  lire et les administrateurs l'écrire, si bien qu'un technicien ne peut pas se donner une autre
  configuration.
- Il n'y a **pas de configuration par utilisateur**, et aucun fichier local ne dit où elle se
  trouve : la console la lit sur le contrôleur de domaine depuis lequel elle lit le domaine.
- Elle ne contient que les réglages qu'elle change ; les autres gardent la valeur par défaut du
  module (`Resources/Configuration.psd1`, chaque réglage commenté).
- Elle est lue comme des données (`Import-PowerShellDataFile`), jamais exécutée. Un fichier
  illisible ou qui contient une valeur fausse est signalé, et les valeurs par défaut s'appliquent.

```powershell
@{
    NewGpo = @{
        Status = 'ComputerOnly'
        SecurityFilteringGroups = @{ Create = $true; Container = 'OU=GPO,OU=Groups' }
    }
    Workflow = @{ Enabled = $true; Creators = 'GPO-Tier1-Admins, GPO-Tier2-Admins' }
}
```

Chaque réglage est décrit dans [la référence de la configuration](../reference/configuration.md).

## La fenêtre Settings

**Settings** dans la barre d'outils liste chaque réglage avec sa valeur, sa valeur par défaut et
l'origine de la valeur. Choisissez un réglage, donnez sa valeur, **Set the value**, ou **Remove**
pour revenir à sa valeur par défaut ; **Save** écrit le fichier, refusé à un compte qui n'est pas
administrateur du domaine. Une valeur est vérifiée avec les autres avant d'être retenue.

![La fenêtre Settings](../assets/screenshots/09-configuration-window.png)

Un annuaire qu'on ne peut pas écrire (l'environnement de démonstration) montre sa configuration
sans l'enregistrer.

## Quand elle est lue

Avec le domaine (`Get-PSGPODirectory`), à l'ouverture de la fenêtre ou de la fenêtre Settings, et
par chaque commande à laquelle on donne un annuaire. `Get-PSGPOConfiguration` montre d'où elle
vient :

```powershell
Get-PSGPOConfiguration -Server dc.hardenbox.labo | Format-List DefaultPath, Domain, DomainPath, DomainFileExists, Problem
```
