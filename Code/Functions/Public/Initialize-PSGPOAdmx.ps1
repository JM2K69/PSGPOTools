Function Initialize-PSGPOAdmx {
    <#
    .SYNOPSIS
        Loads the ADMX/ADML files of a folder (local PolicyDefinitions or a SYSVOL central store).
    .DESCRIPTION
        The language is detected from the names of the language folders of PolicyDefinitions
        (en-US, fr-FR...): the language of the session, else the same language in another
        country, else en-US, else the only one there is. When several languages remain, give
        -UICulture.

        An .admx file without an .adml in the language takes the one of en-US, as the Group
        Policy editor; a file that cannot be read is left out with a warning, and the others are
        loaded. A load that fails, or where no file can be read, loads nothing.

        The files of a folder are parsed once: what is loaded is kept in a cache of the user
        (%LOCALAPPDATA%\PSGPOTools\Admx on Windows; $XDG_CACHE_HOME/PSGPOTools/Admx, else
        ~/.cache/PSGPOTools/Admx elsewhere), read instead of the files while they keep their
        names, sizes and dates. A load with an error, or with a file left out for a reason that may
        pass (the network, the rights), is not cached. -NoCache parses the files.
    .PARAMETER Path
        Folder containing the .admx files and one sub-folder per culture for the .adml files.
        Defaults to the central store of the domain when it holds ADMX files, as GPMC
        (\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions; on a Samba domain controller, its
        SYSVOL), else to %windir%\PolicyDefinitions on Windows; required elsewhere on Linux and macOS.
    .PARAMETER UICulture
        Culture of the ADML files to load (sub-folder name, for example en-US or fr-FR); detected
        when not given.
    .PARAMETER NoCache
        Parses the files, neither reading nor writing the cache.
    .EXAMPLE
        Initialize-PSGPOAdmx -Path '\\contoso.com\SYSVOL\contoso.com\Policies\PolicyDefinitions' -UICulture 'fr-FR'
    .EXAMPLE
        # Linux: a copy of the PolicyDefinitions folder, in the language of the session
        Initialize-PSGPOAdmx -Path ~/PolicyDefinitions
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/initialize-psgpoadmx/
    #>
    [cmdletbinding()]
    Param(
        [ValidateScript( { Test-Path -Path $_ -PathType Container })]
        [String]$Path,

        [string]$UICulture,

        [switch]$NoCache
    )

    if (-not $Path) {
        $Path = @(Get-PSGPOAdmxCentralStore)[0]
    }
    if (-not $Path) {
        if (-not $IsWindows) {
            $found = @(Get-PSGPOAdmxCandidate -CentralStore @())
            $hint = if ($found.Count) { " Found on this computer: $($found -join ', ')." } else { ' Install-PSGPOAdmx installs those of Windows, from the package of Microsoft.' }
            throw "Specify -Path: there is no local PolicyDefinitions folder outside Windows (use a copy of the ADMX files or the SYSVOL central store).$hint"
        }
        $Path = Join-Path -Path $Env:windir -ChildPath 'PolicyDefinitions'
    }
    $Item = Get-Item -Path $Path
    $Language = Resolve-PSGPOAdmxCulture -Path $Item.FullName -Requested $UICulture
    if (-not $Language.Culture) {
        throw "Several languages in '$($Item.FullName)' ($($Language.Available -join ', ')) and none of them is the language of the session: give -UICulture."
    }
    Write-Verbose "ADMX files of $($Item.FullName) in $($Language.Culture)."

    # Empty Statics properties
    [GPOToolsUtility]::RemoveAll()
    $culture = [cultureinfo]::GetCultureInfo($Language.Culture)
    $cache = if (-not $NoCache) { Get-PSGPOAdmxCacheEntry -Path $Item.FullName -Culture $culture.Name }
    $cached = if ($cache) { Import-PSGPOAdmxCache -Entry $cache }
    if ($cached) {
        foreach ($warning in $cached.Warnings) { Write-Warning $warning }
        return
    }

    # The warnings of the parser, shown as they come and kept in the cache to be shown again: all
    # of them, whatever the -WarningAction of this call (Write-Warning applies it). An error that
    # stops the load undoes it; an error that does not, or a file left out, is not cached.
    $warnings = [System.Collections.Generic.List[string]]::new()
    $parse = @{ Errors = 0 }
    try {
        & { $WarningPreference = 'Continue'; [GPOToolsUtility]::InitiateAdmxAdml($Item, $culture) } 2>&1 3>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.WarningRecord]) { $warnings.Add($_.Message); Write-Warning $_.Message }
            elseif ($_ -is [System.Management.Automation.ErrorRecord]) { $parse.Errors += 1; Write-Error -ErrorRecord $_ }
            else { $_ }
        }
    } catch {
        [GPOToolsUtility]::RemoveAll()
        throw
    }
    # No file could be read (the language and en-US without ADML, a folder out of reach): a failure.
    # A file loaded without policies (categories only) is a file loaded.
    if (-not [GPOToolsUtility]::TargetLoad.Count -and [GPOToolsUtility]::SkippedFiles.Count) {
        $reasons = @([GPOToolsUtility]::SkippedFiles) -join '; '
        [GPOToolsUtility]::RemoveAll()
        throw "No ADMX file of '$($Item.FullName)' can be loaded in $($culture.Name): $reasons"
    }
    if ($cache -and -not $parse.Errors -and -not [GPOToolsUtility]::Incomplete) {
        # Without a cache, the next load parses the files again.
        try { Export-PSGPOAdmxCache -Entry $cache -Warnings $warnings }
        catch { Write-Verbose "ADMX cache not written in $($cache.File): $($_.Exception.Message)" }
    }
}
