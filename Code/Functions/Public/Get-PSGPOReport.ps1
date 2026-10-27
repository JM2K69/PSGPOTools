function Get-PSGPOReport {
    <#
    .SYNOPSIS
        Makes the report of GPOs, as Get-GPOReport of GPMC: an object, an XML document or an HTML page.
    .DESCRIPTION
        The report of a GPO holds its details (status, owner, versions, approval, WMI filter), its
        links, its security filtering and delegation, the client-side extensions it declares, and
        the settings of its computer and user configurations as the Settings tab of
        Show-GPOManagerAvalonia lists them: scripts, security settings, advanced audit policy, the
        policies of Registry.pol (by the ADMX files loaded with Initialize-PSGPOAdmx, else as extra
        registry settings), preferences.

        It lists apart what HGPM does not interpret: a client-side extension whose settings it does
        not read (Folder Redirection, Software Installation, IP Security...), a file of the folder of
        the GPO no reader of HGPM reads. The computers apply them all the same: review them with
        GPMC, or in the files of the GPO, before approving it.

        -ReportType Object (the default) gives PSGPOTools.GpoReport objects; Xml an XML document of
        HGPM, in English (namespace https://jm2k69.github.io/PSGPOTools/schemas/gpo-report/1, not
        the schema of the reports of GPMC); Html a page in one file, in the language of the
        interface (-Language), readable in any browser. Without -Path, the XML and the HTML are
        returned as a string; with -Path, written in that file (UTF-8), the file returned.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern).
    .PARAMETER All
        Every GPO of the domain.
    .PARAMETER ReportType
        Object, Xml or Html.
    .PARAMETER Path
        The file the XML or HTML report is written to; one file for all the GPOs.
    .PARAMETER Language
        Language of an HTML report: en-US, or a language of Resources/Strings (fr-FR); by default
        the one of the interface (English in a session that never opened a console).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOReport -Name 'T1 - Servers - Proxy' -ReportType Html -Path ./proxy.html
    .EXAMPLE
        Get-PSGPOReport -All -ReportType Xml -Path ./gpos.xml
    .EXAMPLE
        Get-PSGPOReport -Name * | Where-Object { $_.NotInterpreted } | Select-Object DisplayName, NotInterpreted
    .OUTPUTS
        PSGPOTools.GpoReport, System.String, System.IO.FileInfo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgporeport/
    .LINK
        Approve-PSGPO
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('PSGPOTools.GpoReport', [string], [System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0, ParameterSetName = 'Name')]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All,

        [ValidateSet('Object', 'Xml', 'Html')]
        [string]$ReportType = 'Object',

        [string]$Path,

        [string]$Language,

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    begin {
        if ($Path -and $ReportType -eq 'Object') { throw '-Path writes the report as a file: give -ReportType Xml or Html.' }
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        $reports = [System.Collections.Generic.List[object]]::new()
        $gpos = [System.Collections.Generic.List[object]]::new()
        if ($All) { foreach ($gpo in $Directory.Gpos) { $gpos.Add($gpo) } }
    }
    process {
        if ($All) { return }
        foreach ($gpo in @(Find-PSGPOByName -Directory $Directory -Name $Name)) { $gpos.Add($gpo) }
    }
    end {
        foreach ($gpo in $gpos) {
            try {
                $report = Get-PSGPOReportData -Directory $Directory -Gpo $gpo
            } catch {
                Write-Error "The report of the GPO '$($gpo.DisplayName)' cannot be made: $($_.Exception.GetBaseException().Message)"
                continue
            }
            if ($ReportType -eq 'Object') { $report } else { $reports.Add($report) }
        }
        if ($ReportType -eq 'Object' -or -not $reports.Count) { return }

        $text = if ($ReportType -eq 'Xml') {
            ConvertTo-PSGPOReportXml -Report $reports.ToArray()
        } else {
            # The language asked for, for this report only.
            $previous = $script:PSGPOLanguage
            if ($Language) { $null = Set-PSGPOLanguage -Language $Language }
            try { ConvertTo-PSGPOReportHtml -Report $reports.ToArray() } finally { if ($Language) { $null = Set-PSGPOLanguage -Language $previous } }
        }
        if (-not $Path) { return $text }
        $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        [System.IO.File]::WriteAllText($full, $text, [System.Text.UTF8Encoding]::new($false))
        Get-Item -LiteralPath $full
    }
}
