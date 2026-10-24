<#
    The effective state of the computer for the settings of rule sets, as "Compare to Effective
    State" of Policy Analyzer reads it: the registry values of the computer (HKLM) and of the user
    (HKCU), those of the security options ([Registry Values]) and the startup of the services
    included, the other security settings (secedit /export: the security database of the
    computer, where Group Policy applies them) and the advanced audit policy (auditpol /backup).
    secedit and auditpol need an administrator: without, those settings are left out. Windows only.
#>

# Whether the effective state can be read here: on Windows.
function Test-PSGPOEffectiveStateSupported {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    [bool]$IsWindows
}

# Whether the session runs as an administrator (elevated).
function Test-PSGPOIsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $IsWindows) { return $false }
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The values of a key of the registry (the 64-bit view) as entries of Registry.pol, by name
# (case ignored); $null when there is no such key.
function Get-PSGPOEffectiveRegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Computer', 'User')] [string]$Scope,
        [Parameter(Mandatory)] [string]$Key
    )

    $hive = if ($Scope -eq 'Computer') { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $sub = $base.OpenSubKey($Key.Trim('\'))
        if (-not $sub) { return }
        try {
            $values = [System.Collections.Generic.Dictionary[string, GPOToolsPolEntry]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($name in $sub.GetValueNames()) {
                $kind = $sub.GetValueKind($name)
                $value = $sub.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $entry = switch ($kind) {
                    'String' { [GPOToolsPolEntry]::new($Key, $name, 'String', [GPOToolsPolEntry]::EncodeString("$value")) }
                    'ExpandString' { [GPOToolsPolEntry]::new($Key, $name, 'ExpandString', [GPOToolsPolEntry]::EncodeString("$value")) }
                    # The bytes of the value: an int and a long of the registry, unsigned in Registry.pol.
                    'DWord' { [GPOToolsPolEntry]::new($Key, $name, 'DWord', [BitConverter]::GetBytes([int]$value)) }
                    'QWord' { [GPOToolsPolEntry]::new($Key, $name, 'QWord', [BitConverter]::GetBytes([long]$value)) }
                    'MultiString' {
                        $text = (@($value) | ForEach-Object { "$_`0" }) -join ''
                        [GPOToolsPolEntry]::new($Key, $name, 'MultiString', [System.Text.Encoding]::Unicode.GetBytes($text + "`0"))
                    }
                    'Binary' { [GPOToolsPolEntry]::new($Key, $name, 'Binary', [byte[]]$value) }
                    default { $null }
                }
                if ($entry) { $values[$name] = $entry }
            }
            $values
        } finally {
            $sub.Dispose()
        }
    } finally {
        $base.Dispose()
    }
}

# The security settings of the computer (secedit), as a GptTmpl.inf: those of its security
# database, where Group Policy applies them (/mergedpolicy leaves the user rights out).
function Get-PSGPOEffectiveSecurityTemplate {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param()

    $file = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-secedit-$([guid]::NewGuid()).inf"
    $log = [System.IO.Path]::ChangeExtension($file, '.log')
    try {
        $result = Invoke-PSGPONativeCommand -FilePath (Join-Path ([Environment]::SystemDirectory) 'secedit.exe') -ArgumentList '/export', '/cfg', $file, '/log', $log, '/quiet'
        if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "secedit /export ended with code $($result.ExitCode): $(@($result.Output) -join ' ') $($result.Error)".Trim() }
        , [System.IO.File]::ReadAllBytes($file)
    } finally {
        Remove-Item -LiteralPath $file, $log -ErrorAction SilentlyContinue
    }
}

# The advanced audit policy of the computer (auditpol), as an audit.csv.
function Get-PSGPOEffectiveAuditPolicy {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param()

    $file = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-auditpol-$([guid]::NewGuid()).csv"
    try {
        $result = Invoke-PSGPONativeCommand -FilePath (Join-Path ([Environment]::SystemDirectory) 'auditpol.exe') -ArgumentList "/backup", "/file:$file"
        if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "auditpol /backup ended with code $($result.ExitCode): $(@($result.Output) -join ' ') $($result.Error)".Trim() }
        , [System.IO.File]::ReadAllBytes($file)
    } finally {
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
    }
}

# A line of [Registry Values] as the registry gives it: "<type>,<data>", $null when the value is
# not there (MACHINE\<key>\<value>, the type of the registry).
function Get-PSGPOEffectiveRegistryValueLine {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Path, [hashtable]$Cache)

    $slash = $Path.LastIndexOf('\')
    if ($slash -lt 0 -or -not $Path.StartsWith('MACHINE\', [System.StringComparison]::OrdinalIgnoreCase)) { return }
    $key = $Path.Substring(8, $slash - 8)
    $name = $Path.Substring($slash + 1)
    if (-not $Cache.ContainsKey("Computer|$key")) { $Cache["Computer|$key"] = Get-PSGPOEffectiveRegistryKey -Scope Computer -Key $key }
    $values = $Cache["Computer|$key"]
    if (-not $values -or -not $values.ContainsKey($name)) { return }
    $entry = $values[$name]
    $data = ConvertTo-PSGPOPolicyRuleData -Entry $entry
    switch ($entry.Type) {
        'DWord' { "4,$data" }
        'String' { "1,`"$data`"" }
        'ExpandString' { "2,`"$data`"" }
        'MultiString' { '7,' + (($data -split '\\0') -join ',') }
        'Binary' { "3,$($data.Replace(',', ''))" }
        'QWord' { "11,$data" }
    }
}

# The rule set of the effective state of the computer for the settings of $RuleSet: for each, the
# value the computer (or the user of the session) has now, nothing when it has none. Returns
# RuleSet, and Skipped: the settings not read (secedit, auditpol: not an administrator).
function New-PSGPOPolicyRuleSetFromEffectiveState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPolicyRuleSet[]]$RuleSet,
        [string]$SetName
    )

    if (-not (Test-PSGPOEffectiveStateSupported)) { throw 'The effective state is the one of a Windows computer: run it on Windows.' }
    $computer = [Environment]::MachineName
    if (-not $SetName) { $SetName = "EffectiveState_{0}_{1}" -f $computer, [datetime]::Now.ToString('yyyyMMdd-HHmmss', [cultureinfo]::InvariantCulture) }
    $set = [GPOToolsPolicyRuleSet]::new($SetName)
    $policy = 'Effective state'

    # The settings of the sets, once each (the first rule of each, for its names).
    $wanted = [System.Collections.Generic.List[GPOToolsPolicyRule]]::new()
    $seen = @{}
    foreach ($item in $RuleSet) {
        foreach ($rule in $item.Rules) {
            $identity = $rule.GetIdentity()
            if ($seen.ContainsKey($identity)) {
                # A **delvals. of a key counts, whatever the value of the other GPOs.
                if ($rule.IsDeleteAllValues()) { $seen[$identity] = $rule }
                continue
            }
            $seen[$identity] = $rule
            $wanted.Add($rule)
        }
    }
    $wanted = @($wanted | ForEach-Object { $seen[$_.GetIdentity()] })

    $cache = @{}
    $registryKey = {
        param($Scope, $Key)
        if (-not $cache.ContainsKey("$Scope|$Key")) { $cache["$Scope|$Key"] = Get-PSGPOEffectiveRegistryKey -Scope $Scope -Key $Key }
        $cache["$Scope|$Key"]
    }
    # The values of each key the sets write, for their **delvals.
    $configured = @{}
    foreach ($rule in $wanted) {
        if ($rule.Kind -ne 'Registry' -or $rule.IsDeleteAllValues()) { continue }
        $id = "$($rule.Scope)|$($rule.Key)".ToLowerInvariant()
        if (-not $configured[$id]) { $configured[$id] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
        $null = $configured[$id].Add($rule.GetTargetValueName())
    }

    $needsAdmin = @($wanted | Where-Object { $_.Kind -like 'Audit*' -or $_.Kind -eq 'GlobalAudit' -or ($_.Kind -eq 'SecurityTemplate' -and $_.Section -notin 'Registry Values', 'Service General Setting') })
    $isAdmin = Test-PSGPOIsAdministrator
    $effective = @{}
    $skipped = 0
    if ($needsAdmin.Count -and -not $isAdmin) {
        $skipped = $needsAdmin.Count
    } elseif ($needsAdmin.Count) {
        $files = @{}
        if (@($needsAdmin | Where-Object Kind -EQ 'SecurityTemplate').Count) { $files[[GPOToolsDirectory]::SecurityTemplatePath] = Get-PSGPOEffectiveSecurityTemplate }
        if (@($needsAdmin | Where-Object Kind -NE 'SecurityTemplate').Count) { $files[[GPOToolsDirectory]::AuditPolicyPath] = Get-PSGPOEffectiveAuditPolicy }
        foreach ($rule in @(ConvertTo-PSGPOPolicyRule -Files $files -PolicyName $policy)) {
            # The security options come from the registry; the files of the computer, not a GPO.
            if ($rule.Kind -eq 'SecurityTemplate' -and $rule.Section -in 'Registry Values', 'Service General Setting') { continue }
            $rule.SourceFile = if ($rule.Kind -eq 'SecurityTemplate') { 'secedit /export' } else { 'auditpol /backup' }
            $effective[$rule.GetIdentity()] = $rule
        }
    }

    foreach ($rule in $wanted) {
        $found = $null
        switch ($rule.Kind) {
            'Registry' {
                $values = & $registryKey $rule.Scope $rule.Key
                $hive = if ($rule.Scope -eq 'Computer') { 'HKLM' } else { 'HKCU' }
                if ($rule.IsDeleteAllValues()) {
                    # The key holds no other value than those the sets write.
                    $others = @(if ($values) { $values.Keys | Where-Object { -not $configured["$($rule.Scope)|$($rule.Key)".ToLowerInvariant()] -or -not $configured["$($rule.Scope)|$($rule.Key)".ToLowerInvariant()].Contains($_) } })
                    if (-not $others.Count) { $found = $rule.Clone() }
                } elseif ($values -and $values.ContainsKey($rule.GetTargetValueName())) {
                    $entry = $values[$rule.GetTargetValueName()]
                    $found = [GPOToolsPolicyRule]::new()
                    $found.Kind = 'Registry'
                    $found.Scope = $rule.Scope
                    $found.Key = $rule.Key
                    $found.ValueName = $rule.GetTargetValueName()
                    $found.RegType = $script:PSGPOPolicyRuleTypeName["$($entry.Type)"]
                    $found.RegData = ConvertTo-PSGPOPolicyRuleData -Entry $entry
                } elseif ($rule.IsDelete()) {
                    $found = $rule.Clone()
                }
                if ($found) { $found.SourceFile = "$hive\$($rule.Key)" }
            }
            'SecurityTemplate' {
                if ($rule.Section -eq 'Registry Values') {
                    $line = Get-PSGPOEffectiveRegistryValueLine -Path $rule.GetLineKey() -Cache $cache
                    if ($null -ne $line) {
                        $found = $rule.Clone()
                        $found.LineItem = "$($rule.GetLineKey())=$line"
                        $found.SourceFile = "HKLM\$($rule.GetLineKey().Substring(8))"
                    }
                } elseif ($rule.Section -eq 'Service General Setting') {
                    # The startup of the service; its permissions as the set gives them (not read).
                    $service = $rule.GetLineKey()
                    $values = & $registryKey Computer "SYSTEM\CurrentControlSet\Services\$service"
                    if ($values -and $values.ContainsKey('Start')) {
                        $mode = ConvertTo-PSGPOPolicyRuleData -Entry $values['Start']
                        $permissions = $rule.GetLineValue()
                        $comma = $permissions.IndexOf(',')
                        $permissions = if ($comma -ge 0) { $permissions.Substring($comma) } else { ',""' }
                        $found = $rule.Clone()
                        $found.LineItem = "`"$service`",$mode$permissions"
                        $found.SourceFile = "HKLM\SYSTEM\CurrentControlSet\Services\$service"
                    }
                } elseif ($isAdmin) {
                    $found = $effective[$rule.GetIdentity()]
                    # A right nobody has: secedit leaves it out.
                    if (-not $found -and $rule.Section -eq 'Privilege Rights') {
                        $found = $rule.Clone()
                        $found.LineItem = "$($rule.GetLineKey())="
                        $found.SourceFile = 'secedit /export'
                    }
                }
            }
            default { if ($isAdmin) { $found = $effective[$rule.GetIdentity()] } }
        }
        if (-not $found) { continue }
        $found.PolicyName = $policy
        $found.Precedence = 0
        $set.Rules.Add($found)
    }
    [pscustomobject]@{ RuleSet = $set; Skipped = $skipped }
}
