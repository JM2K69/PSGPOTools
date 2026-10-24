#Requires -Version 7.4
<#
    Makes the fixture of the tests of the rule sets (PSGPOTools.PolicyRules.tests.ps1): two GPMC
    backups of our own in GPOs\ (every registry type, every kind of security setting and audit
    line, a duplicate and conflicts between the two GPOs), then gpo2policyrules.PolicyRules, the
    rule set GPO2PolicyRules.exe of the Microsoft Security Compliance Toolkit makes from them (the
    folder of the fixture written %FIXTURE% in its paths): what Get-PSGPOPolicyRuleSet must make.

    Run on Windows, after CI/03_Build.ps1:
        pwsh -File CI/tests/Fixtures/PolicyRules/New-PolicyRulesFixture.ps1 -Gpo2PolicyRules <path>\GPO2PolicyRules.exe
#>
param([Parameter(Mandatory)] [string]$Gpo2PolicyRules)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' '..' '..' '..' 'HGPM' 'HGPM.psd1') -Force 3>$null
$root = $PSScriptRoot
$gpos = Join-Path $root 'GPOs'
if (Test-Path -LiteralPath $gpos) { Remove-Item -LiteralPath $gpos -Recurse -Force }

# A backup as Backup-GPO writes it, with the files given (path in the GPO -> bytes).
function New-FixtureBackup {
    param([string]$BackupId, [string]$GpoId, [string]$Name, [string]$Machine, [string]$User, [hashtable]$Files)
    $folder = Join-Path $gpos $BackupId
    $null = New-Item -ItemType Directory -Path $folder
    $info = '<BackupInst xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations/Manifest"><GPOGuid><![CDATA[{0}]]></GPOGuid><GPODomain><![CDATA[hgpm.test]]></GPODomain><GPODomainGuid><![CDATA[{{11111111-2222-3333-4444-555555555555}}]]></GPODomainGuid><GPODomainController><![CDATA[dc.hgpm.test]]></GPODomainController><BackupTime><![CDATA[2026-10-24T10:00:00]]></BackupTime><ID><![CDATA[{1}]]></ID><Comment><![CDATA[]]></Comment><GPODisplayName><![CDATA[{2}]]></GPODisplayName></BackupInst>' -f $GpoId, $BackupId, $Name
    [System.IO.File]::WriteAllText((Join-Path $folder 'bkupInfo.xml'), $info)
    $backup = '<?xml version="1.0" encoding="utf-8"?><GroupPolicyBackupScheme bkp:version="2.0" bkp:type="GroupPolicyBackupTemplate" xmlns:bkp="http://www.microsoft.com/GroupPolicy/GPOOperations" xmlns="http://www.microsoft.com/GroupPolicy/GPOOperations"><GroupPolicyObject><SecurityGroups/><FilePaths/><GroupPolicyCoreSettings><ID><![CDATA[{0}]]></ID><Domain><![CDATA[hgpm.test]]></Domain><DisplayName><![CDATA[{1}]]></DisplayName><Options><![CDATA[0]]></Options><UserVersionNumber><![CDATA[65537]]></UserVersionNumber><MachineVersionNumber><![CDATA[65537]]></MachineVersionNumber><MachineExtensionGuids><![CDATA[{2}]]></MachineExtensionGuids><UserExtensionGuids><![CDATA[{3}]]></UserExtensionGuids><WMIFilter/></GroupPolicyCoreSettings></GroupPolicyObject></GroupPolicyBackupScheme>' -f $GpoId, $Name, $Machine, $User
    [System.IO.File]::WriteAllText((Join-Path $folder 'Backup.xml'), $backup)
    foreach ($path in $Files.Keys) {
        $file = [System.IO.Path]::Combine([string[]](@($folder, 'DomainSysvol', 'GPO') + ($path -split '\\')))
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $file -Parent) -Force
        [System.IO.File]::WriteAllBytes($file, [byte[]]$Files[$path])
    }
}

$pol = { param([object[]]$Entries) & (Get-Module HGPM) {
        param($Entries)
        $file = [GPOToolsRegistryPol]::new()
        foreach ($entry in $Entries) { $file.Entries.Add([GPOToolsPolEntry]::new($entry[0], $entry[1], [GPOToolsPolType]$entry[2], [byte[]]$entry[3])) }
        , $file.ToBytes()
    } $Entries }
$text = { param([string]$Value) [System.Text.Encoding]::Unicode.GetBytes($Value + [char]0) }
$dword = { param([uint32]$Value) [BitConverter]::GetBytes($Value) }
$key = 'Software\Policies\HGPM Test'

$machineA = & $pol @(
    , @($key, 'Text', 'String', (& $text "it's <a> & `"b`"`tc"))
    , @($key, 'Expand', 'ExpandString', (& $text '%SystemRoot%\System32'))
    , @($key, 'Multi', 'MultiString', [System.Text.Encoding]::Unicode.GetBytes("one`0two`0three`0`0"))
    , @($key, 'MultiEmpty', 'MultiString', [System.Text.Encoding]::Unicode.GetBytes("`0"))
    , @($key, 'Binary', 'Binary', [byte[]](1, 2, 0xAB, 0xFF))
    , @($key, 'Number', 'DWord', (& $dword 4294967295))
    , @($key, 'Big', 'QWord', [BitConverter]::GetBytes([uint64]12345678901))
    , @($key, 'BigEndian', 'DWordBigEndian', [byte[]](0, 0, 1, 0))
    , @($key, 'Same', 'DWord', (& $dword 1))
    , @($key, 'Differs', 'DWord', (& $dword 1))
    , @($key, 'TypeDiffers', 'DWord', (& $dword 5))
    , @($key, '**del.Gone', 'String', (& $text ' '))
    , @("$key\List", '**delvals.', 'String', (& $text ' '))
    , @("$key\List", '1', 'String', (& $text 'first'))
    , @("$key\Created", '', 'None', [byte[]]::new(0))
    , @($key, 'Empty', 'String', (& $text ''))
)
$userA = & $pol @(, @($key, 'UserValue', 'DWord', (& $dword 2)))
$machineB = & $pol @(
    , @($key, 'Same', 'DWord', (& $dword 1))
    , @($key, 'Differs', 'DWord', (& $dword 2))
    , @($key, 'TypeDiffers', 'String', (& $text '5'))
    , @($key, 'OnlyB', 'DWord', (& $dword 0))
)
$templateA = @'
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordAge = 1
NewAdministratorName = "Admin Name"
[Event Audit]
AuditSystemEvents = 3
[Kerberos Policy]
MaxTicketAge = 10
[Registry Values]
MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash=4,1
MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\LegalNoticeText=7,Line one,Line two
[Privilege Rights]
SeBackupPrivilege = *S-1-5-32-551,*S-1-5-32-544
SeDenyNetworkLogonRight = Guests
[Service General Setting]
"Spooler",4,"D:AR(A;;RPWPCCDCLCSWRCWDWOGA;;;BA)"
"XblGameSave",4,""
[Registry Keys]
"MACHINE\SOFTWARE\HGPM",0,"D:PAR(A;CI;KA;;;BA)"
[File Security]
"%SystemRoot%\HGPM",2,"D:PAR(A;OICI;FA;;;BA)"
[Group Membership]
*S-1-5-32-544__Memberof =
*S-1-5-32-544__Members = *S-1-5-21-1-2-3-500
[Version]
signature="$CHICAGO$"
Revision=1
'@
$templateB = @'
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordAge = 2
[Privilege Rights]
SeBackupPrivilege = *S-1-5-32-544,*S-1-5-32-551
[Version]
signature="$CHICAGO$"
Revision=1
'@
$audit = "Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value`r`n" +
    ",System,Audit Credential Validation,{0cce923f-69ae-11d9-bed3-505054503030},Success and Failure,,3`r`n" +
    ",System,Audit Logon,{0cce9215-69ae-11d9-bed3-505054503030},No Auditing,,0`r`n" +
    ",,Option:CrashOnAuditFail,,Enabled,,1`r`n" +
    ",System,RegistryGlobalSacl,,,,D:(AU;SA;KA;;;WD)`r`n"
$unicode = { param([string]$Value) [byte[]](0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes($Value.Replace("`r`n", "`n").Replace("`n", "`r`n") + "`r`n") }
$securityPath = 'Machine\microsoft\windows nt\SecEdit\GptTmpl.inf'

New-FixtureBackup -BackupId '{A1A1A1A1-0000-4000-8000-000000000001}' -GpoId '{B1B1B1B1-0000-4000-8000-000000000001}' -Name 'HGPM Test - Computer' `
    -Machine '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}][{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}][{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]' `
    -User '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F73-3407-48AE-BA88-E8213C6761F1}]' `
    -Files @{
        'Machine\registry.pol' = $machineA
        'User\registry.pol' = $userA
        $securityPath = (& $unicode $templateA)
        'Machine\microsoft\windows nt\Audit\audit.csv' = [System.Text.Encoding]::UTF8.GetBytes($audit)
    }
New-FixtureBackup -BackupId '{A1A1A1A1-0000-4000-8000-000000000002}' -GpoId '{B1B1B1B1-0000-4000-8000-000000000002}' -Name 'HGPM Test - Second' `
    -Machine '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}][{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]' `
    -User '' `
    -Files @{
        'Machine\registry.pol' = $machineB
        $securityPath = (& $unicode $templateB)
    }

$out = Join-Path $root 'gpo2policyrules.PolicyRules'
& $Gpo2PolicyRules $gpos $out | Out-Null
if ($LASTEXITCODE) { throw "GPO2PolicyRules.exe failed ($LASTEXITCODE)." }
$bytes = [System.IO.File]::ReadAllBytes($out)
$content = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3).Replace("$root\", '%FIXTURE%\')
[System.IO.File]::WriteAllBytes($out, [byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($content))
Get-Item -LiteralPath $out
