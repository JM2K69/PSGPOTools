# Corbeille et modèles

## Supprimer une GPO, et la récupérer

1. Clic droit sur la GPO dans **Group Policy Objects** > **Delete GPO...** : la confirmation liste
   ses liens, supprimés avec elle, et le dossier où elle est d'abord sauvegardée.
2. **Delete GPO**. Elle passe dans **Deleted GPOs**, sa dernière sauvegarde disant quand et par qui.

![Supprimer une GPO](../assets/screenshots/08-delete-gpo.png)

3. Plus tard : **Deleted GPOs** > la GPO > **Restore this GPO...** (ou **Restore...** dans son
   menu).
4. Laissez **Link it again where it was** coché, **Restore**.

![Restaurer une GPO supprimée](../assets/screenshots/07-deleted-gpo.png)

La GPO revient avec un **nouveau GUID**, son nom, ses paramètres, son statut et ses extensions côté
client. Elle est reliée à ses OU qui existent encore, si son filtrage de sécurité était
Authenticated Users et ses liens activés ; sinon la console dit ce qu'il faut régler avant de la
lier.

```powershell
Remove-PSGPO -Server dc.hardenbox.labo -Name 'Demo - Printers' -BackupPath /srv/gpo-backups
Get-PSGPOBackup -Server dc.hardenbox.labo -Path /srv/gpo-backups -Deleted |
    Where-Object DisplayName -EQ 'Demo - Printers' | Restore-PSGPO -Server dc.hardenbox.labo -RestoreLink
```

## Partir d'un modèle pour les nouvelles GPO

1. Construisez une GPO avec les paramètres que chaque nouvelle GPO doit avoir, et sauvegardez-la.
2. Onglet **History** > sélectionnez sa sauvegarde > cochez **Template** > **Save notes**.
3. Clic droit sur une OU > **Create a GPO in this domain, and Link it here...** > **Start from** :
   le modèle.

La nouvelle GPO part des paramètres du modèle, vérifiés par leur SHA-256 ; son statut, ses groupes
de filtrage et son lien sont ceux du formulaire. Un modèle peut venir d'un autre domaine : un
domaine de test prépare les modèles de base de la production.

```powershell
$Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
New-PSGPO -Server dc.hardenbox.labo -Name 'T1 - Servers - Lyon' -Template $Template
```
