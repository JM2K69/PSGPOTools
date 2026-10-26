function Show-AuditLogAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) graphical audit log: what the consoles and the commands
        changed in the domain.
    .DESCRIPTION
        The audit log of HGPM (Get-PSGPOAuditLog) in a window: each change the domain accepted, from
        a console or a command, newest first, with when, which account, from which computer, on
        which domain controller, what and on what (a GPO, a container, the configuration).

        - Filters: the period (the last 24 hours, 7 days, 30 days, everything), the domain, the
          action, a search in every text of a change (account, GPO, computer, details).
        - The details of the selected change: everything the log keeps of it (the options of a
          link changed, the file saved with its SHA-256 and its new version...).
        - The changes shown exported to a CSV file.

        The log is read from Audit.Path of the configuration of the domain (a share the
        administrators write, the same for every console): the domain is read once the window is
        shown (-Server, else the domain of the computer); without a domain, or when its
        configuration sets no folder, the folder Audit of the backups of the account. -Path reads
        another folder. The log is on by default: Audit.Enabled = $false in the configuration of
        the domain stops it.

        Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until
        the window is closed.
    .PARAMETER Path
        Folder of the audit log, instead of Audit.Path of the configuration of the domain.
    .PARAMETER Directory
        The domain (Get-PSGPODirectory), already read: its configuration gives the folder of the log.
    .PARAMETER Server
        Domain controller to read the configuration of the domain from: its DNS name. By default, the
        domain of the computer.
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .PARAMETER Language
        Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the
        language of the session, English when the module has no translation for it.
    .EXAMPLE
        Show-AuditLogAvalonia
    .EXAMPLE
        Show-AuditLogAvalonia -Path \\files\gpo-audit
    .EXAMPLE
        # Linux, Samba AD: Kerberos ticket first
        kinit administrator@HARDENBOX.LABO
        Show-AuditLogAvalonia -Server dc.hardenbox.labo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/show-auditlogavalonia/
    .LINK
        Get-PSGPOAuditLog
    #>
    [CmdletBinding(DefaultParameterSetName = 'Domain')]
    param(
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Directory')]
        [GPOToolsDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
        [string]$Server,

        [Parameter(ParameterSetName = 'Domain')]
        [pscredential]$Credential,

        [Parameter(ParameterSetName = 'Domain')]
        [switch]$UseSsl,

        [string]$Language = [cultureinfo]::CurrentUICulture.Name
    )

    $Language = Set-PSGPOLanguage -Language $Language
    $parameters = @{}
    foreach ($name in 'Server', 'Credential', 'UseSsl') {
        if ($PSBoundParameters.ContainsKey($name)) { $parameters[$name] = $PSBoundParameters[$name] }
    }
    $window = @{ DomainParameters = $parameters; Language = $Language }
    if ($Directory) { $window.Directory = $Directory }
    if ($Path) { $window.Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) }
    Start-PSGPOAuditLogWindow @window
}
