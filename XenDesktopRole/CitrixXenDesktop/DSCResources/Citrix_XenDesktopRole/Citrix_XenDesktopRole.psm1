<#
.SYNOPSIS
	Install the XenDesktop Role on Windows Server.
    The citrixXenDesktopRole provider for Desired State Configuration
    This is designed to install the proper XD software.
    There is a dependency on having the XD Media downloaded which should be handled in the configuration.
.DESCRIPTION
	This script is designed to facilitate setup of XenDesktop as a Gallery Image.
	This version is a prototype / technology preview.
    The assumption is that this is always a Server OS.
    Only one Role is installed per server / machine.
.LEGAL
    Copyright (c) Citrix Systems, Inc. All rights reserved.
 
	SCRIPT PROVIDED "AS IS" WITH NO WARRANTIES OR GUARANTEES OF ANY KIND, INCLUDING BUT NOT LIMITED TO 
	MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  ALL RISKS OF DAMAGE REMAINS WITH THE USER, EVEN IF THE AUTHOR,
	SUPPLIER OR DISTRIBUTOR HAS BEEN ADVISED OF THE POSSIBILITY OF ANY SUCH DAMAGE.  IF YOUR STATE DOES NOT PERMIT THE COMPLETE 
	LIMITATION OF LIABILITY, THEN DELETE THIS FILE SINCE YOU ARE NOW PROHIBITED TO HAVE IT.  TEST ON NON-PRODUCTION SERVERS.
.AUTHOR
	Brian Ehlert, Citrix Labs, Redmond, WA, USA
#>


function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Controller","StoreFront","License","Director","DesktopVDA","SessionVDA")]
		[System.String]
		$XenDesktopRole
	)

    $returnValue = @{}

    # the uninstall registry key must be used due to how the meta installer represents itself in Add/Remove programs
    $regKey = Get-ChildItem -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall |  Where { $_.Name -match "Citrix" }

    # can determine that the metainstaller finished by the registry key, but not what /component were installed.
    if ($regKey) { $returnValue.Add('Ensure', 'Present') } else { $returnValue.Add('Ensure', 'Absent') }

    # Gather all MSI files and note what was installed
    $installedSoftware = Get-WmiObject -Class Win32_Product | where {$_.Vendor -match 'Citrix'}  # XenDesktop Server Setup does not appear here

    foreach ($package in $installedSoftware) {
        $returnValue.Add($package.Name, $package.Version)
    }

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Controller","StoreFront","License","Director","DesktopVDA","SessionVDA")]
		[String]$XenDesktopRole,

		[parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( { Test-Path -Path $_ -PathType Container } )]
		[String]$XenDesktopMediaPath,

		[ValidateSet("Present","Absent")]
		[String]$Ensure
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."

    $logPath = "$env:ProgramData\Citrix\EasyButton\"

    Write-Verbose "The credential executing this script: $env:USERDOMAIN \ $env:USERNAME"
    Write-Verbose "The Role being installed: $XenDesktopRole"
    Write-Verbose "The path to the media:  $XenDesktopMediaPath"

# need to test Present (install) vs Absent (uninstall) prior to beginning

    if ( $Ensure -eq 'Present') {

        # The media can be delivered in a number of ways.  It can be an ISO in a custom resource (SCVMM Service Template), it can be copied by DSC from a pull server (ZIP), it can be attached as a data disk (WAP Gallery Item).
        # Therefore we ask for the path.

        if ((Test-Path -Path ($XenDesktopMediaPath + "\x86\") -PathType Container) -and (Test-Path -Path ($XenDesktopMediaPath + "\x64\") -PathType Container)){
                $xdMediaPath = $XenDesktopMediaPath
        }

        # Format the string properly for the Media Source
        if ($xdMediaPath){
            $xdPath = $xdMediaPath
        }
        elseif ($xdMedia) {
            $xdPath = $xdMedia.DriveLetter + ":"
        }
        else {
            Write-Error -Category ObjectNotFound -Message "No XenDesktop media was found, Citrix products will not be installed" -RecommendedAction "Please verify the DSC configuration is downloading the media or verify the virtual data disk FamilyName, Version, and volume label, or add the ISO to the resource extension package and replace your gallery image" 
            # Return the Ensure as Absent, it cannot be present if we hit this.
            Return
        }

        If(($XenDesktopRole -eq "SessionVDA") -or ($XenDesktopRole -eq "DesktopVDA")){   # The VDA has a unique meta installer
            if ( [System.Environment]::Is64BitOperatingSystem ) {
                $xdSetupPath = $xdPath + "\x64\"
            }
            else { $xdSetupPath = $xdPath + "\x86\" }
            
            # We do not support DSC on Windows XP
            $xdInstall = Get-ChildItem -Path $xdSetupPath -recurse -Filter "XenDesktopVdaSetup.exe"

        }
        Else {   # the Server setup meta installer
            if ( [System.Environment]::Is64BitOperatingSystem ) {
                $xdSetupPath = $xdPath + "\x64\"
            }
            else { $xdSetupPath = $xdPath + "\x86\" }
            
            $xdInstall = Get-ChildItem -Path $xdSetupPath -recurse -Filter "XenDesktopServerSetup.exe"

        }

        If ( $xdInstall ){
            If ($xdInstall.Count -gt 1){  # the VDA creates this case due to a special installer for XP
                foreach ($installExe in $xdInstall){
                    If (Test-Path $installExe.FullName) {
                        If ($installExe.FullName -notmatch "XP") {  # XP is not supported with DSC
                            $FilePath = $installExe.FullName
                        }
                    }
                }
             } 
             elseif ($xdInstall.Count -eq 0) { # media was found, but not the XD media
                Write-Error -Category InvalidData -Message "Media was discovered, but the XenDesktop installer was not located.  Please check the media at $xdMedia.Path"
                Return
             }
             else {
                If (Test-Path $xdInstall.FullName){
                    $FilePath = $xdInstall.FullName
                }
            }
        } else { Write-Verbose "A XenDesktop Server installer was not found" }


        Start-sleep 10   # The OS is still rather busy booting in most cases.

        Switch ($XenDesktopRole){   # The switch means that only one Role option can be installed.

            Controller {
                Write-Verbose "Install the Controller"
                Start-Process -FilePath $FilePath -ArgumentList "/QUIET /NOREBOOT /PASSIVE /verboselog /logpath '$logPath' /configure_firewall /components CONTROLLER,DESKTOPSTUDIO" -Wait -NoNewWindow
                Write-Verbose "XenDesktop Controller install completed"
            }

            StoreFront {
                Write-Verbose "Install the StoreFront"

                Start-Process -FilePath $FilePath -ArgumentList "/verboselog /logpath '$logPath' /configure_firewall /components STOREFRONT /quiet" -Wait -NoNewWindow

                Start-sleep 10
                #IIS Needs time to settle from previous work

                ## This is a second try because every now and then a WIX bug is encountered prior to XD 7.5
                if (!(Get-ItemProperty -Path HKLM:\SOFTWARE\Citrix\DeliveryServicesManagement -Name InstallDir -ErrorAction SilentlyContinue)){
                    Write-Verbose "Didn't install properly, trying again"
                    Write-Verbose "Uninstalling"
                    Get-Date -Format HH:mm:ss
                    Start-Process -FilePath $FilePath -ArgumentList "/remove /verboselog /logpath '$logPath' /configure_firewall /components STOREFRONT /quiet" -Wait -NoNewWindow
                    Start-Sleep 10
                    Write-Verbose "Reinstalling"
                    Get-Date -Format HH:mm:ss
                    Start-Process -FilePath $FilePath -ArgumentList "/verboselog /logpath '$logPath' /configure_firewall /components STOREFRONT /quiet" -Wait -NoNewWindow
                    Start-Sleep 10
                }

                Get-ItemProperty -Path HKLM:\SOFTWARE\Citrix\DeliveryServicesManagement -Name InstallDir
                Write-Verbose "Citrix Receiver StoreFront install completed."

            }

            License {
                Write-Verbose "Install the License server"
                Start-Process -FilePath $FilePath -ArgumentList "/QUIET /verboselog /logpath '$logPath' /configure_firewall /components LICENSESERVER" -Wait -NoNewWindow
                Write-Verbose "Citrix license server install completed"

                # Copy the License File from the Resource Extension.  If this is DSC the download should be part of the configuration.
                $licenseFile = Get-ChildItem -Filter "*.lic" -ErrorAction SilentlyContinue

                try{
                    $licenseFile.CopyTo("${env:ProgramFiles(x86)}\Citrix\Licensing\MyFiles\$licenseFile")
                }
                catch {}

            }

            Director {
                Write-Verbose "Install the Desktop Director"
                Start-Process -FilePath $FilePath -ArgumentList "/verboselog /logpath '$logPath' /configure_firewall /components DESKTOPDIRECTOR /quiet" -Wait -NoNewWindow
                Write-Verbose "XenDesktop Director install completed"

            }

            DesktopVDA {
                Write-Verbose "Install the Desktop VDA"
                
                # Am I running on Server of Client?
                if ( (Get-WmiObject Win32_OperatingSystem).Caption -match "Server" ) {    
                    # Server
                    Start-Process -FilePath $FilePath -ArgumentList "/QUIET /NOREBOOT /PASSIVE /verboselog /logpath '$logPath' /Components VDA,PLUGINS /SERVERVDI /OPTIMIZE /ENABLE_HDX_PORTS /ENABLE_REAL_TIME_TRANSPORT /ENABLE_REMOTE_ASSISTANCE" -Wait -NoNewWindow
                    Write-Verbose "XenDesktop Desktop VDA install completed"
                }
                else {
                    # Client
                    Start-Process -FilePath $FilePath -ArgumentList "/QUIET /NOREBOOT /PASSIVE /verboselog /logpath '$logPath' /Components VDA,PLUGINS /OPTIMIZE /ENABLE_HDX_PORTS /ENABLE_REAL_TIME_TRANSPORT /ENABLE_REMOTE_ASSISTANCE" -Wait -NoNewWindow
                    Write-Verbose "XenDesktop SessionHost VDA install completed"
                }
            }

            SessionVDA {
                Write-Verbose "Install the Session VDA"

                # Assume I am running on Server, if not the caller has a Desktop.
                Start-Process -FilePath $FilePath -ArgumentList "/QUIET /NOREBOOT /PASSIVE /verboselog /logpath '$logPath' /Components VDA,PLUGINS /OPTIMIZE /ENABLE_HDX_PORTS /ENABLE_REAL_TIME_TRANSPORT /ENABLE_REMOTE_ASSISTANCE" -Wait -NoNewWindow
                Write-Verbose "XenDesktop SessionHost VDA install completed"
            }

        }  # close switch


        Start-Sleep 10  # let the OS settle

      	$global:DSCMachineStatus = 1   # I applied a configuration / the meta installer ran and did something, odds are really high I need to reboot.

    } 
    else {  # $Ensure must be 'Absent'
    
        # if installed, uninstall, otherwise do nothing.
        $xdRoleInstalled = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ | where {$_.Name -match "Citrix"}

        if ( $xdRoleInstalled ) {
            $unPath = $xdRoleInstalled.GetValue("ModifyPath")
            Start-Process -FilePath $unPath -ArgumentList "/removeall /quiet /noreboot" -Wait -NoNewWindow
            $global:DSCMachineStatus = 1   #reboot
        } 
        else{
            Write-Verbose "Citrix XenDesktop roles were not found"
            return $xdRoleInstalled
        }
    }
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Controller","StoreFront","License","Director","DesktopVDA","SessionVDA")]
		[String]$XenDesktopRole,

		[String]$XenDesktopMediaPath,

		[ValidateSet("Present","Absent")]
		[String]$Ensure
	)


    $regKey = Get-ChildItem -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall | Where { ($_.GetValue("Publisher") -match "Citrix") }

    # can determine that the metainstaller finished by the registry key, but not what /component were installed.  I can't be any smarter.
    if ($ensure = 'Present'){
        if ($regKey) { $true } else { $false }
    }
    else {
        if ($regKey) { $false } else { $true }
    }
	
}


Export-ModuleMember -Function *-TargetResource


# SIG # Begin signature block
# MIIZVwYJKoZIhvcNAQcCoIIZSDCCGUQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoyaX/Kypgm1sLxRZWqPpgxPn
# v2agghQGMIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
# AQUFADCBizELMAkGA1UEBhMCWkExFTATBgNVBAgTDFdlc3Rlcm4gQ2FwZTEUMBIG
# A1UEBxMLRHVyYmFudmlsbGUxDzANBgNVBAoTBlRoYXd0ZTEdMBsGA1UECxMUVGhh
# d3RlIENlcnRpZmljYXRpb24xHzAdBgNVBAMTFlRoYXd0ZSBUaW1lc3RhbXBpbmcg
# Q0EwHhcNMTIxMjIxMDAwMDAwWhcNMjAxMjMwMjM1OTU5WjBeMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFu
# dGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBALGss0lUS5ccEgrYJXmRIlcqb9y4JsRDc2vCvy5Q
# WvsUwnaOQwElQ7Sh4kX06Ld7w3TMIte0lAAC903tv7S3RCRrzV9FO9FEzkMScxeC
# i2m0K8uZHqxyGyZNcR+xMd37UWECU6aq9UksBXhFpS+JzueZ5/6M4lc/PcaS3Er4
# ezPkeQr78HWIQZz/xQNRmarXbJ+TaYdlKYOFwmAUxMjJOxTawIHwHw103pIiq8r3
# +3R8J+b3Sht/p8OeLa6K6qbmqicWfWH3mHERvOJQoUvlXfrlDqcsn6plINPYlujI
# fKVOSET/GeJEB5IL12iEgF1qeGRFzWBGflTBE3zFefHJwXECAwEAAaOB+jCB9zAd
# BgNVHQ4EFgQUX5r1blzMzHSa1N197z/b7EyALt0wMgYIKwYBBQUHAQEEJjAkMCIG
# CCsGAQUFBzABhhZodHRwOi8vb2NzcC50aGF3dGUuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC50aGF3dGUuY29tL1Ro
# YXd0ZVRpbWVzdGFtcGluZ0NBLmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCAQYwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0y
# MDQ4LTEwDQYJKoZIhvcNAQEFBQADgYEAAwmbj3nvf1kwqu9otfrjCR27T4IGXTdf
# plKfFo3qHJIJRG71betYfDDo+WmNI3MLEm9Hqa45EfgqsZuwGsOO61mWAK3ODE2y
# 0DGmCFwqevzieh1XTKhlGOl5QGIllm7HxzdqgyEIjkHq3dlXPx13SYcqFgZepjhq
# IhKjURmDfrYwggSjMIIDi6ADAgECAhAOz/Q4yP6/NW4E2GqYGxpQMA0GCSqGSIb3
# DQEBBQUAMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBD
# QSAtIEcyMB4XDTEyMTAxODAwMDAwMFoXDTIwMTIyOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTQwMgYDVQQDEytT
# eW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIFNpZ25lciAtIEc0MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAomMLOUS4uyOnREm7Dv+h8GEKU5Ow
# mNutLA9KxW7/hjxTVQ8VzgQ/K/2plpbZvmF5C1vJTIZ25eBDSyKV7sIrQ8Gf2Gi0
# jkBP7oU4uRHFI/JkWPAVMm9OV6GuiKQC1yoezUvh3WPVF4kyW7BemVqonShQDhfu
# ltthO0VRHc8SVguSR/yrrvZmPUescHLnkudfzRC5xINklBm9JYDh6NIipdC6Anqh
# d5NbZcPuF3S8QYYq3AhMjJKMkS2ed0QfaNaodHfbDlsyi1aLM73ZY8hJnTrFxeoz
# C9Lxoxv0i77Zs1eLO94Ep3oisiSuLsdwxb5OgyYI+wu9qU+ZCOEQKHKqzQIDAQAB
# o4IBVzCCAVMwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwcwYIKwYBBQUHAQEEZzBlMCoGCCsGAQUFBzABhh5odHRw
# Oi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wNwYIKwYBBQUHMAKGK2h0dHA6Ly90
# cy1haWEud3Muc3ltYW50ZWMuY29tL3Rzcy1jYS1nMi5jZXIwPAYDVR0fBDUwMzAx
# oC+gLYYraHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5jb20vdHNzLWNhLWcyLmNy
# bDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMjAdBgNV
# HQ4EFgQURsZpow5KFB7VTNpSYxc/Xja8DeYwHwYDVR0jBBgwFoAUX5r1blzMzHSa
# 1N197z/b7EyALt0wDQYJKoZIhvcNAQEFBQADggEBAHg7tJEqAEzwj2IwN3ijhCcH
# bxiy3iXcoNSUA6qGTiWfmkADHN3O43nLIWgG2rYytG2/9CwmYzPkSWRtDebDZw73
# BaQ1bHyJFsbpst+y6d0gxnEPzZV03LZc3r03H0N45ni1zSgEIKOq8UvEiCmRDoDR
# EfzdXHZuT14ORUZBbg2w6jiasTraCXEQ/Bx5tIB7rGn0/Zy2DBYr8X9bCT2bW+IW
# yhOBbQAuOA2oKY8s4bL0WqkBrxWcLC9JG9siu8P+eJRRw4axgohd8D20UaF5Mysu
# e7ncIAkTcetqGVvP6KUwVyyJST+5z3/Jvz4iaGNTmr1pdKzFHTx/kuDDvBzYBHUw
# ggVbMIIEQ6ADAgECAhBZKu9UZuRZKU4BOkjfD0g6MA0GCSqGSIb3DQEBBQUAMIG0
# MQswCQYDVQQGEwJVUzEXMBUGA1UEChMOVmVyaVNpZ24sIEluYy4xHzAdBgNVBAsT
# FlZlcmlTaWduIFRydXN0IE5ldHdvcmsxOzA5BgNVBAsTMlRlcm1zIG9mIHVzZSBh
# dCBodHRwczovL3d3dy52ZXJpc2lnbi5jb20vcnBhIChjKTEwMS4wLAYDVQQDEyVW
# ZXJpU2lnbiBDbGFzcyAzIENvZGUgU2lnbmluZyAyMDEwIENBMB4XDTE0MDcyNDAw
# MDAwMFoXDTE1MDkxNTIzNTk1OVowgYwxCzAJBgNVBAYTAlVTMRAwDgYDVQQIEwdG
# bG9yaWRhMRgwFgYDVQQHEw9Gb3J0IExhdWRlcmRhbGUxHTAbBgNVBAoUFENpdHJp
# eCBTeXN0ZW1zLCBJbmMuMRMwEQYDVQQLFApQb3dlclNoZWxsMR0wGwYDVQQDFBRD
# aXRyaXggU3lzdGVtcywgSW5jLjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAJdE2UnYZRRIwMKq8jivnq5ZSHHTN4bbuXURARHgEYeCnqqGXLwEiu2EqbG5
# GcWhDkPdoyuoRR1TOQDDAxn9Es0dmcSpySCgqr2EjlwdIiTEB91x0upUDuLrAgsY
# 9KcsqxFGB8hZiK3i4VzloaiJfxgL59y4GaVgnjZ8ZM7N52A5eHX5vK7YQtNsxVN/
# s2Yn308BtQe1bDmSo7NaxLtrPrva9933cYTDYmi4KKJ8qXvqZ6mjUBcDNcjpSJ7N
# BvUXIK7Q5g7tUNlLg4PRuvgGFjXfx/41bufwqaneF7I7r9aPKBY/9GGEzz4+lEVh
# Dw206sF/nbbv80X+JrEydXDVYi8CAwEAAaOCAY0wggGJMAkGA1UdEwQCMAAwDgYD
# VR0PAQH/BAQDAgeAMCsGA1UdHwQkMCIwIKAeoByGGmh0dHA6Ly9zZi5zeW1jYi5j
# b20vc2YuY3JsMGYGA1UdIARfMF0wWwYLYIZIAYb4RQEHFwMwTDAjBggrBgEFBQcC
# ARYXaHR0cHM6Ly9kLnN5bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGRYXaHR0cHM6
# Ly9kLnN5bWNiLmNvbS9ycGEwEwYDVR0lBAwwCgYIKwYBBQUHAwMwVwYIKwYBBQUH
# AQEESzBJMB8GCCsGAQUFBzABhhNodHRwOi8vc2Yuc3ltY2QuY29tMCYGCCsGAQUF
# BzAChhpodHRwOi8vc2Yuc3ltY2IuY29tL3NmLmNydDAfBgNVHSMEGDAWgBTPmanq
# eyb0S8mOj9fwBSbv49KnnTAdBgNVHQ4EFgQUY2hVDhNISSu2X+tH8+1CUYnxnMEw
# EQYJYIZIAYb4QgEBBAQDAgQQMBYGCisGAQQBgjcCARsECDAGAQEAAQH/MA0GCSqG
# SIb3DQEBBQUAA4IBAQAkEEcP/T+8Lo4uMgEtZlGbgzwynjip4miCHfhlImbna4lR
# T+h3vLzJPh7cRGhgtUAKPU4WQ+VnaPEfLAe6gYxFm8bbp9ws2LtDeuN/wQPFeMpW
# dbMyLH7fGdZIqPz/KE9A4+Gk+EmJhsAyfpfy/dSCrBkjTNRfDZyBK9IST8e3MXH4
# q8JVRQUWy7D0+hudTG++7CIyu5fYSgsWqo8WzlKF2pKn25PFxWkzuTnI1+2X7Kxs
# 4+EaaJxwXUMVPZa4mCxz0OKZWLczqNOhEmELFhKHMb5R59WFbW9bt4Sl3e2sqHWS
# q/5L0rv7KSx2eksR7dXxYsvY81GMVVIQPGWA49HwMIIGCjCCBPKgAwIBAgIQUgDl
# qiVW/BqG7ZbJ1EszxzANBgkqhkiG9w0BAQUFADCByjELMAkGA1UEBhMCVVMxFzAV
# BgNVBAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBO
# ZXR3b3JrMTowOAYDVQQLEzEoYykgMjAwNiBWZXJpU2lnbiwgSW5jLiAtIEZvciBh
# dXRob3JpemVkIHVzZSBvbmx5MUUwQwYDVQQDEzxWZXJpU2lnbiBDbGFzcyAzIFB1
# YmxpYyBQcmltYXJ5IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IC0gRzUwHhcNMTAw
# MjA4MDAwMDAwWhcNMjAwMjA3MjM1OTU5WjCBtDELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDlZlcmlTaWduLCBJbmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3
# b3JrMTswOQYDVQQLEzJUZXJtcyBvZiB1c2UgYXQgaHR0cHM6Ly93d3cudmVyaXNp
# Z24uY29tL3JwYSAoYykxMDEuMCwGA1UEAxMlVmVyaVNpZ24gQ2xhc3MgMyBDb2Rl
# IFNpZ25pbmcgMjAxMCBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
# APUjS16l14q7MunUV/fv5Mcmfq0ZmP6onX2U9jZrENd1gTB/BGh/yyt1Hs0dCIzf
# aZSnN6Oce4DgmeHuN01fzjsU7obU0PUnNbwlCzinjGOdF6MIpauw+81qYoJM1SHa
# G9nx44Q7iipPhVuQAU/Jp3YQfycDfL6ufn3B3fkFvBtInGnnwKQ8PEEAPt+W5cXk
# lHHWVQHHACZKQDy1oSapDKdtgI6QJXvPvz8c6y+W+uWHd8a1VrJ6O1QwUxvfYjT/
# HtH0WpMoheVMF05+W/2kk5l/383vpHXv7xX2R+f4GXLYLjQaprSnTH69u08MPVfx
# MNamNo7WgHbXGS6lzX40LYkCAwEAAaOCAf4wggH6MBIGA1UdEwEB/wQIMAYBAf8C
# AQAwcAYDVR0gBGkwZzBlBgtghkgBhvhFAQcXAzBWMCgGCCsGAQUFBwIBFhxodHRw
# czovL3d3dy52ZXJpc2lnbi5jb20vY3BzMCoGCCsGAQUFBwICMB4aHGh0dHBzOi8v
# d3d3LnZlcmlzaWduLmNvbS9ycGEwDgYDVR0PAQH/BAQDAgEGMG0GCCsGAQUFBwEM
# BGEwX6FdoFswWTBXMFUWCWltYWdlL2dpZjAhMB8wBwYFKw4DAhoEFI/l0xqGrI2O
# a8PPgGrUSBgsexkuMCUWI2h0dHA6Ly9sb2dvLnZlcmlzaWduLmNvbS92c2xvZ28u
# Z2lmMDQGA1UdHwQtMCswKaAnoCWGI2h0dHA6Ly9jcmwudmVyaXNpZ24uY29tL3Bj
# YTMtZzUuY3JsMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AudmVyaXNpZ24uY29tMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDAzAo
# BgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVmVyaVNpZ25NUEtJLTItODAdBgNVHQ4E
# FgQUz5mp6nsm9EvJjo/X8AUm7+PSp50wHwYDVR0jBBgwFoAUf9Nlp8Ld7LvwMAnz
# Qzn6Aq8zMTMwDQYJKoZIhvcNAQEFBQADggEBAFYi5jSkxGHLSLkBrVaoZA/ZjJHE
# u8wM5a16oCJ/30c4Si1s0X9xGnzscKmx8E/kDwxT+hVe/nSYSSSFgSYckRRHsExj
# jLuhNNTGRegNhSZzA9CpjGRt3HGS5kUFYBVZUTn8WBRr/tSk7XlrCAxBcuc3IgYJ
# viPpP0SaHulhncyxkFz8PdKNrEI9ZTbUtD1AKI+bEM8jJsxLIMuQH12MTDTKPNjl
# N9ZvpSC9NOsm2a4N58Wa96G0IZEzb4boWLslfHQOWP51G2M/zjF8m48blp7FU3aE
# W5ytkfqs7ZO6XcghU8KCU2OvEg1QhxEbPVRSloosnD2SGgiaBS7Hk6VIkdMxggS7
# MIIEtwIBATCByTCBtDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDlZlcmlTaWduLCBJ
# bmMuMR8wHQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTswOQYDVQQLEzJU
# ZXJtcyBvZiB1c2UgYXQgaHR0cHM6Ly93d3cudmVyaXNpZ24uY29tL3JwYSAoYykx
# MDEuMCwGA1UEAxMlVmVyaVNpZ24gQ2xhc3MgMyBDb2RlIFNpZ25pbmcgMjAxMCBD
# QQIQWSrvVGbkWSlOATpI3w9IOjAJBgUrDgMCGgUAoIG4MBkGCSqGSIb3DQEJAzEM
# BgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqG
# SIb3DQEJBDEWBBTa6XKTVr30Qy5FgZmfsLdFoOQN1DBYBgorBgEEAYI3AgEMMUow
# SKAqgCgAQwBpAHQAcgBpAHgAIABTAHkAcwB0AGUAbQBzACwAIABJAG4AYwAuoRqA
# GC1pIGh0dHA6Ly93d3cuY2l0cml4LmNvbTANBgkqhkiG9w0BAQEFAASCAQBdg8U2
# mgMrIDmeogmPTV9lfqMK7zF+0Klr3Wb89WKBxPiIhFx+g+7FFmplEgXimVGYHjVS
# WL8nGpZDlmXCXFeidr2WgItirgP5Nh/QcuDWtEtkjVqLMjOZ/FA8caij+lmKAtuQ
# EQXjQaOAJjBRoUA0oPEz+xUlfTEfiwYWSfywDks998DBFkWqRIn7bVDU3LZhEJ2x
# Z6tnPo/FxY7CcwORh1Vb5r22e07wXrT82Xum1fy6iP1Z/R7ekAone5qvt0umLXkm
# saW0zhch5Q6D5MCXB1hchBLkigBFFHZSJvjIh1Xkcmh0yxnZClKmKIoNH3kFjpk4
# eGCgy7uDl0phZRphoYICCzCCAgcGCSqGSIb3DQEJBjGCAfgwggH0AgEBMHIwXjEL
# MAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTAwLgYD
# VQQDEydTeW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIENBIC0gRzICEA7P
# 9DjI/r81bgTYapgbGlAwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJAzELBgkqhkiG
# 9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE0MDgyMDIyNDQwOVowIwYJKoZIhvcNAQkE
# MRYEFLgv0MN5l/xCMBHIrGmrdjTKuUCwMA0GCSqGSIb3DQEBAQUABIIBAEWDUtBM
# +YF6veqStHLZRC578uQBl43aAcqMSMtf1oEs2jfNTcOfrwk8kCT8AscK0rkK0Ox0
# HJukgwnlGeiRM3i++GmEWHhOuYrgkoduKKo1w1PKPJWTwo8hUquxnOF3P5pTJGuY
# rCj01CVYVOjupKP/SyCx/zCw8w0+5+hZigj50UOS5e7HlbtpcBFmcWFrUxikjeQE
# +BJLkdXgjJtisNkty7gVjTT5q+SThGMycwAJdt1ASfvoMwCz53or8Iq9LBLbbBmm
# 2dNxnlOwbr5JJjk0gDu7Ycu5qkvJVJm1e/TOokTNiiHYC78LPO9jFIFmSjijmPQr
# jgfDFjBEKgD4dGg=
# SIG # End signature block
