Installing XenDesktop using Desired State Configuration
The XenDesktop resource provider for Windows Desired State Configuration allows Citrix customers, Service Providers, and any compatible third party tool to create consistent and repeatable installation of XenDesktop roles.
Desired State Configuration is a base for an easily automated and repeatable deployment process that is consistent regardless of where XenDesktop sits (e.g. public, private, hybrid clouds).
The resource provider uses Desired State Configuration instead of a custom agent to support XenDesktop installation across multiple management platforms.
How it works
Desired State Configuration is an engine that can apply and enforce configurations of software packages through either a push or pull model.
The resource provider for XenDesktop can install any single XenDesktop role to a target machine.  The XenDesktop resource provider supports presentation of the installation media by many methods including ZIP archive, ISO, or data disk; allowing great flexibility in machine deployment.
XenDesktop resource provider requirements
The use of the Desired State Configuration resource provider for XenDesktop depends on the following:
* Server 2012 R2 (or PowerShell v4 with Server 2012 or Server 2008 R2)
* XenDesktop media delivered to the target machine (zip, ISO, DVD, data disk, folder)
o Only XenDesktop 7.5 or later is supported.
* XenDesktop resource provider 
o Must be in the PowerShell for auto-load such as: $env:ProgramFiles\WindowsPowerShell\Modules
o This is required to both create and apply a configuration.

Usage and Examples
Enabling the XenDesktop resource provider
This can be accomplished through a number of different means.  The following example demonstrates manually applying a configuration using a sample script.
Sample
A simple configuration that can be performed at the console of a machine is:
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


In this example the following parameters are defined as:
$XDRole = the XenDesktop Server role that will be installed.  "Controller","StoreFront","License","Director","DesktopVDA","SessionVDA" 
$XDMediaPath = the path to the XenDesktop media.  This can be a mounted ISO, attached DVD (i.e. "D:\"), an unzipped archive ( "C:\unzippath\media" ) or other source.
Additionally
There are a number of useful tools and references that have been created by Microsoft in support of the Desired State Configuration feature.
If problems are encountered the diagnostics module and its Trace-xDscOperation and Get-xDscOperation commands are highly useful in identifying most issues and errors.  http://blogs.msdn.com/b/powershell/archive/2014/02/11/dsc-diagnostics-module-analyze-dsc-logs-instantly-now.aspx
Page 2





Page 1


