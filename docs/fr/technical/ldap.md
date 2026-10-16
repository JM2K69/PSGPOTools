# L'annuaire (LDAP)

La console lit et écrit l'annuaire avec **System.DirectoryServices.Protocols** : wldap32 sous
Windows, la bibliothèque OpenLDAP (`libldap`) sous Linux, face aux contrôleurs de domaine Windows
comme Samba.

## Connexion

| | |
|---|---|
| Windows | Negotiate (Kerberos) avec l'identité de la session, ou `-Credential` |
| Linux | SASL GSSAPI avec le ticket Kerberos de la session (`kinit`) : la signature et le chiffrement viennent de la couche SASL |
| `-Credential` | LDAPS seulement (`-UseSsl`) : un mot de passe n'est jamais envoyé en LDAP en clair |
| Serveur | son nom DNS : Kerberos demande le service `ldap/<dc>` |

`Get-PSGPOLdapErrorMessage` traduit les erreurs LDAP en ce qu'il faut faire : pas de ticket
(`kinit`), module SASL GSSAPI absent, adresse IP donnée au lieu d'un nom, serveur injoignable.

## Ce qui est lu

`Get-PSGPODirectory` lit, en quelques recherches paginées :

| Objet | Attributs |
|---|---|
| rootDSE | `defaultNamingContext`, `dnsHostName`, `vendorName` (Samba le renseigne : `Samba AD`) |
| le domaine | `gPLink`, `gPOptions`, `wellKnownObjects` (le conteneur des utilisateurs), `allowedAttributesEffective` |
| les OU | `name`, `gPLink`, `gPOptions`, `allowedAttributesEffective` |
| `CN=Policies` | `allowedChildClassesEffective` (le compte peut-il créer des GPO) |
| les GPO | `displayName`, `versionNumber`, `flags`, `gPCFileSysPath`, `whenChanged`, `gPC*ExtensionNames`, `allowedAttributesEffective`, `nTSecurityDescriptor` (DACL : filtrage de sécurité ; propriétaire : état d'approbation) |

Le compte connecté vient de l'opération étendue « Who am I? » (RFC 4532,
`1.3.6.1.4.1.4203.1.11.3`) ; ses groupes, pour le workflow d'approbation, de `tokenGroups` (groupes
imbriqués compris).

## gPLink

Un `gPLink` est une liste de `[LDAP://<DN de la GPO>;<options>]`, **la dernière étant l'ordre de
lien 1** ; le bit 0 des options désactive le lien, le bit 1 l'applique (enforced). Un lien dont la
GPO manque est conservé et affiché. La console ajoute un lien en tête de la valeur (la plus faible
priorité), et en retire un en gardant les autres tels quels. L'écriture est une seule requête de
modification **qui retire l'ancienne valeur et ajoute la nouvelle** : le serveur la refuse si la
valeur a changé entre-temps, et la console relit les liens que le domaine contient.

## Descripteurs de sécurité

`nTSecurityDescriptor` est lu et écrit avec le **contrôle SD flags** (`1.2.840.113556.1.4.801`) :
seules les parties nécessaires (DACL ; propriétaire et DACL pour une approbation), si bien que la
SACL, qui demande un privilège, n'est jamais demandée. Le descripteur est lu et écrit par la
console elle-même ([descripteurs de sécurité](security-descriptors.md)).

## Groupes

Les groupes de filtrage de sécurité sont créés en LDAP (`group`, `groupType` de la configuration :
Global `-2147483646`, DomainLocal `-2147483644`, Universal `-2147483640`), avec leur description.

## GPO

La création et la suppression d'une GPO passent par les outils de la plateforme (`New-GPO` /
`Remove-GPO`, `samba-tool gpo create / del`), qui créent ou suppriment son conteneur **et** son
dossier SYSVOL avec leurs droits, comme GPMC. Ensuite la console lit la GPO telle que l'annuaire
l'a, ou vérifie qu'elle a disparu (une recherche d'un objet absent ne renvoie rien avec
`-AllowMissing`).
