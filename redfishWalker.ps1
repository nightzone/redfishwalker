<#

redfishWalker - walks through Redfish OIDs tree and collects data to JSON files

Developed by Sergii Oleshchenko

#>

param([String]$ipaddress,[String]$user,[String]$password,[String]$walkProfile="default.profile")

$scriptVersion = "v1.0 PS"

$product = ""
$vendor = ""
[Boolean]$askProfile = $false

$header = @{}
$header.Add("Content-Type","application/json")
$header.Add("Accept-Language", "en_US")

# Save Progress Preference and set it to silent
$oldProgressPreference = $progressPreference
$progressPreference = 'SilentlyContinue'

Write-Host "`nredfishWalker" $scriptVersion "- walks through Redfish OIDs`n"

# read params
if (!($ipaddress))
{
    $ipaddress = Read-Host "Enter IP address"
    $askProfile = $true
}
if (!($user))
{
    $user = Read-Host "Enter Username"
    $askProfile = $true
}
if (!($password))
{
  #  $password = Read-Host -AsSecureString "Enter Password"
    [SecureString]$password = Read-Host -AsSecureString "Enter Password"
    $decryptPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
    [string]$password = $decryptPassword
    $askProfile = $true
}
if (!($walkProfile) -or $askProfile)
{
    $walkProfile = Read-Host "Enter Profile to use [default.profile]"
    if (!($walkProfile))
    {
        $walkProfile = "default.profile"
    }
}

# write params
Write-Host
Write-Host "IP address:" $ipaddress
Write-Host "Username:  " $user
Write-Host "Profile:   " $walkProfile


# create class to handle SSL errors
$code = @"
public class SSLHandler
{
    public static System.Net.Security.RemoteCertificateValidationCallback GetSSLHandler()
    {
       return new System.Net.Security.RemoteCertificateValidationCallback((sender, certificate, chain, policyErrors) => { return true; });
    }

}
"@

#compile the class
if (-not ([System.Management.Automation.PSTypeName]'SSLHandler').Type)
{
    Add-Type -TypeDefinition $code
}

# added for JavaScript serialized object
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")

# to support zipping
Add-Type -AssemblyName System.IO.Compression.FileSystem

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()

# Check if Redfish API exists on the host
function Check_Redfish_Connection([String]$ipaddress)
{
    $uri = "https://" + $ipaddress + "/redfish/v1/"
    
    $product = ""
    $vendor = ""

    Write-Host "`nConnectivity check......" $ipaddress "...... " -NoNewline

    try
    {
        $respWeb = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -Headers $header -TimeoutSec 5 
        $resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($respWeb)

        if ($resp.ContainsKey("Product"))
        {
            $product = $resp.Product
            $vendor = $resp.Vendor
            Write-Host "Pass."
            Write-Host "Product:" $product
            Write-Host "Vendor: " $vendor
            return $true, $product, $vendor
        }
    }
    catch
    {
        Write-Host "Fail."
        Write-Host "Error ocurred:"
        Write-Host $_
        return $false, $product, $vendor
    }
}


# Authenticate to host and return SessionKey and Location
function Create_Session([String]$IPaddress, [String]$Login, [String]$Password)
{
  $uri = "https://" + $IPaddress + "/redfish/v1/SessionService/Sessions/"
  $sessionKey = ""
  $location = ""

  Write-Host "`nTrying to log on as" $Login "..."

  $body = [Ordered]@{
       "UserName"        = $Login
       "Password"        = $Password
       }

  $bodyJSON = ConvertTo-Json $body

  try
  {
    #disable SSL checks using new class
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()
    $respWeb = Invoke-WebRequest -Uri $uri -Method POST -Headers $header -Body $bodyJSON -UseBasicParsing -TimeoutSec 5
    $headers = $respWeb.Headers
    $sessionKey = $headers."X-Auth-Token"
    $location = $headers.Location
    Write-Host "Logged on successfully."
  }
  catch
  {
    Write-Host "`nLogin failed.`nPlease check credentials."
    Write-Host "Error ocurred:"
    Write-Host $_
  }
  finally
  {
    #enable ssl checks again
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
  }

  return $sessionKey, $location
}

# Create Directory and return Status True - created or exist, False - fails to create
function Create_Dir([String]$Path)
{
    try
    {
	    if(!(Test-Path $Path))
	    {
		    New-Item $Path -ItemType Directory | Out-Null
	    }
    }
    catch
    {
        Write-Host "Cannot create directory:`n" $Path
        Write-Host "Error:"
        Write-Host $_
        return $false
    }
    return $true
}

# Read hardware profile from json file
function Read_Profile_JSON([String]$ProfileName)
{
    $profilePath = Join-Path $PSScriptRoot "profiles" | Join-Path -ChildPath $ProfileName

    try
    {
	    if((Test-Path $profilePath) -and ($profilePath.endswith(".json")) )
	    {
		    $content = Get-Content -Path $profilePath
            $profileObj = $content | ConvertFrom-Json
            return $profileObj
	    }
        else
        {
            Write-Host "System profile" $ProfileName "not found in folder 'profiles'." 
            return $null
        }
    }
    catch
    {
        Write-Host 
        Write-Host "Cannot read profile:`n" $profilePath
        Write-Host "Error:"
        Write-Host $_
        return $null
    }
}

# Read hardware profile from a file
function Read_Profile_Param([String]$ProfileName)
{
    $profilePath = Join-Path $PSScriptRoot "profiles" | Join-Path -ChildPath $ProfileName

    $profileObj = [System.Collections.IDictionary]@{
       scan = @()
       tree = @()
       once = @()
       exclude = @()
    }

    try
    {
	    if((Test-Path $profilePath) -and ($profilePath.endswith(".profile")) )
	    {
		    $content = Get-Content -Path $profilePath
            $section = ""
            foreach ($line in $content)
            {
                if ( ($line -match '^\[.+\]$') -and $line.SubString(1,$line.length-2) -in $profileObj.keys) 
                {
                    $section = $line.SubString(1,$line.length-2)
                    continue
                }
                if ($section -and ($line.length -gt 3) )
                {
                    $profileObj.$section += $line
                }
            }
            return [PSCustomObject]$profileObj
	    }
        else
        {
            Write-Host "System profile" $ProfileName "not found in folder 'profiles'." 
            return $null
        }
    }
    catch
    {
        Write-Host 
        Write-Host "Cannot read profile:`n" $profilePath
        Write-Host "Error:"
        Write-Host $_
        return $null
    }
}

# Read profile if  .profile or .json
function Read_Profile([String]$ProfileName)
{
    if ($ProfileName.endswith(".profile"))
    {
        return Read_Profile_Param -ProfileName $ProfileName
    }
    elseif ($ProfileName.endswith(".json"))
    {
        return Read_Profile_JSON -ProfileName $ProfileName
    }
    else
    {
        Write-Host
        Write-Host "Wrong file extension: .profile or .json supported"
        return $null
    }
}


# check if redfish resource uri contains exlude values
function Check_If_Exclude([String]$redfishResource,[Array]$excludeList)
{
    try
    {
        foreach ($item in $excludeList)
        {
            if ($redfishResource.Contains($item.ToLower()))
            {
                return $true 
            }
        }
    }
    catch
    {
        Write-Host "Cannot check exclude list.`nError:"
        Write-Host $_
        return $false
    }
    return $false
}

# If $Scan is True it gets all found resources
# If $Scan is False it gets only Tree from given resource
# If $Once is True it gets resource and exit
function Get_Redfish_Resource([String]$IPaddress,[String]$Resource,[String]$SessionKey,[String]$OutputDir,[Boolean]$Scan=$true,[Boolean]$Once=$false)
{

    # check if "/" at the end of uri and add if not
    $Resource = $Resource.ToLower()
    if (!$Resource.EndsWith("/"))
    {
        $Resource = $Resource + "/"
    }

    $uri = "https://" + $IPaddress + $Resource
    $filename = "index.json"

    $path = Join-Path $OutputDir $Resource
    $filepath = $path | Join-Path -ChildPath $filename 

    # Get Data if index.json does not exist
    if (!(Test-Path -Path $filePath ))
    {
        try
        {
            Write-Host $Resource
            # get Uri
            $respWeb = Invoke-WebRequest -Uri $uri -Method Get -Headers $header -UseBasicParsing -TimeoutSec 5
            $resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($respWeb)           
            # convert to json
            $jsonResp = $resp | ConvertTo-Json -Depth 99

            # Create or check if Dir exist
            if (Create_Dir -Path $path)
            {    
                # Save json file UTF-8
                [IO.File]::WriteAllLines($filepath, $jsonResp)

                if ($Once) 
                {
                    return $null
                }
                Redfish_Walk -jsonObj $resp -IPaddress $IPaddress -Resource $Resource -OutputDir $OutputDir -Scan $Scan
            }
        }
        catch
        {    
            Write-Host "Error while getting uri:"
            Write-Host $_
            return $null
        }    
    }
    else
    {
        return $null
    }
}

function Redfish_Walk($jsonObj,[String]$IPaddress,[String]$Resource,[String]$SessionKey,[String]$OutputDir,[Boolean]$Scan=$true)
{
    if ($jsonObj -is [System.Collections.IDictionary])
    {
        foreach($key in $jsonObj.Keys)
        {            
            if($jsonObj.$key -is [System.Collections.IDictionary])
            {
                Redfish_Walk -jsonObj $jsonObj.$key -IPaddress $IPaddress -Resource $Resource -OutputDir $OutputDir -Scan $Scan
            }
            elseif($jsonObj.$key -is [Array])
            {
                Redfish_Walk -jsonObj $jsonObj.$key -IPaddress $IPaddress -Resource $Resource -OutputDir $OutputDir -Scan $Scan
            }            
            elseif( ($key -eq "@odata.id") -or ($key -eq "Uri") -or ($key -eq "href") -or ($key -eq "Members@odata.nextLink") -or ($key -eq "@Redfish.ActionInfo") )  
            {
                $nextResource = $jsonObj.$key.ToLower()

                # check if goes only in tree or exclude next resource
                if (!($Scan) -and !($nextResource.contains("$Resource")) -or (Check_If_Exclude -redfishResource $nextResource -excludeList $profileObj.exclude ) )
                {
                   continue
                }
                if( ($nextResource -ne $Resource) -and !($nextResource.contains("#")) -and ($nextResource.StartsWith("/redfish"))  )  #-and ($nextResource.contains("$Resource"))
                {
                    Get_Redfish_Resource -IPaddress $IPaddress -Resource $jsonObj.$key -OutputDir $OutputDir -Scan $Scan
                }
            }
        }
    }
    elseif($jsonObj -is [Array])
    {
        foreach($item in $jsonObj)
        {
            if (($item -is [System.Collections.IDictionary]) -or ($item -is [Array]))
            {
                 Redfish_Walk -jsonObj $item -IPaddress $IPaddress -Resource $Resource -OutputDir $OutputDir -Scan $Scan
            }
        }

    }
}

$if_connect, $product, $vendor = Check_Redfish_Connection -ipaddress $ipaddress
$sessionKey = ""

if ($if_connect)
{
    $sessionKey, $location = Create_Session -IPaddress $ipaddress -Login $user -Password $password
    $header.Add("X-Auth-Token", $sessionKey)
}

if ($sessionKey)
{

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()

    $resource = "/redfish/v1/"

	# Create Temporary Output Directory
	$scriptDir = $PSScriptRoot
	$currentTime = Get-Date -Format "yyyyMMddHHmmss".toString()
	$outputDir = Join-Path $scriptDir ("output" + $currentTime)

	if(!(Test-Path ($outputDir))){
			New-Item $outputDir -ItemType Directory | Out-Null
	}
	else {
		Remove-Item -Path $outputDir -Recurse
		New-Item $outputDir -ItemType Directory | Out-Null
	}

    # Read profile and create profile object
    $profileObj = Read_Profile -ProfileName $walkProfile

    Write-Host "`nLets walk...`n"

    # Scan all resources
    foreach ($item in $profileObj.scan)
    {
        Get_Redfish_Resource -IPaddress $ipaddress -Resource $item -OutputDir $outputDir
    }

    # Scan only specific branch
    foreach ($item in $profileObj.tree)
    {
        Get_Redfish_Resource -IPaddress $ipaddress -Resource $item -OutputDir $outputDir -Scan $false
    }

    # Get specific URI only
    foreach ($item in $profileObj.once)
    {
        Get_Redfish_Resource -IPaddress $ipaddress -Resource $item -OutputDir $outputDir -Once $true
    }

    # Close session
    $respWeb = Invoke-WebRequest -Uri $location -Method Delete -Headers $header -UseBasicParsing 

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null

    # Create and write info.txt
	$scriptMeta = [pscustomobject]@{
		description =  'Redfish OIDs collection'
		application = 'redfishWalker'
		version = $scriptVersion
		system = $ipaddress
        product = $product
		vendor =  $vendor
		timestamp = Get-Date -Format "yyyy-MM-dd hh:mm:ss".ToString()
    }

    $scriptMetaJSON = $scriptMeta | ConvertTo-Json -Depth 99 
    # Save meta file UTF-8
    $scriptMetaFilePath = Join-Path $outputDir "info.txt"
    [IO.File]::WriteAllLines($scriptMetaFilePath, $scriptMetaJSON)

		if(Test-Path $outputDir){
                    $filePrefix = "output"
					$currentTime = Get-Date -Format "yyyyMMdd.HHmmss".toString()
					$archiveName = $filePrefix + "-" + $ipaddress + "-" + $currentTime + ".zip"
					$archivePath = Join-Path $scriptDir $archiveName

                    if(Test-Path $archivePath){
	                     Remove-Item -Path $archivePath
                    }
                    try
                    {
                        Invoke-Command -ScriptBlock {[System.IO.Compression.ZipFile]::CreateFromDirectory($outputDir, $archivePath)} | Wait-Job
                        Remove-Item -Path $outputDir -Recurse
                        Write-Host "`nOutput saved to:"
                        Write-Host "Path: " $scriptDir
                        Write-Host "File: " $archiveName
                    }
                    catch
                    {
                        Write-Host "`nCannot create .zip archive"
                        Write-Host "Configuration located in folder:" $scriptDir.Split("\")[-1]
                    }
                    finally
                    {
                        # Set progress Preference back
                        $progressPreference = $oldProgressPreference

                        #cleanup variables
                        $ipaddress = ""
                        $user = ""
                        $password = ""
                        $walkProfile = ""

                    }

		}
		else {
			# Folder cannot be removed
		}

}