<#
    Modele complet des valeurs de registre d'une policy ADMX :
    - les valeurs ecrites quand la policy est activee / desactivee (enabledValue,
      disabledValue, enabledList, disabledList) ;
    - les elements saisis par l'administrateur (boolean, decimal, longDecimal, text,
      multiText, enum, list) avec leur presentation localisee (ADML).

    Schema : https://learn.microsoft.com/previous-versions/windows/desktop/policy/element-elements
    Les cles de registre sont relatives a la ruche, comme dans Registry.pol : la ruche
    (HKLM ou HKCU) depend du Scope de la policy.
#>

enum GPOToolsRegistryValueType {
    String
    ExpandString
    MultiString
    DWord
    QWord
    Delete
}

class GPOToolsRegistryValue {
    [string]$Key
    [string]$ValueName
    [GPOToolsRegistryValueType]$Type
    [object]$Value
    # Vrai quand la valeur n'est pas ecrite dans l'ADMX mais deduite du comportement de
    # l'editeur de strategie (valueName sans enabledValue...). A confirmer avec la GPMC.
    [bool]$Implicit

    GPOToolsRegistryValue(
        [string]$Key,
        [string]$ValueName,
        [GPOToolsRegistryValueType]$Type,
        [object]$Value
    ){
        $this.Key = $Key
        $this.ValueName = $ValueName
        $this.Type = $Type
        $this.Value = $Value
    }

    <#
        Lit un noeud dont l'enfant est decimal | longDecimal | string | delete
        (value, enabledValue, disabledValue, trueValue, falseValue).
        Retourne $null si le noeud est absent.
    #>
    static [GPOToolsRegistryValue]FromValueNode(
        [System.Xml.XmlNode]$Node,
        [string]$Key,
        [string]$ValueName
    ){
        if ($null -eq $Node){
            return $null
        }
        foreach ($Child in $Node.ChildNodes){
            if ($Child.NodeType -ne [System.Xml.XmlNodeType]::Element){
                continue
            }
            switch ($Child.LocalName){
                'decimal' {
                    return [GPOToolsRegistryValue]::new($Key,$ValueName,[GPOToolsRegistryValueType]::DWord,[uint32]$Child.GetAttribute('value'))
                }
                'longDecimal' {
                    return [GPOToolsRegistryValue]::new($Key,$ValueName,[GPOToolsRegistryValueType]::QWord,[uint64]$Child.GetAttribute('value'))
                }
                'string' {
                    return [GPOToolsRegistryValue]::new($Key,$ValueName,[GPOToolsRegistryValueType]::String,$Child.InnerText)
                }
                'delete' {
                    return [GPOToolsRegistryValue]::new($Key,$ValueName,[GPOToolsRegistryValueType]::Delete,$null)
                }
            }
        }
        return $null
    }

    <#
        Lit une liste d'items <item key? valueName><value>...</value></item>
        (enabledList, disabledList, trueList, falseList, valueList).
        La cle d'un item est, par priorite : item.key, list.defaultKey, $DefaultKey.
    #>
    static [GPOToolsRegistryValue[]]FromListNode(
        [System.Xml.XmlNode]$ListNode,
        [string]$DefaultKey
    ){
        if ($null -eq $ListNode){
            return @()
        }
        $ListKey = $ListNode.GetAttribute('defaultKey')
        if (-not $ListKey){
            $ListKey = $DefaultKey
        }
        $Values = [System.Collections.Generic.List[GPOToolsRegistryValue]]::new()
        foreach ($Item in $ListNode.ChildNodes){
            if ($Item.NodeType -ne [System.Xml.XmlNodeType]::Element -or $Item.LocalName -ne 'item'){
                continue
            }
            $ItemKey = $Item.GetAttribute('key')
            if (-not $ItemKey){
                $ItemKey = $ListKey
            }
            $ItemValue = [GPOToolsRegistryValue]::FromValueNode($Item['value'],$ItemKey,$Item.GetAttribute('valueName'))
            if ($null -ne $ItemValue){
                $Values.Add($ItemValue)
            }
        }
        return $Values.ToArray()
    }

    [string]ToString(){
        return '{0}\{1} = {2} ({3})' -f $this.Key,$this.ValueName,$this.Value,$this.Type
    }
}

# Choix d'un element enum : libelle localise et valeur(s) ecrite(s)
class GPOToolsEnumItem {
    [string]$DisplayName
    [GPOToolsRegistryValue]$Value
    [GPOToolsRegistryValue[]]$ValueList
    Hidden [string]$DisplayNameRef
}

class GPOToolsPolicyElement {
    [string]$Id
    # Boolean, Decimal, LongDecimal, Text, MultiText, Enum, List
    [string]$Type
    [string]$Key
    [string]$ValueName
    [GPOToolsRegistryValueType]$ValueType
    [bool]$Required
    [bool]$Soft
    [string]$ClientExtension

    # decimal / longDecimal
    [uint64]$MinValue
    [uint64]$MaxValue
    [bool]$StoreAsText
    # text / multiText
    [uint32]$MaxLength
    [uint32]$MaxStrings
    [bool]$Expandable
    # list
    [string]$ValuePrefix
    [bool]$Additive
    [bool]$ExplicitValue
    # boolean
    [GPOToolsRegistryValue]$TrueValue
    [GPOToolsRegistryValue]$FalseValue
    [GPOToolsRegistryValue[]]$TrueList = @()
    [GPOToolsRegistryValue[]]$FalseList = @()
    # enum
    [GPOToolsEnumItem[]]$Items = @()

    # Presentation (ADML) : controle, libelle et valeur par defaut proposes a l'utilisateur
    [string]$Control
    [string]$Label
    [object]$DefaultValue

    GPOToolsPolicyElement(
        [System.Xml.XmlElement]$Node,
        [string]$PolicyKey
    ){
        $this.Id = $Node.GetAttribute('id')
        $this.Key = $Node.GetAttribute('key')
        if (-not $this.Key){
            $this.Key = $PolicyKey
        }
        $this.ValueName = $Node.GetAttribute('valueName')
        $this.ClientExtension = $Node.GetAttribute('clientExtension')
        $this.Required = [GPOToolsPolicyElement]::GetBool($Node,'required',$false)
        $this.Soft = [GPOToolsPolicyElement]::GetBool($Node,'soft',$false)

        # Valeurs par defaut du schema PolicyDefinitions
        switch ($Node.LocalName){
            'boolean' {
                $this.Type = 'Boolean'
                $this.ValueType = [GPOToolsRegistryValueType]::DWord
                $this.TrueValue = [GPOToolsRegistryValue]::FromValueNode($Node['trueValue'],$this.Key,$this.ValueName)
                $this.FalseValue = [GPOToolsRegistryValue]::FromValueNode($Node['falseValue'],$this.Key,$this.ValueName)
                if ($this.ValueName){
                    # Sans trueValue/falseValue, la case a cocher ecrit 1 / 0 (DWORD)
                    if ($null -eq $this.TrueValue){
                        $this.TrueValue = [GPOToolsRegistryValue]::new($this.Key,$this.ValueName,[GPOToolsRegistryValueType]::DWord,[uint32]1)
                        $this.TrueValue.Implicit = $true
                    }
                    if ($null -eq $this.FalseValue){
                        $this.FalseValue = [GPOToolsRegistryValue]::new($this.Key,$this.ValueName,[GPOToolsRegistryValueType]::DWord,[uint32]0)
                        $this.FalseValue.Implicit = $true
                    }
                }
                $this.TrueList = [GPOToolsRegistryValue]::FromListNode($Node['trueList'],$this.Key)
                $this.FalseList = [GPOToolsRegistryValue]::FromListNode($Node['falseList'],$this.Key)
            }
            {$_ -in 'decimal','longDecimal'} {
                $this.Type = if ($_ -eq 'decimal') { 'Decimal' } else { 'LongDecimal' }
                $this.MinValue = [GPOToolsPolicyElement]::GetUInt($Node,'minValue',0)
                $this.MaxValue = [GPOToolsPolicyElement]::GetUInt($Node,'maxValue',9999)
                $this.StoreAsText = [GPOToolsPolicyElement]::GetBool($Node,'storeAsText',$false)
                $this.ValueType = if ($this.StoreAsText) {
                    [GPOToolsRegistryValueType]::String
                } elseif ($_ -eq 'decimal') {
                    [GPOToolsRegistryValueType]::DWord
                } else {
                    [GPOToolsRegistryValueType]::QWord
                }
            }
            'text' {
                $this.Type = 'Text'
                $this.MaxLength = [GPOToolsPolicyElement]::GetUInt($Node,'maxLength',1023)
                $this.Expandable = [GPOToolsPolicyElement]::GetBool($Node,'expandable',$false)
                $this.ValueType = if ($this.Expandable) { [GPOToolsRegistryValueType]::ExpandString } else { [GPOToolsRegistryValueType]::String }
            }
            'multiText' {
                $this.Type = 'MultiText'
                $this.MaxLength = [GPOToolsPolicyElement]::GetUInt($Node,'maxLength',1023)
                $this.MaxStrings = [GPOToolsPolicyElement]::GetUInt($Node,'maxStrings',0)
                $this.ValueType = [GPOToolsRegistryValueType]::MultiString
            }
            'enum' {
                $this.Type = 'Enum'
                $EnumItems = [System.Collections.Generic.List[GPOToolsEnumItem]]::new()
                foreach ($ItemNode in $Node.ChildNodes){
                    if ($ItemNode.NodeType -ne [System.Xml.XmlNodeType]::Element -or $ItemNode.LocalName -ne 'item'){
                        continue
                    }
                    $EnumItem = [GPOToolsEnumItem]::new()
                    $EnumItem.DisplayNameRef = $ItemNode.GetAttribute('displayName') -replace '^\$\(string\.(.*)\)$', '$1'
                    $EnumItem.Value = [GPOToolsRegistryValue]::FromValueNode($ItemNode['value'],$this.Key,$this.ValueName)
                    $EnumItem.ValueList = [GPOToolsRegistryValue]::FromListNode($ItemNode['valueList'],$this.Key)
                    $EnumItems.Add($EnumItem)
                }
                $this.Items = $EnumItems.ToArray()
                $First = $this.Items | Where-Object { $null -ne $_.Value } | Select-Object -First 1
                $this.ValueType = if ($First) { $First.Value.Type } else { [GPOToolsRegistryValueType]::DWord }
            }
            'list' {
                $this.Type = 'List'
                $this.ValuePrefix = $Node.GetAttribute('valuePrefix')
                $this.Additive = [GPOToolsPolicyElement]::GetBool($Node,'additive',$false)
                $this.Expandable = [GPOToolsPolicyElement]::GetBool($Node,'expandable',$false)
                $this.ExplicitValue = [GPOToolsPolicyElement]::GetBool($Node,'explicitValue',$false)
                $this.ValueType = if ($this.Expandable) { [GPOToolsRegistryValueType]::ExpandString } else { [GPOToolsRegistryValueType]::String }
            }
            default {
                throw ('[GPOToolsPolicyElement] Unknown element type {0} for {1}' -f $Node.LocalName,$this.Id)
            }
        }
    }

    <#
        Renseigne les libelles a partir de l'ADML : presentation de la policy (controle,
        libelle, valeur par defaut) et noms affiches des choix enum.
    #>
    [void]Localize(
        [GpoToolsAdml]$Adml,
        [hashtable]$Presentation
    ){
        foreach ($Item in $this.Items){
            $Item.DisplayName = $Adml.GetString($Item.DisplayNameRef)
        }
        if ($null -ne $Presentation -and $Presentation.ContainsKey($this.Id)){
            $Presented = $Presentation[$this.Id]
            $this.Control = $Presented.Control
            $this.Label = $Presented.Label
            $this.DefaultValue = $Presented.DefaultValue
        }
    }

    # Lecture d'attribut tolerante a la casse : quelques ADMX ecrivent maxvalue au lieu de maxValue
    static [string]GetAttribute([System.Xml.XmlElement]$Node,[string]$Name){
        if ($Node.HasAttribute($Name)){
            return $Node.GetAttribute($Name)
        }
        foreach ($Attribute in $Node.Attributes){
            if ($Attribute.LocalName -eq $Name){
                return $Attribute.Value
            }
        }
        return $null
    }

    static [bool]GetBool([System.Xml.XmlElement]$Node,[string]$Name,[bool]$Default){
        $Raw = [GPOToolsPolicyElement]::GetAttribute($Node,$Name)
        if ([string]::IsNullOrWhiteSpace($Raw)){
            return $Default
        }
        return $Raw.Trim() -eq 'true'
    }

    static [uint64]GetUInt([System.Xml.XmlElement]$Node,[string]$Name,[uint64]$Default){
        $Raw = [GPOToolsPolicyElement]::GetAttribute($Node,$Name)
        if ([string]::IsNullOrWhiteSpace($Raw)){
            return $Default
        }
        return [uint64]$Raw.Trim()
    }
}
