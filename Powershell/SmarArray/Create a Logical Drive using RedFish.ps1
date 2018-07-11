#IP address of OneView
$IP = "192.168.1.110" 

# OneView Credentials
$username = "Administrator" 
$password = "password" 

# Import the OneView 4.00 library

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -Confirm:$false 


Function MyImport-Module {
    
    # Import a module that can be imported
    # If it cannot, the module is installed
    # When -update parameter is used, the module is updated 
    # to the latest version available on the PowerShell library
    
    param ( 
        $module, 
        [switch]$update 
           )
   
   if (get-module $module -ListAvailable)

        {
        if ($update.IsPresent) 
            {
            # Updates the module to the latest version
            [string]$Moduleinstalled = (Get-Module -Name $module).version
            [string]$ModuleonRepo = (Find-Module -Name $module -ErrorAction SilentlyContinue).version

            $Compare = Compare-Object $Moduleinstalled $ModuleonRepo -IncludeEqual

            If (-not $Compare.SideIndicator -eq '==')
                {
                Update-Module -Name $module -Confirm -Force | Out-Null
           
                }
            Else
                {
                Write-host "You are using the latest version of $module" 
                }
            }
            
        Import-module $module
            
        }

    Else

        {
        Write-Warning "$Module is not present"
        Write-host "`nInstalling $Module ..." 

        Try
            {
                If ( !(get-PSRepository).name -eq "PSGallery" )
                {Register-PSRepository -Default}
                Install-Module –Name $module -Scope CurrentUser –Force -ErrorAction Stop | Out-Null
            }
        Catch
            {
                Write-Warning "$Module cannot be installed" 
                $error[0] | FL * -force
            }
        }

}

#MyImport-Module PowerShellGet
#MyImport-Module FormatPX
#MyImport-Module SnippetPX
MyImport-Module HPOneview.400 #-update
#MyImport-Module PoshRSJob
MyImport-Module hpeRedFishcmdlets -update

# Connection to the Synergy Composer

If ($connectedSessions -and ($connectedSessions | ? {$_.name -eq $IP})) {
    Write-Verbose "Already connected to $IP."
}

Else {
    Try {
        Connect-HPOVMgmt -appliance $IP -UserName $username -Password $password | Out-Null
    }
    Catch {
        throw $_
    }
}




import-HPOVSSLCertificate -ApplianceConnection ($connectedSessions | ? {$_.name -eq $IP})




$sh = Get-HPOVServer | ? model -match Gen10

"Server Hardware: {0}" -f $sh.name

$iloSession = $sh | Get-HPOVIloSso -IloRestSession
$iloSession.RootUri = $iloSession.RootUri.Replace("rest", "redfish")


# Get smartstorageconfig settings
$uri = "/redfish/v1/Systems/1/SmartStorage/"

$data = Get-HPERedfishDataRaw -Odataid $uri -Session $iloSession  -DisableCertificateAuthentication

# Get ArrayControllers
$uri = $data.Links.ArrayControllers.'@odata.id'
$ctrls = Get-HPERedfishDataRaw -Odataid $uri -Session $iloSession -DisableCertificateAuthentication


foreach ($ctrl in $ctrls.members) {
	$my_ctrl = Get-HPERedfishDataRaw -Odataid $ctrl.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
	"model: {0}, Location: {1}, Health: {2}, State: {3}" -f $my_ctrl.Model, $my_ctrl.Location, $my_ctrl.Status.Health, $my_ctrl.Status.State | Write-Host -ForegroundColor Yellow
	"`tEncryptionEnabled={0}, EncryptionStandaloneModeEnabled={1}, EncryptionCryptoOfficerPasswordSet={2}, EncryptionMixedVolumesEnabled={3}" -f $my_ctrl.EncryptionEnabled, $my_ctrl.EncryptionStandaloneModeEnabled, $my_ctrl.EncryptionCryptoOfficerPasswordSet, $my_ctrl.EncryptionMixedVolumesEnabled | Write-Host -ForegroundColor Green
	# Get Physical Drives
	$pDrives = Get-HPERedfishDataRaw -Odataid $my_ctrl.Links.PhysicalDrives.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
	"`t{0} Physical Drive(s) attached to controller" -f $pDrives.'Members@odata.count' | Write-Host
	foreach ($pDrive in $pDrives.members) {
		$my_pDrive = Get-HPERedfishDataRaw -Odataid $pDrive.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
		"`t`tId={0}, Location={1}, Model={2}, Type={3}, CapacityGB={4}, EncryptedDrive={5}" -f $my_pDrive.Id, $my_pDrive.Location, $my_pDrive.Model, ("{0}{1}" -f $my_pDrive.InterfaceType, $my_pDrive.MediaType), $my_pDrive.CapacityGB, $my_pDrive.EncryptedDrive | Write-Host
	}
	
	# Get Logical Drives
	$lDrives = Get-HPERedfishDataRaw -Odataid $my_ctrl.Links.LogicalDrives.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
	"`t{0} Logical Drive(s) configured on controller" -f $lDrives.'Members@odata.count' | Write-Host
	
    foreach ($lDrive in $lDrives.members) {
		$my_lDrive = Get-HPERedfishDataRaw -Odataid $lDrive.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
		"`t`tId={0}, RAID={1}, CapacityMiB={2}, LogicalDriveEncryption={3}, Health={4}, State={5}" -f $my_lDrive.Id, $my_lDrive.Raid, $my_lDrive.CapacityMiB, $my_lDrive.LogicalDriveEncryption, $my_lDrive.CapacityMiB, $my_lDrive.Status.Health, $my_lDrive.Status.State 
		$dataDrives = Get-HPERedfishDataRaw -Odataid $my_lDrive.Links.DataDrives.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
		foreach ($dataDrive in $dataDrives.members) {
			$my_dataDrive = Get-HPERedfishDataRaw -Odataid $dataDrive.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
			"`t`t`tId={0}, Location={1}, Model={2}, Type={3}, CapacityGB={4}, EncryptedDrive={5}" -f $my_dataDrive.Id, $my_dataDrive.Location, $my_dataDrive.Model, ("{0}{1}" -f $my_dataDrive.InterfaceType, $my_dataDrive.MediaType), $my_dataDrive.CapacityGB, $my_dataDrive.EncryptedDrive | Write-Host
		}
	}
	
}
#>

$nb = 1
foreach ($pDrive in $pDrives.members) {
			
            $my_dataDrive = Get-HPERedfishDataRaw -Odataid $pDrive.'@odata.id' -Session $iloSession -DisableCertificateAuthentication
		    
            New-variable -Name "dataDrive$nb" -Value $my_dataDrive.Location -Force
            # Creation of a logical drive using the following disk:
            #Get-variable -Name "dataDrive$nb" -ValueOnly
            $nb++

}

# $dataDrive1
# $datadrive2
# etc

$settings=@{
	"LogicalDrives"=@(
	 	@{
			"Raid"="Raid1"
			"DataDrives"=@("$dataDrive1","$dataDrive2")
            "LogicalDriveName"= "LD_RAID1-2DISKS"
                
		}
	 )
    
    "DataGuard" = "Disabled"
}


<#
Sample of the body content to create a RAID1 logical drive using 2 Drives

$settings=@{
	"LogicalDrives"=@(
	 	@{
			"Raid"="Raid1"
			"DataDrives"=@("3I:1:1","3I:1:2")
            "LogicalDriveName"= "LD_RAID1-2DISKS"
                
		}
	 )
    
    "DataGuard" = "Disabled"
}
#>


# $settings | Convertto-Json -d 99



# Edit smartstorageconfig settings

$uri = "/redfish/v1/systems/1/smartstorageconfig/settings/"

$return = Edit-HPERedfishData -Odataid $uri -Setting $settings -Session $iloSession -ErrorAction Stop -DisableCertificateAuthentication

$message = $return.error.'@Message.ExtendedInfo'.MessageId

Write-host "$message" -f Green

