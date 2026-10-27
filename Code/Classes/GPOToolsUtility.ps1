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
    # Index Name -> List[GpoToolsCategory], alimente par AddCategory()
    static hidden [hashtable]$CategoryIndex = @{}
    # Index Dossier -> (Namespace -> List[FileInfo]), alimente par FindDependancyFile()
    static hidden [hashtable]$NamespaceIndex = @{}
    # Namespace of each admx file read (its path): read once, its target only
    static hidden [hashtable]$NamespaceByFile = @{}

    static [void]InitiateAdmxAdml(
        [System.IO.DirectoryInfo]$Folder,
        [cultureinfo]$UICulture
    ){
        #Importer l'ensemble des fichiers admx
        #Importer les dependances en premier lieu !
        #Pour chaque fichier ADMX on importe le fichier AMDL correspondant
        #On incremente les categories
        #Comment valider que les dependances sont bien deja presents et pas necessaire de les recharger ?
        #noter un element unique (nom du fichier ?) hashtable ?

        #On passe en revu chaque fichier admx
        if (Test-Path -Path $Folder.FullName){
            Write-Verbose "Initialization of ADMX file in $Folder"
            $AdmxFiles = [GPOToolsUtility]::GetAdmxFiles($Folder.FullName)
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

                #On verifie si il a besoin de dependance et on les charges
                [GPOToolsUtility]::CheckAndInitiateDependancy($ADMX,$UICulture)

                #On determine le fichier ADML correspondant
                $ADMLPath = [GPOToolsUtility]::GetADMLPathFromADMX($File,$UICulture)

                #On charge le fichier ADML correspondant
                $ADML = [GpoToolsAdml]::New($ADMLPath)

                #On cree les objets SupportedOn
                #et on les incremente dans la propriete statique
                foreach ($SupportedOn in $ADMX.SupportedOnDefinition){
                    [GPOToolsutility]::SupportOnTable.Add([GPOToolsSupportedOn]::New($SupportedOn,$ADML))
                }

                #On initialise les objets Category
                [GPOToolsCategory]::LoadAdmxAdml($Admx,$Adml)

                #On cree les objet Policy et on les incremente dans la propriete statique
                #Une policy de classe Both existe cote Machine et cote User, comme dans la GPMC
                foreach ($Policy in $ADMX.Policies){
                    if ($Policy.Class -eq 'Both'){
                        [GPOToolsutility]::Policies.Add([GPOToolsPolicy]::New($Policy,$ADML,[ScopePolicy]::Machine))
                        [GPOToolsutility]::Policies.Add([GPOToolsPolicy]::New($Policy,$ADML,[ScopePolicy]::User))
                    }Else{
                        [GPOToolsutility]::Policies.Add([GPOToolsPolicy]::New($Policy,$ADML))
                    }
                }

                [GPOToolsutility]::TargetLoad.Add($ADMX.Target.namespace)

            }Else{
                Write-Verbose "$File is already Initiate"
            }
        }Else{
            Write-Error "File $File not found"
        }
    }

    # Namespace of an admx file: its first target element, read once per file. The file was read
    # in full, line by line, for each admx loaded and for the index of the dependencies: three times
    # per file, through the network for the central store of SYSVOL.
    static [string]GetNamespaceAdmx(
        [System.IO.FileInfo]$AdmxFile
    ){
        $Known = [GPOToolsUtility]::NamespaceByFile[$AdmxFile.FullName]
        if ($null -ne $Known){
            return $Known
        }
        $Namespace = ''
        $Reader = [System.Xml.XmlReader]::Create($AdmxFile.FullName)
        try {
            while ($Reader.Read()){
                if ($Reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $Reader.LocalName -eq 'target'){
                    $Namespace = $Reader.GetAttribute('namespace')
                    break
                }
            }
        } finally {
            $Reader.Dispose()
        }
        [GPOToolsUtility]::NamespaceByFile[$AdmxFile.FullName] = $Namespace
        return $Namespace
    }

    # An admx or adml file as an XML document: read at once, its encoding from its byte order mark
    # or its declaration (not line by line through the pipeline).
    static [xml]ReadXml([string]$Path){
        $Xml = [System.Xml.XmlDocument]::new()
        $Xml.Load($Path)
        return $Xml
    }
    static [string]GetADMLPathFromADMX(
        [System.IO.FileInfo]$AdmxFile,
        [cultureinfo]$UICulture
    ){
        $ParentPath = Split-Path -Path $AdmxFile.FullName
        $ADMLName = $AdmxFile.Name -replace '\.admx$','.adml'
        $ADMLPath  = [System.IO.Path]::Combine($ParentPath,$UICulture.Name,$ADMLName)
        if (Test-Path -LiteralPath $ADMLPath){
            return $ADMLPath
        }
        # Les fichiers Microsoft n'ont pas toujours la meme casse (inetres.admx / InetRes.adml,
        # kdc.admx / KDC.adml) : sur un systeme de fichiers sensible a la casse (Linux, SYSVOL
        # Samba en acces local), on cherche le dossier de langue et le fichier sans tenir compte de la casse.
        $CultureFolder = Get-ChildItem -LiteralPath $ParentPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $UICulture.Name } | Select-Object -First 1
        if ($null -ne $CultureFolder){
            $ADMLFile = Get-ChildItem -LiteralPath $CultureFolder.FullName -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $ADMLName } | Select-Object -First 1
            if ($null -ne $ADMLFile){
                return $ADMLFile.FullName
            }
        }
        Throw "The ADML File $ADMLPath doesn't exist."
    }

    # Fichiers .admx d'un dossier, extension comparee sans tenir compte de la casse
    static [System.IO.FileInfo[]]GetAdmxFiles([string]$FolderPath){
        return @(Get-ChildItem -LiteralPath $FolderPath -File | Where-Object { $_.Extension -eq '.admx' })
    }

    static [void]CheckAndInitiateDependancy(
        [GpoToolsAdmx]$ADMX,
        [cultureinfo]$UICulture
    ){
        $ADMX.Using | Foreach-Object {
            #On verifie si la dependance est deja charge ou si il s'agit de product
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
        # Les namespaces d'un dossier ne sont lus qu'une fois : sans cache, chaque
        # dependance relisait tous les fichiers admx du dossier
        $Index = [GPOToolsUtility]::NamespaceIndex[$FolderPath]
        if ($null -eq $Index){
            $Index = @{}
            foreach ($AdmxFile in [GPOToolsUtility]::GetAdmxFiles($FolderPath)){
                $Ns = [GPOToolsUtility]::GetNamespaceAdmx($AdmxFile)
                if ($null -eq $Index[$Ns]){
                    $Index[$Ns] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
                }
                $Index[$Ns].Add($AdmxFile)
            }
            [GPOToolsUtility]::NamespaceIndex[$FolderPath] = $Index
        }
        $File = if ($null -ne $Index[$namespace]) { $Index[$namespace].ToArray() } else { @() }
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
        [AdmxNamespace]$target
    ){
        return $null -ne [GPOToolsUtility]::FindCategory($Name,$target)
    }

    <# Ajoute une category dans la propriete statique Categories et dans l'index
     par nom utilise pour les recherches (evite de parcourir toute la liste).
     Use :
        [GPOToolsCategory]::Create()
    #>
    static [void]AddCategory(
        [GPOToolsCategory]$Category
    ){
        [GPOToolsUtility]::Categories.Add($Category)
        $List = [GPOToolsUtility]::CategoryIndex[$Category.Name]
        if ($null -eq $List){
            $List = [System.Collections.Generic.List[GPOToolsCategory]]::new()
            [GPOToolsUtility]::CategoryIndex[$Category.Name] = $List
        }
        $List.Add($Category)
    }

    # Retourne les categories chargees portant ce nom (tableau vide si aucune)
    static [GPOToolsCategory[]]FindCategory(
        [string]$Name
    ){
        $List = [GPOToolsUtility]::CategoryIndex[$Name]
        if ($null -eq $List){
            return @()
        }
        return $List.ToArray()
    }

    # Retourne la category chargee correspondant au nom, prefix et namespace ($null si aucune)
    static [GPOToolsCategory]FindCategory(
        [string]$Name,
        [AdmxNamespace]$target
    ){
        foreach ($Cat in [GPOToolsUtility]::FindCategory($Name)){
            if (($Cat.target.prefix -eq $target.prefix) -and ($Cat.target.namespace -eq $target.namespace)){
                return $Cat
            }
        }
        return $null
    }

    <# Surcharge de Methode pour verifier la presence d'une category dans la
     propriete static de la classe GPOToolsUtility. Cette surcharge se base seulement
     sur le nom du prefix et pas sur le namespace. Cela reduit le precision de la
     verification.
     Use :
        [GPOToolsCategory]::Create()
    #>
    static [bool]CheckCategoryPresence(
        [string]$Name,
        [string]$TargetPrefix
    ){
        $return = $false
        $Result = @([GPOToolsUtility]::FindCategory($Name).Where({ $_.target.prefix -eq $TargetPrefix }))
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
                [GPOToolsUtility]::TargetLoad,
                [GPOToolsUtility]::CategoryIndex,
                [GPOToolsUtility]::NamespaceIndex,
                [GPOToolsUtility]::NamespaceByFile
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
        $this.DisplayName = $Adml.GetString($Support.DisplayName)
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
        $this.DisplayName = $Adml.GetString($Cat.DisplayName)
        if ($null -ne $Cat.explainText){
            $this.ExplainText = $Adml.GetString($Cat.ExplainText)
        }

        #Gestion du Parent
        if ($null -ne $Cat.ParentCategory){
            # Si la categorie a un parent dans l'admx on le cherche et on l'ajoute
            $this.ParentCategory = [GPOToolsCategory]::FindParentCategory($Cat,$AllCat,$Adml)
            Write-Verbose ("[GPOToolsCategory] {0} Category have a parent : {1}" -f $Cat.Name,$Cat.ParentCategory.Name)

        }Else{
            # la categorie n'a pas de parent
            Write-Verbose "[GPOToolsCategory] $($Cat.Name) Category doesn't have parent"
        }
    }

    static [GPOToolsCategory]Create(
        [AdmxCategory]$Category,
        [System.Collections.ArrayList]$AllCat,
        [GpoToolsAdml]$Adml
    ){
        # Si la category est presente dans la classe utility on rappel l'objet
        $Existing = [GPOToolsUtility]::FindCategory($Category.Name,$Category.target)
        if ($null -eq $Existing){
            Write-Verbose "[GPOToolsCategory]Loading of $($Category.Name) Category"
            $NewCat = [GpoToolsCategory]::New($Category,$AllCat,$Adml)

            # On ajoute la category au membre statique de la classe GPOToolsUtility
            [GPOToolsUtility]::AddCategory($NewCat)
            return $NewCat
        }Else{
            Write-Verbose "[GPOToolsCategory] $($Category.Name) Category is already load in [GPOToolsUtility]::Categories"
            return $Existing
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
        #Parmi les categories de meme nom que celle recherchee
        $Candidates = [GPOToolsUtility]::FindCategory($Cat.ParentCategory.Name)
        # Le prefix de la reference a ete resolu en namespace : correspondance exacte
        $ParentCat = @($Candidates.Where({ $_.target.namespace -eq $Cat.ParentCategory.namespace }))
        if ($ParentCat.Count -eq 0){
            # Repli quand le namespace n'est pas charge (ex. using vers un fichier absent)
            $ParentCat = @($Candidates.Where({
                    # Si son prefix est similaire a celui de la category parent recherchee
                    $_.target.prefix -eq $Cat.ParentCategory.prefix -or
                    #Ou si la category parent est present dans le meme fichier admx avec
                    #le meme prefix que la category enfant
                    $_.target.prefix -eq $Cat.target.prefix
                }))
        }
        if ($ParentCat.Count -eq 0){
            Write-Verbose "[GPOToolsCategory](FindParentCategory) No ParentCategory found for $($Cat.Name) Name in [GPOToolsUtility]::Categories static property"
            # La category parent peut etre definie plus loin dans le meme fichier admx : on la cree maintenant
            $AdmxParent = @($Categories.Where({
                $_.Name -eq $Cat.ParentCategory.Name -and $Cat.ParentCategory.prefix -eq $Cat.target.prefix
            }))
            if ($AdmxParent.Count -eq 1) {
                return [GPOToolsCategory]::Create($AdmxParent[0],$Categories,$Adml)
            }ElseIf ($AdmxParent.Count -ge 2) {
                Throw "[GPOToolsCategory](FindParentCategory) To many ParentCategory found for $($Cat.Name) in ADMX file"
            }Else{
                Write-Warning ('[GPOToolsCategory](FindParentCategory) No category parent {0} found for {1} category in [GPOToolsUtility]::Categories static property and ADMX file' -f $Cat.ParentCategory.Name,$Cat.Name)
                return $null
            }
        }ElseIf($ParentCat.count -ge 2){
            Throw "[GPOToolsCategory](FindParentCategory) To many ParentCategory found for $($Cat.Name)"
        }Else{
            return $ParentCat[0]
        }
    }

    static [void]LoadAdmxAdml(
        [GpoToolsAdmx]$Admx,
        [GpoToolsAdml]$Adml
    ){
        foreach ($Category in $Admx.Categories){
            $null = [GPOToolsCategory]::Create($Category,$Admx.Categories,$Adml)
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
    # Classe ADMX : User, Machine ou Both. Une policy Both donne un objet par Scope.
    [string]$Class
    [string]$FileName
    # Cle de registre relative a la ruche du Scope (HKLM pour Machine, HKCU pour User)
    [string]$RegistryKey
    [GPOToolsRegistryValue[]]$EnabledValues = @()
    [GPOToolsRegistryValue[]]$DisabledValues = @()
    [GPOToolsPolicyElement[]]$Elements = @()
    # Ordre de presentation ADML : @(@{ RefId; Control; Label }), textes libres compris
    Hidden [object[]]$Layout = @()
    Hidden [GpoToolscategory]$Category
    Hidden [GPOToolsSupportedOn]$SupportedOn

    # Scope deduit de la classe ADMX (Both : User). Prefere le constructeur avec Scope.
    GPOToolsPolicy([AdmxPolicy]$Policy,[GpoToolsAdml]$ADMLPol){
        $DefaultScope = if ($Policy.Class -eq 'Machine') { [ScopePolicy]::Machine } else { [ScopePolicy]::User }
        $this.Init($Policy,$ADMLPol,$DefaultScope)
    }

    GPOToolsPolicy([AdmxPolicy]$Policy,[GpoToolsAdml]$ADMLPol,[ScopePolicy]$Scope){
        $this.Init($Policy,$ADMLPol,$Scope)
    }

    Hidden [void]Init([AdmxPolicy]$Policy,[GpoToolsAdml]$ADMLPol,[ScopePolicy]$Scope){
        $this.ID = $Policy.Name
        $this.Name = $ADMLPol.GetString($Policy.Name)
        $this.DisplayName = $ADMLPol.GetString($Policy.DisplayName)
        $this.Description = $ADMLPol.GetString($Policy.explainText)
        $this.Class = $Policy.Class
        $this.Scope = $Scope
        $this.FileName = [System.IO.Path]::GetFileName($ADMLPol.FilePath) -Replace 'l$','x'
        $this.Category = [GPOToolsPolicy]::FindParentCategory($Policy)
        $this.Path = $this.GeneratePath()

        $this.Registry = [GPOToolsRegistry]::New($Policy,$Scope)
        $this.RegistryKey = $Policy.RegKey
        $this.EnabledValues = $Policy.EnabledValues
        $this.DisabledValues = $Policy.DisabledValues
        $Presentation = $ADMLPol.GetPresentation($Policy.Presentation)
        foreach ($Element in $Policy.Elements){
            $Element.Localize($ADMLPol,$Presentation)
        }
        $this.Elements = $Policy.Elements
        $this.Layout = $ADMLPol.GetPresentationLayout($Policy.Presentation)
    }

    [string]GeneratePath(){
        if($null -ne $this.Category){
            $GNPath = '{0}\{1}' -f $this.Scope,[GPOToolsPolicy]::GeneratePath($this.Category)
        }Else{
            $GNpath = '{0}\' -f $this.Scope
        }
        return $GnPath
    }
    static [string]GeneratePath([GpoToolscategory]$Cat){
        if($null -ne $Cat.ParentCategory){
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
        #Parmi les categories de meme nom que celle recherchee
        $Candidates = [GPOToolsUtility]::FindCategory($Pol.ParentCategory.Name)
        # Le prefix de la reference a ete resolu en namespace : correspondance exacte
        $ParentCat = @($Candidates.Where({ $_.target.namespace -eq $Pol.ParentCategory.namespace }))
        if ($ParentCat.Count -eq 0){
            # Repli quand le namespace n'est pas charge : meme prefix que la reference
            $ParentCat = @($Candidates.Where({ $_.target.prefix -eq $Pol.ParentCategory.prefix }))
        }
        if ($ParentCat.Count -eq 0){
            Write-Warning "[GPOToolsPolicy](FindParentCategory) No ParentCategory found for $($Pol.Name) policy in [GPOToolsUtility]::Categories static property"
            return $null
        }ElseIf($ParentCat.count -ge 2){
            Throw "[GPOToolsPolicy](FindParentCategory) To many ParentCategory found for $($Pol.Name) policy"
        }Else{
            return $ParentCat[0]
        }
    }

    [StatePolicy]GetPolicyState(){
        if (-not (Test-path $This.Registry.Path)){
            $State = [StatePolicy]::NotConfigured
        }Else{
            $RegProperty = Get-ItemProperty $This.Registry.Path  -name $This.Registry.Key -ErrorAction SilentlyContinue
            if($null -eq $RegProperty){
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
    $Value #Active/Desactive
    $DefaultValue

    GPOToolsRegistry([AdmxPolicy]$Pol) {
        $DefaultScope = if ($Pol.Class -eq 'Machine') { [ScopePolicy]::Machine } else { [ScopePolicy]::User }
        $this.Init($Pol,$DefaultScope)
    }

    GPOToolsRegistry([AdmxPolicy]$Pol,[ScopePolicy]$Scope) {
        $this.Init($Pol,$Scope)
    }

    Hidden [void]Init([AdmxPolicy]$Pol,[ScopePolicy]$Scope) {
        if ($Scope -eq [ScopePolicy]::Machine){
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
        $Xml = [GPOToolsUtility]::ReadXml($File.FullName)

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

        # Les prefix des references parentCategory sont des alias locaux au fichier
        # (ex. netcon:NetworkConnections alors que NetworkConnections.admx declare le
        # prefix networkconnections) : on les resout en namespace via using/target.
        $Namespaces = @{ $trgt.prefix = $trgt.namespace }
        foreach ($Ns in $this.Using){
            $Namespaces[$Ns.prefix] = $Ns.namespace
        }
        foreach ($Item in @($this.Categories) + @($this.Policies)){
            if ($null -ne $Item.ParentCategory){
                $Item.ParentCategory.namespace = $Namespaces[$Item.ParentCategory.prefix]
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
    [string]$Presentation
    [GPOToolsRegistryValue[]]$EnabledValues = @()
    [GPOToolsRegistryValue[]]$DisabledValues = @()
    [GPOToolsPolicyElement[]]$Elements = @()

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
        if ($null -ne $policy.ParentCategory.ref){
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
        $this.Presentation = $policy.GetAttribute('presentation') -replace '^\$\(presentation\.(.*)\)$', '$1'

        # Valeurs ecrites a l'activation / desactivation : enabledValue (ou, a defaut,
        # le comportement de l'editeur : DWORD 1 sur valueName) puis enabledList.
        $Enabled = [System.Collections.Generic.List[GPOToolsRegistryValue]]::new()
        $Disabled = [System.Collections.Generic.List[GPOToolsRegistryValue]]::new()
        $Value = [GPOToolsRegistryValue]::FromValueNode($policy['enabledValue'],$this.RegKey,$this.ValueName)
        if ($null -eq $Value -and $this.ValueName){
            $Value = [GPOToolsRegistryValue]::new($this.RegKey,$this.ValueName,[GPOToolsRegistryValueType]::DWord,[uint32]1)
            $Value.Implicit = $true
        }
        if ($null -ne $Value){ $Enabled.Add($Value) }
        # Desactivation sans disabledValue : la valeur est supprimee
        $Value = [GPOToolsRegistryValue]::FromValueNode($policy['disabledValue'],$this.RegKey,$this.ValueName)
        if ($null -eq $Value -and $this.ValueName){
            $Value = [GPOToolsRegistryValue]::new($this.RegKey,$this.ValueName,[GPOToolsRegistryValueType]::Delete,$null)
            $Value.Implicit = $true
        }
        if ($null -ne $Value){ $Disabled.Add($Value) }
        foreach ($Item in [GPOToolsRegistryValue]::FromListNode($policy['enabledList'],$this.RegKey)){ $Enabled.Add($Item) }
        foreach ($Item in [GPOToolsRegistryValue]::FromListNode($policy['disabledList'],$this.RegKey)){ $Disabled.Add($Item) }
        $this.EnabledValues = $Enabled.ToArray()
        $this.DisabledValues = $Disabled.ToArray()

        # Elements saisis par l'administrateur
        if ($null -ne $policy['elements']){
            $PolicyElements = [System.Collections.Generic.List[GPOToolsPolicyElement]]::new()
            foreach ($Node in $policy['elements'].ChildNodes){
                if ($Node.NodeType -eq [System.Xml.XmlNodeType]::Element){
                    $PolicyElements.Add([GPOToolsPolicyElement]::new($Node,$this.RegKey))
                }
            }
            $this.Elements = $PolicyElements.ToArray()
        }
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
        if ($null -ne $Category.parentcategory.ref){
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
        $Xml = [GPOToolsUtility]::ReadXml($File.FullName)

        $This.FilePath = $File.FullName
        $This.BaseName = $File.BaseName
        $this.StringTable = @{}

        Write-Verbose ('Chargement de la table StringTable pour le fichier {0}' -f $File.BaseName)
        foreach ($String in $xml.policyDefinitionResources.resources.stringTable.string){
            $this.StringTable.Add($String.id,$String.'#Text')
        }
        $this.LoadPresentations($Xml)
    }

    # Presentations de l'ADML : id -> (refId -> @{ Control; Label; DefaultValue })
    Hidden [hashtable]$Presentations

    [hashtable]GetPresentation([string]$Id){
        if ([string]::IsNullOrEmpty($Id) -or $null -eq $this.Presentations){
            return $null
        }
        return $this.Presentations[$Id]
    }

    # Ordre d'affichage des presentations : id -> @(@{ RefId; Control; Label }), textes libres compris
    Hidden [hashtable]$PresentationLayouts

    [object[]]GetPresentationLayout([string]$Id){
        if ([string]::IsNullOrEmpty($Id) -or $null -eq $this.PresentationLayouts -or -not $this.PresentationLayouts.ContainsKey($Id)){
            return @()
        }
        return $this.PresentationLayouts[$Id]
    }

    Hidden [void]LoadPresentations([xml]$Xml){
        $this.Presentations = @{}
        $this.PresentationLayouts = @{}
        foreach ($Presentation in $Xml.policyDefinitionResources.resources.presentationTable.presentation){
            $Controls = @{}
            $Layout = [System.Collections.Generic.List[object]]::new()
            foreach ($Node in $Presentation.ChildNodes){
                if ($Node.NodeType -ne [System.Xml.XmlNodeType]::Element){
                    continue
                }
                $RefId = $Node.GetAttribute('refId')
                $Label = if ($null -ne $Node['label']) { $Node['label'].InnerText } else { $Node.InnerText }
                $Layout.Add(@{ RefId = $RefId; Control = $Node.LocalName; Label = "$Label".Trim() })
                if (-not $RefId){
                    continue
                }
                $Default = switch ($Node.LocalName){
                    'checkBox' { [GPOToolsPolicyElement]::GetBool($Node,'defaultChecked',$false) }
                    'dropdownList' { [GPOToolsPolicyElement]::GetAttribute($Node,'defaultItem') }
                    'decimalTextBox' { [GPOToolsPolicyElement]::GetAttribute($Node,'defaultValue') }
                    'longDecimalTextBox' { [GPOToolsPolicyElement]::GetAttribute($Node,'defaultValue') }
                    'textBox' { if ($null -ne $Node['defaultValue']) { $Node['defaultValue'].InnerText } }
                    'comboBox' { if ($null -ne $Node['default']) { $Node['default'].InnerText } }
                    default { $null }
                }
                $Controls[$RefId] = @{
                    Control = $Node.LocalName
                    Label = "$Label".Trim()
                    DefaultValue = $Default
                    # dropdownList : sans noSort="true", l'editeur trie les choix par libelle
                    NoSort = [GPOToolsPolicyElement]::GetBool($Node,'noSort',$false)
                    SpinStep = [GPOToolsPolicyElement]::GetUInt($Node,'spinStep',1)
                }
            }
            $this.Presentations[$Presentation.id] = $Controls
            $this.PresentationLayouts[$Presentation.id] = $Layout.ToArray()
        }
    }

    # Retourne la chaine localisee d'un identifiant ($null si absent).
    # L'indexeur est utilise car l'acces par membre dynamique ($Table."$Id") est
    # environ 200 fois plus lent sur des milliers d'identifiants differents.
    [string]GetString([string]$Id){
        if ([string]::IsNullOrEmpty($Id)){
            return $null
        }
        return $this.StringTable[$Id]
    }
}