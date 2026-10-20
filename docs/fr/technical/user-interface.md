# L'interface

## Avalonia depuis PowerShell

La fenêtre est en [Avalonia 11](https://avaloniaui.net/), hébergée par PowerShell 7 :

- le **XAML** de chaque fenêtre est une chaîne, lue à l'exécution
  (`AvaloniaRuntimeXamlLoader.Parse`) : aucune assembly compilée dans le module ;
- l'application est démarrée une fois par session, et la fenêtre fait tourner sa propre boucle de
  messages (`Dispatcher.UIThread.MainLoop`) jusqu'à sa fermeture : l'appel bloque, comme une
  console modale ;
- les données des listes et des arbres sont de petites classes PowerShell (`AvaloniaTreeNode`,
  `AvaloniaHistoryNode`, `AvaloniaConfigurationRow`…) : Avalonia se lie à leurs propriétés.

## Le runtime

`Resources/AvaloniaPackages.json` épingle les 21 paquets NuGet de la fenêtre (Avalonia, Skia,
HarfBuzz, leurs fichiers natifs par runtime) avec le SHA-512 du catalogue nuget.org. À la première
ouverture d'une fenêtre, la console télécharge les paquets du runtime de l'ordinateur, vérifie
chaque empreinte avant d'extraire quoi que ce soit, les prépare, puis les met en place d'un coup :
dans le dossier du module quand on peut y écrire, sinon dans le dossier de données de
l'utilisateur.

## Arbres et détails sans fenêtre

`New-PSGPODirectoryTree`, `New-PSGPOPolicyTree` et `Get-PSGPODirectoryDetail` construisent ce que
montre la fenêtre (nœuds, icônes, libellés, détails) sans aucun type Avalonia : ils sont testés sans
interface.

## Icônes

[Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons) (MIT), taille 20,
style regular, dans `Resources/Icons` : la fenêtre lit le tracé de chaque SVG comme une géométrie
Avalonia, disponible en XAML sous `{StaticResource Icon.<nom>}`. Des emoji étaient utilisés avant,
mais la plupart des bureaux Linux n'ont pas de police pour les dessiner.

## Pièges rencontrés

!!! note "Les fermetures (closures)"
    Un gestionnaire créé avec `GetNewClosure()` tourne dans un nouveau module dynamique : il ne
    voit plus les fonctions privées du module, ni ses classes. Les gestionnaires capturent d'abord
    ce qu'ils appellent (`$Save = ${function:Save-PSGPODomainConfiguration}`,
    `$RowType = [AvaloniaConfigurationRow]`).

!!! note "Le pipeline"
    La sortie du pipeline enveloppe les objets dans `PSObject`, auquel Avalonia ne sait pas se lier :
    les listes sont construites avec `List[T]` et `foreach`. `if (...) { @(...) }` déroule une liste
    d'un seul élément : les listes sont affectées dans les branches. `Select-Object` enveloppe aussi
    ses objets : une liste faite avec lui prend `.PSObject.BaseObject` de chaque élément.

!!! note "Le bouton de la vue affichée"
    La classe `accent` du thème Fluent ne colore pas un bouton ici : les fenêtres partagent le
    style `Button.active` (`Get-PSGPOWindowResourceXaml`, avec les pinceaux des deux thèmes).

## Tests de la fenêtre

`Start-PSGPOManagerWindow -OnShown { param($Ui) ... }` (et `Start-PSGPOPasswordPolicyWindow` pour
la console des PSO, sa fenêtre d'un PSO dans `$Ui.Editor`) ouvre la vraie fenêtre et exécute le bloc
une fois qu'elle est affichée, avec ses contrôles par nom : les tests de l'interface cliquent,
saisissent et vérifient ce que montre la fenêtre, puis la fenêtre se ferme. Ils tournent sous
Windows et dans la session X d'un ordinateur Linux.
