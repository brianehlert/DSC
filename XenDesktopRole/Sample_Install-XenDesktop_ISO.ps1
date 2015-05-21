<#
.SYNOPSIS
	Install the XenDesktop Role on Windows Server.
    The media should be delivered to the machine in the same path as this script.
    This would work with the Azure Script extension, or Windows Azure Pack, or SCVMM Service Template.
    This mounts an ISO that is in the machine file system.
.DESCRIPTION
	This version is a prototype / technology preview.
    The assumption is that this is always a Server OS.
    Only one Role is installed per server / machine.
    This does not include configuration.
.LEGAL
    Copyright (c) Citrix Systems, Inc. All rights reserved.
 
	SCRIPT PROVIDED "AS IS" WITH NO WARRANTIES OR GUARANTEES OF ANY KIND, INCLUDING BUT NOT LIMITED TO 
	MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  ALL RISKS OF DAMAGE REMAINS WITH THE USER, EVEN IF THE AUTHOR,
	SUPPLIER OR DISTRIBUTOR HAS BEEN ADVISED OF THE POSSIBILITY OF ANY SUCH DAMAGE.  IF YOUR STATE DOES NOT PERMIT THE COMPLETE 
	LIMITATION OF LIABILITY, THEN DELETE THIS FILE SINCE YOU ARE NOW PROHIBITED TO HAVE IT.  TEST ON NON-PRODUCTION SERVERS.
.PARAMETERS
    $XDRole = the XenDesktop Server role that will be installed
.AUTHOR
	Brian Ehlert, Citrix Labs, Redmond, WA, USA
#>

Param
(
    [parameter(Mandatory = $true)] # No default, this must be declared.
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Controller","StoreFront","License","Director","DesktopVDA","SessionVDA", ignorecase=$true)]
    [String]$XDRole,

    [parameter(Mandatory = $true)]
    [ValidateScript( { Test-Path -Path $_ } )]
	[String]$XDIso
)

$iso = ( Get-Item -Path $XDIso ).FullName

$diskImage = Mount-DiskImage -ImagePath $iso -PassThru

$xdMedia = (Get-Volume -DiskImage $diskImage ).DriveLetter + ':\'

Configuration xdServerRole
{
    
    Param (
        [string]$xdRole,
        [string]$iso,
        [string]$xdMedia
    )

    Import-DscResource -Module CitrixXenDesktop

    Node localhost
    {

        # set the LocalConfigurationManager properly
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }


        # Install XenDesktop Role
        Citrix_XenDesktopRole xdRole
        {
            Ensure = "Present"
            XenDesktopRole = $xdRole
            XenDesktopMediaPath = $xdMedia
        }

        # Dismount the ISO when installation is complete
        Script xdIsoDismount
        {
            SetScript = { Dismount-DiskImage -ImagePath $using:iso }
            TestScript = { try { if ( (Get-DiskImage -ImagePath $using:iso).Attached ) { $false } } catch { $true } }
            GetScript = { 
                $returnValue = @{
                    Ensure = if (((Get-DiskImage -ImagePath $using:iso).Attached)) {'Present'} else {'Absent'}
                }
                $returnValue
            }
            DependsOn = "[Citrix_XenDesktopRole]xdRole"
        }

    }  # close of Node
}  # close of configuration




# compile the configuration into a MOF format
xdServerRole -xdRole $XDRole -iso $iso -xdMedia $xdMedia

# set the meta.mof to support DSC handling the rebooting
Set-DscLocalConfigurationManager -Path .\xdServerRole -ComputerName localhost -Verbose

# Run the configuration on localhost
Start-DscConfiguration -Path .\xdServerRole -ComputerName localhost -Force -Verbose -wait


