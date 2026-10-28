# Comptes bien connus

Les comptes de tout ordinateur, et ceux de tout domaine par leur RID, tels que HGPM les connaît :
la même table nomme les SID d'une GPO (droits utilisateur, groupes restreints, délégation), trouve
les noms saisis, et donne les suggestions pendant la frappe et la complétion des commandes
([éditeur de stratégies](../features/policy-editor.md#accounts-and-sids)).

- Un nom est trouvé en anglais ou en français, court (`Administrateurs`) ou avec ce que Windows
  écrit avant (`BUILTIN\Administrateurs`, `AUTORITE NT\Système`, `NT AUTHORITY\SYSTEM`).
- Un compte du domaine (`DOMAIN`) a le SID du domaine avant son RID : la console le lit dans le
  domaine. Quand le domaine le nomme dans une autre langue (`Domain Admins` sur un contrôleur de
  domaine anglais), le nom de l'autre langue est trouvé par son RID tout de même.
- Administrateurs de l'entreprise, Administrateurs du schéma, Administrateurs clés Enterprise et
  Contrôleurs de domaine d'entreprise en lecture seule sont du domaine racine de la forêt.
- `GptTmpl.inf` écrit un compte par son SID (`*S-1-5-32-544`), comme GPMC : le même sur chaque
  ordinateur, quelle que soit sa langue.

| SID | Avant le nom | Nom | Nom français |
|---|---|---|---|
| `S-1-1-0` |  | Everyone | Tout le monde |
| `S-1-3-0` |  | CREATOR OWNER | CREATEUR PROPRIETAIRE |
| `S-1-3-1` |  | CREATOR GROUP | GROUPE CREATEUR |
| `S-1-5-2` | NT AUTHORITY | NETWORK | RESEAU |
| `S-1-5-3` | NT AUTHORITY | BATCH | TACHE |
| `S-1-5-4` | NT AUTHORITY | INTERACTIVE | INTERACTIF |
| `S-1-5-6` | NT AUTHORITY | SERVICE | SERVICE |
| `S-1-5-7` | NT AUTHORITY | ANONYMOUS LOGON | ANONYMOUS LOGON |
| `S-1-5-9` | NT AUTHORITY | ENTERPRISE DOMAIN CONTROLLERS | CONTROLEURS DE DOMAINE D'ENTREPRISE |
| `S-1-5-10` | NT AUTHORITY | SELF | SELF |
| `S-1-5-11` | NT AUTHORITY | Authenticated Users | Utilisateurs authentifiés |
| `S-1-5-13` | NT AUTHORITY | TERMINAL SERVER USER | UTILISATEUR TERMINAL SERVER |
| `S-1-5-14` | NT AUTHORITY | REMOTE INTERACTIVE LOGON | OUVERTURE DE SESSION INTERACTIVE A DISTANCE |
| `S-1-5-17` | NT AUTHORITY | IUSR | IUSR |
| `S-1-5-18` | NT AUTHORITY | SYSTEM | Système |
| `S-1-5-19` | NT AUTHORITY | LOCAL SERVICE | SERVICE LOCAL |
| `S-1-5-20` | NT AUTHORITY | NETWORK SERVICE | SERVICE RÉSEAU |
| `S-1-5-113` | NT AUTHORITY | Local account | Compte local |
| `S-1-5-114` | NT AUTHORITY | Local account and member of Administrators group | Compte local et membre du groupe Administrateurs |
| `S-1-5-32-544` | BUILTIN | Administrators | Administrateurs |
| `S-1-5-32-545` | BUILTIN | Users | Utilisateurs |
| `S-1-5-32-546` | BUILTIN | Guests | Invités |
| `S-1-5-32-547` | BUILTIN | Power Users | Utilisateurs avec pouvoir |
| `S-1-5-32-548` | BUILTIN | Account Operators | Opérateurs de compte |
| `S-1-5-32-549` | BUILTIN | Server Operators | Opérateurs de serveur |
| `S-1-5-32-550` | BUILTIN | Print Operators | Opérateurs d'impression |
| `S-1-5-32-551` | BUILTIN | Backup Operators | Opérateurs de sauvegarde |
| `S-1-5-32-552` | BUILTIN | Replicator | Duplicateurs |
| `S-1-5-32-554` | BUILTIN | Pre-Windows 2000 Compatible Access | Accès compatible pré-Windows 2000 |
| `S-1-5-32-555` | BUILTIN | Remote Desktop Users | Utilisateurs du Bureau à distance |
| `S-1-5-32-556` | BUILTIN | Network Configuration Operators | Opérateurs de configuration réseau |
| `S-1-5-32-557` | BUILTIN | Incoming Forest Trust Builders | Générateurs d'approbations de forêt entrante |
| `S-1-5-32-558` | BUILTIN | Performance Monitor Users | Utilisateurs de l'Analyseur de performances |
| `S-1-5-32-559` | BUILTIN | Performance Log Users | Utilisateurs du journal de performances |
| `S-1-5-32-560` | BUILTIN | Windows Authorization Access Group | Groupe d'accès d'autorisation Windows |
| `S-1-5-32-561` | BUILTIN | Terminal Server License Servers | Serveurs de licences des services Terminal Server |
| `S-1-5-32-562` | BUILTIN | Distributed COM Users | Utilisateurs du modèle COM distribué |
| `S-1-5-32-568` | BUILTIN | IIS_IUSRS | IIS_IUSRS |
| `S-1-5-32-569` | BUILTIN | Cryptographic Operators | Opérateurs de chiffrement |
| `S-1-5-32-573` | BUILTIN | Event Log Readers | Lecteurs des journaux d'événements |
| `S-1-5-32-574` | BUILTIN | Certificate Service DCOM Access | Accès DCOM service de certificats |
| `S-1-5-32-575` | BUILTIN | RDS Remote Access Servers | Serveurs RDS Remote Access |
| `S-1-5-32-576` | BUILTIN | RDS Endpoint Servers | Serveurs RDS Endpoint |
| `S-1-5-32-577` | BUILTIN | RDS Management Servers | Serveurs RDS Management |
| `S-1-5-32-578` | BUILTIN | Hyper-V Administrators | Administrateurs Hyper-V |
| `S-1-5-32-579` | BUILTIN | Access Control Assistance Operators | Opérateurs d'assistance de contrôle d'accès |
| `S-1-5-32-580` | BUILTIN | Remote Management Users | Utilisateurs de gestion à distance |
| `S-1-5-80-0` | NT SERVICE | ALL SERVICES | TOUS LES SERVICES |
| `S-1-5-83-0` | NT VIRTUAL MACHINE | Virtual Machines | Ordinateurs virtuels |
| `S-1-5-90-0` | Window Manager | Window Manager Group | Groupe Gestionnaire de fenêtres |
| `S-1-15-2-1` | APPLICATION PACKAGE AUTHORITY | ALL APPLICATION PACKAGES | TOUS LES PACKAGES D'APPLICATION |
| `<SID du domaine>-498` | DOMAIN | Enterprise Read-only Domain Controllers | Contrôleurs de domaine d'entreprise en lecture seule |
| `<SID du domaine>-500` | DOMAIN | Administrator | Administrateur |
| `<SID du domaine>-501` | DOMAIN | Guest | Invité |
| `<SID du domaine>-502` | DOMAIN | krbtgt | krbtgt |
| `<SID du domaine>-512` | DOMAIN | Domain Admins | Admins du domaine |
| `<SID du domaine>-513` | DOMAIN | Domain Users | Utilisateurs du domaine |
| `<SID du domaine>-514` | DOMAIN | Domain Guests | Invités du domaine |
| `<SID du domaine>-515` | DOMAIN | Domain Computers | Ordinateurs du domaine |
| `<SID du domaine>-516` | DOMAIN | Domain Controllers | Contrôleurs de domaine |
| `<SID du domaine>-517` | DOMAIN | Cert Publishers | Éditeurs de certificats |
| `<SID du domaine>-518` | DOMAIN | Schema Admins | Administrateurs du schéma |
| `<SID du domaine>-519` | DOMAIN | Enterprise Admins | Administrateurs de l'entreprise |
| `<SID du domaine>-520` | DOMAIN | Group Policy Creator Owners | Propriétaires créateurs de la stratégie de groupe |
| `<SID du domaine>-521` | DOMAIN | Read-only Domain Controllers | Contrôleurs de domaine en lecture seule |
| `<SID du domaine>-522` | DOMAIN | Cloneable Domain Controllers | Contrôleurs de domaine clonables |
| `<SID du domaine>-525` | DOMAIN | Protected Users | Protected Users |
| `<SID du domaine>-526` | DOMAIN | Key Admins | Administrateurs clés |
| `<SID du domaine>-527` | DOMAIN | Enterprise Key Admins | Administrateurs clés Enterprise |
| `<SID du domaine>-553` | DOMAIN | RAS and IAS Servers | Serveurs RAS et IAS |
| `<SID du domaine>-571` | DOMAIN | Allowed RODC Password Replication Group | Groupe de réplication dont le mot de passe RODC est autorisé |
| `<SID du domaine>-572` | DOMAIN | Denied RODC Password Replication Group | Groupe de réplication dont le mot de passe RODC est refusé |
