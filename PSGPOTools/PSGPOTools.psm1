#Generated at 02/10/2020 15:47:03 by Nicolas BAUDIN
enum StatePolicy {
    Enabled
    Disabled
    NotConfigured
}

enum ScopePolicy {
    User
    Machine
}

class GPOToolsUtility {
    static [System.Collections.Generic.List[GpoToolsSupportedOn]]$SupportOnTable = @()
    static [System.Collections.Generic.List[GpoToolsCategory]]$Categories = @()
    static [System.Collections.Generic.List[GpoToolsPolicy]]$Policies = @()
    static [System.Collections.ArrayList]$TargetLoad = @()

    static [void]InitiateAdmxAdml(
        [System.IO.DirectoryInfo]$Folder,
        [cultureinfo]$UICulture
    ){
        #Importer l'ensemble des fichiers admx
        #Importer les dÃ©pendances en premier lieu !
        #Pour chaque fichier ADMX on importe le fichier AMDL correspondant
        #On incrÃ©mente les catÃ©gories
        #Comment valider que les dÃ©pendances sont bien dÃ©jÃ  prÃ©sents et pas nÃ©cessaire de les recharger ?
        #noter un Ã©lÃ©ment unique (nom du fichier ?) hashtable ?

        #On passe en revu chaque fichier admx
        if (Test-Path -Path $Folder.FullName){
            Write-Verbose "Initialization of ADMX file in $Folder"
            $AdmxFiles = Get-ChildItem -Path $Folder.FullName -File -Filter *.admx
            foreach ($File in $AdmxFiles) {
                [GPOToolsUtility]::InitiateAdmxAdml($File,$UICulture)
            }
        }Else{
            Write-Error "Foler $Folder not found"
        }

    }

    static [void]InitiateAdmxAdml(
        [System.IO.FileInfo]$File,
        [cultureinfo]$UICulture
    ){
        if((Test-Path -Path $File.FullName) -and ($File.Name -Like '*.admx')){
            #On verifie que le fichier AMDX n'a pas deja ete charge.
            If (![GPOToolsUtility]::TargetLoad.Contains([GPOToolsUtility]::GetNamespaceAdmx($File))){
                Write-Verbose "Initialization of $File"
                #Creation de l'objet ADMX
                $ADMX = [GpoToolsAdmx]::New($File.FullName)

                #On verifie si il a besoin de dÃ©pendance et on les charges
                [GPOToolsUtility]::CheckAndInitiateDependancy($ADMX,$UICulture)

                #On determine le fichier ADML correspondant
                $ADMLPath = [GPOToolsUtility]::GetADMLPathFromADMX($File,$UICulture)

                #On charge le fichier ADML correspondant
                $ADML = [GpoToolsAdml]::New($ADMLPath)

                #On cree les objets SupportedOn
                $Support = $ADMX.SupportedOnDefinition | Foreach-Object { [GPOToolsSupportedOn]::New($_,$ADML) }

                #On initialise les objets Category
                [GPOToolsCategory]::LoadAdmxAdml($Admx,$Adml)

                #On cree les objet Policy
                $Pols = $ADMX.Policies | Foreach-Object {[GPOToolsPolicy]::New($_,$ADML)}

                #On incremente les objets dans les proprietes statiques
                if ($Support.count -gt 0){
                    $Support | Foreach-Object {[GPOToolsutility]::SupportOnTable.Add($_)}
                }
                if ($Pols.count -gt 0){
                    $Pols | Foreach-Object {[GPOToolsutility]::Policies.Add($_)}
                }

                [GPOToolsutility]::TargetLoad.Add($ADMX.Target.namespace)

            }Else{
                Write-Verbose "$File is already Initiate"
            }
        }Else{
            Write-Error "File $File not found"
        }
    }

    static [string]GetNamespaceAdmx(
        [System.IO.FileInfo]$AdmxFile
    ){
        [xml]$Xml = Get-Content -Path $AdmxFile.FullName -Encoding UTF8
        return $Xml.policyDefinitions.policyNamespaces.target.namespace
    }
    static [string]GetADMLPathFromADMX(
        [System.IO.FileInfo]$AdmxFile,
        [cultureinfo]$UICulture
    ){
        $ParentPath = Split-Path -Path $AdmxFile.FullName
        $ADMLPath  = '{0}\{1}\{2}' -f $ParentPath,$UICulture,$($AdmxFile.Name -replace '\.admx','.adml')
        if (Test-Path -Path $ADMLPath){
            return $ADMLPath
        }Else{
            Throw "The ADML File $ADMLPath doesn't exist."
        }
    }

    static [void]CheckAndInitiateDependancy(
        [GpoToolsAdmx]$ADMX,
        [cultureinfo]$UICulture
    ){
        $ADMX.Using | Foreach-Object {
            #On verifie si la dependance est deja  charge ou si il s'agit de product
            if (![GPOToolsUtility]::TargetLoad.Contains($_.namespace) -and $($ADMX.Target.namespace -ne 'Microsoft.Policies.Products')){
                Write-Verbose ('The ADMX {0} need {1} dependancy' -f $ADMX.FilePath,$_.namespace)
                #on determine de fichier ADMX dont le premier depend
                #Rajouter un trycatch en cas de generation d'erreur et mise en place d'un warning
                Try{
                    $DepFile = [GPOToolsUtility]::FindDependancyFile($ADMX.FilePath,$_.namespace)
                }
                Catch {
                    Write-Warning $_.Exception.message
                    $DepFile = $null
                }
                #On charge la dependance si il y en a une
                if ($null -ne $DepFile){
                    [GPOToolsUtility]::InitiateAdmxAdml($DepFile,$UICulture)
                }
            }
        }
    }
    <#
        Method utilise pour rechercher les fichiers admx dont depend un fichier admx
        Exe. : WindowsBackup.admx a besoin de windows.admx
        Use :
            [GPOToolsUTility]::CheckAndInitiateDependancy()
    #>
    static [System.IO.FileInfo]FindDependancyFile(
        [string]$Path,
        [string]$namespace
    ){
        $FolderPath = Split-Path -Path $Path
        $Files = Get-ChildItem -Path $FolderPath -Filter *.admx -Exclude $Path.Name
        $File = $Files | Foreach-Object {
            if([GPOToolsUtility]::GetNamespaceAdmx($_) -eq $namespace){
                $_
            }
        }
        switch ($File.count){
            1 {
                break
            }
            {$_ -ge 2} {
                Throw ('Too many dependancy file found for {0} target in {1} ADMX file' -f $namespace,$Path)
            }
            0 {
                Throw ('No dependancy file found for {0} target in {1} ADMX file' -f $namespace,$Path)
            }
            default {
                Throw ('Unknwon error for find {0} target in {1} ADMX file' -f $namespace,$Path)
            }
        }

        return $File
    }
    <# Methode pour verifier la presence d'une category dans la propriete static de
     la classe GPOToolsUtility. Elle se base sur la propriete target de l'objet
     Category. Target comprend le prefix et le namespace pour avoir un filtre plus
     precis.

     Use :
    #>
    static [bool]CheckCategoryPresence(
        [string]$Name,
        [hashtable]$target
    ){
        $Result = [GPOToolsUtility]::Categories |
            Where-Object {
                ($_.Name -eq $Name) -and
                ($_.target.prefix -eq $target.prefix) -and
                ($_.target.namespace -eq $target.namespace)
            }
        if ($Result.count -eq 0){
            return $false
        }Else{
            return $true
        }
    }

    <# Surcharge de Methode pour verifier la presence d'une category dans la
     propriete static de la classe GPOToolsUtility. Cette surcharge se base seulement
     sur le nom du prefix et pas sur le namespace. Cela rÃ©duit le prÃ©cision de la
     verification.
     Use :
        [GPOToolsCategory]::Create()
    #>
    static [bool]CheckCategoryPresence(
        [string]$Name,
        [string]$TargetPrefix
    ){
        $return = $false
        $Result = [GPOToolsUtility]::Categories |
            Where-Object {
                ($_.Name -eq $Name) -and
                ($_.target.prefix -eq $TargetPrefix)
            }
        switch ($Result.Count){
            1 {$return = $true}
            0 {$return =  $false}
            {$_ -ge 2} {
                throw ('[GPOToolsUtility](CheckCategoryPresence) To many Category found for {0}.' -f $Name)
            }
            default {
                throw ('[GPOToolsUtility](CheckCategoryPresence) Unknow error for {0} category.' -f $Name)
            }
        }
        return $return
    }

    # Methode pour vider les membre static de GPOToolsUtility. Cela permet d'en
    # initialiser de nouveaux.
    static [void]RemoveAll(){
        foreach($Property in @(
                [GPOToolsUtility]::SupportOnTable,
                [GPOToolsUtility]::Categories,
                [GPOToolsUtility]::Policies,
                [GPOToolsUtility]::TargetLoad
                #[GPOToolsCategory]::AllParentCategory
            )
        ){
            $Property.Clear()
        }
    }

}# End GPOToolsUtility

#Classe SupportedOn
class GPOToolsSupportedOn {
    [string]$Name
    [string]$DisplayName

    GPOToolsSupportedOn(
        [AdmxSupportedOn]$Support,
        [GpoToolsAdml]$Adml
    ){
        $this.Name = $Support.Name
        $this.DisplayName = $Adml.StringTable."$($Support.DisplayName)"
    }

    static [Array]LoadAdmxAdml(
        [GpoToolsAdmx]$Admx,
        [GpoToolsAdml]$Adml
    ){
        $Result = $Admx.SupportedOnDefinition | Foreach-Object {
            [GPOToolsSupportedOn]::New($_,$Adml)
        }
        return $Result
    }
}
<#
class GPOToolsSupportedOnDefinition : GPOToolsSupportedOn {
    [system.collections.ArrayList]$Or
    [system.collections.Arraylist]$And
}
class GPOToolsSupportedOnProduct : GPOToolsSupportedOn {
    $MajorVersion
}
#>
#Classe Category

class GPOToolsCategory {
    [string]$Name
    [string]$DisplayName
    [string]$ExplainText
    Hidden [Admxnamespace]$target
    [GPOToolsCategory]$ParentCategory
    # A retirer pour ne laisser qu'une liste de categories
    #static hidden [System.Collections.Generic.List[GpoToolsCategory]]$AllParentCategory = @()

    <#
        Constructeur de la classe GPOToolsCategory.
        Seulement utilise dans la methode Create() pour limiter les creations en double d'objet category
    #>
    Hidden GPOToolsCategory(
        [AdmxCategory]$Cat,
        [System.Collections.ArrayList]$AllCat,
        [GpoToolsAdml]$Adml
    ){
        $this.Name = $Cat.Name
        $this.target = $Cat.target
        $this.DisplayName = $Adml.StringTable."$($Cat.DisplayName)"
        if ($null -ne $Cat.explainText){
            $this.ExplainText = $Adml.StringTable."$($Cat.ExplainText)"
        }

        #Gestion du Parent
        if ($Cat.ParentCategory -ne $null){
            # Si la categorie a un parent dans l'admx on le cherche et on l'ajoute
            $this.ParentCategory = [GPOToolsCategory]::FindParentCategory($Cat,$AllCat,$Adml)
            Write-Verbose ("[GPOToolsCategory] {0} Category have a parent : {1}" -f $Cat.Name,$Cat.ParentCategory.Name)

        }Else{
            # la categorie n'a pas de parent
            Write-Verbose "[GPOToolsCategory] $($Cat.Name) Category doesn't have parent"
        }
    }

    static [System.Collections.Generic.List[GpoToolsCategory]]Create(
        [AdmxCategory]$Category,
        [System.Collections.ArrayList]$AllCat,
        [GpoToolsAdml]$Adml
    ){
        # Si la category est presente dans la classe utility on rappel l'objet
        if (![GPOToolsUtility]::CheckCategoryPresence($Category.Name,$Category.target) ){
            Write-Verbose "[GPOToolsCategory]Loading of $($Category.Name) Category"
            $NewCat = [GpoToolsCategory]::New($Category,$AllCat,$Adml)

            # On ajoute la category au membre statique de la classe GPOToolsUtility
            [GPOToolsUtility]::Categories.Add($NewCat)
            return $NewCat
        }Else{
            Write-Verbose "[GPOToolsCategory] $($Category.Name) Category is already load in [GPOToolsUtility]::Categories"
            return [GPOToolsUtility]::Categories | Where-Object {$_.Name -eq $Category.Name}
        }
    }
    <#
        Methode static utilisee pour trouver la category parent d'une category.
        Elle recherche dans la propriete statique Categories de la classe GPOToolsUtility

        Use :
            [GPOToolsCategory]::New()
    #>
    static [GPOToolsCategory]FindParentCategory(
        [AdmxCategory]$Cat,
        [AdmxCategory[]]$Categories,
        [GpoToolsAdml]$Adml
    ){
        # Pour chaque category de Categories
        $ParentCat = [GPOToolsUtility]::Categories |
            Where-Object {
                    #Si la categorie a le meme nom que celle recherchÃ©
                    $_.Name -eq $Cat.ParentCategory.Name -and
                    (# Et que son prefix est similaire a celui de la category parent recherchee
                        $_.target.prefix -eq $Cat.ParentCategory.prefix -or
                        #Ou si la category parent est present dans le meme fichier admx avec
                        #le meme prefix que la category enfant
                        $_.target.prefix -eq $Cat.target.prefix
                    )
                }
        if ($null -eq $ParentCat.count){
            Write-Verbose "[GPOToolsCategory](FindParentCategory) No ParentCategory found for $($Cat.Name) Name in [GPOToolsUtility]::Categories static property"
            if($Categories.Name -contains $Cat.ParentCategory.Name){
                $ParentCat = $Categories.Name | Where-Object {$_.Name -eq $Category.ParentCategory.Name}
                if ($ParentCat -eq 1) {
                    return [GPOToolsCategory]::New($ParentCat,$Categories,$Adml)
                }Else{
                    Throw "[GPOToolsCategory](FindParentCategory) To many ParentCategory found for $($Cat.Name) in ADMX file"
                }
            }Else{
                throw ('[GPOToolsCategory](FindParentCategory) No category parent {0} found for {1} category in [GPOToolsUtility]::Categories static property and ADMX file' -f $Cat.ParentCategory.Name,$Cat.Name)
            }
        }ElseIf($ParentCat.count -ge 2){
            Throw "[GPOToolsCategory](FindParentCategory) To many ParentCategory found for $($Cat.Name)"
        }Else{
            return $ParentCat
        }
    }

    static [void]LoadAdmxAdml(
        [GpoToolsAdmx]$Admx,
        [GpoToolsAdml]$Adml
    ){
        $Result = $Admx.Categories | Foreach-Object {
            [GPOToolsCategory]::Create($_,$Admx.Categories,$Adml)
        }
    }
}

#Classe Policy
class GPOToolsPolicy {
    [string]$Path #Manque la notion d'Administrative Template
    [string]$Name
    [string]$DisplayName
    #[string]$State # Mettre une enumeration? Mettre simplement une methode, l'interrogation de l'ensemble du registre va prendre du temps
    [string]$Description
    [string]$ID
    [GpoToolsRegistry]$Registry
    [ScopePolicy]$Scope
    [string]$FileName
    Hidden [GpoToolscategory]$Category
    Hidden [GPOToolsSupportedOn]$SupportedOn

    GPOToolsPolicy([AdmxPolicy]$Policy,[GpoToolsAdml]$ADMLPol){
        $this.ID = $Policy.Name
        $this.Name = $ADMLPol.StringTable."$($Policy.Name)"
        $this.DisplayName = $ADMLPol.StringTable."$($Policy.DisplayName)"
        $this.Description = $ADMLPol.StringTable."$($Policy.explainText)"
        if ($Policy.Class -eq 'Machine'){
            $this.scope = [ScopePolicy]::Machine
        }Else{
            $this.scope = [ScopePolicy]::User
        }
        $this.FileName = (Split-Path $ADMLPol.FilePath -Leaf) -Replace 'l$','x'
        $this.Category = [GPOToolsPolicy]::FindParentCategory($Policy)
        $this.Path = $this.GeneratePath()

        $this.Registry = [GPOToolsRegistry]::New($Policy)
    }

    [string]GeneratePath(){
        if($this.Category -ne $Null){
            $GNPath = '{0}\{1}' -f $this.Scope,[GPOToolsPolicy]::GeneratePath($this.Category)
        }Else{
            $GNpath = '{0}\' -f $this.Scope
        }
        return $GnPath
    }
    static [string]GeneratePath([GpoToolscategory]$Cat){
        if($Cat.ParentCategory -ne $Null){
            $GNPath = '{0}{1}\' -f [GPOToolsPolicy]::GeneratePath($Cat.ParentCategory),$Cat.DisplayName
        }Else{
            $GNpath = '{0}\' -f $Cat.DisplayName
        }
        return $GNpath
    }

    <#
        Method static pour rechercher une category parent d'une policy
    #>
    static [GPOToolsCategory]FindParentCategory(
        [AdmxPolicy]$Pol
    ){
        # Pour chaque category de Categories
        $ParentCat = [GPOToolsUtility]::Categories |
            Where-Object {
                    #Si la categorie a le meme nom que celle recherchÃ©
                    $_.Name -eq $Pol.ParentCategory.Name -and
                    (# Et que son prefix est similaire a celui de la category parent recherchee
                        $_.target.prefix -eq $Pol.ParentCategory.prefix -or
                        #Ou si la category parent est present dans le meme fichier admx avec
                        #le meme prefix que la policy enfant
                        $_.target.prefix -eq $Pol.target.prefix
                    )
                }
        if ($null -eq $ParentCat.count){
            Throw "[GPOToolsCategory](FindParentCategory) No ParentCategory found for $($Pol.Name) policy in [GPOToolsUtility]::Categories static property"
        }ElseIf($ParentCat.count -ge 2){
            Throw "[GPOToolsCategory](FindParentCategory) To many ParentCategory found for $($Pol.Name) policy"
        }Else{
            return $ParentCat
        }
    }

    [StatePolicy]GetPolicyState(){
        if (-not (Test-path $This.Registry.Path)){
            $State = [StatePolicy]::NotConfigured
        }Else{
            $RegProperty = Get-ItemProperty $This.Registry.Path  -name $This.Registry.Key -ErrorAction SilentlyContinue
            if($RegProperty -eq $null){
                $State = [StatePolicy]::NotConfigured
            }Elseif($RegProperty.{$This.Registry.Key} -eq $this.Registry.Value.Enable){
                $State = [StatePolicy]::Enabled
            }Elseif($RegProperty.{$This.Registry.Key} -eq $this.Registry.Value.Disable){
                $State = [StatePolicy]::Disabled
            }Else{
                throw ('[GPOToolsPolicy](GetPolicyState) State not determinate for {0} policy' -f $this.DisplayName)
            }
        }

        return $State
    }
}

class GPOToolsRegistry {
    $Path
    $Key
    $Value
    $DefaultValue

    GPOToolsRegistry([AdmxPolicy]$Pol) {
        if ($Pol.Class -eq 'Machine'){
            $this.Path = 'HKLM:\{0}' -f $Pol.RegKey
        }Else{
            $this.Path = 'HKCU:\{0}' -f $Pol.RegKey
        }
        $this.Key = $Pol.ValueName
        $this.Value = @{
            Enable = $Pol.enableValue
            Disable = $pol.disableValue
        }
    }
}

#Classe de recuperation des informations contenues dans les fichiers amdx
class GpoToolsAdmx {
    [string]$FilePath
    [string]$BaseName
    [AdmxNamespace]$Target
    [System.Collections.ArrayList]$Using = @()
    [System.Collections.ArrayList]$SupportedOnDefinition = @()
    [System.Collections.ArrayList]$Categories = @()
    [System.Collections.ArrayList]$Policies = @()

    GpoToolsAdmx([string]$AdmxPath) {
        $File = Get-Item -Path $AdmxPath
        [xml]$Xml = Get-Content -Path $File.FullName -Encoding UTF8

        $PolicyDefinitions = $xml.policyDefinitions
        $trgt = [AdmxNamespace]::New($PolicyDefinitions.policyNamespaces.target)


        $This.FilePath = $File.FullName
        $This.BaseName = $File.BaseName
        $This.Target = $trgt

        if ($null -ne $PolicyDefinitions.policyNamespaces.using){
            $PolicyDefinitions.policyNamespaces.using | Foreach-Object {
                $This.Using.Add([AdmxNamespace]::New($_))
            }
        }

        if ($null -ne $PolicyDefinitions.supportedOn.definitions){
            $PolicyDefinitions.supportedOn.definitions.definition | Foreach-Object {
                $This.SupportedOnDefinition.Add([AdmxSupportedOn]::New($_))
            }
        }

        if ($null -ne $PolicyDefinitions.categories){
            $PolicyDefinitions.categories.Category | Foreach-Object {
                $this.Categories.Add($([AdmxCategory]::New($_,$trgt)))
            }
        }

        if ($null -ne $PolicyDefinitions.Policies){
            $PolicyDefinitions.Policies.policy | Foreach-Object {
                $this.Policies.Add($([AdmxPolicy]::New($_,$trgt)))
            }
        }
    }
}
#Classe utilisee dans GPOToolsAdmx  pour lire les policy
class AdmxPolicy {
    $Name
    $Class
    $DisplayName
    $explainText
    $RegKey
    $ValueName
    [hashtable]$ParentCategory
    $SupportedOn
    $enableValue
    $disableValue
    $elements

    AdmxPolicy ($Policy,[AdmxNamespace]$target){
        $this.Name = $policy.Name
        $this.Class = $policy.Class
        $this.DisplayName = $policy.DisplayName -replace '\$\(string\.(.*)\)', '$1'
        $this.explainText = $policy.explainText -replace '\$\(string\.(.*)\)', '$1'
        $this.RegKey = $policy.Key
        $this.ValueName = $policy.ValueName
        $this.SupportedOn = $policy.SupportedOn
        $this.enableValue = $policy.enabledValue.decimal.Value
        $this.disableValue = $policy.disabledValue.decimal.Value
        if ($policy.ParentCategory.ref -ne $null){
            $SplitResult = $policy.ParentCategory.ref -split ':'
            if ($SplitResult.count -eq 1){
                $this.ParentCategory = @{
                    prefix = $target.prefix
                    name = $SplitResult[0]
                }
            }Else{
                $this.ParentCategory = @{
                    prefix = $SplitResult[0]
                    name = $SplitResult[1]
                }
            }
        }Else{
            Write-Verbose ("[AdmxPolicy] No parent category found for {0} policy" -f $policy.Name)
        }
        #$this.elements = $policy.elements


    }
}

#Classe utilise dans GPOToolsAdmx pour les categories des fichiers admx
class AdmxCategory {
    [string]$Name
    [string]$DisplayName
    [AdmxNamespace]$target
    [string]$explainText
    [hashtable]$ParentCategory

    AdmxCategory ($Category,[AdmxNamespace]$target){
        $this.Name = $Category.Name
        $this.DisplayName = $Category.DisplayName -replace '\$\(string\.(.*)\)', '$1'
        $this.target = $target
        $this.explainText = $Category.explainText -replace '\$\(string\.(.*)\)', '$1'
        if ($Category.parentcategory.ref -ne $null){
            $SplitResult = $Category.parentcategory.ref -split ':'
            if ($SplitResult.count -eq 1){
                $this.ParentCategory = @{
                    prefix = $target.prefix
                    name = $SplitResult[0]
                }
            }Else{
                $this.ParentCategory = @{
                    prefix = $SplitResult[0]
                    name = $SplitResult[1]
                }
            }
        }Else{
            Write-Verbose ("[AdmxCategory] No parent category found for {0} category" -f $Category.Name)
        }
    }
}
# Class pour les ressources SupportedOn (Exemple Windows.admx)
class AdmxSupportedOn {
    [string]$Name
    [string]$DisplayName

    AdmxSupportedOn ($SupportedOn) {
        $This.Name = $SupportedOn.Name
        $THis.DisplayName = $SupportedOn.DisplayName -replace '\$\(string\.(.*)\)', '$1'
    }
}

class AdmxNamespace {
    [string]$prefix
    [string]$namespace

    AdmxNamespace($namesp) {
        $this.prefix = $namesp.prefix
        $this.namespace = $namesp.namespace
    }
}


#Classe de recuperation des informations contenues dans les fichiers admx
class GpoToolsAdml {
    [string]$FilePath
    [string]$BaseName
    [Hashtable]$StringTable

    #presentationTable

    GpoToolsAdml ([string]$AdmlPath) {
        $File = Get-Item -Path $AdmlPath
        [xml]$Xml = Get-Content -Path $File.FullName -Encoding UTF8

        $This.FilePath = $File.FullName
        $This.BaseName = $File.BaseName
        $this.StringTable = @{}

        $xml.policyDefinitionResources.resources.stringTable.string | Foreach-Object {
            Write-Verbose ('Ajout du champ {0} dans la table StringTable pour le fichier {1}' -f $_.id,$File.BaseName)
            $this.StringTable.Add($_.id,$_.'#Text')
        }
    }
}
function Get-PSGPOCategory {
    [cmdletbinding()]
    Param()

    ### VAR ###
    ### MAIN ###
    $Categories =  [GpoToolsUtility]::Categories
    If ($null -eq $Categories){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }Else{
        return $Categories
    }
}
function Get-PSGPOPolicy {
    [cmdletbinding()]
    Param(
        [ValidateSet("User", "Machine")]
        [string]$Scope
    )

    ### VAR ###
    ### MAIN ###
    $Policies =  [GpoToolsUtility]::Policies | Where-Object { $_.Scope -eq $Scope }
    If ($null -eq $Policies){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }Else{
        return $Policies
    }
}
function Get-PSGPOSupportedOn {
    [cmdletbinding()]
    Param()

    ### VAR ###
    ### MAIN ###
    $Support =  [GpoToolsUtility]::SupportOnTable
    If ($null -eq $Support){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }Else{
        return $Support
    }
}
function Initialize-PSGPOAdmx {
    [cmdletbinding()]
    Param(
        [ValidateScript( { Test-Path -Path $_ })]
        [String]$Path = "$Env:windir\PolicyDefinitions\",

        [cultureinfo]$UICulture = [cultureinfo]::CurrentUICulture
    )

    ### VAR ###
    $Item = Get-Item -Path $Path
    ### MAIN ###
    # Empty Statics properties
    [GPOToolsUtility]::RemoveAll()

    # Sequential processing to load ADMX and ADML files
    [GPOToolsUtility]::InitiateAdmxAdml($Item, $UICulture)
}

function Show-GPOManager {
    [cmdletbinding()]
    Param()

    # Ensure WPF assemblies are loaded for PowerShell 7.5 and .NET 9 compatibility
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager'
        Height='700' Width='1200'
        MinHeight='500' MinWidth='800'
        WindowStartupLocation='CenterScreen'
        Background='#F5F5F5'
        Name='MainWindow'>
    <Window.Resources>
        <!-- Light Theme Colors -->
        <SolidColorBrush x:Key='PrimaryBrush' Color='#0078D4'/>
        <SolidColorBrush x:Key='PrimaryHoverBrush' Color='#106EBE'/>
        <SolidColorBrush x:Key='PrimaryPressedBrush' Color='#005A9E'/>
        <SolidColorBrush x:Key='AccentBrush' Color='#00BCF2'/>
        <SolidColorBrush x:Key='BackgroundBrush' Color='#FFFFFF'/>
        <SolidColorBrush x:Key='SecondaryBackgroundBrush' Color='#F5F5F5'/>
        <SolidColorBrush x:Key='BorderBrush' Color='#E1E1E1'/>
        <SolidColorBrush x:Key='TextBrush' Color='#1F1F1F'/>
        <SolidColorBrush x:Key='SecondaryTextBrush' Color='#605E5C'/>
        <SolidColorBrush x:Key='TreeViewSelectedBrush' Color='#0078D4'/>
        <SolidColorBrush x:Key='TreeViewSelectedTextBrush' Color='#FFFFFF'/>
        <SolidColorBrush x:Key='TreeViewHoverBrush' Color='#F3F2F1'/>
        <SolidColorBrush x:Key='IconFolderBrush' Color='#FDB900'/>
        <SolidColorBrush x:Key='IconFileBrush' Color='#0078D4'/>
        <SolidColorBrush x:Key='IconScopeBrush' Color='#107C10'/>
        <SolidColorBrush x:Key='HeaderBackgroundBrush' Color='#F3F2F1'/>
        <SolidColorBrush x:Key='HeaderTextBrush' Color='#1F1F1F'/>

        <!-- Modern Button Style -->
        <Style x:Key='ModernButton' TargetType='Button'>
            <Setter Property='Background' Value='{StaticResource PrimaryBrush}'/>
            <Setter Property='Foreground' Value='White'/>
            <Setter Property='BorderThickness' Value='0'/>
            <Setter Property='Padding' Value='16,8'/>
            <Setter Property='FontSize' Value='14'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Cursor' Value='Hand'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='Button'>
                        <Border Background='{TemplateBinding Background}'
                                CornerRadius='4'
                                Padding='{TemplateBinding Padding}'>
                            <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property='IsMouseOver' Value='True'>
                    <Setter Property='Background' Value='{StaticResource PrimaryHoverBrush}'/>
                </Trigger>
                <Trigger Property='IsPressed' Value='True'>
                    <Setter Property='Background' Value='{StaticResource PrimaryPressedBrush}'/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern TextBox Style -->
        <Style x:Key='ModernTextBox' TargetType='TextBox'>
            <Setter Property='Background' Value='{StaticResource BackgroundBrush}'/>
            <Setter Property='Foreground' Value='{StaticResource TextBrush}'/>
            <Setter Property='BorderBrush' Value='{StaticResource BorderBrush}'/>
            <Setter Property='BorderThickness' Value='1'/>
            <Setter Property='Padding' Value='12,8'/>
            <Setter Property='FontSize' Value='14'/>
            <Setter Property='VerticalContentAlignment' Value='Center'/>
            <Setter Property='Template'>
                <Setter.Value>
                    <ControlTemplate TargetType='TextBox'>
                        <Border Background='{TemplateBinding Background}'
                                BorderBrush='{TemplateBinding BorderBrush}'
                                BorderThickness='{TemplateBinding BorderThickness}'
                                CornerRadius='4'>
                            <ScrollViewer x:Name='PART_ContentHost' Margin='2'/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property='IsMouseOver' Value='True'>
                                <Setter Property='BorderBrush' Value='{StaticResource PrimaryBrush}'/>
                            </Trigger>
                            <Trigger Property='IsFocused' Value='True'>
                                <Setter Property='BorderBrush' Value='{StaticResource PrimaryBrush}'/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern TreeView Style with proper selection colors -->
        <Style TargetType='TreeView'>
            <Setter Property='Background' Value='{DynamicResource BackgroundBrush}'/>
            <Setter Property='BorderBrush' Value='{DynamicResource BorderBrush}'/>
            <Setter Property='BorderThickness' Value='1'/>
            <Setter Property='Padding' Value='8'/>
            <Setter Property='FontSize' Value='13'/>
        </Style>

        <Style TargetType='TreeViewItem'>
            <Setter Property='Padding' Value='4'/>
            <Setter Property='Margin' Value='0,1'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
            <Style.Triggers>
                <Trigger Property='IsMouseOver' Value='True'>
                    <Setter Property='Background' Value='{DynamicResource TreeViewHoverBrush}'/>
                </Trigger>
                <Trigger Property='IsSelected' Value='True'>
                    <Setter Property='Background' Value='{DynamicResource TreeViewSelectedBrush}'/>
                    <Setter Property='Foreground' Value='{DynamicResource TreeViewSelectedTextBrush}'/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern DataGrid Style -->
        <Style TargetType='DataGrid'>
            <Setter Property='Background' Value='{DynamicResource BackgroundBrush}'/>
            <Setter Property='BorderBrush' Value='{DynamicResource BorderBrush}'/>
            <Setter Property='BorderThickness' Value='1'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
            <Setter Property='RowBackground' Value='{DynamicResource BackgroundBrush}'/>
            <Setter Property='AlternatingRowBackground' Value='{DynamicResource SecondaryBackgroundBrush}'/>
            <Setter Property='GridLinesVisibility' Value='None'/>
            <Setter Property='HeadersVisibility' Value='Column'/>
            <Setter Property='FontSize' Value='13'/>
            <Setter Property='CanUserResizeRows' Value='False'/>
        </Style>

        <Style TargetType='DataGridColumnHeader'>
            <Setter Property='Background' Value='{DynamicResource HeaderBackgroundBrush}'/>
            <Setter Property='Foreground' Value='{DynamicResource HeaderTextBrush}'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Padding' Value='12,8'/>
            <Setter Property='BorderThickness' Value='0,0,0,2'/>
            <Setter Property='BorderBrush' Value='{DynamicResource BorderBrush}'/>
        </Style>

        <Style TargetType='DataGridRow'>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
        </Style>

        <Style TargetType='DataGridCell'>
            <Setter Property='BorderThickness' Value='0'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
        </Style>

        <!-- Label Style -->
        <Style x:Key='LabelStyle' TargetType='TextBlock'>
            <Setter Property='FontSize' Value='12'/>
            <Setter Property='FontWeight' Value='SemiBold'/>
            <Setter Property='Foreground' Value='{DynamicResource SecondaryTextBrush}'/>
            <Setter Property='Margin' Value='0,8,0,4'/>
        </Style>

        <Style x:Key='ReadOnlyTextBox' TargetType='TextBox' BasedOn='{StaticResource ModernTextBox}'>
            <Setter Property='IsReadOnly' Value='True'/>
            <Setter Property='Background' Value='{DynamicResource SecondaryBackgroundBrush}'/>
            <Setter Property='Foreground' Value='{DynamicResource TextBrush}'/>
            <Setter Property='TextWrapping' Value='Wrap'/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='*'/>
        </Grid.RowDefinitions>

        <!-- Header Section with Modern Search and Theme Toggle -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}'
                BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}'
                Padding='20,16'>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width='Auto'/>
                    <ColumnDefinition Width='*'/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                    <TextBlock Text='GPO Policy Manager'
                               FontSize='22'
                               FontWeight='Bold'
                               Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Text='Explore and manage Group Policy Objects'
                               FontSize='12'
                               Foreground='{DynamicResource SecondaryTextBrush}'
                               Margin='0,2,0,0'/>
                </StackPanel>

                <StackPanel Grid.Column='1'
                           Orientation='Horizontal'
                           HorizontalAlignment='Right'
                           VerticalAlignment='Center'>
                    <Button Name='themeToggleButton'
                            Content='🌙 Mode Sombre'
                            Height='36'
                            Width='140'
                            Style='{StaticResource ModernButton}'
                            Margin='0,0,12,0'/>
                    <TextBox Name='searchTextBox'
                             Width='320'
                             Height='36'
                             Style='{StaticResource ModernTextBox}'
                             VerticalContentAlignment='Center'
                             Margin='0,0,12,0'
                             Text='Rechercher une GPO...'
                             Foreground='#999999'/>
                    <Button Name='searchButton'
                            Content='🔍 Rechercher'
                            Height='36'
                            Width='130'
                            Style='{StaticResource ModernButton}'/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Content Area with Splitter -->
        <Grid Grid.Row='1' Margin='0'>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width='2*' MinWidth='250'/>
                <ColumnDefinition Width='Auto'/>
                <ColumnDefinition Width='3*' MinWidth='300'/>
            </Grid.ColumnDefinitions>

            <!-- TreeView Panel -->
            <Border Grid.Column='0'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='16,16,8,16'
                    CornerRadius='8'
                    BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'>
                <Border.Effect>
                    <DropShadowEffect BlurRadius='10' ShadowDepth='2' Opacity='0.1' Color='Black'/>
                </Border.Effect>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height='Auto'/>
                        <RowDefinition Height='*'/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row='0'
                            Name='treeHeaderBorder'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12'
                            CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <TextBlock Name='treeTitleTextBlock'
                                       Text='📁 Policy Structure'
                                       FontSize='15'
                                       FontWeight='SemiBold'
                                       Foreground='{DynamicResource HeaderTextBrush}'/>
                            <TextBlock Name='breadcrumbTextBlock'
                                       Text='Select a policy to see its path'
                                       FontSize='11'
                                       Foreground='{DynamicResource SecondaryTextBrush}'
                                       Margin='0,4,0,0'
                                       TextTrimming='CharacterEllipsis'/>
                        </StackPanel>
                    </Border>

                    <TreeView Name='treeView' Grid.Row='1' Margin='8'>
                        <TreeView.ContextMenu>
                            <ContextMenu Name='treeViewContextMenu'>
                                <MenuItem Name='enableMenuItem' Header='✅ Enable this parameter'/>
                                <MenuItem Name='disableMenuItem' Header='❌ Disable this parameter'/>
                                <Separator/>
                                <MenuItem Name='createGpoMenuItem' Header='➕ Create a GPO'/>
                            </ContextMenu>
                        </TreeView.ContextMenu>
                    </TreeView>
                </Grid>
            </Border>

            <!-- Splitter -->
            <GridSplitter Grid.Column='1'
                         Width='6'
                         HorizontalAlignment='Center'
                         VerticalAlignment='Stretch'
                         Background='Transparent'
                         ShowsPreview='True'/>

            <!-- Details Panel -->
            <Border Grid.Column='2'
                    Background='{DynamicResource BackgroundBrush}'
                    Margin='8,16,16,16'
                    CornerRadius='8'
                    BorderThickness='1'
                    BorderBrush='{DynamicResource BorderBrush}'>
                <Border.Effect>
                    <DropShadowEffect BlurRadius='10' ShadowDepth='2' Opacity='0.1' Color='Black'/>
                </Border.Effect>
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height='Auto'/>
                        <RowDefinition Height='*'/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row='0'
                            Name='detailsHeaderBorder'
                            Background='{DynamicResource HeaderBackgroundBrush}'
                            Padding='16,12'
                            CornerRadius='8,8,0,0'>
                        <TextBlock Name='detailsTitleTextBlock'
                                   Text='ℹ️ Policy Details'
                                   FontSize='15'
                                   FontWeight='SemiBold'
                                   Foreground='{DynamicResource HeaderTextBrush}'/>
                    </Border>

                    <ScrollViewer Grid.Row='1'
                                 VerticalScrollBarVisibility='Auto'
                                 Padding='16'>
                        <StackPanel Name='detailsPanel'>
                            <TextBlock Text='Display Name' Style='{StaticResource LabelStyle}'/>
                            <TextBox Name='displayNameTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Description' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='descriptionTextBox'
                                    Style='{StaticResource ReadOnlyTextBox}'
                                    MinHeight='60'
                                    MaxHeight='120'
                                    VerticalScrollBarVisibility='Auto'/>

                            <TextBlock Text='Scope' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='scopeTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Registry Path' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='registryPathTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Registry Key' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <TextBox Name='registryKeyTextBox' Style='{StaticResource ReadOnlyTextBox}'/>

                            <TextBlock Text='Registry Values' Style='{StaticResource LabelStyle}' Margin='0,16,0,4'/>
                            <DataGrid Name='registryValuesGrid'
                                     AutoGenerateColumns='False'
                                     IsReadOnly='True'
                                     MaxHeight='200'
                                     Margin='0,0,0,16'>
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header='Name' Binding='{Binding Key}' Width='*'/>
                                    <DataGridTextColumn Header='Value' Binding='{Binding Value}' Width='2*'/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

        $xmlDocument = New-Object System.Xml.XmlDocument
        $xmlDocument.LoadXml($xaml)
        $reader = New-Object System.Xml.XmlNodeReader $xmlDocument
        $window = [Windows.Markup.XamlReader]::Load($reader)

    $treeView = $window.FindName("treeView")
    $themeToggleButton = $window.FindName("themeToggleButton")
    $treeTitleTextBlock = $window.FindName("treeTitleTextBlock")
    $detailsTitleTextBlock = $window.FindName("detailsTitleTextBlock")

    # Theme management
    $isDarkTheme = $false

    function Set-Theme {
        param([bool]$dark)

        $resources = $window.Resources

        if ($dark) {
            # Dark Theme - Improved colors
            $resources['PrimaryBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0086F0')
            $resources['PrimaryHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#3399FF')
            $resources['PrimaryPressedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0066CC')
            $resources['AccentBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#00D4FF')
            $resources['BackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1E1E1E')
            $resources['SecondaryBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#2D2D30')
            $resources['BorderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#3F3F46')
            $resources['TextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['SecondaryTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#CCCCCC')
            $resources['TreeViewSelectedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0086F0')
            $resources['TreeViewSelectedTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['TreeViewHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#2D2D30')
            $resources['IconFolderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFD700')
            $resources['IconFileBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#64B5F6')
            $resources['IconScopeBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#81C784')
            $resources['HeaderBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#252526')
            $resources['HeaderTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')

            $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1E1E1E')
            $themeToggleButton.Content = '☀️ Mode Clair'

            # Update header backgrounds
            $treeHeaderBorder = $window.FindName("treeHeaderBorder")
            $detailsHeaderBorder = $window.FindName("detailsHeaderBorder")
            if ($treeHeaderBorder) {
                $treeHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#252526')
            }
            if ($detailsHeaderBorder) {
                $detailsHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#252526')
            }
        } else {
            # Light Theme
            $resources['PrimaryBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
            $resources['PrimaryHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#106EBE')
            $resources['PrimaryPressedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#005A9E')
            $resources['AccentBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#00BCF2')
            $resources['BackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['SecondaryBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F5F5F5')
            $resources['BorderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#E1E1E1')
            $resources['TextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1F1F1F')
            $resources['SecondaryTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#605E5C')
            $resources['TreeViewSelectedBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
            $resources['TreeViewSelectedTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FFFFFF')
            $resources['TreeViewHoverBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            $resources['IconFolderBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FDB900')
            $resources['IconFileBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#0078D4')
            $resources['IconScopeBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#107C10')
            $resources['HeaderBackgroundBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            $resources['HeaderTextBrush'] = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#1F1F1F')

            $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F5F5F5')
            $themeToggleButton.Content = '🌙 Mode Sombre'

            # Update header backgrounds
            $treeHeaderBorder = $window.FindName("treeHeaderBorder")
            $detailsHeaderBorder = $window.FindName("detailsHeaderBorder")
            if ($treeHeaderBorder) {
                $treeHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            }
            if ($detailsHeaderBorder) {
                $detailsHeaderBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#F3F2F1')
            }
        }
    }

    $themeToggleButton.Add_Click({
        $script:isDarkTheme = -not $script:isDarkTheme
        Set-Theme -dark $script:isDarkTheme
    })

    # Get context menu items from XAML
    $enableMenuItem = $window.FindName("enableMenuItem")
    $disableMenuItem = $window.FindName("disableMenuItem")
    $createGpoMenuItem = $window.FindName("createGpoMenuItem")

    # Add click handlers to menu items
    if ($enableMenuItem) {
        $enableMenuItem.Add_Click({
            $selectedItem = $treeView.SelectedItem
            if ($selectedItem -and $selectedItem.Tag -is [GPOToolsPolicy]) {
                Write-Host "Enable: $($selectedItem.Tag.DisplayName)"
            }
        })
    }

    if ($disableMenuItem) {
        $disableMenuItem.Add_Click({
            $selectedItem = $treeView.SelectedItem
            if ($selectedItem -and $selectedItem.Tag -is [GPOToolsPolicy]) {
                Write-Host "Disable: $($selectedItem.Tag.DisplayName)"
            }
        })
    }

    if ($createGpoMenuItem) {
        $createGpoMenuItem.Add_Click({
            $selectedItem = $treeView.SelectedItem
            if ($selectedItem -and $selectedItem.Tag -is [GPOToolsPolicy]) {
                Write-Host "Create GPO for: $($selectedItem.Tag.DisplayName)"
            }
        })
    }

    $displayNameTextBox = $window.FindName("displayNameTextBox")
    $descriptionTextBox = $window.FindName("descriptionTextBox")
    $scopeTextBox = $window.FindName("scopeTextBox")
    $registryPathTextBox = $window.FindName("registryPathTextBox")
    $registryKeyTextBox = $window.FindName("registryKeyTextBox")
    $registryValuesGrid = $window.FindName("registryValuesGrid")
    $searchTextBox = $window.FindName("searchTextBox")
    $searchButton = $window.FindName("searchButton")
    $breadcrumbTextBlock = $window.FindName("breadcrumbTextBlock")

    $treeView.add_SelectedItemChanged({
        $selectedItem = $treeView.SelectedItem
        if ($selectedItem -is [Windows.Controls.TreeViewItem]) {
            $policy = $selectedItem.Tag

            # Build breadcrumb path
            $breadcrumbPath = ""
            $currentItem = $selectedItem
            $pathParts = @()

            while ($currentItem -ne $null) {
                if ($currentItem.Tag -is [GPOToolsPolicy]) {
                    $pathParts = @($currentItem.Tag.DisplayName) + $pathParts
                } elseif ($currentItem.Tag -is [GPOToolsCategory]) {
                    $pathParts = @($currentItem.Tag.DisplayName) + $pathParts
                } elseif ($currentItem.Tag -is [ScopePolicy]) {
                    $pathParts = @($currentItem.Tag.ToString()) + $pathParts
                }
                $currentItem = $currentItem.Parent
                if ($currentItem -isnot [Windows.Controls.TreeViewItem]) {
                    break
                }
            }

            $breadcrumbPath = $pathParts -join ' > '
            if ($breadcrumbPath) {
                $breadcrumbTextBlock.Text = "📍 $breadcrumbPath"
            } else {
                $breadcrumbTextBlock.Text = "Select a policy to see its path"
            }

            if ($policy -is [GPOToolsPolicy]) {
                $displayNameTextBox.Text = $policy.DisplayName
                $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { "(Aucune description disponible)" }
                $scopeTextBox.Text = $policy.Scope.ToString()

                # Handle registry information with null checks
                if ($policy.Registry) {
                    $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { "(Aucun chemin de registre défini)" }
                    $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { "(Aucune clé de registre définie)" }

                    # Populate registry values in the DataGrid
                    if ($policy.Registry.Value -and $policy.Registry.Value.Keys.Count -gt 0) {
                        $registryValuesGrid.ItemsSource = @(
                            foreach ($key in $policy.Registry.Value.Keys) {
                                [PSCustomObject]@{
                                    Key   = $key
                                    Value = if ($policy.Registry.Value[$key]) { $policy.Registry.Value[$key] } else { "(Valeur non définie)" }
                                }
                            }
                        )
                    } else {
                        $registryValuesGrid.ItemsSource = @(
                            [PSCustomObject]@{
                                Key   = "Information"
                                Value = "(Aucune valeur de registre disponible pour cette GPO)"
                            }
                        )
                    }
                } else {
                    $registryPathTextBox.Text = "(Cette GPO ne nécessite pas de configuration de registre)"
                    $registryKeyTextBox.Text = "(Aucune clé de registre)"
                    $registryValuesGrid.ItemsSource = @(
                        [PSCustomObject]@{
                            Key   = "Information"
                            Value = "(Cette policy ne stocke pas de données dans le registre)"
                        }
                    )
                }
            } else {
                $displayNameTextBox.Text = ""
                $descriptionTextBox.Text = ""
                $scopeTextBox.Text = ""
                $registryPathTextBox.Text = ""
                $registryKeyTextBox.Text = ""
                $registryValuesGrid.ItemsSource = $null
            }
        }
    })

    function Populate-TreeView {
        param(
            [string]$Filter = ''
        )
        $treeView.Items.Clear()
        $scopes = [Enum]::GetValues([ScopePolicy])
        foreach ($scope in $scopes) {
            $scopeItem = New-Object Windows.Controls.TreeViewItem

            # Create StackPanel for icon + text
            $scopePanel = New-Object Windows.Controls.StackPanel
            $scopePanel.Orientation = 'Horizontal'

            $scopeIcon = New-Object Windows.Controls.TextBlock
            $scopeIcon.Text = '📋 '
            $scopeIcon.FontSize = 14
            $scopeIcon.Foreground = $window.Resources['IconScopeBrush']

            $scopeText = New-Object Windows.Controls.TextBlock
            $scopeText.Text = $scope.ToString()
            $scopeText.FontWeight = 'SemiBold'

            $scopePanel.Children.Add($scopeIcon) | Out-Null
            $scopePanel.Children.Add($scopeText) | Out-Null
            $scopeItem.Header = $scopePanel
            $scopeItem.Tag = $scope

            $policies = Get-PSGPOPolicy -Scope $scope
            if ($Filter -and $Filter -ne '' -and $Filter -ne 'Rechercher une GPO...') {
                $policies = $policies | Where-Object { $_.DisplayName -like "*$Filter*" }
            }

            foreach ($policy in $policies) {
                $category = $policy.Category
                $parentCategory = $category.ParentCategory
                $currentItem = $scopeItem

                while ($null -ne $parentCategory) {
                    # Check if category already exists
                    $existingItem = $null
                    foreach ($item in $currentItem.Items) {
                        if ($item.Tag -and $item.Tag.DisplayName -eq $parentCategory.DisplayName) {
                            $existingItem = $item
                            break
                        }
                    }

                    if (-not $existingItem) {
                        $newItem = New-Object Windows.Controls.TreeViewItem

                        # Create StackPanel for folder icon + text
                        $folderPanel = New-Object Windows.Controls.StackPanel
                        $folderPanel.Orientation = 'Horizontal'

                        $folderIcon = New-Object Windows.Controls.TextBlock
                        $folderIcon.Text = '📂 '
                        $folderIcon.FontSize = 13
                        $folderIcon.Foreground = $window.Resources['IconFolderBrush']

                        $folderText = New-Object Windows.Controls.TextBlock
                        $folderText.Text = $parentCategory.DisplayName

                        $folderPanel.Children.Add($folderIcon) | Out-Null
                        $folderPanel.Children.Add($folderText) | Out-Null
                        $newItem.Header = $folderPanel
                        $newItem.Tag = $parentCategory

                        $currentItem.Items.Add($newItem) | Out-Null
                        $currentItem = $newItem
                    } else {
                        $currentItem = $existingItem
                    }
                    $parentCategory = $parentCategory.ParentCategory
                }

                $policyItem = New-Object Windows.Controls.TreeViewItem

                # Create StackPanel for file icon + text
                $policyPanel = New-Object Windows.Controls.StackPanel
                $policyPanel.Orientation = 'Horizontal'

                $policyIcon = New-Object Windows.Controls.TextBlock
                $policyIcon.Text = '📄 '
                $policyIcon.FontSize = 13
                $policyIcon.Foreground = $window.Resources['IconFileBrush']

                $policyText = New-Object Windows.Controls.TextBlock
                $policyText.Text = $policy.DisplayName

                $policyPanel.Children.Add($policyIcon) | Out-Null
                $policyPanel.Children.Add($policyText) | Out-Null
                $policyItem.Header = $policyPanel
                $policyItem.Tag = $policy

                $currentItem.Items.Add($policyItem) | Out-Null
            }

            if ($scopeItem.Items.Count -gt 0) {
                $treeView.Items.Add($scopeItem) | Out-Null
            }
        }
    }

    # Initial population

    Populate-TreeView

    # Modern search functionality with placeholder behavior
    $searchPlaceholder = "Rechercher une GPO..."

    $searchTextBox.Add_GotFocus({
        if ($searchTextBox.Text -eq $searchPlaceholder) {
            $searchTextBox.Text = ""
            $searchTextBox.Foreground = [System.Windows.Media.Brushes]::Black
        }
    })

    $searchTextBox.Add_LostFocus({
        if ([string]::IsNullOrWhiteSpace($searchTextBox.Text)) {
            $searchTextBox.Text = $searchPlaceholder
            $searchTextBox.Foreground = [System.Windows.Media.Brushes]::Gray
        }
    })

    $searchButton.Add_Click({
        $filter = $searchTextBox.Text
        if ($filter -ne $searchPlaceholder) {
            Populate-TreeView -Filter $filter
        } else {
            Populate-TreeView
        }
    })

    $searchTextBox.Add_KeyDown({
        if ($_.Key -eq 'Return') {
            $filter = $searchTextBox.Text
            if ($filter -ne $searchPlaceholder) {
                Populate-TreeView -Filter $filter
            } else {
                Populate-TreeView
            }
        }
    })

    # Set window icon if available
    try {
        $window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]::new("pack://application:,,,/icon.ico"))
    } catch {
        # Icon not found, continue without it
    }

    $window.ShowDialog() | Out-Null
}