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

## Le code d'une fenêtre

Chaque contrôle nommé d'une fenêtre (`Name='...'` dans son XAML) est dans une variable de son nom
(`$treeView`, `$applySettingButton`…), créée à partir du XAML en une boucle
(`Get-PSGPOAvaloniaNamedControl`), et non une ligne par contrôle. La console GPO est découpée par
vue : `Start-PSGPOManagerWindow` construit la fenêtre, puis dot-source chaque vue
(`Initialize-PSGPOManagerSettingView`, `...HistoryView`, `...WmiFilterView`…), un fichier chacune,
dont l'état, les fonctions et les gestionnaires vivent dans la portée de la fenêtre tant qu'elle
est ouverte.

Une variable mal orthographiée ne serait que `$null` à l'exécution :
`PSGPOTools.WindowCode.tests.ps1` lit le code de la console (son arbre syntaxique) et échoue sur
une variable lue qui n'est ni affectée ni un contrôle de son XAML.

## Une erreur qu'aucun gestionnaire n'a traitée

Une erreur qui sort d'un gestionnaire (un clic, une minuterie, une action postée) ne ferme pas la
fenêtre : la boucle de chaque fenêtre (`Invoke-PSGPOWindowLoop -KeepOpenOnError`) la reçoit de
`Dispatcher.UIThread.UnhandledException`, l'affiche dans une notification de la fenêtre (en haut à
droite, pendant 30 secondes) et l'écrit dans le journal technique (`ERROR`, avec le script et la
ligne où elle s'est produite). La même erreur répétée dans les 5 secondes n'est dite qu'une fois.
Les tests de l'interface ouvrent les fenêtres sans elle : une erreur y arrête la boucle et fait
échouer le test.

## Les opérations longues en arrière-plan { #les-operations-longues-en-arriere-plan }

La console GPO lit et écrit des choses qui prennent des secondes ou des minutes : Actualiser (F5)
et Changer de contrôleur de domaine..., Détecter maintenant (onglet État), Sauvegarder et Tout
sauvegarder (onglet Historique), Enregistrer le rapport.... Elles tournent dans un worker de la
console : un runspace à lui, ouvert au démarrage de la console, où HGPM est importé une fois
(quelques secondes sous Windows, où le module est analysé ; la première opération l'attend). La
fenêtre reste dessinée et répond : un bandeau dit ce qui tourne, l'arbre et les détails du domaine
attendent (aucune autre modification ne commence entre-temps), et **Annuler** arrête une lecture
(pas une sauvegarde, qui écrit et n'est pas laissée à moitié).

Le bloc d'une opération tourne dans la portée du module, dans le worker : il trouve les fonctions de
HGPM, et ce dont il a besoin de la fenêtre lui est passé en arguments. Les objets de HGPM vont au
worker et en reviennent tels quels, ses classes étant les mêmes types dans les deux runspaces ; le
worker reçoit la langue et la configuration du domaine de la fenêtre au début de l'opération, et les
fichiers ADMX chargés sont des membres statiques, déjà partagés (`PSGPOWindowOperation.ps1`,
`Initialize-PSGPOManagerOperationView`). Les tests de l'interface exécutent plutôt les opérations
sur le fil de la fenêtre, où sont leurs mocks ; le worker a ses propres tests (un résultat, une
erreur, une annulation, une seconde opération refusée).

!!! note "Les classes et les runspaces"
    Une méthode d'une classe de HGPM qui appelle le module s'exécute dans le runspace qui a défini
    la classe, celui de la fenêtre, même quand le worker l'appelle (la lecture des fichiers d'une
    GPO pour un rapport). Ce runspace ne prend un tel appel qu'entre deux commandes de son
    pipeline, jamais pendant la boucle de la fenêtre : le worker attendait sans fin. Pendant une
    opération, sa minuterie exécute `Start-Sleep -Milliseconds 0` toutes les 5 ms, ce qui permet
    à la fenêtre de les prendre. Les classes gardent leur affinité : avec `[NoRunspaceAffinity()]`,
    leurs méthodes chercheraient les fonctions du module dans la session de l'appelant, où une
    closure ou un script de l'utilisateur ne les a pas. Vérifié sur le labo Samba et le labo
    Windows : Actualiser, Détecter maintenant et un rapport dans le worker, la fenêtre répondant
    pendant ce temps.

## Tests de la fenêtre

`Start-PSGPOManagerWindow -OnShown { param($Ui) ... }` (et `Start-PSGPOPasswordPolicyWindow` pour
la console des PSO, sa fenêtre d'un PSO dans `$Ui.Editor`) ouvre la vraie fenêtre et exécute le bloc
une fois qu'elle est affichée, avec ses contrôles par nom : les tests de l'interface cliquent,
saisissent et vérifient ce que montre la fenêtre, puis la fenêtre se ferme. Ils tournent sous
Windows et dans la session X d'un ordinateur Linux.
