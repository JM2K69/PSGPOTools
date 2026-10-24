function Show-PolicyAnalyzerAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) graphical Policy Analyzer: GPOs and the security
        baselines of Microsoft compared setting by setting.
    .DESCRIPTION
        The Policy Analyzer of HGPM, as the one of the Microsoft Security Compliance Toolkit, with the
        same .PolicyRules files:

        - Rule sets: the .PolicyRules files of a folder (Documents\PolicyAnalyzer by default, as
          Policy Analyzer: the files of the security baselines of Microsoft), GPOs of the domain as
          they are now, GPMC backups (the GPOs folder of a baseline). The domain is read the first
          time its GPOs are asked for (-Server, else the domain of the computer).
        - Comparison: the sets checked, a row per setting and a column per set, with the colours of
          Policy Analyzer (yellow: different values; grey: not configured; light grey: set more than
          once); only the differences, only the conflicts, a search; the details of a setting:
          where GPMC shows it, the value each GPO gives it, its explanation.
        - A set saved as a .PolicyRules file (Policy Analyzer, LGPO.exe /p), the comparison
          exported to an Excel workbook.

        The settings are named as GPMC names them with the ADMX files loaded (Initialize-PSGPOAdmx,
        -PolicyDefinitions; the central store or %windir%\PolicyDefinitions by default on Windows);
        without them, a registry value is shown by its key.

        Hosted on Avalonia UI under PowerShell 7+, as Show-GPOManagerAvalonia; the call blocks until
        the window is closed. Get-PSGPOPolicyRuleSet and Compare-PSGPOPolicyRuleSet do the same in a
        script.
    .PARAMETER Path
        The folder of the .PolicyRules files shown at start, instead of the one of the last time.
    .PARAMETER Directory
        The domain of the GPOs (Get-PSGPODirectory), already read.
    .PARAMETER Server
        Domain controller to read the GPOs from: its DNS name. By default, the domain of the computer.
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .PARAMETER PolicyDefinitions
        Folder of the ADMX files that name the registry values, when none is loaded.
    .PARAMETER UICulture
        Language of the ADML files (en-US, fr-FR...).
    .PARAMETER Language
        Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default the
        language of the session, English when the module has no translation for it.
    .EXAMPLE
        Show-PolicyAnalyzerAvalonia
    .EXAMPLE
        Show-PolicyAnalyzerAvalonia -Path '.\Windows 11 v25H2 Security Baseline\Documentation'
    .EXAMPLE
        # Linux, Samba AD: Kerberos ticket first
        kinit administrator@HARDENBOX.LABO
        Show-PolicyAnalyzerAvalonia -Server dc.hardenbox.labo -PolicyDefinitions ~/PolicyDefinitions
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/show-policyanalyzeravalonia/
    .LINK
        Get-PSGPOPolicyRuleSet
    .LINK
        Compare-PSGPOPolicyRuleSet
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

        [ValidateScript( { Test-Path -Path $_ -PathType Container })]
        [string]$PolicyDefinitions,

        [string]$UICulture,

        [string]$Language = [cultureinfo]::CurrentUICulture.Name
    )

    $Language = Set-PSGPOLanguage -Language $Language
    # The names of the settings: the ADMX files given, else those loaded, else those found.
    if ($PolicyDefinitions -or $UICulture) {
        $admx = @{}
        if ($PolicyDefinitions) { $admx.Path = $PolicyDefinitions }
        if ($UICulture) { $admx.UICulture = $UICulture }
        Initialize-PSGPOAdmx @admx -WarningAction SilentlyContinue
    } elseif ([GPOToolsUtility]::Policies.Count -eq 0) {
        try {
            Initialize-PSGPOAdmx -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        } catch {
            Write-Verbose "No ADMX file loaded: $($_.Exception.Message)"
        }
    }

    $parameters = @{}
    foreach ($name in 'Server', 'Credential', 'UseSsl') {
        if ($PSBoundParameters.ContainsKey($name)) { $parameters[$name] = $PSBoundParameters[$name] }
    }
    $window = @{ DomainParameters = $parameters; Language = $Language }
    if ($Directory) { $window.Directory = $Directory }
    if ($Path) { $window.Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) }
    Start-PSGPOPolicyAnalyzerWindow @window
}
