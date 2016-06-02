    

 [CmdletBinding(SupportsShouldProcess=$True)]
    Param (

        [parameter(Mandatory=$false, ValueFromPipeline= $true, ParameterSetName='Enable')]
        [ValidateScript({Test-Path $_})]
        [Alias('f', 'file', 'backup')]
        [string] $VcBackupFile,

        [parameter(Mandatory=$false,ParameterSetName='Enable')]
        [ValidateSet(1.20, 2.00)]
        [Alias('v', 'version')]
        [decimal]$ovVersion=2.00,

        [parameter(Mandatory=$false,ParameterSetName='Enable')]
        [Alias('l', 'log')]
        [string]$logDir,

        [parameter(Mandatory=$false,ParameterSetName='Enable')]
        [Alias('t', 'ComeFromTool')]
        [bool]$fromTool,

        [parameter(Mandatory=$false, ValueFromPipeline= $true, ParameterSetName='Enable')]
        [ValidateScript({Test-Path $_})]
        [Alias('u', 'UnCompressedFile', 'UnCompressed')]
        [string] $VcUnCompressed
    )



Begin {



Add-Type -AssemblyName System.xml.Linq

Function Write-Log([string]$contents, [bool]$dateStamp=$true){
	
	#param($contents)
    Write-Verbose $contents
	$logfile = get-childitem env:logfile
    if($dateStamp){$contents=(get-date).tostring() + " -- " + $contents}
	out-file -inputobject $contents -filepath $logfile.value -append -noclobber

}

Function Create-ErrorObject([string]$status, [string]$message, [string] $action, [string] $type ,[string] $source, [string] $sourceType){
    $errObj = New-Object -TypeName PSObject
    $errObj | Add-Member -Name "Status" -MemberType NoteProperty -Value $status
    $errObj | Add-Member -Name "Description" -MemberType NoteProperty -Value $message
    $errObj | Add-Member -Name "Action" -MemberType NoteProperty -Value $action
    $errObj | Add-Member -Name "Type" -MemberType NoteProperty -Value $type
	$errObj | Add-Member -Name "Source" -MemberType NoteProperty -Value $source
	$errObj | Add-Member -Name "SourceType" -MemberType NoteProperty -Value $sourceType
    $errObj
}

Function Expand-Gzip {

[CmdletBinding()]
Param
    (
        # Enter the path to the target GZip file, *.gz
        [Parameter(
        Mandatory = $true,
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter the path to the target GZip file, *.gz",
        ParameterSetName='Default')]             
        [Alias("Fullname")]
        [String]$Path,
        # Specify the type of encoding of the original file, acceptable formats are, "ASCII","Unicode","BigEndianUnicode","Default","UTF32","UTF7","UTF8"
        [Parameter(Mandatory=$false,
        ParameterSetName='Default')]
        [ValidateSet("ASCII","Unicode","BigEndianUnicode","Default","UTF32","UTF7","UTF8")]
        [String]$Encoding = "ASCII"
    )
Begin 
    {
        Set-StrictMode -Version Latest
        Write-Verbose "Create Encoding object"
        $enc= [System.Text.Encoding]::$encoding
    }
Process 
    {
        Write-Debug "Beginning process for file at path: $Path"
        Write-Verbose "test path"
        if (-not ([system.io.path]::IsPathRooted($path)))
          {
            Write-Verbose 'Generating absolute path'
            Try {$path = (Resolve-Path -Path $Path -ErrorAction Stop).Path} catch {throw 'Failed to resolve path'}
            Write-Debug "New Path: $Path"
          } 
        Write-Verbose "Opening file stream for $path"
        $file = New-Object System.IO.FileStream $path, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
        Write-Verbose "Create MemoryStream Object, the MemoryStream will hold the decompressed data until it is loaded into `$array"
        $stream = new-object -TypeName System.IO.MemoryStream
        Write-Verbose "Construct a new [System.IO.GZipStream] object, created in Decompress mode"
        $GZipStream = New-object -TypeName System.IO.Compression.GZipStream -ArgumentList $file, ([System.IO.Compression.CompressionMode]::Decompress)
        Write-Verbose "Open a Buffer that will be used to move the decompressed data from `$GZipStream to `$stream"
        $buffer = New-Object byte[](1024)
        Write-Verbose "Instantiate `$count outside of the Do/While loop"
        $count = 0
        Write-Verbose "Start Do/While loop, this loop will perform the job of reading decopressed data from the gzipstream object into the MemoryStream object.  The Do/While loop continues until `$GZipStream has been emptied of all data, which is when `$count = 0"
        do
            {
                $count = $gzipstream.Read($buffer, 0, 1024)
                if ($count -gt 0)
                    {
                        $Stream.Write($buffer, 0, $count)
                    }
            }
        While ($count -gt 0)
        Write-Verbose "Take the data from the MemoryStream and convert it to a Byte Array"
        $array = $stream.ToArray()
        Write-Verbose "Close the GZipStream object instead of waiting for a garbage collector to perform this function"
        $GZipStream.Close()
        Write-Verbose "Close the MemoryStream object instead of waiting for a garbage collector to perform this function"
        $stream.Close()
        Write-Verbose "Close the FileStream object instead of waiting for a garbage collector to perform this function"
        $file.Close()
        Write-Verbose "Create string(s) from byte array, a split is added after the conversion to ensure each new line character creates a new string"
        $enc.GetString($array).Split("`n")
    }
End {}
}

Function DeGZip-File{
    Param(
        $infile,
        $outfile = ($infile -replace '\.gz$','')
        )

    $input = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $input, ([IO.Compression.CompressionMode]::Decompress)

    $buffer = New-Object byte[](1024)
    while($true){
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $output.Write($buffer, 0, $read)
        }

    $gzipStream.Close()
    $output.Close()
    $input.Close()
}

Function Get-FileName($initialDirectory, $title="Select the VC backup file.", $filter = "All files (*.*)| *.*"){   
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = $filter
    $OpenFileDialog.ShowHelp = $true
    $OpenFileDialog.Title = $title
    $OpenFileDialog.ShowDialog() | out-null
    if(!$OpenFileDialog.FileName){Throw "No file selected or file not found!"}
    else {$OpenFileDialog.filename}

 
} #end function Get-FileName

Function Get-CustomModule($fName, $modName){
    
#Check if module is not currently loaded
if(!(Get-Module | ? {$_.name -eq $modName})){

    #Attempt to load module from modules directories
    try {
        import-module $modName
        $loaded = $true
        }
    catch {
        Write-Log "Module $modName not in PowerShell modules path. Module not loaded."
        $loaded = $false
        }
    if(!$loaded){
        if(!(Get-ChildItem $PSScriptRoot | ? {$_.name -match $fName})){
            Write-Log "$fName not found in current directory."
            Write-Log "Prompting for location of $fName"
            $fName = Get-FileName -initialDirectory $script:sd -title "Select the $modName module file." -filter "psd1 files | *.psd1"
            }
        else{
            $fName = (Get-ChildItem $PSScriptRoot | ? {$_.name -match $fName}).fullname
            }
        if(!$fName){throw "Module not found or nothing selected!"}
        write-debug "FNAME = $fname"
        Write-Log "Loading module $modName"
        try{
            import-module $fName
            }
        catch{
            Write-Log "Error importing custom module $modName"
            $_.Exception; return
            }
        }

    }

}

Function Get-CustomModuleX($fName, $modName){
    
    if(!(Get-Module | ? {$_.name -eq $modName})){
    #Check for module in present directory
        if(!(Get-ChildItem $script:sd | ? {$_.name -match $fName})){
            Write-Log "$fName not found in current directory."
            Write-Log "Prompting for location of $fName"
            $fName = Get-FileName -initialDirectory $script:sd -title "Select the $modName module file." -filter "psd1 files | *.psd1"
            }
        else{
            $fName = (Get-ChildItem $script:sd | ? {$_.name -match $fName}).fullname
            }
        if(!$fName){throw "Module not found or nothing selected!"}
        write-debug "FNAME = $fname"
        Write-Log "Loading module $modName"
        try{
            import-module $fName
            }
        catch{
            Write-Log "Error importing custom module $modName"
            $_.Exception; return
            }
            
    }
} #end function Get-CustomModule

function Get-Config ($theFile) {
    
    #Write-Log "Processing $theFile" $false
    try {
        $fContents = gc $theFile -ErrorAction Stop
    
        $configObj = New-Object -TypeName PSObject
        $domNets = @()

        foreach($line in $fContents){
            if($line.startswith("/EnetNetwork")){
                $thisNet = New-Object -TypeName PSObject
                #write-host "ignoring $line"
                $line = $line.Substring(1)
                $theNet = $line.Substring(0, $line.indexof("="))
                $theRest = $line.Substring($line.indexof("=") + 1)
                $props = $theRest.Split(";")
                
                ForEach($p in $props) {
                    if($p){
                        if(($p.IndexOf("\") -eq -1)) {
                            $thisProp = ($p.split("="))[0]
                            $thisVal = ($p.Split("="))[1]
                            $thisNet | Add-Member -NotePropertyName $thisProp -NotePropertyValue $thisVal
                        }
                        else {
                            $thisProp = $p.Substring(0, $p.IndexOf("="))
                            $theRest = $p.Substring($p.IndexOf("=") + 1)
                            $theRest = $theRest.Replace("\\", ",")
                            $theRest = $theRest.Split("\").Trim()
                            #write-host $theRest
                            #write-host $theRest.count
                            $pObj = New-Object -TypeName PSObject
                            ForEach ($inst in $theRest){
                                if($inst){
                                    #$inst | out-host
                                    $pName = $inst.Split("=")[0]
                                    $pval = $inst.Split("=")[1]
                                    $pObj | Add-Member -NotePropertyName $pName -NotePropertyValue $pval
                                    #$pObj | Out-Host
                                }
                            
                            }
                            $thisNet | Add-Member -NotePropertyName $thisProp -NotePropertyValue $pObj
                            #write-host $thisNet
                        }
                    } 
                }
                $domNets += $thisNet
                #continue
            }
            else {
                $props = $line.Split("=")
                $configObj | Add-Member -MemberType NoteProperty -Name $props[0] -Value $props[1]
            }
        }
        if($domNets) {$configObj | Add-Member -NotePropertyName Networks -NotePropertyValue $domNets}
        
       
                return $configObj
            

    }
    catch {
        write-log "$theFile does not exist" $false
        return
    }
#
    
}

function Get-vcServers ($srvList){
    
    Write-Log "Processing Physical Servers" $false
    $physical = @()
    ForEach($s in $serverList){
    Write-Log "`t$($s.name)"
    [string]$configPath = $s.FullName + "\config.dat"
    $physicalBlade = Get-ServerConfig $configPath
    $configPath = $s.FullName + "\PhysicalServer"
    if (Test-Path $configPath) { #physical server exists, get the properties
        #physical
        $portList = Get-ChildItem $configPath
        $physicalPorts = @()
        Write-Log "`t`tProcessing $($s.name) ports"
        ForEach ($port in $portList){
            Write-Log "`t`t`t$($port.name)"
            #Get the physical port data
            if($port.psIsContainer){
                $thisPort = @{
                            name = $port.Name
                            portInfo = @{}
                            subPorts = @()
                            }
                
                gci $port.FullName -recurse | ForEach-Object -process {
                    if(!$_.psIsContainer){
                        $portObject = Get-Config $_.FullName

                        $portType = ($_.Directory.Name.split("_"))[0]
                        switch ($portType) {
                            "EnetServerPort"{
                                $thisPort.portInfo = $portObject
                                if(!$portObject.model.contains("Flex")){
                                    $script:configErrors += Create-ErrorObject "Critical" "$($portObject.model) in bay $($physicalBlade.Bay) is unsupported" "If possible replace this adapter with a supported model" "Servers and IO modules" "$($physicalBlade.BladeInfo.name)" "Server"
                                    }
                                    #added by Thabet Handle green
                                    else 
                                    {
                                        $script:configErrors += Create-ErrorObject "Green" "$($portObject.model) in bay $($physicalBlade.Bay) is unsupported" "Green" "Servers and IO modules" "$($physicalBlade.BladeInfo.name)" "Server"
                                    }
                                }
                            "FcServerPort"{
                                $thisPort.portInfo = $portObject
                                if(!$portObject.model.contains("8Gb") -and !$portObject.model.contains("16")){
                                    $script:configErrors += Create-ErrorObject "Critical" "$($portObject.model) in bay $($physicalBlade.Bay) is unsupported" "If possible replace this adapter with a supported model" "Servers and IO modules" "$($physicalBlade.BladeInfo.name)" "Server"
                                    }
                                    #added by Thabet Handle green
                                    else 
                                    {
                                        $script:configErrors += Create-ErrorObject "Green" "$($portObject.model) in bay $($physicalBlade.Bay) is unsupported" "Green" "Servers and IO modules" "$($physicalBlade.BladeInfo.name)" "Server"
                                    }
                                }
                            "EnetServerVirtualPort"{
                                $thisPort.subPorts += $portObject}
                            }
                        }
                    
                    }
                $physicalPorts += $thisPort
                }
           
        }
        $physicalBlade | Add-Member -NotePropertyName ports -NotePropertyValue $physicalPorts
        if ($global:MES) { $physicalBlade.Bay = $physicalBlade.GUID.Substring(0, $physicalBlade.GUID.IndexOf(':')+1) + $physicalBlade.Bay }
        #Check server is supported in OneView
             If($aServers -notcontains ($physicalBlade.BladeInfo.name).toLower()){
            If ($physicalBlade.BladeInfo.name -match "Gen9"){
                $script:configErrors += Create-ErrorObject "Warning" "$($physicalBlade.BladeInfo.ProductName),$($physicalBlade.BladeInfo.name),$($physicalBlade.BladeInfo.serverName),$($physicalBlade.BladeInfo.serialNumber),in bay $($physicalBlade.Bay) is not supported for migration with an assigned profile" "Unassign the profile from the server prior to migration." "Servers and IO modules"
            }
            else { 
                $script:configErrors += Create-ErrorObject "Critical" "$($physicalBlade.BladeInfo.ProductName),$($physicalBlade.BladeInfo.name),$($physicalBlade.BladeInfo.serverName),$($physicalBlade.BladeInfo.serialNumber),in bay $($physicalBlade.Bay) is not supported for OneView management" "Remove the server from the enclosure or import the enclosure for monitoring." "Servers and IO modules"
            }
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "$($physicalBlade.BladeInfo.ProductName),$($physicalBlade.BladeInfo.name),$($physicalBlade.BladeInfo.serverName),$($physicalBlade.BladeInfo.serialNumber),in bay $($physicalBlade.Bay) is not supported for OneView management" "Green" "Servers and IO modules"
         }
 
        $physical += $physicalBlade
        } 

    }

    $physical
}

function Get-ServerConfig ($theFile) {
    $xmlPre = '<?xml version="1.0"?>
                <SOAP-ENV:Envelope
                xmlns:SOAP-ENV="http://www.w3.org/2003/05/soap-envelope"
                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
                xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:hpoa="hpoa.xsd">
                <SOAP-ENV:Body>'
    $xmlPost = '</SOAP-ENV:Body></SOAP-ENV:Envelope>'

    $fContents = gc $theFile
    $configObj = New-Object -TypeName PSObject

    foreach($line in $fContents){
        $props = $line.Split("=")
        if($props[0] -eq "BladeInfoString"){break} #Get out of the loop
        $configObj | Add-Member -MemberType NoteProperty -Name $props[0] -Value $props[1]
    }

    #Get the file contents as a raw string
    $strContents = gc $theFile -Raw
    $i = $strContents.IndexOf("BladeInfoString=")

    #Get BladeCNAInfoString and trim it from the main string
    $bladeCNA = $strContents.Substring($strContents.IndexOf("BladeCNAInfoString"))
    $strContents = $strContents.Substring($i, $strContents.IndexOf("BladeCNAInfoString") - $i)
    #$strContents

    #BladePortMapString
    $bladePortMap = $strContents.Substring($strContents.IndexOf("BladePortMapString"))
    $strContents = $strContents.Substring(0, $strContents.IndexOf("BladePortMapString"))

    $bladeCNA = $bladeCNA.Substring($bladeCNA.IndexOf("=")+1)
    [xml]$bladeCNA = $xmlPre + $bladeCNA + $xmlPost
    $configObj | Add-Member -MemberType NoteProperty -Name "BladeCNAInfo" -Value $bladeCNA.Envelope.Body.getBladeCNAInfo

    $bladePortMap = $bladePortMap.Substring($bladePortMap.IndexOf("=")+1)
    [xml]$bladePortMap = $xmlPre + $bladePortMap + $xmlPost
    $configObj | Add-Member -MemberType NoteProperty -Name "BladePortInfo" -Value $bladePortMap.Envelope.Body.bladePortMapwithClpInfo

    $strContents = $strContents.Substring($strContents.IndexOf("=")+1)
    [xml]$strContents = $xmlPre + $strContents + $xmlPost
    $configObj | Add-Member -MemberType NoteProperty -Name "BladeInfo" -Value $strContents.Envelope.Body.bladeInfo
    
    
                return $configObj
            
}

Function Get-ResourceCollection ($directoryList) {
    $resourceObjects = @()
    $directoryList | Get-ChildItem -Recurse | ForEach-Object -process {
    
        if(!$_.psIsContainer){
            #Write-Log "Processing $($_.Directory.Name)"
            $cfgObj = Get-Config $_.FullName
            $resourceObjects += $cfgObj
        }
    }

    $resources = $resourceObjects | ? {$_.name}
    ForEach ($r in $resources){
        $ports = @()
        #get ports
        if($directoryList.name -match "EnetNetwork") {
            $ports += $resourceObjects | ? { $_.NetworkID -match $r.guid -and !$_.name}
            }
        else {
            $ports += $resourceObjects | ? { $_.GUID -match $r.guid -and !$_.name}
            }
        #add the ports to the module object
        $r | Add-Member -NotePropertyName ports -NotePropertyValue $ports
    
    }

   
                return $resources
            
}

function Get-ProfilesConnectionMap {
    
     [CmdletBinding()]
    Param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object]$thisProfile
        )

    $serverConnsMap = @()
    Write-Log "Processing connections for profile $($thisProfile.Name)"

    $sriovCustom = $false
    $sriovAuto = $false
    $sriovDefault = $false
    $sriovDisabled = $false
    [DateTime]$baseDate = "8/27/2014"
    $conns = $thisProfile.ports

    #Check if Gen9 server for boot mode check
    $thisServer = $vcServers | ? {$_.guid -match $thisProfile.ServerBayId} | % {$_.bladeInfo.name}

    #Boot mode set to Auto
    if (($thisServer -match "Gen9") -and ($thisServer.ProfileBootMode -eq 2)) {
        Write-Log "Profile assigned to Gen9 server with AUTO boot mode configured. Enable checks for bootable connections."
        $autoBoot = $true
    } 

    #Boot mode set to UEFI
    if (($thisServer -match "Gen9") -and ($thisServer.ProfileBootMode -eq 1)) {
        Write-Log "Checking ROM Version against minimum for UEFI boot setting."
        [DateTime]$romDate = $thisServer.BladeInfo.romVersion.split(" ")[1]
        Write-Log $romDate
        If ($romDate -le $baseDate) {
            $uefiBootCheck = $true
        }
    } 

    

    #added by Thabet : $IsPassed used to check if it passed all 3 checks or not
    [bool]$IsPassed =$true

    #$serverBay = ($thisProfile.ServerBayId.split(":"))[1].replace("devbay", "")
  
    ForEach ($c in $conns){
        
        #Initialize $IsPassed = true foreach connection 
        $IsPassed=$true
        
        #Bool for Gen9 boot settings
        $bootBios = $true

        #if a FC initiator or FC boot target, ignore main processing
        if($c.GUID -match ":fcic" -or $c.GUID -match ":fcbtc") { Write-Log "Ignoring port $($c.GUID)"}
        else {
            #Get the short name for the connection (ec1, fcoe1, fc1, etc.)
            $cId = $c.GUID.split(":")[1]
            Write-Log "Processing connection $($c.GUID)"
            if(!$c.DownlinkPortId){
                #An unassigned or unmapped connection
                #write the error and continue with the next connection
                $msg = "Profile $($thisProfile.name): Connection $cId is unmapped or unassigned."
                $e = Create-ErrorObject "Warning" $msg "This connection will not be migrated with the profile." "Profiles"
                $script:configErrors += $e

                $IsPassed=$false
                
                }
              
        }
        #
        #Write-Log "$($connectionPort.AdapterLocation)"
        
        #FC, FCoE, or Ethernet port
        if($c.GUID -match ":ec") {
            
            # Get SR-IOV Settings
            if ($vcFw -ge 4.41){
                
                switch ($c.ConnectionSriovType){

                    1 { $sriovCustom = $true }
                    2 { $sriovAuto = $true }
                    3 { $sriovDefault = $true }
                    4 { $sriovDisabled = $true }
            
                }
            }

            #PXE Boot Setting
            Write-Log "Get PXE boot setting on connection."
            if($c.PxeBootSetting -ne 2){
                $bootBios = $false
            }
        }    

        if ($c.GUID -match ":fc") {

            Write-Log "Get FC Boot setting on connection."
            if ($c.BootPriority -ne 4) { 
                $bootBios = $false
            }

            #Is it bootable
            if($c.NumFcBootTargetConfigs -gt 0){
                Write-Log "Fibre Channel connection is bootable. Set boot target configuration."
                #Get boot target information
                $fcbtc = $conns | ? {$_.GUID -match $c.GUID -and $_.GUID -match ":fcbtc"}
            }
                    
            #Get assigned fabric or direct attached SAN
            #if ($c.vFabricId) {
            #    
            #    #Check for dual-hp FCoE connection
            #    $dhFcoe = $VcEnetNetworks | ? {$_.GUID -match $c.vFabricId}
            #    if($dhFcoe){
            #        $msg = "Profile $($thisProfile.name): Connection $cId`: Dual-hop FCoE connection identified"
            #        $e = Create-ErrorObject "Critical" $msg "Remove the FCoE network or import the enclosure for monitoring." "Profiles"
            #        $script:configErrors += $e
            #
            #        $IsPassed=$false
            #        
            #        }
            #        
            #    
            #}
        
       
    } 

        # Check connection speed type is not set to disabled
        if($c.DownlinkPortId -and $c.ConnectionSpeedType -eq 4){
            $msg = "Profile $($thisProfile.name) $($c.ConnectionSpeedType): Connection $cId port speed type is set to disabled."
            $e = Create-ErrorObject "Critical" $msg "Remove or enable the profile connection" "Profiles"
            $script:configErrors += $e

            $IsPassed=$false
        }


        #added by Thabet Handle green in case of it passed all 3 checks above
         If($IsPassed) 
         {
            $msg = "Profile $($thisProfile.name) $($c.ConnectionSpeedType): Connection $cId port speed type is set to disabled."
            $script:configErrors += Create-ErrorObject "Green" $msg "Green" "Profiles"
         }
    
}#End $cConns for loop
    
    #Process SR-IOV
    if ($vcFw -ge 4.41){
        
        if($sriovDefault -and !$sriovCustom -and !$sriovAuto -and !$sriovDisabled){
            #Add Warning
        }

        elseif ($sriovAuto -and $sriovDisabled){
            #Add Warning
        }
        elseif ($sriovAuto -and !$sriovCustom -and !$sriovDefault -and !$sriovDisabled){
            #Good
        }

        elseif ($sriovDisabled -and !$sriovAuto -and !$sriovCustom -and !$sriovDefault){
            #Good
        }
        elseif ($sriovCustom){
            #Add Critical
        }


    }

    #Process Gen9 boot setting
    if ($bootBios = $false) {
        
        if($autoBoot){
            $script:configErrors += Create-ErrorObject "Critical" "Boot mode in profile $($thisProfile.name) is configured as Auto and some connections are not configured to boot BIOS" "Configure all PXE, FC, or FCoE connections to boot from BIOS, or change the boot mode to something other than Auto." "Profiles"
        }

        if($uefiBootCheck) {
            $script:configErrors += Create-ErrorObject "Critical" "ROM version of server with profile $thisProfile.name does not support UEFI boot order management and some connections are not configured to boot BIOS" "Update the server ROM to a version that supports UEFI boot order management. Consult the OneView Support Matrix for supported versions. Alternatively, manage the boot order manually using RBSU (ROM-Based Setup Utility)." "Profiles"
        }
    }

}

Function Confirm-NetSet {

    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object]$netset
        )
    
    write-log "Processing netset on profile $($netset.profile) at port $($netset.portNumber)"
    $err = 0
    #Retrieve all the networks and corresponding vlan ids
    $netVlanPairs = ($netSet.psobject.Properties.Match('NetVlanpair*')).value
    $nsNetNames = @()

    #Loop through the array of pairs for untagged VLANs in the set
    ForEach($pair in $netVlanPairs){
        
        $thisGuid = $pair.split(";")[0]
        $thisVlanId = $pair.split(";")[1]
        #get the enetNetwork object
        $thisNet = $VcEnetNetworks | ? {$_.guid -match $thisGuid}
        $nsNetNames += $thisNet.name

        if($thisNet.ExternalVlanId) {
            if ($thisNet.ExternalVlanId -ne $thisVlanId -and $thisNet.GUID -ne $netSet.UntaggedNet){
                $msg = "$($netset.profile) contains mapped VLAN ids in the connection assignment on port $($netset.port)."
                $err = 1
                #break
                }
            }
        else {
            #Tunneled or untagged network in the collection
            $msg = "$($netset.profile) contains tunneled or untagged networks in the connection assignement on $($netset.port)."
            $err = 1
            #break
            }
    }
    if($err -eq 1){
        #send the netset info to the log
        $script:configErrors += Create-ErrorObject "Critical" "$msg" "Mapped VLAN ids, tunneled, and untagged networks cannot be placed in a OneView network set" "Networks"
        Write-Log "Invalid network set.  Network set information follows."
        Write-Log "GUID = $($netSet.GUID), Networks = $nsNetNames"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" $msg "Green" "Networks"
         }
    
}
    
    # Log file / Output file directory
    if (!$logDir) {
    
        #Check that the script directory is writeable
        if((Get-ChildItem $PSScriptRoot).isreadonly){
            Do{
                "$PSScriptRoot is read only. Please select a destination for the log file." | out-host
                $logDir = Get-Folder "Please select a destination for the log file."
                } while ((Get-ChildItem $logDir).isreadonly)
            }

        else {
            $logDir = $PSScriptRoot
            }
    }

    else {
        if(!(Test-Path $logDir)){
            md $logDir
        }
    }
    $env:logfile = "$logDir\OVfromVCBackup.log"
    
    #Init the log
    ECHO . > $env:logfile
    #HARD CODED BELOW FOR TESTING
    #$workDir = "D:\HP Work\Fusion\OneView-Programming\Migration\FromBackupFile"

    #Get a working directory
    Write-Log "Getting temporary working directory..."
    $workDir = $env:TEMP + "\" + "vcToOv"

    #check if it exists and clear it if so
    if(Test-Path $workDir){
        write-log "$workdir exists... deleting"
        Remove-Item "$workDir\*" -recurse
    }
    else{ md $workDir }

    ########################################################
    ##### Thabet : Exclude PowerShell community extension 
    ########################################################
    if(!$fromTool)
    {
        #Check for required pscx module
        Write-Log "Checking fo pscx module presence..."
        Get-CustomModule "Pscx.psm1" "pscx"
    }

    $allReports = @()
    $allServers = @()
    $aServers = @()
    $aServers += "HP Proliant BL420c Gen8", "Proliant BL420c Gen8"
    $aServers += "HP Proliant BL460c G7", "Proliant BL460c G7" , "HP Proliant BL460c Gen8", "Proliant BL460c Gen8", "Proliant BL460c Gen9"
    $aServers += "HP Proliant BL465c G7", "HP Proliant BL465c Gen8", "Proliant BL465c G7", "Proliant BL465c Gen8"
    $aServers += "HP Proliant BL490c G7", "Proliant BL490c G7"
    $aServers += "HP Proliant BL620c G7", "Proliant BL620c G7"
    $aServers += "HP Proliant BL660c Gen8", "Proliant BL660c Gen8", "Proliant BL660c Gen9"
    $aServers += "HP Proliant BL685c G7", "Proliant BL685c G7"
    $aServers += "HP Proliant WS460c Gen8", "Proliant WS460c Gen8", "HP Proliant WS460c Gen9", "Proliant WS460c Gen9"
    
    #######################################    
    #Thabet
    #In case call come from OVRAT tool , we set the path for uncompressed folder path here
    #######################################
    if( $fromTool)
    {
      $vcDomain= "$VcUnCompressed\VcDomain"
      $workDir=$VcUnCompressed
    }
    #######################################
    #End
    #######################################

    $vcUserDb = "$workDir\UserDb"
    $vcDomain = "$workDir\vcDomain"
    $vcLogical = "$vcDomain\Logical"
    $vcPhysical = "$vcDomain\Physical"
    #$vcPhyEnclosure = "$vcDomain\Physical\EnclosureG1_0"
    $vcEnetNets = "$vcLogical\EnetNetworks"
    $vcFabrics = "$vcLogical\FcFabrics"
    $vcNetmon = "$vcLogical\NetMon"

    $continue = $true
}
# End Begin Processing



Process {

################  BEGIN MAIN SCRIPT
    write-log "Processing $_"
    
    
    #Initialize our object arrays
    $script:configErrors = @()
    $vcProfiles =@()
    $VcEnetNetworks = @()
    $vcEnclosures = @()
    $vcServers = @()
    $enetModules = @()
    $fcModules = @()
    $vcNetSets = @()
    $vcFcNetworks = @()
    $vcUplinkSets = @()
    
    ###################################################
    ##### Thabet : Hide generated html in case you are run script from tool
    ####################################################
    if(!$fromTool)
    {
            ##Start extracting
            Write-Log "Retrieving VC backup file..."
            Write-Log $thabet
            if(!$vcBackupFile){$vcBackupFile = Get-FileName $PSScriptRoot}
            
            # Check if a simple .tar file (should only execute for test/dev situation)
            if($vcBackupFile.EndsWith(".tar")) {
                $continue=$true
                try {Expand-Archive -Path $vcBackupFile -OutputPath $workDir -ShowProgress}
                catch {
                    write-log "$($vcFile.Name) is not a valid archive or is corrupt."
                    #CleanUp
                    if(Test-Path $workDir) {Remove-Item "$workDir\*" -recurse}
                    $continue=$false
                    }
    
            }
            else {
                $continue=$true
                $vcFile = Get-Item $VcBackupFile
                if(!$vcFile.PSIsContainer) {
                    $outFile = $workDir + "\" + $vcFile.Name
                    Write-Log "Extracting VC backup archive $($vcFile.Name)"
            
                    try {
                        if(! $fromTool)
                        {
                            DeGZip-File $vcFile.FullName $outFile
                            $compressedFile = Get-ChildItem $workDir
                            Expand-Archive -Path $compressedFile.FullName -OutputPath $workDir -ShowProgress
                            $compressedFile = Get-ChildItem $workDir | ? {$_.Name -match "tgz" }
                            Expand-Archive -Path $compressedFile.FullName -OutputPath $workDir -ShowProgress
                            $compressedFile = Get-ChildItem $workDir | ? {$_.Name -match "tar" }
                            Expand-Archive -Path $compressedFile.FullName -OutputPath $workDir -ShowProgress
                         }
                 
                      }
                    catch {
                        write-log "$($vcFile.Name) is not a valid archive or is corrupt."
                        #CleanUp
                        Remove-Item "$workDir\*" -recurse
                        $continue=$false
                        }
                    }
                else {
                    Write-Log "Skipping $vcFile directory."
                    $continue=$false
                    }
        
            }
     }
    
    if ($continue) {
        Write-Log "Processing VC backup information..."
        ##### VC Domain settings
        Write-Log "Domain Information"
        $script:vcDomainInfo = Get-Config "$vcDomain\config.dat"
        $script:vMacSetting = gci "$vcDomain\MacAddressPoolMgr" -r | ? {!$_.psIsContainer} | ? {gc $_.pspath | Select-String -pattern "IsSelected=1"}
        $script:vWwnSetting = gci "$vcDomain\WwnAddressPoolMgr" -r | ? {!$_.psIsContainer} | ? {gc $_.pspath | Select-String -pattern "IsSelected=1"}
        $script:vMacSetting = gci "$vcDomain\VsnPoolMgr" -r | ? {!$_.psIsContainer} | ? {gc $_.pspath | Select-String -pattern "IsSelected=1"}
        
        
        
        ################################
         
        # Retrieve configuration objects
        
        ################################
        
        $enclosureList = Get-ChildItem $vcPhysical | ? {$_.name.StartsWith("EnclosureG")}
        if ( $enclosureList.Count -gt 1 ) { $global:MES = $true }
        #$enclosureList | out-host
        ForEach ($enc in $enclosureList) {
            
            ###### Enclosures
            Write-Log "Enclosures"
            $vcEnclosures = Get-Config "$($enc.FullName)\config.dat"
			$vcEnclosureNames+= $vcEnclosures.Name + " ; "
			# Mahmoud Abbas - 13-1-2016 #
			$vcEnclosureSerial +=$vcEnclosures.SerialNumber + " ; "

            ###### Physical Servers
            Write-Log "Physical Servers"
            $serverList = @()
            $serverList = Get-ChildItem $enc.FullName | ? {$_.Name.StartsWith("ServerBay")}
            $vcServers += Get-vcServers $serverList
            # Cleanup
            if($serverList){Remove-Variable serverList}
            if($physicalBlade){Remove-Variable physicalBlade}
            
            ###### Ethernet Modules
            Write-Log "Processing Ethernet modules."
            $emList = Get-ChildItem $enc.FullName | ? {$_.Name.StartsWith("EnetModule")}
            if($emList){$enetModules += Get-ResourceCollection $emList $True}
            Remove-Variable emlist
            
            ###### Fibre Channel Modules
            Write-Log "Processing Fibre Channel modules"
            $fcmList = Get-ChildItem $enc.FullName | ? {$_.Name.StartsWith("FcModule")}
            if($fcmList){$fcModules += Get-ResourceCollection $fcmList $True}
            Remove-Variable fcmList
        
        }

        ###### Ethernet Networks
        Write-Log "Processing Ethernet Networks"
        $eNetFile = $vcLogical + "\EnetNetworks\config.dat"
        $vcEnetSettings = Get-Config $eNetFile
        if($vcEnetSettings.Networks) {$vcEnetNetworks = $vcEnetSettings.Networks}
        else {
            $enetDir = "$vcLogical\EnetNetworks" | Get-ChildItem -Recurse | ? { $_.name -match "EnetNetwork" }
            if($enetDir){$VcEnetNetworks = Get-ResourceCollection $enetDir $True}
            Remove-Variable enetDir
            }
        Remove-Variable eNetFile
        
        
        ###### FcFabrics
        $fcFile = $vcLogical + "\FcFabrics\config.dat"
        $vcFcSettings = Get-Config $fcFile
        
        $fcDir = "$vcLogical\FcFabrics" | Get-ChildItem -Recurse | ? { $_.name -match "Fabric" }
        if($fcDir){$VcFcNetworks = Get-ResourceCollection $fcDir $False}
        Remove-Variable fcFile
        Remove-Variable fcDir
        
        ###### Uplink Sets
        $usDir = "$vcLogical\EnetNetworks" | Get-ChildItem | ? { $_.name -match "UplinkPortSet" }
        if($usDir) {$vcUplinkSets = Get-ResourceCollection $usDir $False}
        #Get the networks for the uplink sets
        ForEach ($us in $vcUplinkSets){
         $nets = $VcEnetNetworks | ? {$_.UplinkPortSetId -eq $us.GUID}
         $us | Add-Member -NotePropertyName networks -NotePropertyValue $nets -force
        }
        
        ###### Profiles
        Write-Log "Processing profiles"
        $profilesDir = $vcLogical | Get-ChildItem | ? {$_.name -match "Profile"}
        if($profilesDir) {
            $vcProfiles = Get-ResourceCollection $profilesDir $True
            $vcProfilesEmpty = $vcProfiles | ? {($_.ServerBayId -notin $vcServers.GUID) -and ($_.ServerBayId)}
            $unassigned = $vcProfiles | ? {!$_.ServerBayId}
            $vcProfiles = $vcProfiles | ? {($_.ServerBayId -in $vcServers.GUID) -and ($_.ServerBayId)}
            }
        Remove-Variable profilesDir
        
        ###### Ethernet network sets from VC profiles
        $nsDir = gci $vcLogical -recurse | ? {$_.name -match "vcNetCollection"}
        if($nsDir){
            ForEach ($ns in $nsDir) {
            
                $thisNs = Get-Config (gci $ns.FullName).FullName
                $profileName = $vcProfiles | ? {$_.ports.vcNetCollectionId -eq $thisNs.GUID} | % {$_.name}
                $profilePort = $vcProfiles.ports | ? {$_.vcNetCollectionId -eq $thisNs.GUID} | % {$_.PortNumber}
                $thisNs | Add-Member -NotePropertyName Profile -NotePropertyValue $profileName
                $thisNs | Add-Member -NotePropertyName PortNumber -NotePropertyValue $profilePort
                $VcNetSets += $thisNs
            }
        Remove-Variable nsDir
        }
        
        #SNMP Configuration
        $vcSnmp = ([xml](gc "$vcLogical\NetMon\config.dat" | ? {$_.contains("vcSnmp=")}).replace("vcSnmp=","")).snmpConfiguration
        
        # VC Features

        #multicast
        $mCast = Get-Config "$vcEnetNets\McastAccessConfig\config.dat"

        #QoS
        $qos = Get-Config "$vcLogical\QosConfig\config.dat"

        #sFlow
        $sFlow = Get-Config "$vcLogical\Sflow\config.dat"

        #Auto-Deployment
        $autoDeploy = Get-Config "$vcLogical\AutoDeployment\config.dat"

        #NAGs
        $netAccessGroups = Get-ResourceCollection "$vcLogical\NetworkAccessGroups"
        ################################
         
        # Compatibility Checks
        
        ################################
        
        # MES
        $numEnclosures = (gci $vcPhysical | ? {$_.name -match "Enclosure"}).count
        if ($numEnclosures -gt 1){
            $script:configErrors += Create-ErrorObject "Critical" "Multi-Enclosure configuration detected" "Consult your HP professional to assist in migrating this domain" "Global settings"
        
            }
         #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "Multi-Enclosure configuration detected" "Green" "Global settings"
         }
        Remove-Variable numEnclosures
        
        # VCEM
        if((Get-Content $vcUserDb\users) -match "Virtual Connect Enterprise Manager"){
            $script:configErrors += Create-ErrorObject "Warning" "Domain is managed by VCEM" "Remove the domain from the VCEM domain group prior to attempting migration" "Global settings"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "Domain is managed by VCEM" "Green" "Global settings"
         }

        # Virtual Connect Firmware
        if($vcDomainInfo.CurrentFwVersion) {$vcFw = $vcDomainInfo.CurrentFwVersion}
        else {$vcFw = $vcDomainInfo.VcmDbVersion}
        
        if($vcFw -lt 410){
            $script:configErrors += Create-ErrorObject "Critical" "Virtual Connect firmware version, $vcFw, is not at the minimum level for OneView migration." "Update the firmware using VCUtil prior to attempting migration" "Global settings"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "Virtual Connect firmware version, $vcFw, is not at the minimum level for OneView migration." "Green" "Global settings"
         }
        
        #if($ovVersion -eq 1.20){
        #
        #    if($vcFw -ge 440){
        #        $script:configErrors += Create-ErrorObject "Critical" "VC firmware is newer than 4.3x" "Insure the firmware is at a supported level for migration into the version of OneView."
        #    }
        #
        #}

        #Servers with missing SN/PN/UUID
        ForEach ($_server in $vcServers) {
            
            if(!($_server.bladeInfo.partNumber)) {$script:configErrors += Create-ErrorObject "Critical" "Unable to retrieve the part number for server in bay $($_server.Bay)." "Check iLO communication or ROM settings" "Servers and IO modules"}
            if(!($_server.bladeInfo.serialNumber)) {$script:configErrors += Create-ErrorObject "Critical" "Unable to retrieve the serial number for server in bay $($_server.Bay)." "Check iLO communication or ROM settings" "Servers and IO modules"}
            if(!($_server.bladeInfo.uuid)) {{$script:configErrors += Create-ErrorObject "Critical" "Unable to retrieve the uuid for server in bay $($_server.Bay)." "Check iLO communication or ROM settings" "Servers and IO modules"}}

        }
        
        #Ethernet Modules
        ForEach ($mod in $enetModules){
            If($mod.name -notmatch "Flex") {$script:configErrors += Create-ErrorObject "Critical" "$($mod.name) at $($mod.GUID) is not supported for management." "Upgrade the interconnect hardware." "Servers and IO modules" "$($mod.name)" "EnetModule"}
            #added by Thabet Handle green
             else 
             {
                $script:configErrors += Create-ErrorObject "Green" "$($mod.name) at $($mod.GUID) is not supported for management." "Green" "Servers and IO modules" "$($mod.name)" "EnetModule"
             }
        }
        #Check for mixture of TAA and non-TAA FlexFabric modules
        if(($enetmodules.partnumber -contains '691367-B21') -and ($enetmodules.partnumber -contains '691367-B22')){
            #Add Warning - "Mixture of TAA and non-TAA modules found in the enclosure."
            }



        #FC Modules
        ForEach ($mod in $fcModules){
           if($mod.name -notmatch "8Gb") {$script:configErrors += Create-ErrorObject "Critical" "$($mod.name) at $($mod.GUID) is not supported for management." "Upgrade the interconnect hardware." "Servers and IO modules" "$($mod.name)" "FCModule"}
            #added by Thabet Handle green
            else 
             {
                $script:configErrors += Create-ErrorObject "Green" "$($mod.name) at $($mod.GUID) is not supported for management." "Green" "Servers and IO modules" "$($mod.name)" "FCModule"
             }
        }

        if($VcEnetNetworks.count -gt 1000) {
            $script:configErrors += Create-ErrorObject "Critical" "$($VcEnetNetworks.count) Ethernet networks found." "Reduce the number of networks to 1000 or less." "Networks"
        }
        #added by Thabet Handle green
        else 
        {
            $script:configErrors += Create-ErrorObject "Green" "$($VcEnetNetworks.count) Ethernet networks found." "Green" "Networks"
        }

        ## Dual-hop FCoE
        #$fcoeNets = $vcUplinkSets | ? {$_.FcoeNetworkId}
        #if ($fcoeNets) {
        #    $fcoeNets | ForEach-Object {$script:ConfigErrors += Create-ErrorObject "Critical" "FCoE network configured on uplink set $($fcoeNets.name)" "" "Networks"}
        #    }
        #    #added by Thabet Handle green
        #    else 
        #    {
        #        $script:ConfigErrors += Create-ErrorObject "Green" "FCoE network configured on uplink set $($fcoeNets.name)" "Green" "Networks"
        #    }
        
        # iSCSI
        $iscsiNets = $vcProfiles | ? {$_.NumIscsiProfileConnections -gt 0}
        If ($iscsiNets) 
        {
            $iscsiNets | ForEach-Object {$script:ConfigErrors += Create-ErrorObject "Critical" "iSCSI connection in profile $($_.name)" "Remove the iSCSI connection before attempting migration" "Profiles"}
        } 
        else 
        {
            $script:ConfigErrors += Create-ErrorObject "Green" "iSCSI connection in profile $($_.name)" "Green" "Profiles"
        }


        # Check for non-migratible profiles
        if($unassigned){
            $unassigned | ForEach-Object {$script:configErrors += Create-ErrorObject -status "Warning" -message "Profile $($_.name) is unassigned." "Profile will not be migrated." "Profiles"}
            #$script:configErrors += Create-ErrorObject -status "Warning" -message "One or more profiles is unassigned and will not be migrated.`r`n$($unassigned.name)"
            }
            else
            {
                $script:configErrors += Create-ErrorObject -status "Green" -message "Profile $($_.name) is unassigned." "Green" "Profiles"
            
            }

        if($vcProfilesEmpty){
            $vcProfilesEmpty | ForEach-Object {$script:configErrors += Create-ErrorObject -status "Warning" -message "Profile $($_.name) is assigned to an empty device bay." "The profile will not be migrated." "Profiles"}
            #$script:configErrors += Create-ErrorObject -status "Warning" -message "One or more profiles is assigned to an empty device bay and will not be migrated.`r`n$($vcProfilesEmpty.name)"
            }
            else
            {
                $script:configErrors += Create-ErrorObject -status "Green" -message "Profile $($_.name) is assigned to an empty device bay." "Green" "Profiles"
            }
        
        # Profile Connections
        Write-Log "$($vcProfiles.count) profiles"
        ForEach($vcp in $vcProfiles) {Get-ProfilesConnectionMap $vcp}

        # Multiple network assignments (Network Sets)
        if($vcNetSets) { ForEach ($vcNs in $vcNetSets) {Confirm-NetSet $vcNs} }
        
        #SNMP
        If($vcSnmp.enableSmis -eq "false") {
            $script:configErrors += Create-ErrorObject "Warning" "SMI-S is disabled" "SMI-S will be enabled after migration" "Global settings"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "SMI-S is disabled" "Green" "Global settings"
         }

        If($vcSnmp.commonTrapDestinationConfiguration -eq "SNMPv3") {
            $script:configErrors += Create-ErrorObject "Critical" "SNMPv3 is enabled" "Disable SNMPv3 before attempting migration." "Global settings"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "SNMPv3 is enabled" "Green" "Global settings"
         }

        #MultiCast
        if($mCast -and ($mCast.NumberOfObjects_EnetMcastFilter -ne 0)){
            $script:configErrors += Create-ErrorObject "Critical" "IGMP multicast filters detected" "Remove/disable IGMP filtering prior to migration." "Global settings"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "IGMP multicast filters detected" "Green" "Global settings"
         }

        ##QoS
        #if($qos -and ($qos.ActiveQosConfigurationType -ne "0")) {
        #    $script:configErrors += Create-ErrorObject "Critical" "QoS configuration enabled" "Disable QoS prior to attempting migration." "Global settings"
        #}
        ##added by Thabet Handle green
        # else 
        # {
        #    $script:configErrors += Create-ErrorObject "Green" "QoS configuration enabled" "Green" "Global settings"
        # }

        #sFlow
        if($sFlow.StateEnabled -and $sFlow.StateEnabled -ne 0) {
            $script:configErrors += Create-ErrorObject "Warning" "SFlow enabled" "Disable SFlow prior to attempting migration." "Global settings"
        }
        #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "SFlow enabled" "Green" "Global settings"
         }

        # Tagged LLDP on downlinks enabled
        if ($vcEnetSettings.TaggedLldp -and ($vcEnetSettings.TaggedLldp -ne 0)) {
            $script:configErrors += Create-ErrorObject "Critical" "Tagged LLDP on downlinks enabled." "Disable this feature prior to attempting migration." "Global settings"
        }
        else 
         {
            $script:configErrors += Create-ErrorObject "Green" "Tagged LLDP on downlinks enabled." "Green" "Global settings"
         }




        #C3000 Enclosures
        if($vcEnclosures.EnclosureType -match "C3000") {
                Write-Log "C3000 Enclosure identified... skipping"
                $script:configErrors = Create-ErrorObject "Critical" "C3000 Enclosures identified." "Domain cannot be migrated." "Global settings"
            }
         #added by Thabet Handle green
         else 
         {
            $script:configErrors += Create-ErrorObject "Green" "C3000 Enclosures identified." "Green" "Global settings"
         }

        "$($vcDomainInfo.name) check complete" | Out-Host
        
        $script:configErrors | select * -unique | Format-Table -AutoSize -Wrap
        $script:configErrors = $script:configErrors | select * -unique
        #Send the report to a file
        $checkFile= "$logDir\$($vcDomainInfo.name).compatibility-check.txt"
        Out-File -InputObject ($script:configErrors | select * -unique | format-list) -FilePath $checkFile -width 120
        
        ###################################################
            ##### Thabet : Hide generated html in case you are run script from tool
            ####################################################
            if(!$fromTool)
            {
                #Cleanup the working directory
                if(Test-Path $workDir){
                    Remove-Item "$workDir\*" -recurse
                }
            }

        Write-Log "Log and compatibility check files saved to $logDir."
        "Log and compatibility check files saved to $logDir." | out-host
        Write-Log "All Done!"
        Write-Log "#####################################################`r`n"
        
        if ($script:configErrors) {
            
            if($script:configErrors.status -contains "Critical"){$status = "Critical"}
            else {$status = "Warning"}
        }
        else {
            $status = "Ready to Migrate"
            $numCritical = 0
            $numWarning = 0
            }

          
                #####  Generating HTML Report
                [psCustomObject]$thisReport = @{
                                Name = $script:vcDomainInfo.name;
                                EnclosureName = $vcEnclosureNames; 
								# Mahmoud Abbas - 13-1-2016 #
								EnclosureSerials = $vcEnclosureSerial  ;                  
                                Status = $status;
								SerialNumber =$vcEnclosures.SerialNumber;
                                Issues = $script:configErrors;
                                File = "$logDir\$($vcDomainInfo.name).report.html";
                                Summary = $null

                            }
        
                        switch ($thisReport.status) {
    
                                "Critical"{
                                    $thisReport.Summary = "<table><tr style=font-size:18px><td>Status:</td><td bgcolor=#DF0101>Blocking conditions exist. VC Domain cannot be migrated..</td></tr></table>"
                                }
                                "Warning"{
                                    $thisReport.Summary = "<table><tr style=font-size:18px><td>Status:</td><td bgcolor=#FFFF00>Warning conditions exist. VC Domain can be migrated.</td></tr></table>"
                                }
                                "Ready to Migrate"{
                                    $thisReport.Summary = "<table><tr style=font-size:18px><td>Status:</td><td bgcolor=#04B404>VC Domain is ready to migrate</td></tr></table>"
                                }
                          }#end of switch

$style = @"
<style>
TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TH {border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color: #6495ED;}
TD {border-width: 1px;padding: 5px;border-style: solid;border-color: black;}
</style>
"@

        $head = "<h1>$($thisReport.name)<br></h1>"
        
        #Thabet : if you run PS from PS itself ,exclude Status column and all green items   
        $body = $thisReport.issues | select Status,Description,Action -unique |where Status –ne "Green" | convertto-html -head $style  | out-string
        $body += "<br>"

         ###################################################
            ##### Thabet : Hide generated html in case you are run script from tool
            ####################################################
            if(!$fromTool)
            {
                $report = Convertto-Html -title "VC migration report" -head $head -body "$($thisReport.Summary) $body"
                $report | out-file $thisReport.File
            

                $allReports += $thisReport            
                $allServers += $vcServers
                #CleanUp
                Remove-Item "$workDir\*" -recurse
            }
            else
            {
              return $thisReport
            }
        return
    }

}

end {

    If ($allReports.count -gt 1){

        $body = $Null
        

        $head = "<h1>VC Migration Summary Report<br></h1>"
        ForEach($r in $allReports){
            $criticalCount = (($r.issues | ? {$_.status -eq "Critical"}) | measure).count
            $warningCount = (($r.issues | ? {$_.status -eq "Warning"}) | measure).count

            $body += "<h1><a href=`"$($r.File)`" target=`"_blank`">$($r.name)</a></h1><br>"
            $body += "$($r.Summary) Blocking Conditions=$criticalCount, Warning Conditions=$warningCount"
        }#end of ForEach

        
         ###################################################
            ##### Thabet : Hide generated html in case you are run script from tool
            ####################################################
            if(!$fromTool)
            {
         
                $endReport = Convertto-Html -title "VC migration report" -head $head -body "$body"
                $endReport | out-file "$logDir\VCMigrationSummary.html"; 
                Invoke-Expression "& `"$logDir\VCMigrationSummary.html`""
            }
            
    } #end of If
#
    else {

    
         ###################################################
            ##### Thabet : Hide generated html in case you are run script from tool
            ####################################################
            if(!$fromTool)
            {

                Invoke-Expression "& `"$($allReports[0].file)`""
            }
    }
    
#
}

