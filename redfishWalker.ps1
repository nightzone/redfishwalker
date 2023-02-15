
$_ip = "10.72.14.119"

$_uri = "https://" + $_ip + "/redfish/v1"

$_header = @{}
$_header.Add("Content-Type","application/json")
$_header.Add("Accept-Language", "en_US")

# create class to handle SSL errors
$_code = @"
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
    Add-Type -TypeDefinition $_code
}

# added for JavaScript serialized object
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()

# Check if Redfish API exists on the host
function Check_Redfish_Connection([String]$IPaddress)
{
    $_uri = "https://" + $ipaddress + "/redfish/v1"
    
    Write-Host "`nConnectivity check......" $ipaddress "...... " -NoNewline

    try
    {
        $_respWeb = Invoke-WebRequest -Uri $_uri -Method Get -Headers $_header -UseBasicParsing 
        $_resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($_respWeb)

        if ($_resp.ContainsKey("Product"))
        {
            Write-Host "Pass."
            Write-Host "Product:" $_resp.Product
            Write-Host "Vendor: " $_resp.Vendor
            return $true
        }
    }
    catch
    {
        Write-Host "Fail."
        Write-Host "Error ocurred:"
        Write-Host $_
        return $false
    }
}


# Authenticate to host and return SessionKey and Location
function Create_Session([String]$IPaddress, [String]$Login, [String]$Password)
{
  $_uri = "https://" + $IPaddress + "/redfish/v1/SessionService/Sessions"
  $_sessionKey = ""
  $_location = ""

  Write-Host "`nTrying to log on as" $Login "..."
  # Check if domain credentials
  if($Login.Contains("\"))
  {
    $_domain = $Login.Split("\")[0]
    $_username = $Login.Split("\")[1]
  }
  else
  {
    $_domain = ""
    $_username = $Login
  }

  $_body = [Ordered]@{
     #  "authLoginDomain" = $domain
     #  "loginMsgAck"     = 'true'
       "UserName"        = $Login
       "Password"        = $Password
       }

  $_bodyJSON = ConvertTo-Json $_body

  try
  {
    #disable SSL checks using new class
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()
    $_respWeb = Invoke-WebRequest -Uri $_uri -Method POST -Headers $_header -Body $_bodyJSON -UseBasicParsing
    $_headers = $_respWeb.Headers
    $_sessionKey = $_headers."X-Auth-Token"
    $_location = $_headers.Location
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

  return $_sessionKey, $_location
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

# Read hardware profile from json folder
function Read_Profile([String]$ProfileName)
{
    $_profileDir = "profiles"
    $_profilePath = Join-Path $PSScriptRoot "profiles" | Join-Path -ChildPath $ProfileName

    try
    {
	    if((Test-Path $_profilePath) -and ($_profilePath.endswith(".json")) )
	    {
		    $_content = Get-Content -Path $_profilePath
            $_profileObj = $_content | ConvertFrom-Json
            return $_profileObj
	    }
        else
        {
            Write-Host "System profile" $ProfileName "not found in folder 'profiles'." 
            return $null
        }
    }
    catch
    {
        Write-Host "Cannot read profile:`n" $_profilePath
        Write-Host "Error:"
        Write-Host $_
        return $null
    }
}

# If $Scan is True it gets all found resources
# If $Scan is False it gets only Tree from given resource
# If $Once is True it gets resource and exit
function Get_Redfish_Resource([String]$IPaddress,[String]$Resource,[String]$SessionKey,[String]$OutputDir,[Boolean]$Scan=$true,[Boolean]$Once=$false)
{
    $Resource = $Resource.ToLower()

    $_uri = "https://" + $IPaddress + $Resource
    $_filename = "index.json"

    $_path = Join-Path $OutputDir $Resource
    $_filepath = $_path | Join-Path -ChildPath $_filename 

    # Get Data if index.json does not exist
    if (!(Test-Path -Path $_filePath ))
    {
        try
        {
            Write-Host $Resource
            # get Uri
            $_respWeb = Invoke-WebRequest -Uri $_uri -Method Get -Headers $_header -UseBasicParsing -TimeoutSec 20
            $_resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($_respWeb)           
            # convert to json
            $_jsonResp = $_resp | ConvertTo-Json -Depth 99

            # Create or check if Dir exist
            if (Create_Dir -Path $_path)
            {    
                # Save json file UTF-8
                [IO.File]::WriteAllLines($_filepath, $_jsonResp)

                if ($Once) 
                {
                    return $null
                }
                Redfish_Walk -jsonObj $_resp -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir -Scan $Scan
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
        foreach($_key in $jsonObj.Keys)
        {            
            if($jsonObj.$_key -is [System.Collections.IDictionary])
            {
                Redfish_Walk -jsonObj $jsonObj.$_key -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir -Scan $Scan
            }
            elseif($jsonObj.$_key -is [Array])
            {
                Redfish_Walk -jsonObj $jsonObj.$_key -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir -Scan $Scan
            }            
            elseif( ($_key -eq "@odata.id") -or ($_key -eq "Uri") -or ($_key -eq "Members@odata.nextLink") -or ($_key -eq "@Redfish.ActionInfo") )  
            {
                $_nextResource = $jsonObj.$_key.ToLower()

                # check if goes only in tree
                if (!($Scan) -and !($_nextResource.contains("$Resource")))
                {
                   continue
                }
                if( ($_nextResource -ne $Resource) -and !($_nextResource.contains("#")) -and ($_nextResource.StartsWith("/redfish"))  )  #-and ($_nextResource.contains("$Resource"))
                {
                    Get_Redfish_Resource -IPaddress $_ipaddress -Resource $jsonObj.$_key -OutputDir $scriptDir -Scan $Scan
                }
            }
        }
    }
    elseif($jsonObj -is [Array])
    {
        foreach($_item in $jsonObj)
        {
            if (($_item -is [System.Collections.IDictionary]) -or ($_item -is [Array]))
            {
                 Redfish_Walk -jsonObj $_item -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir -Scan $Scan
            }
        }

    }
}



$_ipaddress = "10.72.14.119"


$_if_connect = Check_Redfish_Connection -ipaddress $_ipaddress
$_sessionKey, $_location = Create_Session -IPaddress $_ipaddress -Login hpadmin -Password hpinvent

$_header.Add("X-Auth-Token", $_sessionKey)



[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()

$_resource = "/redfish/v1"
#$_resource = "/redfish/v1/Systems/1/PCIDevices"

$scriptDir = $PSScriptRoot + "\output"

$_profileObj = Read_Profile -ProfileName "iLO5.json"

foreach ($_item in $_profileObj.scan)
{
    Get_Redfish_Resource -IPaddress $_ipaddress -Resource $_item -OutputDir $scriptDir
}

foreach ($_item in $_profileObj.tree)
{
    Get_Redfish_Resource -IPaddress $_ipaddress -Resource $_item -OutputDir $scriptDir -Scan $false
}

foreach ($_item in $_profileObj.once)
{
    Get_Redfish_Resource -IPaddress $_ipaddress -Resource $_item -OutputDir $scriptDir -Once $true
}

# Close session
$_respWeb = Invoke-WebRequest -Uri $_location -Method Delete -Headers $_header -UseBasicParsing 

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null