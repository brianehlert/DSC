<#
.SYNOPSIS
	Install the XenDesktop Role on Windows Server.
    The media can be delivered in any way, a folder is expected.
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
    $XDMediaPath = the path to the XenDesktop media.  This can be a mounted ISO, attached DVD (i.e. "D:\"), an unzipped archive ( "C:\unzippath\media" ) or other source.
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
    [ValidateScript( { Test-Path -Path $_ -PathType Container } )]
	[String]$XDMediaPath
)


Configuration xdServerRole
{

    Param (
        [string]$XDRole,
        [string]$XDMediaPath
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
            XenDesktopRole = $XDRole
            XenDesktopMediaPath = $XDMediaPath
        }

    }  # close of Node
}  # close of configuration



# compile the configuration into a MOF format
xdServerRole -XDRole "License" -XDMediaPath "D:\"

# set the meta.mof to support DSC handling the rebooting
Set-DscLocalConfigurationManager -Path .\xdServerRole -ComputerName localhost -Verbose

# Run the configuration on localhost
Start-DscConfiguration -Path .\xdServerRole -ComputerName localhost -Force -Verbose -Wait

