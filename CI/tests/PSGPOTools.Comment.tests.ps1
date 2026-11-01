#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The comment of a GPO, as GPMC keeps it (GPO.cmt at the root of its folder, UTF-16 with a byte
# order mark): its text whatever the encoding of the file, written without changing the version
# of the GPO, by Set-PSGPO and New-PSGPO, and in the report. The file in a real SYSVOL is tested in
# PSGPOTools.Ldap.tests.ps1.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
    }

    Describe 'GPO.cmt' {
        It 'Reads UTF-16 with its mark (GPMC), big endian, UTF-8 with or without a mark, and UTF-16 without one' {
            $Text = "CHG-2041: kiosques`r`nowner: workplace"
            ConvertFrom-PSGPOCommentByte -Bytes ([byte[]](@(0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Text))) | Should -BeExactly $Text
            ConvertFrom-PSGPOCommentByte -Bytes ([byte[]](@(0xFE, 0xFF) + [System.Text.Encoding]::BigEndianUnicode.GetBytes($Text))) | Should -BeExactly $Text
            ConvertFrom-PSGPOCommentByte -Bytes ([byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($Text))) | Should -BeExactly $Text
            ConvertFrom-PSGPOCommentByte -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)) | Should -BeExactly $Text
            ConvertFrom-PSGPOCommentByte -Bytes ([System.Text.Encoding]::Unicode.GetBytes($Text)) | Should -BeExactly $Text
            ConvertFrom-PSGPOCommentByte -Bytes ([byte[]](@(0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes("$Text`0"))) | Should -BeExactly $Text -Because 'a final NUL is not text'
            ConvertFrom-PSGPOCommentByte -Bytes $null | Should -BeExactly ''
            ConvertFrom-PSGPOCommentByte -Bytes ([byte[]]@()) | Should -BeExactly ''
        }

        It 'Writes UTF-16 little endian with its mark, the lines ended by CR LF, as GPMC' {
            $Bytes = ConvertTo-PSGPOCommentByte -Comment "first`nsecond"
            $Bytes[0..1] | Should -Be @(0xFF, 0xFE)
            [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) | Should -BeExactly "first`r`nsecond"
            (ConvertTo-PSGPOCommentByte -Comment '').Length | Should -Be 2 -Because 'no comment: the mark only'
        }
    }

    Describe 'Comment of a GPO in a directory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = @($Directory.Gpos | Where-Object CanEdit)[0]
        }

        It 'Has none at first, then the one written, the version of the GPO unchanged' {
            $Directory.ReadGpoComment($Gpo) | Should -BeExactly ''
            $Version = $Gpo.Version
            $Directory.WriteGpoComment($Gpo, "Owner: workplace team`nCHG-2041")
            $Directory.ReadGpoComment($Gpo) | Should -BeExactly "Owner: workplace team`r`nCHG-2041"
            $Gpo.Version | Should -Be $Version -Because 'the comment is not a setting the computers apply'
            $Directory.ReadGpoFile($Gpo, 'GPO.cmt')[0..1] | Should -Be @(0xFF, 0xFE)
        }

        It 'Refuses the comment of a GPO the account does not edit' {
            $Other = $Gpo
            $Other.CanEdit = $false
            { $Directory.WriteGpoComment($Other, 'x') } | Should -Throw '*cannot edit the GPO*'
        }

        It 'Is not a setting: the Settings tab and the drift leave it out' {
            $Directory.WriteGpoComment($Gpo, 'A comment')
            $Settings = Get-PSGPOFolderSetting -Files $Directory.ReadGpoFolder($Gpo) -MachineExtensionNames $Gpo.MachineExtensionNames -UserExtensionNames $Gpo.UserExtensionNames
            @($Settings.Uninterpreted).Name | Should -Not -Contain 'GPO.cmt'
        }
    }

    Describe 'Commands' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Directory.IsReadOnly = $false
            $Gpo = @($Directory.Gpos | Where-Object CanEdit)[0]
        }

        It 'Set-PSGPO -Comment sets it, and an empty text removes it' {
            $Result = Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -Comment 'CHG-2041' -Confirm:$false
            $Result | Should -Be $Gpo
            $Directory.ReadGpoComment($Gpo) | Should -BeExactly 'CHG-2041'
            Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -Comment '' -Confirm:$false | Out-Null
            $Directory.ReadGpoComment($Gpo) | Should -BeExactly ''
        }

        It 'Set-PSGPO -Comment changes nothing with -WhatIf, and says what it would do' {
            Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -Comment 'never' -WhatIf 6>$null | Should -BeNullOrEmpty
            $Directory.ReadGpoComment($Gpo) | Should -BeExactly ''
        }

        It 'New-PSGPO -Comment creates the GPO with its comment' {
            $New = New-PSGPO -Directory $Directory -Name 'C - Kiosks - Halls' -Comment "Kiosks of the halls`nOwner: workplace" -Confirm:$false
            $Directory.ReadGpoComment($New) | Should -BeExactly "Kiosks of the halls`r`nOwner: workplace"
        }
    }

    Describe 'Report of a GPO' {
        It 'Has its comment, the lines kept in the HTML page' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = @($Directory.Gpos | Where-Object CanEdit)[0]
            $Directory.WriteGpoComment($Gpo, "CHG-2041 <kiosks>`nOwner: workplace")
            $Data = Get-PSGPOReportData -Directory $Directory -Gpo $Gpo
            $Data.Comment | Should -BeExactly "CHG-2041 <kiosks>`r`nOwner: workplace"
            ConvertTo-PSGPOReportHtml -Report $Data | Should -BeLike '*<td>Comment</td><td>CHG-2041 &lt;kiosks&gt;<br>Owner: workplace</td>*'
        }

        It 'Has no comment row without a comment' {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = @($Directory.Gpos | Where-Object CanEdit)[0]
            (Get-PSGPOReportData -Directory $Directory -Gpo $Gpo).Comment | Should -BeExactly ''
            ConvertTo-PSGPOReportHtml -Report (Get-PSGPOReportData -Directory $Directory -Gpo $Gpo) | Should -Not -BeLike '*<td>Comment</td>*'
        }
    }
}
