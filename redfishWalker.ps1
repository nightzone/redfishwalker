
$ip = "10.72.14.119"

$uri = "https://" + $ip + "/redfish/v1"

$header = @{}
$header.Add("Content-Type","application/json")
$header.Add("Accept-Language", "en_US")

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

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [SSLHandler]::GetSSLHandler()

$respWeb = Invoke-WebRequest -Uri $uri -Method Get -Headers $header -ErrorAction Stop
$resp = (New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer -Property @{MaxJsonLength=67108864}).DeserializeObject($respWeb)

$resp
