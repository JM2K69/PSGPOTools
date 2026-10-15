<#
    Group Policy Preferences ([MS-GPPREF]): the catalog of the preference types (Resources/
    Preferences.json: their file, outer element, item elements, client-side extension and the
    attributes of the types the console edits), and the items of a preference file: read, created,
    changed, deleted and moved, as GPMC writes them.

    Passwords are never written: the cpassword attribute is encrypted with a key Microsoft
    published ([MS-GPPREF] 2.2.1.1.4), so every user of the domain can read it (MS14-025). An
    item that holds one is reported, and its password kept as it is.
#>

# The preference types, read once from the catalog.
function Get-PSGPOPreferenceCatalog {
    [CmdletBinding()]
    param()

    if (-not $script:PSGPOPreferenceCatalog) {
        $path = Join-Path $PSScriptRoot 'Resources' 'Preferences.json'
        $script:PSGPOPreferenceCatalog = @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).Extensions)
    }
    $script:PSGPOPreferenceCatalog
}

# The preference types of a scope (Machine or User), in the order of the editor: Windows
# Settings, then Control Panel Settings.
function Get-PSGPOPreferenceExtension {
    [CmdletBinding()]
    param(
        [ValidateSet('Machine', 'User')] [string]$Scope,
        [string]$Id
    )

    Get-PSGPOPreferenceCatalog | Where-Object {
        (-not $Scope -or $_.Scopes -contains $Scope) -and (-not $Id -or $_.Id -eq $Id)
    }
}

# Path of the file of a preference type in the folder of a GPO.
function Get-PSGPOPreferencePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Extension,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    "$Scope\Preferences\$($Extension.Path)"
}

$script:PSGPOPreferenceActions = [ordered]@{ C = 'Create'; R = 'Replace'; U = 'Update'; D = 'Delete' }

# Name of an item from its values and the NameFormat of its type: {a|b} is the first of a and b
# that is not empty, |leaf keeps the last part of a path.
function Format-PSGPOPreferenceName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string]$Format,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values
    )

    if (-not $Format) { return '' }
    [regex]::Replace($Format, '\{([^}]+)\}', {
            param($Match)
            $parts = @($Match.Groups[1].Value -split '\|')
            $leaf = $parts[-1] -eq 'leaf'
            if ($leaf) { $parts = @($parts | Select-Object -SkipLast 1) }
            $value = ''
            foreach ($part in $parts) { if ("$($Values[$part])") { $value = "$($Values[$part])"; break } }
            if ($leaf -and $value) { $value = @($value.TrimEnd('\', '/') -split '[\\/]')[-1] }
            $value
        })
}

# The items of a preference file, in their order, those of the Collection elements included:
# Element (the XmlElement), Type (its type in the catalog, $null when the console does not edit
# it), Name, Action, Properties (the attributes of Properties), the common options, and what
# the console keeps as it is (targeting filters, a password).
function Get-PSGPOPreferenceItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPreferenceFile]$File,
        [Parameter(Mandatory)] $Extension
    )

    $walk = {
        param([System.Xml.XmlElement]$Parent, [string]$Collection)
        foreach ($element in @($Parent.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.LocalName -ne 'Filters' })) {
            $type = $Extension.Items | Where-Object Element -EQ $element.LocalName | Select-Object -First 1
            if ($type -and $type.IsCollection) {
                & $walk $element $(if ($Collection) { "$Collection > $($element.GetAttribute('name'))" } else { $element.GetAttribute('name') })
                continue
            }
            $properties = $element.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.LocalName -eq 'Properties' } | Select-Object -First 1
            $values = [ordered]@{}
            if ($properties) { foreach ($attribute in $properties.Attributes) { $values[$attribute.Name] = $attribute.Value } }
            $members = @(if ($properties) {
                    foreach ($member in $properties.SelectNodes('Members/Member')) {
                        [pscustomobject]@{ Name = $member.GetAttribute('name'); Sid = $member.GetAttribute('sid'); Action = $member.GetAttribute('action') }
                    }
                })
            $filters = $element.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.LocalName -eq 'Filters' } | Select-Object -First 1
            [pscustomobject]@{
                PSTypeName = 'PSGPOTools.PreferenceItem'
                Element = $element
                Type = $type
                Collection = $Collection
                ElementName = $element.LocalName
                Label = if ($type) { $type.Label } else { $element.LocalName }
                Name = $element.GetAttribute('name')
                Uid = $element.GetAttribute('uid')
                Changed = $element.GetAttribute('changed')
                Action = "$($values['action'])"
                Disabled = $element.GetAttribute('disabled') -eq '1'
                Description = $element.GetAttribute('desc')
                BypassErrors = $element.GetAttribute('bypassErrors') -eq '1'
                UserContext = $element.GetAttribute('userContext') -eq '1'
                RemovePolicy = $element.GetAttribute('removePolicy') -eq '1'
                FilterCount = if ($filters) { @($filters.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] }).Count } else { 0 }
                HasPassword = [bool]("$($values['cpassword'])$($values['cPassword'])")
                Properties = $values
                Members = $members
                Editable = [bool]($type -and $type.Properties)
            }
        }
    }
    & $walk $File.GetRoot() ''
}

# What an item does, in a few words: the action and its main values.
function Get-PSGPOPreferenceSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Item)

    $values = $Item.Properties
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($Item.Action -and $script:PSGPOPreferenceActions.Contains($Item.Action)) { $parts.Add($script:PSGPOPreferenceActions[$Item.Action]) }
    $properties = if ($Item.Type -and $Item.Type.Properties) { @($Item.Type.Properties) } else { @($values.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Label = $_; Type = 'Text' } }) }
    foreach ($property in $properties) {
        if ($property.Name -eq 'action' -or $property.Type -in 'Password', 'Members') { continue }
        $value = "$($values[$property.Name])"
        if (-not $value -or ($property.Type -eq 'Bool' -and $value -eq '0') -or $value -in 'NOCHANGE', 'NO_CHANGE') { continue }
        $parts.Add($(if ($property.Type -eq 'Bool') { $property.Label } else { "$($property.Label): $value" }))
        if ($parts.Count -ge 7) { break }
    }
    if ($Item.Members.Count) { $parts.Add("$($Item.Members.Count) member(s): $(@($Item.Members | ForEach-Object { "$($_.Action) $(if ($_.Name) { $_.Name } else { $_.Sid })" }) -join ', ')") }
    $parts -join ' - '
}

# Writes the values of an item (the attributes of its Properties, its Members) and the common
# options to its element; the attributes the type does not define are kept.
function Set-PSGPOPreferenceElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement]$Element,
        [Parameter(Mandatory)] $Type,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [System.Collections.IDictionary]$Common = @{}
    )

    $document = $Element.OwnerDocument
    $properties = $Element.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.LocalName -eq 'Properties' } | Select-Object -First 1
    if (-not $properties) {
        $properties = $document.CreateElement('Properties')
        [void]$Element.PrependChild($properties)
    }
    foreach ($property in @($Type.Properties)) {
        if ($property.Type -eq 'Password') {
            if ("$($Values[$property.Name])") { throw "Passwords are not written in preferences: any user of the domain can read them (MS14-025)." }
            continue
        }
        if ($property.Type -eq 'Members') {
            if (-not $Values.Contains('Members')) { continue }
            $members = $properties.SelectSingleNode('Members')
            if (-not $members) { $members = $document.CreateElement('Members'); [void]$properties.AppendChild($members) }
            $members.RemoveAll()
            foreach ($member in @($Values['Members'])) {
                $node = $document.CreateElement('Member')
                $node.SetAttribute('name', "$($member.Name)")
                $node.SetAttribute('action', $(if ("$($member.Action)") { "$($member.Action)".ToUpperInvariant() } else { 'ADD' }))
                $node.SetAttribute('sid', "$($member.Sid)")
                [void]$members.AppendChild($node)
            }
            continue
        }
        if (-not $Values.Contains($property.Name)) { continue }
        $value = "$($Values[$property.Name])"
        if ($property.Required -and -not $value) { throw "$($property.Label) is required." }
        if ($property.Type -eq 'Choice' -and $property.Choices -notcontains $value) { throw "$($property.Label): '$value' is not one of $(@($property.Choices | Where-Object { $_ }) -join ', ')." }
        if ($property.Type -eq 'Number' -and $value -and $value -notmatch '^\d+$') { throw "$($property.Label) must be a number." }
        if ($property.Type -eq 'Bool' -and $value -notin '0', '1') { throw "$($property.Label) must be 0 or 1." }
        if ($property.Type -eq 'Action' -and $value -notin 'C', 'R', 'U', 'D') { throw "The action must be C, R, U or D (Create, Replace, Update, Delete)." }
        $properties.SetAttribute($property.Name, $value)
    }

    # Name and status shown by the editors, the date of the change, the icon of the action.
    $all = [ordered]@{}
    foreach ($attribute in $properties.Attributes) { $all[$attribute.Name] = $attribute.Value }
    $name = Format-PSGPOPreferenceName -Format $Type.NameFormat -Values $all
    if (-not $name) { $name = $Type.Label }
    $Element.SetAttribute('name', $name)
    if ($Type.StatusFormat) { $Element.SetAttribute('status', (Format-PSGPOPreferenceName -Format $Type.StatusFormat -Values $all)) }
    $action = "$($all['action'])"
    if ($action) { $Element.SetAttribute('image', "$([array]::IndexOf(@('C', 'R', 'U', 'D'), $action))") }
    $Element.SetAttribute('changed', [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture))
    foreach ($option in 'desc', 'bypassErrors', 'userContext', 'removePolicy') {
        if (-not $Common.Contains($option)) { continue }
        $value = "$($Common[$option])"
        if ($option -ne 'desc' -and $value -eq '0') { $value = '' }
        if ($value) { $Element.SetAttribute($option, $value) } else { $Element.RemoveAttribute($option) }
    }
}

# Adds an item of a type at the end of a preference file; returns its element.
function New-PSGPOPreferenceItem {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlElement])]
    param(
        [Parameter(Mandatory)] [GPOToolsPreferenceFile]$File,
        [Parameter(Mandatory)] $Type,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Values,
        [System.Collections.IDictionary]$Common = @{}
    )

    if (-not $Type.Properties) { throw "Items of the type '$($Type.Label)' are created with GPMC: the console reads, keeps and deletes them." }
    foreach ($property in @($Type.Properties | Where-Object Type -EQ 'Password')) {
        if ("$($Values[$property.Name])") { throw "Passwords are not written in preferences: any user of the domain can read them (MS14-025)." }
    }
    $element = $File.Document.CreateElement($Type.Element)
    $element.SetAttribute('clsid', $Type.Clsid)
    $element.SetAttribute('name', $Type.Label)
    $element.SetAttribute('uid', ('{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'))
    # The defaults of the type for what is not given.
    $all = [ordered]@{}
    foreach ($property in @($Type.Properties)) {
        if ($property.Type -in 'Password', 'Members') { continue }
        $all[$property.Name] = if ($Values.Contains($property.Name)) { $Values[$property.Name] } elseif ($null -ne $property.Default) { "$($property.Default)" } else { '' }
    }
    if ($Values.Contains('Members')) { $all['Members'] = $Values['Members'] }
    try {
        Set-PSGPOPreferenceElement -Element $element -Type $Type -Values $all -Common $Common
    } catch {
        throw
    }
    [void]$File.GetRoot().AppendChild($element)
    $element
}

function Remove-PSGPOPreferenceElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Xml.XmlElement]$Element)

    [void]$Element.ParentNode.RemoveChild($Element)
}

# Moves an item before the previous one or after the next one: the items apply in their order.
function Move-PSGPOPreferenceElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement]$Element,
        [Parameter(Mandatory)] [ValidateSet('Up', 'Down')] [string]$Direction
    )

    $parent = $Element.ParentNode
    if ($Direction -eq 'Up') {
        $previous = $Element.PreviousSibling
        while ($previous -and $previous -isnot [System.Xml.XmlElement]) { $previous = $previous.PreviousSibling }
        if ($previous) { [void]$parent.InsertBefore($Element, $previous) }
    } else {
        $next = $Element.NextSibling
        while ($next -and $next -isnot [System.Xml.XmlElement]) { $next = $next.NextSibling }
        if ($next) { [void]$parent.InsertAfter($Element, $next) }
    }
}

# Settings report rows of the preferences of a scope, from the files of a GPO: one per item,
# by the path of its type, with its action and every value (the password left out), keyed by
# its uid so that a change of name shows as a change of the item.
function Get-PSGPOConfiguredPreference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $label = if ($Scope -eq 'Machine') { 'Computer' } else { 'User' }
    foreach ($extension in @(Get-PSGPOPreferenceExtension -Scope $Scope)) {
        $path = Get-PSGPOPreferencePath -Extension $extension -Scope $Scope
        if (-not $Files.Contains($path)) { continue }
        $file = try { [GPOToolsPreferenceFile]::Parse([byte[]]$Files[$path]) } catch { $null }
        $category = "Preferences > $($extension.Group) > $($extension.Name)"
        if (-not $file) {
            [pscustomobject]@{ Key = "$label|$category|unreadable"; Scope = $label; Path = $category; Name = $extension.Name; State = 'Unreadable XML'; Options = ''; IsExtra = $true }
            continue
        }
        foreach ($item in @(Get-PSGPOPreferenceItem -File $file -Extension $extension)) {
            $state = if ($script:PSGPOPreferenceActions.Contains($item.Action)) { $script:PSGPOPreferenceActions[$item.Action] }
                elseif ($item.Properties.Contains('deviceAction')) { $item.Properties['deviceAction'] }
                else { $item.Label }
            if ($item.Disabled) { $state += ' (disabled)' }
            $options = @(foreach ($name in $item.Properties.Keys) {
                    if ($name -in 'action', 'cpassword', 'cPassword') { continue }
                    if ("$($item.Properties[$name])") { "$name = $($item.Properties[$name])" }
                })
            if ($item.Members.Count) { $options += "Members: $(@($item.Members | ForEach-Object { "$($_.Action) $(if ($_.Name) { $_.Name } else { $_.Sid })" }) -join ', ')" }
            if ($item.HasPassword) { $options += 'A password is stored (readable by any user of the domain, MS14-025)' }
            if ($item.FilterCount) { $options += "$($item.FilterCount) item-level targeting filter(s)" }
            $row = [AvaloniaSettingRow]::new()
            $row.Path = "Policies > $category$(if ($item.Collection) { " > $($item.Collection)" })"
            $row.Name = if ($item.Name) { $item.Name } else { $item.Label }
            $row.State = $state
            $row.Options = $options -join [Environment]::NewLine
            [pscustomobject]@{ Key = "$label|$category|$($item.Uid)"; Scope = $label; Path = $row.Path; Name = $row.Name; State = $row.State; Options = $row.Options; Row = $row }
        }
    }
}
