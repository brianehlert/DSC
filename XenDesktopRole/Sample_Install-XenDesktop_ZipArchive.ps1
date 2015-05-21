<#
.SYNOPSIS
	Install the XenDesktop Role on Windows Server.
    The media should be delivered to the machine in the same path as this script.
    This would work with the Azure Script extension, or Windows Azure Pack, or SCVMM Service Template.
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
	[String]$XDZip
)

$zip = ( Get-Item -Path $XDZip ).FullName

Configuration xdServerRole
{

    Param (
        [string]$xdRole,
        [string]$zip
    )

    Import-DscResource -Module CitrixXenDesktop

    Node localhost
    {
        # set the LocalConfigurationManager properly
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        # unzip known archive name that is in the same path as this script.
        Archive xdMediaUnzip
        {
            Ensure = "Present"
            Path = $zip
            Destination = "$PWD\XenDesktop"
        }

        # Install XenDesktop Role
        Citrix_XenDesktopRole xdRole
        {
            Ensure = "Present"
            XenDesktopRole = $XDRole
            XenDesktopMediaPath = "$PWD\XenDesktop"
            DependsOn = "[Archive]xdMediaUnzip"
        }

    }  # close of Node
}  # close of configuration




# compile the configuration into a MOF format
xdServerRole -xdRole $XDRole -zip $zip

# set the meta.mof to support DSC handling the rebooting
Set-DscLocalConfigurationManager -Path .\xdServerRole -ComputerName localhost -Verbose

# Run the configuration on localhost
Start-DscConfiguration -Path .\xdServerRole -ComputerName localhost -Force -Verbose -Wait

