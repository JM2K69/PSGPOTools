
# The parameters that take an account complete the well-known accounts (Tab): Authenticated Users,
# Domain Admins, Administrateurs... (GPOToolsWellKnownSid), in English or French, quoted when they
# hold a space.
$PSGPOAccountCompleter = {
    param($CommandName, $ParameterName, $WordToComplete)
    $null = $CommandName, $ParameterName
    $word = "$WordToComplete".Trim("'", '"')
    foreach ($entry in [GPOToolsWellKnownSid]::All) {
        foreach ($name in @($entry.Name, $entry.FrenchName | Select-Object -Unique)) {
            if (-not $name.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $text = if ($name -match "[\s']") { "'$($name.Replace("'", "''"))'" } else { $name }
            $tip = if ($entry.IsDomainAccount()) { "$name (<SID of the domain>$($entry.Sid))" } else { "$($entry.GetQualifiedName('')) ($($entry.Sid))" }
            [System.Management.Automation.CompletionResult]::new($text, $name, 'ParameterValue', $tip)
        }
    }
}
foreach ($parameter in 'ApplyTo', 'DenyTo') { Register-ArgumentCompleter -CommandName 'Approve-PSGPO' -ParameterName $parameter -ScriptBlock $PSGPOAccountCompleter }
Register-ArgumentCompleter -CommandName 'Set-PSGPOPermission', 'Set-PSGPOWmiFilterPermission' -ParameterName 'Account' -ScriptBlock $PSGPOAccountCompleter

# At import: the version of HGPM, and the command that installs a newer one from the PowerShell
# Gallery (Write-PSGPOImportBanner).
Write-PSGPOImportBanner
