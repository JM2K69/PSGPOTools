<#
    Starter GPOs, as GPMC keeps them: a folder SYSVOL\<domain>\StarterGPOs\{GUID} for each, no
    object in the directory. StarterGPO.tmplx (UTF-8 with its mark) says what it is: its type
    (System: those of Microsoft, which GPMC adds with the folder; Custom: those of the domain), its
    name, description, author and product, its versions and its client-side extensions; a System
    Starter GPO has its texts in <culture>\StarterGPO.tmpll. Its settings are Administrative
    Templates only: Machine\Registry.pol and User\Registry.pol, and their comments (comment.cmtx).
    A new GPO starts from a Starter GPO with these settings, as New GPO > Source Starter GPO.
#>

$script:PSGPOStarterNamespace = 'http://www.microsoft.com/GroupPolicy/TemplateDefinitions'
# The snap-in GPMC names with the extension of the Administrative Templates of a Starter GPO.
$script:PSGPOStarterSnapin = '{B05566AC-FE9C-4368-BE01-7A4CBB6CBA11}'
# The tools GPMC declares with the Administrative Templates of a GPO it creates from a Starter GPO
# (Computer Policy Setting, User Policy Setting), seen on a Windows lab: not those of the editor.
$script:PSGPOStarterTool = @{ Machine = '{0F6B957D-509E-11D1-A7CC-0000F87571E3}'; User = '{0F6B957E-509E-11D1-A7CC-0000F87571E3}' }
# The files a Starter GPO holds besides StarterGPO.tmplx: its settings and their comments.
$script:PSGPOStarterSettingFiles = 'Machine\Registry.pol', 'User\Registry.pol', 'Machine\comment.cmtx', 'User\comment.cmtx'

# An XML document of a Starter GPO, read without a DTD (the folder is written by the accounts that
# create Starter GPOs; an entity could not make it grow).
function ConvertTo-PSGPOStarterXml {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param([Parameter(Mandatory)] [byte[]]$Bytes)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stream = [System.IO.MemoryStream]::new($Bytes)
    try {
        $reader = [System.Xml.XmlReader]::Create($stream, $settings)
        $document = [System.Xml.XmlDocument]::new()
        $document.Load($reader)
        , $document
    } finally {
        $stream.Dispose()
    }
}

# The strings of a string table (resources/stringTable/string) of a Starter GPO file, by id.
function Get-PSGPOStarterString {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowNull()] [System.Xml.XmlDocument]$Document)

    $strings = @{}
    if (-not $Document) { return $strings }
    foreach ($node in @($Document.GetElementsByTagName('string', $script:PSGPOStarterNamespace))) {
        $id = $node.GetAttribute('id')
        if ($id) { $strings[$id] = $node.InnerText }
    }
    $strings
}

# The fields of a StarterGPO.tmplx: Id, Type (System or Custom), DisplayName, Description, Author,
# Product, ComputerVersion, UserVersion, ComputerExtensions and UserExtensions (the guidExtension of
# each pair). A $(resource.<id>) text comes from the string table of the file, else from $Resource
# (the .tmpll of a System Starter GPO).
function ConvertFrom-PSGPOStarterTemplate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [byte[]]$Template,
        [byte[]]$Resource
    )

    $document = ConvertTo-PSGPOStarterXml -Bytes $Template
    $element = @($document.GetElementsByTagName('template', $script:PSGPOStarterNamespace))[0]
    if (-not $element) { throw 'StarterGPO.tmplx has no <template> element: it is not a Starter GPO of GPMC.' }
    $strings = Get-PSGPOStarterString -Document $document
    if ($Resource) {
        $resources = Get-PSGPOStarterString -Document (ConvertTo-PSGPOStarterXml -Bytes $Resource)
        foreach ($id in $resources.Keys) { if (-not $strings.ContainsKey($id)) { $strings[$id] = $resources[$id] } }
    }
    $text = {
        param([string]$Value)
        $match = [regex]::Match("$Value", '^\$\(resource\.([^)]+)\)$')
        if ($match.Success) { "$($strings[$match.Groups[1].Value])" } else { "$Value" }
    }
    $extensions = {
        param([string]$Name)
        @(foreach ($part in @($document.GetElementsByTagName($Name, $script:PSGPOStarterNamespace))) {
                foreach ($pair in @($part.GetElementsByTagName('guidPair', $script:PSGPOStarterNamespace))) { $pair.GetAttribute('guidExtension').ToUpperInvariant() }
            })
    }
    $id = [guid]::Empty
    $null = [guid]::TryParse($element.GetAttribute('uniqueID').Trim('{', '}'), [ref]$id)
    $version = { param([string]$Value) $number = 0; if ([int]::TryParse($Value, [ref]$number)) { $number } else { $null } }
    [pscustomobject]@{
        Id = $id
        Type = if ($element.GetAttribute('templateType') -eq 'System') { 'System' } else { 'Custom' }
        DisplayName = & $text $element.GetAttribute('displayName')
        Description = & $text $element.GetAttribute('description')
        Author = & $text $element.GetAttribute('author')
        Product = & $text $element.GetAttribute('product')
        ComputerVersion = & $version $element.GetAttribute('computerVersion')
        UserVersion = & $version $element.GetAttribute('userVersion')
        ComputerExtensions = & $extensions 'computerExtensions'
        UserExtensions = & $extensions 'userExtensions'
    }
}

# A StarterGPO.tmplx of a Custom Starter GPO, as GPMC writes it: UTF-8 with its mark, its name and
# description in its string table, the extension of the Administrative Templates for each part
# that has settings.
function ConvertTo-PSGPOStarterTemplate {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)] [guid]$Id,
        [Parameter(Mandatory)] [string]$DisplayName,
        [AllowEmptyString()] [string]$Description = '',
        [int]$ComputerVersion,
        [int]$UserVersion,
        [switch]$ComputerSettings,
        [switch]$UserSettings
    )

    $escape = { param([string]$Value) [System.Security.SecurityElement]::Escape($Value) }
    $pair = '<guidPair guidExtension="{0}" guidSnapin="{1}"></guidPair>' -f [GPOToolsDirectory]::RegistryExtension, $script:PSGPOStarterSnapin
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("<?xml version='1.0' encoding='utf-8'?>")
    $lines.Add('<policyTemplate xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" revision="1.0" schemaVersion="1.0" xmlns="{0}">' -f $script:PSGPOStarterNamespace)
    $lines.Add(('  <template minRequiredRevision="1.0" uniqueID="{{{0}}}" templateType="Custom" computerVersion="{1}" userVersion="{2}" displayName="$(resource.displayName)" description="$(resource.description)"></template>' -f $Id.ToString().ToUpperInvariant(), $ComputerVersion, $UserVersion))
    if ($ComputerSettings) { $lines.Add('  <computerExtensions>'); $lines.Add("    $pair"); $lines.Add('  </computerExtensions>') }
    if ($UserSettings) { $lines.Add('  <userExtensions>'); $lines.Add("    $pair"); $lines.Add('  </userExtensions>') }
    $lines.Add('  <resources minRequiredRevision="1.0">')
    $lines.Add('    <stringTable>')
    $lines.Add('      <string id="displayName">{0}</string>' -f (& $escape $DisplayName))
    $lines.Add('      <string id="description">{0}</string>' -f (& $escape ($Description -replace '\r?\n', "`r`n")))
    $lines.Add('    </stringTable>')
    $lines.Add('  </resources>')
    $lines.Add('</policyTemplate>')
    $encoding = [System.Text.UTF8Encoding]::new($true)
    , [byte[]]($encoding.GetPreamble() + $encoding.GetBytes(($lines -join "`r`n") + "`r`n"))
}

# The Starter GPOs of a directory, by name: Id, DisplayName, Description, Author, Product, Type,
# ComputerVersion, UserVersion, Files (by path in its folder: StarterGPO.tmplx, its settings) and
# Problem (a folder whose StarterGPO.tmplx cannot be read: kept, said). The texts of a System
# Starter GPO in the language of the interface, else in English, else the first it has.
function Get-PSGPOStarterGpoData {
    [CmdletBinding()]
    [OutputType('PSGPOTools.StarterGpo')]
    param([Parameter(Mandatory)] [GPOToolsDirectory]$Directory)

    $folders = [ordered]@{}
    foreach ($entry in $Directory.ReadStarterGpoFiles().GetEnumerator()) {
        $separator = $entry.Key.IndexOf('\')
        if ($separator -lt 1) { continue }
        $folder = $entry.Key.Substring(0, $separator)
        if (-not $folders.Contains($folder)) { $folders[$folder] = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase) }
        $folders[$folder][$entry.Key.Substring($separator + 1)] = $entry.Value
    }
    $cultures = @($script:PSGPOLanguage, 'en-US') | Select-Object -Unique
    $starters = foreach ($folder in $folders.Keys) {
        $files = $folders[$folder]
        $id = [guid]::Empty
        $null = [guid]::TryParse($folder.Trim('{', '}'), [ref]$id)
        $starter = [pscustomobject]@{
            PSTypeName = 'PSGPOTools.StarterGpo'
            Id = $id; DisplayName = $folder; Description = ''; Author = ''; Product = ''; Type = 'Custom'
            ComputerVersion = $null; UserVersion = $null; Files = $files; Problem = $null
        }
        try {
            if (-not $files.Contains('StarterGPO.tmplx')) { throw 'it has no StarterGPO.tmplx' }
            $resource = $null
            foreach ($culture in $cultures) { if ($files.Contains("$culture\StarterGPO.tmpll")) { $resource = $files["$culture\StarterGPO.tmpll"]; break } }
            if (-not $resource) { $resource = @($files.Keys | Where-Object { $_ -like '*\StarterGPO.tmpll' } | ForEach-Object { $files[$_] })[0] }
            $template = ConvertFrom-PSGPOStarterTemplate -Template $files['StarterGPO.tmplx'] -Resource $resource
            foreach ($name in 'DisplayName', 'Description', 'Author', 'Product', 'Type', 'ComputerVersion', 'UserVersion') {
                if ($name -ne 'DisplayName' -or $template.DisplayName) { $starter.$name = $template.$name }
            }
        } catch {
            $starter.Problem = "The Starter GPO $folder cannot be read: $($_.Exception.GetBaseException().Message)"
        }
        $starter
    }
    @($starters | Sort-Object DisplayName)
}

# The settings of a Starter GPO (or of a GPO, for a new Starter GPO) a GPO or a Starter GPO takes:
# its Administrative Templates and their comments, by path.
function Select-PSGPOStarterSettingFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [System.Collections.IDictionary]$Files)

    $settings = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $script:PSGPOStarterSettingFiles) { if ($Files.Contains($path)) { $settings[$path] = [byte[]]$Files[$path] } }
    , $settings
}

# The files of a new Custom Starter GPO: StarterGPO.tmplx and the settings given.
function New-PSGPOStarterGpoFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [guid]$Id,
        [Parameter(Mandatory)] [string]$DisplayName,
        [AllowEmptyString()] [string]$Description = '',
        [System.Collections.IDictionary]$Settings = @{}
    )

    $computer = $Settings.Contains('Machine\Registry.pol')
    $user = $Settings.Contains('User\Registry.pol')
    $files = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
    $files['StarterGPO.tmplx'] = ConvertTo-PSGPOStarterTemplate -Id $Id -DisplayName $DisplayName -Description $Description `
        -ComputerVersion $(if ($computer) { 1 } else { 0 }) -UserVersion $(if ($user) { 1 } else { 0 }) -ComputerSettings:$computer -UserSettings:$user
    foreach ($path in $Settings.Keys) { $files[$path] = [byte[]]$Settings[$path] }
    , $files
}

# The settings of a Starter GPO given to a GPO just created from it, as GPMC: its Administrative
# Templates (Registry.pol) and their comments, declared with the extension of the Administrative
# Templates and the tool GPMC gives it for each part; the version of the GPO increases. Nothing for
# a Starter GPO without settings. GPMC does not take its description as the comment of the GPO.
function Copy-PSGPOStarterSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [PSTypeName('PSGPOTools.StarterGpo')] $StarterGpo
    )

    if ($StarterGpo.Problem) { throw $StarterGpo.Problem }
    $settings = Select-PSGPOStarterSettingFile -Files $StarterGpo.Files
    if (-not $settings.Count) { return }
    $machine = if ($settings.Contains('Machine\Registry.pol')) { Add-PSGPOExtensionName -Current '' -Extension ([GPOToolsDirectory]::RegistryExtension) -Tool $script:PSGPOStarterTool.Machine } else { '' }
    $user = if ($settings.Contains('User\Registry.pol')) { Add-PSGPOExtensionName -Current '' -Extension ([GPOToolsDirectory]::RegistryExtension) -Tool $script:PSGPOStarterTool.User } else { '' }
    $Directory.RestoreGpo($Gpo, $settings, $Gpo.Flags, $machine, $user)
}

# The Starter GPOs of a directory named $Name (Test-PSGPONameMatch), as the commands find them.
function Find-PSGPOStarterGpoByName {
    [CmdletBinding()]
    [OutputType('PSGPOTools.StarterGpo')]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Name
    )

    $found = @(Get-PSGPOStarterGpoData -Directory $Directory | Where-Object { Test-PSGPONameMatch -Name $_.DisplayName -Pattern $Name })
    if (-not $found) { throw "No Starter GPO named '$Name' in $($Directory.DomainName)." }
    $found
}
