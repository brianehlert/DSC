<#
.SYNOPSIS
	Install the XenDesktop Role on Windows Server.
    The media is downloaded into the VM using the Azure Custom Script extension, similar to as it would for a ResExt package.
.DESCRIPTION
	This script is designed to facilitate setup of XenDesktop as a Gallery Image.
	This version is a prototype / technology preview.
    The assumption is that this is always a Server OS.
    Only one Role is installed per server / machine.
    This does not include configuration but could be extended to.
.LEGAL
    Copyright (c) Citrix Systems, Inc. All rights reserved.
 
	SCRIPT PROVIDED "AS IS" WITH NO WARRANTIES OR GUARANTEES OF ANY KIND, INCLUDING BUT NOT LIMITED TO 
	MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  ALL RISKS OF DAMAGE REMAINS WITH THE USER, EVEN IF THE AUTHOR,
	SUPPLIER OR DISTRIBUTOR HAS BEEN ADVISED OF THE POSSIBILITY OF ANY SUCH DAMAGE.  IF YOUR STATE DOES NOT PERMIT THE COMPLETE 
	LIMITATION OF LIABILITY, THEN DELETE THIS FILE SINCE YOU ARE NOW PROHIBITED TO HAVE IT.  TEST ON NON-PRODUCTION SERVERS.
.AUTHOR
	Brian Ehlert, Citrix Labs, Redmond, WA, USA
#>

# Azure Account Set-up
Import-Module -Name Azure

Switch-AzureMode -Name AzureServiceManagement

(Get-AzureSubscription).SubscriptionName
Set-AzureSubscription -SubscriptionName "Your Cool Subscription"

(Get-AzureStorageAccount).StorageAccountName
Set-AzureStorageAccount -StorageAccountName "Your excellent storage account"

# Upload the XenDesktop media
$xdMedia = Get-Item -Path D:\Foo\XenDesktop75.zip
Set-AzureStorageBlobContent -Verbose -Force -Container "your media container" -File $xdMedia.FullName -Blob $xdMedia.Name

$container = Get-AzureStorageContainer -Name "your media container"
$mediaUri = ($container.CloudBlobContainer.Uri.AbsoluteUri) + "/" + ($xdMedia.Name)

# Define the configuration

# Upload the configuration
Publish-AzureVMDscConfiguration -ConfigurationPath D:\Foo\XenDesktopInAzure.ps1 -Verbose -Force

### Define the VM
# the most recent Server 2012 R2 Image
$img = Get-AzureVMImage `
     | where { $_.PublisherName -match 'Microsoft' -and $_.ImageFamily -match '2012 R2 Datacenter' } `
     | Sort-Object -Property PublishedDate -Descending `
     | select -First 1

$Vm = New-AzureVMConfig -Name "VM Name" -InstanceSize Small -ImageName $img.ImageName

$Vm = Add-AzureProvisioningConfig -VM $Vm `
                        -Windows `
                        -AdminUsername 'some local username' `
                        -Password 'super secure password'

$Vm = Set-AzureVMDSCExtension -VM $Vm `
                        -ConfigurationArchive "XenDesktopInAzure.ps1.zip" `
                        -ConfigurationName "xdServerRole" `
                        -ConfigurationArgument @{ mediaUri = $mediaUri; xdRoleType = "Controller" } `
                        -Force


# Create the VM
New-AzureVM -Location 'some datacenter' -VM $Vm -ServiceName 'your Azure service'


### applying a new configuration
# configurations are not 'undone' only added to.
$newVm = Get-AzureVM -ServiceName 'your Azure service' -Name "VM Name"

$newVm = Set-AzureVMDSCExtension -VM $newVm `
                        -ConfigurationArchive "XenDesktopInAzure.ps1.zip" `
                        -ConfigurationName "xdServerRole" `
                        -ConfigurationArgument @{ mediaUri = "$mediaUri"; xdRoleType = "Director" } `
                        -Force

Get-AzureVMDscExtension -VM $newVM

$newVm | Update-AzureVM


