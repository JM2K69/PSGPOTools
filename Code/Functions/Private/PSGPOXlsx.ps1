<#
    An Excel workbook (.xlsx, Office Open XML SpreadsheetML) written without Excel nor any module,
    on any platform: a zip of XML parts. Each sheet has a header row (bold, frozen, with filters)
    and text cells, each with a style of $script:PSGPOXlsxStyle.
#>

# The styles of the cells (cellXfs of styles.xml): the fills Policy Analyzer uses.
$script:PSGPOXlsxStyle = @{ Normal = 0; Header = 1; Conflict = 2; Absent = 3; Duplicate = 4 }

# A cell of a sheet: its text and style.
function New-PSGPOXlsxCell {
    param([AllowNull()] [AllowEmptyString()] [string]$Text, [string]$Style = 'Normal')
    [pscustomobject]@{ Text = $Text; Style = $Style }
}

# The letters of a column (0 -> A, 26 -> AA).
function Get-PSGPOXlsxColumnName {
    [OutputType([string])]
    param([int]$Index)

    $name = ''
    $number = $Index + 1
    while ($number -gt 0) {
        $rest = [int](($number - 1) % 26)
        $name = [char](65 + $rest) + $name
        $number = [int][math]::Floor(($number - 1) / 26)
    }
    $name
}

# Text for an XML part: escaped, without the characters XML does not allow, and as long as a cell
# of Excel can hold (32,767 characters).
function ConvertTo-PSGPOXlsxText {
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    if (-not $Text) { return '' }
    if ($Text.Length -gt 32767) { $Text = $Text.Substring(0, 32767) }
    $clean = [regex]::Replace($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]', '')
    [System.Security.SecurityElement]::Escape($clean)
}

# Writes the workbook. $Sheets: Name, Columns (header texts), Widths (characters, optional) and
# Rows (arrays of cells, New-PSGPOXlsxCell).
function Write-PSGPOXlsxWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [object[]]$Sheets
    )

    $main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    $relationships = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    $parts = [ordered]@{}

    $overrides = for ($index = 1; $index -le $Sheets.Count; $index++) {
        "<Override PartName=`"/xl/worksheets/sheet$index.xml`" ContentType=`"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml`"/>"
    }
    $parts['[Content_Types].xml'] = $header + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
        ($overrides -join '') + '</Types>'
    $parts['_rels/.rels'] = $header + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'

    $sheetList = [System.Text.StringBuilder]::new()
    $sheetRelations = [System.Text.StringBuilder]::new()
    $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($index = 1; $index -le $Sheets.Count; $index++) {
        # A name of a sheet: 31 characters, none of []:*?/\, unique.
        $name = ($Sheets[$index - 1].Name -replace '[\[\]:\*\?/\\]', ' ').Trim()
        if (-not $name) { $name = "Sheet$index" }
        if ($name.Length -gt 31) { $name = $name.Substring(0, 31) }
        $base = $name
        for ($number = 2; -not $used.Add($name); $number++) { $name = $base.Substring(0, [math]::Min($base.Length, 27)) + " ($number)" }
        [void]$sheetList.Append("<sheet name=`"$(ConvertTo-PSGPOXlsxText $name)`" sheetId=`"$index`" r:id=`"rId$index`"/>")
        [void]$sheetRelations.Append("<Relationship Id=`"rId$index`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet`" Target=`"worksheets/sheet$index.xml`"/>")
    }
    $parts['xl/workbook.xml'] = $header + "<workbook xmlns=`"$main`" xmlns:r=`"$relationships`"><sheets>$sheetList</sheets></workbook>"
    $parts['xl/_rels/workbook.xml.rels'] = $header + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + $sheetRelations +
        "<Relationship Id=`"rId$($Sheets.Count + 1)`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles`" Target=`"styles.xml`"/></Relationships>"

    # Fills 0 and 1 are reserved (none, gray125); then the header, conflict (yellow), absent
    # (grey) and duplicate (light grey).
    $fill = { param($Rgb) "<fill><patternFill patternType=`"solid`"><fgColor rgb=`"FF$Rgb`"/><bgColor indexed=`"64`"/></patternFill></fill>" }
    $parts['xl/styles.xml'] = $header + "<styleSheet xmlns=`"$main`">" +
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
        '<fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' + (& $fill 'DDEBF7') + (& $fill 'FFFF00') + (& $fill 'BFBFBF') + (& $fill 'EDEDED') + '</fills>' +
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
        '<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="top" wrapText="1"/></xf>' +
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment vertical="top" wrapText="1"/></xf>' +
        '<xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"><alignment vertical="top" wrapText="1"/></xf>' +
        '<xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0" applyFill="1"><alignment vertical="top" wrapText="1"/></xf>' +
        '<xf numFmtId="0" fontId="0" fillId="5" borderId="0" xfId="0" applyFill="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>' +
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'

    for ($index = 1; $index -le $Sheets.Count; $index++) {
        $sheet = $Sheets[$index - 1]
        $columns = @($sheet.Columns)
        $text = [System.Text.StringBuilder]::new()
        [void]$text.Append($header).Append("<worksheet xmlns=`"$main`" xmlns:r=`"$relationships`">")
        [void]$text.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
        if ($columns.Count) {
            [void]$text.Append('<cols>')
            for ($column = 0; $column -lt $columns.Count; $column++) {
                $width = if ($sheet.Widths -and $column -lt @($sheet.Widths).Count) { @($sheet.Widths)[$column] } else { 20 }
                [void]$text.Append("<col min=`"$($column + 1)`" max=`"$($column + 1)`" width=`"$width`" customWidth=`"1`"/>")
            }
            [void]$text.Append('</cols>')
        }
        [void]$text.Append('<sheetData>')
        $all = @(, @($columns | ForEach-Object { New-PSGPOXlsxCell -Text $_ -Style Header })) + @($sheet.Rows)
        for ($row = 0; $row -lt $all.Count; $row++) {
            [void]$text.Append("<row r=`"$($row + 1)`">")
            $cells = @($all[$row])
            for ($column = 0; $column -lt $cells.Count; $column++) {
                $cell = $cells[$column]
                $style = $script:PSGPOXlsxStyle["$($cell.Style)"]
                $reference = "$(Get-PSGPOXlsxColumnName $column)$($row + 1)"
                $value = ConvertTo-PSGPOXlsxText $cell.Text
                [void]$text.Append("<c r=`"$reference`" s=`"$style`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$value</t></is></c>")
            }
            [void]$text.Append('</row>')
        }
        [void]$text.Append('</sheetData>')
        if ($columns.Count) { [void]$text.Append("<autoFilter ref=`"A1:$(Get-PSGPOXlsxColumnName ($columns.Count - 1))$($all.Count)`"/>") }
        [void]$text.Append('</worksheet>')
        $parts["xl/worksheets/sheet$index.xml"] = $text.ToString()
    }

    Add-Type -AssemblyName System.IO.Compression
    $stream = [System.IO.File]::Create($Path)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            foreach ($name in $parts.Keys) {
                $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
                $writer = [System.IO.StreamWriter]::new($entry.Open(), $utf8)
                try { $writer.Write($parts[$name]) } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
}
