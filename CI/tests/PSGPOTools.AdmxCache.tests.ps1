#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The cache of the ADMX files (Initialize-PSGPOAdmx, PSGPOAdmxCache.ps1): a folder parsed once is
# read again from the cache, with the same objects to the last property, while its files do not change.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $CacheBefore = $env:PSGPOTOOLS_CACHE_PATH
        $PolicyDefinitions = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'sources' 'PolicyDefinitions')).Path

        # Every case of the parser in one file: the element types, the lists of values, a value
        # of 64 bits, a choice with its list, a policy of class Both, a category missing (a
        # warning), an empty string, a text that is not ASCII, a text in a CDATA section and a
        # default value that reads as a date.
        $Admx = @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitions revision="1.0" schemaVersion="1.0">
  <policyNamespaces>
    <target prefix="cache" namespace="HGPM.Tests.Cache" />
  </policyNamespaces>
  <resources minRequiredRevision="1.0" />
  <supportedOn>
    <definitions>
      <definition name="SUPPORTED_Test" displayName="$(string.SUPPORTED_Test)" />
    </definitions>
  </supportedOn>
  <categories>
    <category name="Root" displayName="$(string.Root)" explainText="$(string.Root_Help)" />
    <category name="Child" displayName="$(string.Child)">
      <parentCategory ref="Root" />
    </category>
  </categories>
  <policies>
    <policy name="Everything" class="Both" displayName="$(string.Everything)" explainText="$(string.Everything_Help)" presentation="$(presentation.Everything)" key="Software\Policies\HGPM\Cache" valueName="On">
      <parentCategory ref="Child" />
      <supportedOn ref="SUPPORTED_Test" />
      <enabledValue><decimal value="1" /></enabledValue>
      <disabledValue><delete /></disabledValue>
      <enabledList defaultKey="Software\Policies\HGPM\Cache\List">
        <item valueName="A"><value><string>alpha</string></value></item>
        <item key="Software\Policies\HGPM\Other" valueName="B"><value><longDecimal value="18446744073709551615" /></value></item>
      </enabledList>
      <elements>
        <boolean id="Flag" valueName="Flag">
          <trueList><item valueName="FlagOn"><value><decimal value="7" /></value></item></trueList>
          <falseList><item valueName="FlagOff"><value><delete /></value></item></falseList>
        </boolean>
        <decimal id="Count" valueName="Count" minValue="2" maxValue="50" storeAsText="true" />
        <longDecimal id="Big" valueName="Big" maxValue="18446744073709551615" required="true" />
        <text id="Start" valueName="Start" maxLength="40" expandable="true" />
        <multiText id="Names" valueName="Names" maxStrings="5" />
        <enum id="Mode" valueName="Mode">
          <item displayName="$(string.Mode_Off)"><value><decimal value="0" /></value></item>
          <item displayName="$(string.Mode_On)"><value><string>on</string></value>
            <valueList><item valueName="ModeExtra"><value><decimal value="3" /></value></item></valueList>
          </item>
        </enum>
        <list id="Sites" key="Software\Policies\HGPM\Cache\Sites" valuePrefix="" additive="true" />
      </elements>
    </policy>
    <policy name="Orphan" class="Machine" displayName="$(string.Orphan)" explainText="$(string.Orphan_Help)" key="Software\Policies\HGPM\Cache" valueName="Orphan">
      <parentCategory ref="Missing" />
    </policy>
    <policy name="NoText" class="User" displayName="$(string.NoText)" key="Software\Policies\HGPM\Cache">
      <parentCategory ref="Root" />
    </policy>
  </policies>
</policyDefinitions>
'@
        $Adml = @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitionResources revision="1.0" schemaVersion="1.0">
  <displayName>Cache</displayName>
  <description>Cache</description>
  <resources>
    <stringTable>
      <string id="SUPPORTED_Test">At least the tests</string>
      <string id="Root">Root</string>
      <string id="Root_Help"></string>
      <string id="Child">Child</string>
      <string id="Everything">Everything "quoted" &amp; cafe</string>
      <string id="Everything_Help">Line one
Line two</string>
      <string id="Mode_Off">Off</string>
      <string id="Mode_On">On</string>
      <string id="Orphan">Orphan</string>
      <string id="Orphan_Help"><![CDATA[Its category is <missing>.]]></string>
      <string id="NoText">No text</string>
    </stringTable>
    <presentationTable>
      <presentation id="Everything">
        <checkBox refId="Flag" defaultChecked="true">Flag</checkBox>
        <decimalTextBox refId="Count" defaultValue="5" spinStep="5">Count</decimalTextBox>
        <longDecimalTextBox refId="Big" defaultValue="10">Big</longDecimalTextBox>
        <textBox refId="Start"><label>Start</label><defaultValue>2000-01-01T02:00:00</defaultValue></textBox>
        <multiTextBox refId="Names">Names</multiTextBox>
        <dropdownList refId="Mode" noSort="true" defaultItem="1">Mode</dropdownList>
        <listBox refId="Sites">Sites</listBox>
        <text>A free text line</text>
      </presentation>
    </presentationTable>
  </resources>
</policyDefinitionResources>
'@
        # A template whose policy is in a category of Cache.admx (a dependency).
        $Dependent = @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitions revision="1.0" schemaVersion="1.0">
  <policyNamespaces>
    <target prefix="dependent" namespace="HGPM.Tests.Dependent" />
    <using prefix="cache" namespace="HGPM.Tests.Cache" />
  </policyNamespaces>
  <resources minRequiredRevision="1.0" />
  <policies>
    <policy name="Dependent" class="Machine" displayName="$(string.Dependent)" key="Software\Policies\HGPM\Dependent" valueName="On">
      <parentCategory ref="cache:Child" />
    </policy>
  </policies>
</policyDefinitions>
'@
        $DependentAdml = @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitionResources revision="1.0" schemaVersion="1.0">
  <displayName>Dependent</displayName>
  <description>Dependent</description>
  <resources>
    <stringTable>
      <string id="Dependent">Dependent</string>
    </stringTable>
  </resources>
</policyDefinitionResources>
'@

        # A text that is not ASCII (written so: this file stays ASCII).
        $Adml = $Adml.Replace('&amp; cafe', "&amp; caf$([char]0xE9)")

        # A PolicyDefinitions folder of the file above, in the given languages.
        function New-CacheFolder {
            param([string]$Name, [string[]]$Culture = @('en-US'))
            $Path = Join-Path $TestDrive $Name
            $null = New-Item -ItemType Directory -Path $Path -Force
            Set-Content -LiteralPath (Join-Path $Path 'Cache.admx') -Value $Admx -Encoding utf8
            foreach ($Folder in $Culture) {
                $null = New-Item -ItemType Directory -Path (Join-Path $Path $Folder) -Force
                Set-Content -LiteralPath (Join-Path $Path $Folder 'Cache.adml') -Value $Adml -Encoding utf8
            }
            (Get-Item -LiteralPath $Path).FullName
        }

        # Loads a folder; Cached: whether it was read from the cache.
        function Read-CacheFolder {
            param([string]$Path, [string]$Culture = 'en-US', [switch]$NoCache)
            $Warnings = $null
            $Verbose = @(Initialize-PSGPOAdmx -Path $Path -UICulture $Culture -NoCache:$NoCache -Verbose -WarningVariable Warnings -WarningAction SilentlyContinue 4>&1)
            @{
                Cached = [bool]@($Verbose | Where-Object { "$_" -like 'ADMX files read from the cache*' }).Count
                Warnings = @($Warnings | ForEach-Object { "$_" })
            }
        }

        # Everything loaded, to the last property (the hidden ones too), with the type of each
        # value and $null apart from ''; $File keeps the policies of these files only.
        function Get-AdmxDump {
            param([string[]]$File)
            $Lines = [System.Collections.Generic.List[string]]::new()
            $Write = $null
            $Write = {
                param($Value, [string]$Prefix, [int]$Depth)
                if ($null -eq $Value) { $Lines.Add("$Prefix=<null>"); return }
                if ($Depth -gt 20) { throw "Too deep: $Prefix [$($Value.GetType().FullName)]" }
                $Type = $Value.GetType()
                if ($Type.IsPrimitive -or $Value -is [string] -or $Value -is [enum]) { $Lines.Add("$Prefix=[$($Type.Name)]$Value"); return }
                if ($Value -is [System.Collections.IDictionary]) {
                    foreach ($Key in @($Value.Keys | Sort-Object)) { & $Write $Value[$Key] "$Prefix{$Key}" ($Depth + 1) }
                    $Lines.Add("$Prefix=[$($Type.Name)]{$($Value.Count)}")
                    return
                }
                if ($Value -is [System.Collections.IEnumerable]) {
                    $Index = 0
                    foreach ($Item in $Value) { & $Write $Item "$Prefix[$Index]" ($Depth + 1); $Index++ }
                    $Lines.Add("$Prefix=[$($Type.Name)]#$Index")
                    return
                }
                # A category below a policy or another category: by its name and target.
                if ($Value -is [GPOToolsCategory] -and $Depth -gt 0) { $Lines.Add("$Prefix=CAT $($Value.Name)|$($Value.target.prefix)|$($Value.target.namespace)"); return }
                $Lines.Add("$Prefix=[$($Type.Name)]")
                foreach ($Property in $Type.GetProperties([System.Reflection.BindingFlags]'Public, Instance') | Sort-Object Name) {
                    if ($Property.GetIndexParameters().Count) { continue }
                    & $Write $Property.GetValue($Value) "$Prefix.$($Property.Name)" ($Depth + 1)
                }
            }
            $Index = 0
            foreach ($Policy in [GPOToolsUtility]::Policies) {
                if (-not $File -or $File -contains $Policy.FileName) { & $Write $Policy "P$Index" 0 }
                $Index++
            }
            if (-not $File) {
                $Index = 0; foreach ($Category in [GPOToolsUtility]::Categories) { & $Write $Category "C$Index" 0; $Index++ }
                $Index = 0; foreach ($Support in [GPOToolsUtility]::SupportOnTable) { & $Write $Support "S$Index" 0; $Index++ }
                $Lines.Add("TargetLoad=$([GPOToolsUtility]::TargetLoad -join ',')")
                $Lines.Add("NamespaceByFile=$(@([GPOToolsUtility]::NamespaceByFile.Keys | Sort-Object | ForEach-Object { "$_=$([GPOToolsUtility]::NamespaceByFile[$_])" }) -join ',')")
                $Lines.Add("CategoryIndex=$(@([GPOToolsUtility]::CategoryIndex.Keys | Sort-Object | ForEach-Object { "$_=$(@([GPOToolsUtility]::CategoryIndex[$_]).Count)" }) -join ',')")
            }
            $Lines.Add("Policies=$([GPOToolsUtility]::Policies.Count)")
            , $Lines.ToArray()
        }
    }
    AfterAll {
        $env:PSGPOTOOLS_CACHE_PATH = $CacheBefore
        [GPOToolsUtility]::RemoveAll()
    }

    Describe 'Cache of the ADMX files' {
        BeforeEach {
            $env:PSGPOTOOLS_CACHE_PATH = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        }

        It 'Reads a folder from the cache the second time, with the objects the files give' {
            $Path = New-CacheFolder 'Same'
            (Read-CacheFolder $Path -NoCache).Cached | Should -BeFalse
            $Parsed = Get-AdmxDump
            Test-Path -LiteralPath $env:PSGPOTOOLS_CACHE_PATH | Should -BeFalse -Because '-NoCache writes no cache'

            (Read-CacheFolder $Path).Cached | Should -BeFalse -Because 'there is no cache yet'
            @(Get-ChildItem -LiteralPath $env:PSGPOTOOLS_CACHE_PATH -Filter *.json).Count | Should -Be 1
            (Read-CacheFolder $Path).Cached | Should -BeTrue
            $Cached = Get-AdmxDump
            $Cached.Count | Should -Be $Parsed.Count
            @(Compare-Object $Parsed $Cached -SyncWindow 0 | Select-Object -First 5 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) | Should -BeNullOrEmpty

            # What the tests above would not see in a text: the types, the 64 bits, the sharing.
            $Machine, $User = @([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Everything')
            $Start = $Machine.Elements | Where-Object Id -EQ 'Start'
            $Start.DefaultValue | Should -BeOfType ([string]) -Because 'a text that reads as a date stays a text'
            $Start.DefaultValue | Should -Be '2000-01-01T02:00:00'
            ($Machine.Elements | Where-Object Id -EQ 'Flag').DefaultValue | Should -BeOfType ([bool])
            ($Machine.Elements | Where-Object Id -EQ 'Big').MaxValue | Should -Be ([uint64]::MaxValue)
            ($Machine.EnabledValues | Where-Object ValueName -EQ 'B').Value | Should -BeOfType ([uint64])
            ($Machine.EnabledValues | Where-Object ValueName -EQ 'A').Value | Should -BeOfType ([string])
            [object]::ReferenceEquals($Machine.Elements[0], $User.Elements[0]) | Should -BeTrue -Because 'the two scopes of a policy of class Both share their elements, as parsed'
            $Machine.DisplayName | Should -Be "Everything `"quoted`" & caf$([char]0xE9)"
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Orphan').Description | Should -Be 'Its category is <missing>.' -Because 'a text in a CDATA section is read'
        }

        It 'Loads the other files when one cannot be read, their categories included, and caches what it left out' {
            $Path = New-CacheFolder 'Unreadable'
            # A malformed file, and a template whose category is in Cache.admx, read before it:
            # the namespaces of the folder are read for its dependency, the malformed one too.
            Set-Content -LiteralPath (Join-Path $Path 'Broken.admx') -Value '<policyDefinitions><policies>' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $Path 'A.admx') -Value $Dependent -Encoding utf8
            Set-Content -LiteralPath (Join-Path $Path 'en-US' 'A.adml') -Value $DependentAdml -Encoding utf8
            $First = Read-CacheFolder $Path
            @($First.Warnings | Where-Object { $_ -like 'Broken.admx is not loaded: *' }).Count | Should -Be 1
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Dependent').Path | Should -Be 'Machine\Root\Child\' -Because 'the dependency is found, the malformed file aside'
            @([GPOToolsUtility]::Policies).Count | Should -Be 5
            @([GPOToolsUtility]::SkippedFiles) | Should -BeLike 'Broken.admx: *'

            # Malformed while it does not change: cached, and still said.
            $Again = Read-CacheFolder $Path
            $Again.Cached | Should -BeTrue
            @([GPOToolsUtility]::SkippedFiles) | Should -BeLike 'Broken.admx: *'
            $Again.Warnings | Should -Be $First.Warnings
        }

        It 'Undoes what a file added before it failed: nothing of it stays loaded' {
            # Two templates of the same prefix define VendorRoot; the third uses it through a
            # namespace that is missing: its policy finds two parents and the file fails after
            # its supportedOn, its category and a first policy were added.
            $Path = Join-Path $TestDrive 'HalfLoaded'
            $null = New-Item -ItemType Directory -Path (Join-Path $Path 'en-US') -Force
            $Vendor = {
                param($Name, $Namespace, $Body)
                Set-Content -LiteralPath (Join-Path $Path "$Name.admx") -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitions revision="1.0" schemaVersion="1.0">
  <policyNamespaces>
    <target prefix="vendor" namespace="$Namespace" />
    <using prefix="common" namespace="Vendor.Common" />
  </policyNamespaces>
  <resources minRequiredRevision="1.0" />
$Body
</policyDefinitions>
"@
                Set-Content -LiteralPath (Join-Path $Path 'en-US' "$Name.adml") -Encoding utf8 -Value @"
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitionResources revision="1.0" schemaVersion="1.0">
  <displayName>$Name</displayName><description>$Name</description>
  <resources><stringTable><string id="Text">$Name</string></stringTable></resources>
</policyDefinitionResources>
"@
            }
            $Root = '<categories><category name="VendorRoot" displayName="$(string.Text)" /></categories>'
            & $Vendor 'V1' 'Vendor.One' $Root
            & $Vendor 'V2' 'Vendor.Two' $Root
            & $Vendor 'V3' 'Vendor.Three' (@'
  <supportedOn><definitions><definition name="SUPPORTED_V3" displayName="$(string.Text)" /></definitions></supportedOn>
  <categories><category name="Own" displayName="$(string.Text)" /></categories>
  <policies>
    <policy name="First" class="Machine" displayName="$(string.Text)" key="Software\Policies\Vendor" valueName="First"><parentCategory ref="Own" /></policy>
    <policy name="Second" class="Machine" displayName="$(string.Text)" key="Software\Policies\Vendor" valueName="Second"><parentCategory ref="common:VendorRoot" /></policy>
  </policies>
'@ -replace 'ref="common:VendorRoot"', 'ref="vendor:VendorRoot"')
            $Loaded = Read-CacheFolder $Path
            @([GPOToolsUtility]::SkippedFiles) | Should -BeLike 'V3.admx: *'
            @([GPOToolsUtility]::Policies | Where-Object FileName -EQ 'V3.admx').Count | Should -Be 0
            @([GPOToolsUtility]::Categories | Where-Object Name -EQ 'Own').Count | Should -Be 0
            @([GPOToolsUtility]::CategoryIndex['Own']).Count | Should -Be 0
            @([GPOToolsUtility]::SupportOnTable | Where-Object Name -EQ 'SUPPORTED_V3').Count | Should -Be 0
            @([GPOToolsUtility]::Categories | Where-Object Name -EQ 'VendorRoot').Count | Should -Be 2 -Because 'V1 and V2 are loaded'
            @($Loaded.Warnings | Where-Object { $_ -like 'V3.admx is not loaded: *To many ParentCategory*' }).Count | Should -Be 1
        }

        It 'Counts a file not reached, or a folder not listed, as an error that may pass' {
            [GPOToolsUtility]::IsTransient([System.IO.FileNotFoundException]::new('gone')) | Should -BeTrue
            [GPOToolsUtility]::IsTransient([System.Management.Automation.ItemNotFoundException]::new('gone')) | Should -BeTrue
            [GPOToolsUtility]::IsTransient([System.Exception]::new('outer', [System.UnauthorizedAccessException]::new('denied'))) | Should -BeTrue
            [GPOToolsUtility]::IsTransient([System.Xml.XmlException]::new('malformed')) | Should -BeFalse
            [GPOToolsUtility]::IsTransient([System.Management.Automation.RuntimeException]::new("The ADML File x doesn't exist.")) | Should -BeFalse
            # A file gone between the listing and its reading: whatever the -ErrorAction of the caller.
            $Missing = [System.IO.FileInfo](Join-Path $TestDrive 'Gone' 'Gone.admx')
            { [GPOToolsUtility]::InitiateAdmxAdml($Missing, [cultureinfo]'en-US') } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
        }

        It 'Fails and loads nothing when no file can be read' {
            # fr-FR has an ADML, not for this template, and there is no en-US.
            $Path = New-CacheFolder 'Nothing' 'fr-FR'
            Move-Item -LiteralPath (Join-Path $Path 'fr-FR' 'Cache.adml') -Destination (Join-Path $Path 'fr-FR' 'Other.adml')
            { Initialize-PSGPOAdmx -Path $Path -UICulture fr-FR -WarningAction SilentlyContinue } | Should -Throw "*No ADMX file of*can be loaded in fr-FR: Cache.admx: *"
            [GPOToolsUtility]::Policies.Count | Should -Be 0
            [GPOToolsUtility]::SkippedFiles.Count | Should -Be 0
            Test-Path -LiteralPath $env:PSGPOTOOLS_CACHE_PATH | Should -BeFalse
        }

        It 'Takes the ADML of en-US for a template without the language, and parses again when it comes' {
            $Path = New-CacheFolder 'Fallback' 'en-US', 'fr-FR'
            Remove-Item -LiteralPath (Join-Path $Path 'fr-FR' 'Cache.adml')
            Set-Content -LiteralPath (Join-Path $Path 'fr-FR' 'Other.adml') -Value $Adml -Encoding utf8
            $First = Read-CacheFolder $Path 'fr-FR'
            $First.Warnings | Should -Contain 'Cache.admx has no ADML in fr-FR: the one of en-US is used.'
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'NoText').DisplayName | Should -Be 'No text'
            $Again = Read-CacheFolder $Path 'fr-FR'
            $Again.Cached | Should -BeTrue
            $Again.Warnings | Should -Be $First.Warnings

            # Its ADML in French: the stamp watches the folder of the language.
            Set-Content -LiteralPath (Join-Path $Path 'fr-FR' 'Cache.adml') -Value ($Adml -replace '>No text<', '>Sans texte<') -Encoding utf8
            (Read-CacheFolder $Path 'fr-FR').Cached | Should -BeFalse
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'NoText').DisplayName | Should -Be 'Sans texte'
        }

        It 'Shows the warnings of the files again when it reads the cache' {
            $Path = New-CacheFolder 'Warnings'
            $First = Read-CacheFolder $Path
            $First.Warnings | Should -BeLike '*No ParentCategory found for Orphan*'
            $Again = Read-CacheFolder $Path
            $Again.Cached | Should -BeTrue
            $Again.Warnings | Should -Be $First.Warnings
        }

        It 'Parses the files again when one of them changes' {
            $Path = New-CacheFolder 'Changed'
            $null = Read-CacheFolder $Path
            $File = Join-Path $Path 'en-US' 'Cache.adml'
            Set-Content -LiteralPath $File -Value ($Adml -replace '>Orphan<', '>Orphan again<') -Encoding utf8
            (Read-CacheFolder $Path).Cached | Should -BeFalse
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Orphan').DisplayName | Should -Be 'Orphan again'
            (Read-CacheFolder $Path).Cached | Should -BeTrue -Because 'the cache was written again'

            # A file of the same size, of another date.
            (Get-Item -LiteralPath $File).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-5)
            (Read-CacheFolder $Path).Cached | Should -BeFalse
        }

        It 'Parses the files again when the cache cannot be read' {
            $Path = New-CacheFolder 'Broken'
            $null = Read-CacheFolder $Path
            $Cache = Get-ChildItem -LiteralPath $env:PSGPOTOOLS_CACHE_PATH -Filter *.json | Select-Object -First 1
            $Text = [System.IO.File]::ReadAllText($Cache.FullName)
            [System.IO.File]::WriteAllText($Cache.FullName, $Text.Substring(0, [int]($Text.Length / 2)))

            (Read-CacheFolder $Path).Cached | Should -BeFalse
            @([GPOToolsUtility]::Policies).Count | Should -Be 4 -Because 'Everything for both scopes, Orphan and NoText'
            (Read-CacheFolder $Path).Cached | Should -BeTrue -Because 'the cache was written again'
        }

        It 'Keeps a cache for each folder and language' {
            $Path = New-CacheFolder 'Languages' 'en-US', 'fr-FR'
            Set-Content -LiteralPath (Join-Path $Path 'fr-FR' 'Cache.adml') -Value ($Adml -replace '>No text<', '>Sans texte<') -Encoding utf8
            $null = Read-CacheFolder $Path 'en-US'
            $null = Read-CacheFolder $Path 'fr-FR'
            @(Get-ChildItem -LiteralPath $env:PSGPOTOOLS_CACHE_PATH -Filter *.json).Count | Should -Be 2
            (Read-CacheFolder $Path 'en-US').Cached | Should -BeTrue
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'NoText').DisplayName | Should -Be 'No text'
            (Read-CacheFolder $Path 'fr-FR').Cached | Should -BeTrue
            ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'NoText').DisplayName | Should -Be 'Sans texte'
        }

        It 'Names the settings of a GPO with the policies loaded last, the files loaded again' {
            # The same policies in another language: as many, in the same list.
            $Path = New-CacheFolder 'Reloaded' 'en-US', 'fr-FR'
            Set-Content -LiteralPath (Join-Path $Path 'fr-FR' 'Cache.adml') -Value ($Adml -replace '>Orphan<', '>Orpheline<') -Encoding utf8
            $null = Read-CacheFolder $Path 'en-US'
            $Pol = [GPOToolsRegistryPol]::new()
            Set-PSGPOPolicyState -Policy ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Orphan') -Pol $Pol -State Enabled
            (Get-PSGPOConfiguredPolicy -Pol $Pol -Scope Machine).Policy.DisplayName | Should -Be 'Orphan'

            $null = Read-CacheFolder $Path 'fr-FR'
            $Configured = @(Get-PSGPOConfiguredPolicy -Pol $Pol -Scope Machine)
            $Configured.Policy.DisplayName | Should -Be 'Orpheline'
            [object]::ReferenceEquals($Configured[0].Policy, ([GPOToolsUtility]::Policies | Where-Object ID -EQ 'Orphan')) | Should -BeTrue
        }

        It 'Reads the ADMX files of Windows from the cache as they are parsed' {
            # A few of them: a default value that reads as a date (msched), choices with their
            # lists (Bits), policies of class Both (AutoPlay), and the files they need.
            $Path = Join-Path $TestDrive 'Windows'
            $null = New-Item -ItemType Directory -Path (Join-Path $Path 'en-US') -Force
            foreach ($Name in 'Windows', 'msched', 'Bits', 'AutoPlay') {
                Copy-Item -LiteralPath (Join-Path $PolicyDefinitions "$Name.admx") -Destination $Path
                Copy-Item -LiteralPath (Join-Path $PolicyDefinitions 'en-US' "$Name.adml") -Destination (Join-Path $Path 'en-US')
            }
            $null = Read-CacheFolder $Path -NoCache
            $Parsed = Get-AdmxDump
            $null = Read-CacheFolder $Path
            (Read-CacheFolder $Path).Cached | Should -BeTrue
            $Cached = Get-AdmxDump
            [GPOToolsUtility]::Policies.Count | Should -BeGreaterThan 20
            @(Compare-Object $Parsed $Cached -SyncWindow 0 | Select-Object -First 5 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) | Should -BeNullOrEmpty
            (([GPOToolsUtility]::Policies | Where-Object ID -EQ 'ActivationBoundaryPolicy').Elements | Where-Object Id -EQ 'ActivationBoundary').DefaultValue | Should -Be '2000-01-01T02:00:00'
        }
    }
}
