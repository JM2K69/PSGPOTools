#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The code of the windows read as code, without Avalonia: each named control of a window is in a
# variable of its name, made from its XAML (Get-PSGPOAvaloniaNamedControl), not one line per
# control. A variable that the window reads and nothing assigns would then be $null, not an error
# when the window opens: each must be a control of its XAML (a misspelt control would be found
# here).
BeforeDiscovery {
    $Code = Join-Path $PSScriptRoot '..' '..' 'Code' 'Functions' 'Private'
    # A window, the views its function dot-sources (their variables live in its scope), its XAML.
    $Windows = @(
        @{
            Name  = 'The GPO console'
            Files = @(Get-ChildItem -LiteralPath $Code -Filter '*.ps1' | Where-Object Name -Match '^(Start-PSGPOManagerWindow|Initialize-PSGPOManager\w+View)\.ps1$' | ForEach-Object FullName)
            Xaml  = @(Join-Path $Code 'Get-PSGPOManagerWindowXaml.ps1')
        }
    )
}

Describe 'Variables of the windows' {
    BeforeAll {
        # Set by PowerShell, not by the window.
        $script:Automatic = @(
            '_', 'PSItem', 'true', 'false', 'null', 'Matches', 'args', 'this', 'input', 'sender', 'EventArgs', 'Event',
            'PSCmdlet', 'PSBoundParameters', 'MyInvocation', 'PSScriptRoot', 'PSCommandPath', 'IsWindows', 'IsLinux', 'IsMacOS',
            'HOME', 'PID', 'LASTEXITCODE', 'Error', 'ExecutionContext', 'Host', 'PSVersionTable', 'StackTrace',
            'ErrorActionPreference', 'VerbosePreference', 'WarningPreference', 'ConfirmPreference', 'WhatIfPreference'
        )
        function Get-TestWindowVariable {
            param([string[]]$Path)
            $read = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $assigned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($file in $Path) {
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors)
                if ($errors) { throw "$file does not parse: $($errors[0].Message)" }
                # The variables assigned: $a = , [type]$a = , $a, $b = ; not $a.Property = nor $a[0] = .
                foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                    $targets = @(if ($node.Left -is [System.Management.Automation.Language.ArrayLiteralAst]) { $node.Left.Elements } else { $node.Left })
                    foreach ($target in $targets) {
                        while ($target -is [System.Management.Automation.Language.ConvertExpressionAst]) { $target = $target.Child }
                        if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) { $null = $assigned.Add($target.VariablePath.UserPath) }
                    }
                }
                foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) { $null = $assigned.Add($node.Variable.VariablePath.UserPath) }
                foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) { $null = $assigned.Add($node.Name.VariablePath.UserPath) }
                foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
                    # $script:, $env:, $using:...: not of the window.
                    if ($node.VariablePath.UserPath -notmatch ':') { $null = $read.Add($node.VariablePath.UserPath) }
                }
            }
            [pscustomobject]@{ Read = $read; Assigned = $assigned }
        }
        function Get-TestXamlName {
            param([string[]]$Path)
            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($file in $Path) {
                foreach ($match in [regex]::Matches((Get-Content -LiteralPath $file -Raw), '\bName\s*=\s*[''"]([A-Za-z_]\w*)[''"]')) { $null = $names.Add($match.Groups[1].Value) }
            }
            , $names
        }
    }

    It '<Name>: reads no variable that is neither assigned nor a control of its XAML' -ForEach $Windows {
        $Variables = Get-TestWindowVariable -Path $Files
        $Names = Get-TestXamlName -Path $Xaml
        $Names.Count | Should -BeGreaterThan 100
        $Unknown = @($Variables.Read | Where-Object { -not $Variables.Assigned.Contains($_) -and -not $Names.Contains($_) -and $_ -notin $script:Automatic } | Sort-Object)
        $Unknown | Should -BeNullOrEmpty -Because 'a variable read is assigned, or is a control of the window (Name= in its XAML)'
    }

    It '<Name>: assigns no variable a control of its XAML is put in' -ForEach $Windows {
        $Variables = Get-TestWindowVariable -Path $Files
        $Names = Get-TestXamlName -Path $Xaml
        $Clash = @($Names | Where-Object { $Variables.Assigned.Contains($_) } | Sort-Object)
        $Clash | Should -BeNullOrEmpty -Because 'the variable of a control (Get-PSGPOAvaloniaNamedControl) would be overwritten, or would overwrite another variable'
    }
}

