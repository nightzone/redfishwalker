
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

function Get_Redfish_Resource([String]$IPaddress,[String]$Resource,[String]$SessionKey,[String]$OutputDir)
{
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
            $_respWeb = Invoke-WebRequest -Uri $_uri -Method Get -Headers $_header -UseBasicParsing 
            $_resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($_respWeb)           
            # convert to json
            $_jsonResp = $_resp | ConvertTo-Json -Depth 99

            
          #  $_filepath = $_path | Join-Path -ChildPath $_filename 
           # $_jsonResp | Out-File -Encoding ascii $_filepath
            if (Create_Dir -Path $_path)
            {    
                # Save json file UTF-8
                [IO.File]::WriteAllLines($_filepath, $_jsonResp)
                Redfish_Walk -jsonObj $_resp -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir
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
 #       Write-Host "Resource already collected:"
 #       Write-Host $Resource
        return $null
    }
}

function Redfish_Walk($jsonObj,[String]$IPaddress,[String]$Resource,[String]$SessionKey,[String]$OutputDir)
{
    if ($jsonObj -is [System.Collections.IDictionary])
    {
        foreach($_key in $jsonObj.Keys)
        {            
            if($jsonObj.$_key -is [System.Collections.IDictionary])
            {
                Redfish_Walk -jsonObj $jsonObj.$_key -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir
            }
            elseif($jsonObj.$_key -is [Array])
            {
                Redfish_Walk -jsonObj $jsonObj.$_key -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir
            }            
            elseif( (($_key -eq "@odata.id") -or ($_key -eq "Uri")) -and ($jsonObj.$_key -ne $Resource) -and !($jsonObj.$_key.contains("#")) -and ($jsonObj.$_key.StartsWith("/redfish")) )  #-and ($jsonObj.$_key.contains("$Resource"))
            {
                Get_Redfish_Resource -IPaddress $_ipaddress -Resource $jsonObj.$_key -OutputDir $scriptDir
            }
        }
    }
    elseif($jsonObj -is [Array])
    {
        foreach($_item in $jsonObj)
        {
            if (($_item -is [System.Collections.IDictionary]) -or ($_item -is [Array]))
            {
                 Redfish_Walk -jsonObj $_item -IPaddress $IPaddress -Resource $Resource -OutputDir $scriptDir
            }
        }

    }
}



$_ipaddress = "10.72.14.119"


$_if_connect = Check_Redfish_Connection -ipaddress $_ipaddress
$_sessionKey, $_location = Create_Session -IPaddress $_ipaddress -Login hpadmin -Password hpinvent

$_header.Add("X-Auth-Token", $_sessionKey)



[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()


#$_respWeb = Invoke-WebRequest -Uri $_uri -Method Get -Headers $_header -UseBasicParsing 
#$_resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($_respWeb)


#$_filename = "index.json"
$_resource = "/redfish/v1"
#$_resource = "/redfish/v1/Systems/1/PCIDevices"

$scriptDir = $PSScriptRoot + "\output"

#Get_Uri -IPaddress $_ipaddress -odataID $_odataID -OutputDir $scriptDir

Get_Redfish_Resource -IPaddress $_ipaddress -Resource $_resource -OutputDir $scriptDir

# $_resp -is [System.Collections.IDictionary]

# Close session
$_respWeb = Invoke-WebRequest -Uri $_location -Method Delete -Headers $_header -UseBasicParsing 

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null