#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# WMI filters: the queries of msWMI-Parm2, the link of a GPO (gPCWQLFilter), the commands, and
# the WMI filter in the backups, the drift and the restore; on a directory in memory.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $SamplePath = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'Samples' 'Directory.sample.json'
    }

    Describe 'msWMI-Parm2 and gPCWQLFilter' {
        It 'Reads the queries GPMC writes, a semicolon in a query included' {
            $Text = '2;3;10;57;WQL;root\CIMv2;SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1;3;10;46;WQL;root\CIMv2;SELECT * FROM Win32_Service WHERE Name = "a;b";'
            $Queries = @(ConvertFrom-PSGPOWmiQueryText -Text $Text)
            $Queries.Count | Should -Be 2
            $Queries[0].Namespace | Should -Be 'root\CIMv2'
            $Queries[0].Query | Should -Be 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'
            $Queries[1].Query | Should -Be 'SELECT * FROM Win32_Service WHERE Name = "a;b"'
            ConvertTo-PSGPOWmiQueryText -Query $Queries | Should -BeExactly $Text
        }

        It 'Refuses what is not a list of queries' {
            { ConvertFrom-PSGPOWmiQueryText -Text '1;3;10;99;WQL;root\CIMv2;SELECT;' } | Should -Throw -ExpectedMessage 'Not the queries of a WMI filter*'
        }

        It 'Reads the filter a GPO is linked to' {
            ConvertFrom-PSGPOWqlFilterLink -Value '[contoso.com;{6C5B8B5E-3F5A-4C3E-9D4B-2A1B3C4D5E6F};0]' | Should -Be ([guid]'6c5b8b5e-3f5a-4c3e-9d4b-2a1b3c4d5e6f')
            ConvertFrom-PSGPOWqlFilterLink -Value '' | Should -BeNullOrEmpty
            ConvertFrom-PSGPOWqlFilterLink -Value 'garbage' | Should -BeNullOrEmpty
        }
    }

    Describe 'WMI filters of a directory in memory' {
        BeforeEach {
            $Directory = Import-PSGPODirectory -Path $SamplePath
            $Gpo = $Directory.FindGpo('C - Laptops - Power Management')
        }

        It 'Creates a filter, links a GPO to it, and shows it in the details' {
            $Filter = New-PSGPOWmiFilter -Directory $Directory -Name 'Laptops' -Query 'SELECT * FROM Win32_Battery' -Description 'Computers with a battery'
            $Filter.Queries | Should -Be 'root\CIMv2: SELECT * FROM Win32_Battery'
            (Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -WmiFilter 'Laptops').WmiFilterId | Should -Be $Filter.Id
            @((Get-PSGPOWmiFilter -Directory $Directory -Name 'Laptops').Gpos) | Should -Be @('C - Laptops - Power Management')
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo
            ($Detail.Properties | Where-Object Key -EQ 'WMI filter').Value | Should -Be 'Laptops (root\CIMv2: SELECT * FROM Win32_Battery)'
            { New-PSGPOWmiFilter -Directory $Directory -Name 'laptops' -Query 'SELECT * FROM Win32_Battery' } | Should -Throw -ExpectedMessage '*already exists*'
        }

        It 'Does not delete a filter a GPO uses, then deletes it once unlinked' {
            $null = New-PSGPOWmiFilter -Directory $Directory -Name 'Laptops' -Query 'SELECT * FROM Win32_Battery'
            $null = Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -WmiFilter 'Laptops'
            Remove-PSGPOWmiFilter -Directory $Directory -Name 'Laptops' -Confirm:$false -ErrorVariable Problem -ErrorAction SilentlyContinue
            "$Problem" | Should -BeLike '*is used by C - Laptops - Power Management*'
            $null = Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -NoWmiFilter
            $Gpo.WmiFilterId | Should -BeNullOrEmpty
            Remove-PSGPOWmiFilter -Directory $Directory -Name 'Laptops' -Confirm:$false
            $Directory.WmiFilters.Count | Should -Be 0
        }

        It 'Changes the name, description and queries of a filter, the GPO linked to it keeping it' {
            $Filter = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Directory.SetWmiFilter($Gpo, $Filter)
            $null = New-PSGPOWmiFilter -Directory $Directory -Name 'Workstations' -Query 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 1'

            $Result = Set-PSGPOWmiFilter -Directory $Directory -Name 'Laptops' -NewName 'Portables' -Query 'SELECT * FROM Win32_Battery', 'SELECT * FROM Win32_PortableBattery'
            $Result.Name | Should -Be 'Portables'
            $Result.Queries | Should -Be 'root\CIMv2: SELECT * FROM Win32_Battery; root\CIMv2: SELECT * FROM Win32_PortableBattery'
            $Result.Description | Should -Be 'Computers with a battery' -Because 'what is not given does not change'
            @($Result.Gpos) | Should -Be @('C - Laptops - Power Management')
            $Gpo.WmiFilterId | Should -Be $Filter.Id
            @($Directory.WmiFilters.Name) | Should -Be @('Portables', 'Workstations') -Because 'the filters stay sorted by name'

            $Result = Set-PSGPOWmiFilter -Directory $Directory -Name 'Portables' -Description '' -Namespace 'root\cimv2'
            $Result.Description | Should -BeNullOrEmpty
            $Result.Queries | Should -BeLike 'root\cimv2: *; root\cimv2: *'

            { Set-PSGPOWmiFilter -Directory $Directory -Name 'Portables' -NewName 'workstations' } | Should -Throw -ExpectedMessage "*'workstations' already exists*"
            { Set-PSGPOWmiFilter -Directory $Directory -Name 'Portables' } | Should -Throw -ExpectedMessage '*what changes*'
            { Set-PSGPOWmiFilter -Directory $Directory -Name 'Nothing' -Description '' } | Should -Throw -ExpectedMessage "*No WMI filter named 'Nothing'*"
            { $Directory.EditWmiFilter($Filter, 'Portables', '', @()) } | Should -Throw -ExpectedMessage '*at least one query*'
            # A name that only changes its case is the same filter.
            (Set-PSGPOWmiFilter -Directory $Directory -Name 'Portables' -NewName 'PORTABLES').Name | Should -Be 'PORTABLES'
        }

        It 'Shows WMI Filters and each filter, with its queries and the GPOs using it' {
            $Filter = $Directory.NewWmiFilter('Laptops', 'Computers with a battery', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Directory.SetWmiFilter($Gpo, $Filter)
            $Node = (New-PSGPODirectoryTree -Directory $Directory)[0].Children | Where-Object Header -EQ 'WMI Filters'
            @($Node.Children.Tag) | Should -Be @($Filter)
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item 'WmiFilters'
            ($Detail.Properties | Where-Object Key -EQ 'Laptops').Value | Should -Be 'root\CIMv2: SELECT * FROM Win32_Battery'
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Filter
            $Detail.Title | Should -Be 'Laptops'
            ($Detail.Properties | Where-Object Key -EQ 'Query').Value | Should -Be 'root\CIMv2: SELECT * FROM Win32_Battery'
            ($Detail.Properties | Where-Object Key -EQ 'GPOs using it').Value | Should -Be 'C - Laptops - Power Management'
            ($Detail.Properties | Where-Object Key -EQ 'Description').Value | Should -Be 'Computers with a battery'
        }

        It 'Says a filter is not in the domain anymore' {
            $Gpo.WmiFilterId = [guid]::NewGuid()
            $Detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $Gpo
            ($Detail.Properties | Where-Object Key -EQ 'WMI filter').Value | Should -BeLike '*not in the domain anymore*'
        }

        It 'Refuses an unknown filter and a call that changes nothing' {
            { Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName -WmiFilter 'Nothing' } | Should -Throw -ExpectedMessage "*No WMI filter named 'Nothing'*"
            { Set-PSGPO -Directory $Directory -Name $Gpo.DisplayName } | Should -Throw -ExpectedMessage '*what changes*'
        }

        It 'Backs up the filter of a GPO, shows when it changed, and links it again at the restore' {
            $Root = Join-Path $TestDrive "wmi-$([guid]::NewGuid())"
            $Filter = $Directory.NewWmiFilter('Laptops', '', @([pscustomobject]@{ Namespace = 'root\CIMv2'; Query = 'SELECT * FROM Win32_Battery' }))
            $Directory.SetWmiFilter($Gpo, $Filter)
            $With = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $With.WmiFilter.Name | Should -Be 'Laptops'
            $With.HasWmiFilter | Should -BeTrue

            $Directory.SetWmiFilter($Gpo, $null)
            $Without = Backup-PSGPO -Directory $Directory -Path $Root -Name $Gpo.DisplayName
            $Without.Result | Should -Be 'Created' -Because 'the GPO changed: its WMI filter'
            $Change = @(Compare-PSGPOBackup -ReferenceBackup $With -DifferenceBackup $Without) | Where-Object Name -EQ 'WMI filter'
            $Change.Change | Should -Be 'Removed'

            $Result = Restore-PSGPO -Backup $With -Directory $Directory -Confirm:$false
            $Gpo.WmiFilterId | Should -Be $Filter.Id -Because 'the restore links it again'
            $Result.Problems | Should -BeNullOrEmpty

            # A filter deleted since: the restore says so.
            $Directory.SetWmiFilter($Gpo, $null)
            $Directory.RemoveWmiFilter($Filter)
            $Result = Restore-PSGPO -Backup $With -Directory $Directory -Confirm:$false
            "$($Result.Problems)" | Should -BeLike "*WMI filter 'Laptops' is not in the domain anymore*"
        }
    }
}
