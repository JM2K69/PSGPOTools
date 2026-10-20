function Show-PSOManagerAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) graphical console for the fine-grained password policies (PSO).
    .DESCRIPTION
        The password settings of the Active Directory Administrative Center, for Windows and Samba AD
        domains, from Windows or Linux. Two views:

        - Password Settings: the PSOs of the Password Settings Container by order of priority, with
          their settings and the users and groups each one directly applies to; New, Properties and
          Delete as in the Administrative Center (precedence, minimum length, history, complexity,
          reversible encryption, minimum and maximum age, lockout, protection from accidental
          deletion, description, "Directly Applies To"). The password policy of the domain is shown
          under the list: it applies to the accounts no PSO applies to.
        - Resultant Password Settings: search a user or a group, select it, and see every PSO that
          concerns it (directly, or through which groups, nested ones included) by order of
          priority, the one that applies and why the others do not. For a user, the domain
          controller gives the PSO it applies (msDS-ResultantPSO).

        Without -Server, the domain of the computer is read; when no domain is discovered, the window
        shows sample policies (Samples/PasswordPolicy.sample.json) under a "demonstration environment"
        banner, and their changes stay in memory. The changes of a domain are written over LDAP, and
        to the audit log of HGPM (Get-PSGPOAuditLog).

        Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until
        the window is closed.
    .PARAMETER Server
        Domain controller to read the domain from: its DNS name. By default, the domain of the
        computer (see Get-PSGPODirectory).
    .PARAMETER Credential
        Account to read and change the domain with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .PARAMETER View
        View shown at launch: Policies (Password Settings), or Resultant (Resultant Password Settings).
    .PARAMETER Language
        Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the
        language of the session, English when the module has no translation for it.
    .EXAMPLE
        Show-PSOManagerAvalonia
    .EXAMPLE
        # Linux, Samba AD: Kerberos ticket first
        kinit administrator@HARDENBOX.LABO
        Show-PSOManagerAvalonia -Server dc.hardenbox.labo -Language fr-FR
    .EXAMPLE
        Show-PSOManagerAvalonia -View Resultant
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/show-psomanageravalonia/
    .LINK
        Get-PSGPOFineGrainedPasswordPolicy
    .LINK
        Get-PSGPOResultantPasswordPolicy
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl,
        [ValidateSet('Policies', 'Resultant')]
        [string]$View = 'Policies',
        [string]$Language = [cultureinfo]::CurrentUICulture.Name
    )

    $Language = Set-PSGPOLanguage -Language $Language
    $store = $null
    $storeError = $null
    $platform = Get-PSGPOPlatform
    if ($Server -or $platform.DomainName) {
        try {
            $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
            Write-Verbose "Password policies read: $($store.Source)"
        } catch {
            $storeError = $_.Exception.GetBaseException().Message
            Write-Warning "The domain could not be read: $storeError"
        }
    } else {
        # Nothing to read: the sample policies, flagged as a demonstration.
        $sample = Join-Path $PSScriptRoot 'Samples' 'PasswordPolicy.sample.json'
        Write-Verbose "$platform`: no domain discovered, demonstration policies $sample."
        try {
            $store = Import-PSGPOPasswordPolicyStore -Path $sample
            $store.IsDemonstration = $true
        } catch {
            Write-Warning "No domain discovered and the demonstration policies cannot be read: $($_.Exception.Message)"
        }
    }
    Start-PSGPOPasswordPolicyWindow -Store $store -StoreError $storeError -StartView $View -Language $Language
}
