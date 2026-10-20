# HGPM

**HGPM** est une console de gestion des stratégies de groupe, dans l'esprit de GPMC, écrite
en PowerShell 7 avec une interface [Avalonia](https://avaloniaui.net/). Elle fonctionne sous
**Windows et Linux**, et gère aussi bien les GPO des domaines **Samba AD** que ceux d'**Active
Directory**.

![La vue Group Policy Management sur un domaine Samba AD](assets/screenshots/01-console-domain.png)

## Ce qu'elle fait

<div class="grid cards" markdown>

- **Vue Group Policy Management**

    Le domaine, ses OU et leurs liens de GPO, les Group Policy Objects, comme GPMC les montre :
    créer, lier, supprimer et restaurer des GPO, appliquer (Enforced), désactiver et ordonner leurs liens, bloquer l'héritage, régler leur statut et leur filtrage de sécurité.
    [La console](features/console.md)

- **Éditeur de stratégies**

    Les modèles d'administration (ADMX/ADML), les paramètres de sécurité (GptTmpl.inf) et les
    préférences de stratégie de groupe d'une GPO, lus dans SYSVOL et enregistrés là.
    [L'éditeur de stratégies](features/policy-editor.md)

- **Historique et approbation**

    Des sauvegardes avec commentaires et étiquettes, la frise de chaque GPO, les différences entre
    deux versions, la restauration, l'écart avec la version approuvée, et un workflow
    d'approbation Tier 0 / Tier 1.
    [Sauvegardes et historique](features/backup-history.md)

- **Les droits du domaine**

    La console montre ce que le compte gère (ses délégations), la configuration est celle du
    domaine (SYSVOL), et le workflow ne repose que sur les ACL de l'annuaire et de SYSVOL.
    [Délégation](features/delegation.md)

- **Stratégies de mot de passe (PSO)**

    Une deuxième console, `Show-PSOManagerAvalonia`, pour les stratégies de mot de passe affinées,
    comme le Centre d'administration Active Directory : les créer, les appliquer, et voir celle qui
    s'applique à un utilisateur ou à un groupe, et pourquoi.
    [Stratégies de mot de passe](features/password-policies.md)

</div>

## En bref

| | |
|---|---|
| **Fonctionne sous** | Windows 10/11 et Server, Linux (Debian, Ubuntu, RHEL…), avec PowerShell 7.4 ou plus |
| **Domaines** | Samba AD (4.x) et Active Directory (contrôleurs de domaine Windows Server) |
| **Annuaire** | LDAP (System.DirectoryServices.Protocols), Kerberos ; LDAPS avec un mot de passe |
| **SYSVOL** | le chemin UNC sous Windows ; `smbclient` et les bindings Python de Samba sous Linux |
| **Création et suppression de GPO** | RSAT (`New-GPO`, `Remove-GPO`) sous Windows ; `samba-tool` sous Linux |
| **Interface** | Avalonia 11, installé à la première ouverture de la fenêtre |

## Par où commencer

1. [Installer le module](getting-started/installation.md) et ce qu'il demande sur votre plateforme.
2. [Ouvrir la console](getting-started/first-steps.md) sur votre domaine.
3. Suivre un [workflow](workflows/index.md) : créer et lier une GPO, la sauvegarder et la
   restaurer, faire approuver les GPO des techniciens Tier 1.

Les captures de cette documentation viennent du [labo](getting-started/lab.md) : un domaine Samba
AD `hardenbox.labo` et un domaine Windows `powershell.labo`.
