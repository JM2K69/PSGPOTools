# Well-known accounts

The accounts every computer has, and those every domain has by their RID, as HGPM knows them: the
same table names the SIDs of a GPO (the user rights, the restricted groups, the delegation), finds
the names typed, and gives the suggestions while typing and the completion of the commands
([policy editor](../features/policy-editor.md#accounts-and-sids)).

- A name is found in English or in French, short (`Administrators`) or with what Windows writes
  before it (`BUILTIN\Administrators`, `NT AUTHORITY\SYSTEM`, `AUTORITE NT\Système`).
- An account of the domain (`DOMAIN`) has the SID of the domain before its RID: the console reads
  it from the domain. When the domain names it in another language (`Admins du domaine` on a
  French domain controller), the name of the other language is found by its RID all the same.
- Enterprise Admins, Schema Admins, Enterprise Key Admins and Enterprise Read-only Domain
  Controllers are of the root domain of the forest.
- `GptTmpl.inf` writes an account as its SID (`*S-1-5-32-544`), as GPMC does: the same on every
  computer, whatever its language.

| SID | Before the name | Name | French name |
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
| `<domain SID>-498` | DOMAIN | Enterprise Read-only Domain Controllers | Contrôleurs de domaine d'entreprise en lecture seule |
| `<domain SID>-500` | DOMAIN | Administrator | Administrateur |
| `<domain SID>-501` | DOMAIN | Guest | Invité |
| `<domain SID>-502` | DOMAIN | krbtgt | krbtgt |
| `<domain SID>-512` | DOMAIN | Domain Admins | Admins du domaine |
| `<domain SID>-513` | DOMAIN | Domain Users | Utilisateurs du domaine |
| `<domain SID>-514` | DOMAIN | Domain Guests | Invités du domaine |
| `<domain SID>-515` | DOMAIN | Domain Computers | Ordinateurs du domaine |
| `<domain SID>-516` | DOMAIN | Domain Controllers | Contrôleurs de domaine |
| `<domain SID>-517` | DOMAIN | Cert Publishers | Éditeurs de certificats |
| `<domain SID>-518` | DOMAIN | Schema Admins | Administrateurs du schéma |
| `<domain SID>-519` | DOMAIN | Enterprise Admins | Administrateurs de l'entreprise |
| `<domain SID>-520` | DOMAIN | Group Policy Creator Owners | Propriétaires créateurs de la stratégie de groupe |
| `<domain SID>-521` | DOMAIN | Read-only Domain Controllers | Contrôleurs de domaine en lecture seule |
| `<domain SID>-522` | DOMAIN | Cloneable Domain Controllers | Contrôleurs de domaine clonables |
| `<domain SID>-525` | DOMAIN | Protected Users | Protected Users |
| `<domain SID>-526` | DOMAIN | Key Admins | Administrateurs clés |
| `<domain SID>-527` | DOMAIN | Enterprise Key Admins | Administrateurs clés Enterprise |
| `<domain SID>-553` | DOMAIN | RAS and IAS Servers | Serveurs RAS et IAS |
| `<domain SID>-571` | DOMAIN | Allowed RODC Password Replication Group | Groupe de réplication dont le mot de passe RODC est autorisé |
| `<domain SID>-572` | DOMAIN | Denied RODC Password Replication Group | Groupe de réplication dont le mot de passe RODC est refusé |
