<#
    The well-known accounts of Windows and of Active Directory ([MS-DTYP] 2.4.2.4): the SIDs every
    computer knows (Everyone, NT AUTHORITY, BUILTIN...), and the accounts every domain has by their
    RID (Domain Admins is <domain SID>-512). One table for the names shown and the names typed: the
    name of an English Windows, and the one of a French Windows (Administrateurs, Admins du domaine),
    so that a name of either is found whatever the language of the domain controller.
#>
class GPOToolsWellKnownSid {
    # S-1-5-32-544; an account of the domain by its RID, with a dash: -512
    [string]$Sid
    # What Windows writes before the name: NT AUTHORITY, BUILTIN, NT SERVICE...; empty for
    # Everyone or CREATOR OWNER; DOMAIN for an account of the domain (its NetBIOS name then)
    [string]$Authority
    [string]$Name
    [string]$FrenchName

    GPOToolsWellKnownSid([string]$Sid, [string]$Authority, [string]$Name, [string]$FrenchName) {
        $this.Sid = $Sid
        $this.Authority = $Authority
        $this.Name = $Name
        $this.FrenchName = $FrenchName
    }

    [bool] IsDomainAccount() { return $this.Sid.StartsWith('-') }

    # Its SID in a domain (an account of the domain needs the SID of the domain; $null without it).
    [string] GetSid([string]$DomainSid) {
        if (-not $this.IsDomainAccount()) { return $this.Sid }
        if (-not $DomainSid) { return $null }
        return $DomainSid + $this.Sid
    }

    # BUILTIN\Administrators, NT AUTHORITY\SYSTEM, Everyone, CONTOSO\Domain Admins (its domain when given).
    [string] GetQualifiedName([string]$Domain) {
        $Prefix = if ($this.IsDomainAccount()) { $Domain } else { $this.Authority }
        if ($Prefix) { return "$Prefix\$($this.Name)" }
        return $this.Name
    }

    static [GPOToolsWellKnownSid[]] $All = @(
        # Every computer.
        [GPOToolsWellKnownSid]::new('S-1-1-0', '', 'Everyone', 'Tout le monde')
        [GPOToolsWellKnownSid]::new('S-1-3-0', '', 'CREATOR OWNER', 'CREATEUR PROPRIETAIRE')
        [GPOToolsWellKnownSid]::new('S-1-3-1', '', 'CREATOR GROUP', 'GROUPE CREATEUR')
        [GPOToolsWellKnownSid]::new('S-1-5-2', 'NT AUTHORITY', 'NETWORK', 'RESEAU')
        [GPOToolsWellKnownSid]::new('S-1-5-3', 'NT AUTHORITY', 'BATCH', 'TACHE')
        [GPOToolsWellKnownSid]::new('S-1-5-4', 'NT AUTHORITY', 'INTERACTIVE', 'INTERACTIF')
        [GPOToolsWellKnownSid]::new('S-1-5-6', 'NT AUTHORITY', 'SERVICE', 'SERVICE')
        [GPOToolsWellKnownSid]::new('S-1-5-7', 'NT AUTHORITY', 'ANONYMOUS LOGON', 'ANONYMOUS LOGON')
        [GPOToolsWellKnownSid]::new('S-1-5-9', 'NT AUTHORITY', 'ENTERPRISE DOMAIN CONTROLLERS', "CONTROLEURS DE DOMAINE D'ENTREPRISE")
        [GPOToolsWellKnownSid]::new('S-1-5-10', 'NT AUTHORITY', 'SELF', 'SELF')
        [GPOToolsWellKnownSid]::new('S-1-5-11', 'NT AUTHORITY', 'Authenticated Users', 'Utilisateurs authentifiés')
        [GPOToolsWellKnownSid]::new('S-1-5-13', 'NT AUTHORITY', 'TERMINAL SERVER USER', 'UTILISATEUR TERMINAL SERVER')
        [GPOToolsWellKnownSid]::new('S-1-5-14', 'NT AUTHORITY', 'REMOTE INTERACTIVE LOGON', 'OUVERTURE DE SESSION INTERACTIVE A DISTANCE')
        [GPOToolsWellKnownSid]::new('S-1-5-17', 'NT AUTHORITY', 'IUSR', 'IUSR')
        [GPOToolsWellKnownSid]::new('S-1-5-18', 'NT AUTHORITY', 'SYSTEM', 'Système')
        [GPOToolsWellKnownSid]::new('S-1-5-19', 'NT AUTHORITY', 'LOCAL SERVICE', 'SERVICE LOCAL')
        [GPOToolsWellKnownSid]::new('S-1-5-20', 'NT AUTHORITY', 'NETWORK SERVICE', 'SERVICE RÉSEAU')
        [GPOToolsWellKnownSid]::new('S-1-5-113', 'NT AUTHORITY', 'Local account', 'Compte local')
        [GPOToolsWellKnownSid]::new('S-1-5-114', 'NT AUTHORITY', 'Local account and member of Administrators group', 'Compte local et membre du groupe Administrateurs')
        [GPOToolsWellKnownSid]::new('S-1-5-32-544', 'BUILTIN', 'Administrators', 'Administrateurs')
        [GPOToolsWellKnownSid]::new('S-1-5-32-545', 'BUILTIN', 'Users', 'Utilisateurs')
        [GPOToolsWellKnownSid]::new('S-1-5-32-546', 'BUILTIN', 'Guests', 'Invités')
        [GPOToolsWellKnownSid]::new('S-1-5-32-547', 'BUILTIN', 'Power Users', 'Utilisateurs avec pouvoir')
        [GPOToolsWellKnownSid]::new('S-1-5-32-548', 'BUILTIN', 'Account Operators', 'Opérateurs de compte')
        [GPOToolsWellKnownSid]::new('S-1-5-32-549', 'BUILTIN', 'Server Operators', 'Opérateurs de serveur')
        [GPOToolsWellKnownSid]::new('S-1-5-32-550', 'BUILTIN', 'Print Operators', "Opérateurs d'impression")
        [GPOToolsWellKnownSid]::new('S-1-5-32-551', 'BUILTIN', 'Backup Operators', 'Opérateurs de sauvegarde')
        [GPOToolsWellKnownSid]::new('S-1-5-32-552', 'BUILTIN', 'Replicator', 'Duplicateurs')
        [GPOToolsWellKnownSid]::new('S-1-5-32-554', 'BUILTIN', 'Pre-Windows 2000 Compatible Access', 'Accès compatible pré-Windows 2000')
        [GPOToolsWellKnownSid]::new('S-1-5-32-555', 'BUILTIN', 'Remote Desktop Users', 'Utilisateurs du Bureau à distance')
        [GPOToolsWellKnownSid]::new('S-1-5-32-556', 'BUILTIN', 'Network Configuration Operators', 'Opérateurs de configuration réseau')
        [GPOToolsWellKnownSid]::new('S-1-5-32-557', 'BUILTIN', 'Incoming Forest Trust Builders', "Générateurs d'approbations de forêt entrante")
        [GPOToolsWellKnownSid]::new('S-1-5-32-558', 'BUILTIN', 'Performance Monitor Users', "Utilisateurs de l'Analyseur de performances")
        [GPOToolsWellKnownSid]::new('S-1-5-32-559', 'BUILTIN', 'Performance Log Users', 'Utilisateurs du journal de performances')
        [GPOToolsWellKnownSid]::new('S-1-5-32-560', 'BUILTIN', 'Windows Authorization Access Group', "Groupe d'accès d'autorisation Windows")
        [GPOToolsWellKnownSid]::new('S-1-5-32-561', 'BUILTIN', 'Terminal Server License Servers', 'Serveurs de licences des services Terminal Server')
        [GPOToolsWellKnownSid]::new('S-1-5-32-562', 'BUILTIN', 'Distributed COM Users', 'Utilisateurs du modèle COM distribué')
        [GPOToolsWellKnownSid]::new('S-1-5-32-568', 'BUILTIN', 'IIS_IUSRS', 'IIS_IUSRS')
        [GPOToolsWellKnownSid]::new('S-1-5-32-569', 'BUILTIN', 'Cryptographic Operators', 'Opérateurs de chiffrement')
        [GPOToolsWellKnownSid]::new('S-1-5-32-573', 'BUILTIN', 'Event Log Readers', "Lecteurs des journaux d'événements")
        [GPOToolsWellKnownSid]::new('S-1-5-32-574', 'BUILTIN', 'Certificate Service DCOM Access', 'Accès DCOM service de certificats')
        [GPOToolsWellKnownSid]::new('S-1-5-32-575', 'BUILTIN', 'RDS Remote Access Servers', 'Serveurs RDS Remote Access')
        [GPOToolsWellKnownSid]::new('S-1-5-32-576', 'BUILTIN', 'RDS Endpoint Servers', 'Serveurs RDS Endpoint')
        [GPOToolsWellKnownSid]::new('S-1-5-32-577', 'BUILTIN', 'RDS Management Servers', 'Serveurs RDS Management')
        [GPOToolsWellKnownSid]::new('S-1-5-32-578', 'BUILTIN', 'Hyper-V Administrators', 'Administrateurs Hyper-V')
        [GPOToolsWellKnownSid]::new('S-1-5-32-579', 'BUILTIN', 'Access Control Assistance Operators', "Opérateurs d'assistance de contrôle d'accès")
        [GPOToolsWellKnownSid]::new('S-1-5-32-580', 'BUILTIN', 'Remote Management Users', 'Utilisateurs de gestion à distance')
        [GPOToolsWellKnownSid]::new('S-1-5-80-0', 'NT SERVICE', 'ALL SERVICES', 'TOUS LES SERVICES')
        [GPOToolsWellKnownSid]::new('S-1-5-83-0', 'NT VIRTUAL MACHINE', 'Virtual Machines', 'Ordinateurs virtuels')
        [GPOToolsWellKnownSid]::new('S-1-5-90-0', 'Window Manager', 'Window Manager Group', 'Groupe Gestionnaire de fenêtres')
        [GPOToolsWellKnownSid]::new('S-1-15-2-1', 'APPLICATION PACKAGE AUTHORITY', 'ALL APPLICATION PACKAGES', "TOUS LES PACKAGES D'APPLICATION")
        # Every domain, by RID. Enterprise Admins, Schema Admins, Enterprise Key Admins and the
        # Enterprise Read-only Domain Controllers are of the root domain of the forest.
        [GPOToolsWellKnownSid]::new('-498', 'DOMAIN', 'Enterprise Read-only Domain Controllers', "Contrôleurs de domaine d'entreprise en lecture seule")
        [GPOToolsWellKnownSid]::new('-500', 'DOMAIN', 'Administrator', 'Administrateur')
        [GPOToolsWellKnownSid]::new('-501', 'DOMAIN', 'Guest', 'Invité')
        [GPOToolsWellKnownSid]::new('-502', 'DOMAIN', 'krbtgt', 'krbtgt')
        [GPOToolsWellKnownSid]::new('-512', 'DOMAIN', 'Domain Admins', 'Admins du domaine')
        [GPOToolsWellKnownSid]::new('-513', 'DOMAIN', 'Domain Users', 'Utilisateurs du domaine')
        [GPOToolsWellKnownSid]::new('-514', 'DOMAIN', 'Domain Guests', 'Invités du domaine')
        [GPOToolsWellKnownSid]::new('-515', 'DOMAIN', 'Domain Computers', 'Ordinateurs du domaine')
        [GPOToolsWellKnownSid]::new('-516', 'DOMAIN', 'Domain Controllers', 'Contrôleurs de domaine')
        [GPOToolsWellKnownSid]::new('-517', 'DOMAIN', 'Cert Publishers', 'Éditeurs de certificats')
        [GPOToolsWellKnownSid]::new('-518', 'DOMAIN', 'Schema Admins', 'Administrateurs du schéma')
        [GPOToolsWellKnownSid]::new('-519', 'DOMAIN', 'Enterprise Admins', "Administrateurs de l'entreprise")
        [GPOToolsWellKnownSid]::new('-520', 'DOMAIN', 'Group Policy Creator Owners', 'Propriétaires créateurs de la stratégie de groupe')
        [GPOToolsWellKnownSid]::new('-521', 'DOMAIN', 'Read-only Domain Controllers', 'Contrôleurs de domaine en lecture seule')
        [GPOToolsWellKnownSid]::new('-522', 'DOMAIN', 'Cloneable Domain Controllers', 'Contrôleurs de domaine clonables')
        [GPOToolsWellKnownSid]::new('-525', 'DOMAIN', 'Protected Users', 'Protected Users')
        [GPOToolsWellKnownSid]::new('-526', 'DOMAIN', 'Key Admins', 'Administrateurs clés')
        [GPOToolsWellKnownSid]::new('-527', 'DOMAIN', 'Enterprise Key Admins', 'Administrateurs clés Enterprise')
        [GPOToolsWellKnownSid]::new('-553', 'DOMAIN', 'RAS and IAS Servers', 'Serveurs RAS et IAS')
        [GPOToolsWellKnownSid]::new('-571', 'DOMAIN', 'Allowed RODC Password Replication Group', 'Groupe de réplication dont le mot de passe RODC est autorisé')
        [GPOToolsWellKnownSid]::new('-572', 'DOMAIN', 'Denied RODC Password Replication Group', 'Groupe de réplication dont le mot de passe RODC est refusé')
    )

    # The entry of a SID: a well-known one, or an account of a domain by its RID (S-1-5-21-x-y-z-512);
    # $null when it is none of them.
    static [GPOToolsWellKnownSid] FindBySid([string]$Sid) {
        $Value = $Sid.TrimStart('*')
        $Rid = if ($Value -match '^S-1-5-21-\d+-\d+-\d+(-\d+)$') { $Matches[1] } else { $null }
        foreach ($Entry in [GPOToolsWellKnownSid]::All) {
            if ($Entry.Sid -eq $Value -or ($Rid -and $Entry.Sid -eq $Rid)) { return $Entry }
        }
        return $null
    }

    # The entry of a name, English or French, short or with what Windows writes before it
    # (BUILTIN\Administrateurs, NT AUTHORITY\SYSTEM, AUTORITE NT\Système, CONTOSO\Domain Admins);
    # $null when it is none of them. An account of the domain is found only when its domain may
    # be the one before its name (-DomainAccounts).
    static [GPOToolsWellKnownSid] FindByName([string]$Name, [bool]$DomainAccounts) {
        $Text = $Name.Trim()
        $Prefix = ''
        $Separator = $Text.LastIndexOf('\')
        if ($Separator -ge 0) { $Prefix = $Text.Substring(0, $Separator); $Text = $Text.Substring($Separator + 1) }
        foreach ($Entry in [GPOToolsWellKnownSid]::All) {
            if (-not ([string]::Equals($Entry.Name, $Text, [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($Entry.FrenchName, $Text, [System.StringComparison]::OrdinalIgnoreCase))) { continue }
            if ($Entry.IsDomainAccount()) {
                if ($DomainAccounts) { return $Entry }
                continue
            }
            # BUILTIN\Users is not NT AUTHORITY\Users: the prefix, when there is one, is its own.
            if ($Prefix -and -not ([string]::Equals($Prefix, $Entry.Authority, [System.StringComparison]::OrdinalIgnoreCase) -or
                    ($Entry.Authority -eq 'NT AUTHORITY' -and $Prefix -eq 'AUTORITE NT'))) { continue }
            return $Entry
        }
        return $null
    }
}
