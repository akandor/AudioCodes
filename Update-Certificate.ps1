# Update-Certificate.ps1
# Update the AudioCodes SBC TLS Context with a Let's encrypt certificate
# using Cloudflare hosted Domain
#
# Version 1.1.0 (Build 1.0.0-2023-02-21)
# 
# AT
#
#########################################################################################

#########################################################################################
#                                                                                       #
# Requirements:                                                                         #
#                                                                                       #
# Open Powershell command box as administrator                                          #
# Run Install-Module -Name Posh-ACME                                                    #
#                                                                                       #
#########################################################################################


#########################################################################################
#                     Insert Data for Certificate and Cloudflare                        #
#########################################################################################
 
$CFAuthEmail = 'email@email.com' # Your cloudflare account email
$CFAuthKey = 'xxxxxxxxYourCloudFlareAPIKeyxxxxxxxxxx' # Gloabl API Key | https://poshac.me/docs/v4/Plugins/Cloudflare/#using-the-plugin
$PFXPass = 'StrongPFXPasswordGoesHere' # Change to a strong Password for the PFX file. Generated key will be saved without password
$Domains = @("*.root.com","*.sub.root.com","root.com") #  Example for wilcard and subdomain "*.root.com","*.sub.root.com","root.com"
$DownloadPath = "~/certs/_LetsEncryptCerts$((Get-Date).ToString('yyyyMM'))" # Set filepath for the let's encrypt files
$ContactEmail = 'email@email.com' # Contact Email for Let's encrypt

#########################################################################################
#                            Insert your SBC Data here                                  #
#########################################################################################

$ip = "[IP-Address]"
$username = "[Username]"
$password = "[Password]"
$tlsContextID = 3

#########################################################################################
#                            DO NOT EDIT BELOW THESE LINES!                             #
#########################################################################################

Set-StrictMode -Version "2.0"

$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# Import Local Copy of ImportExcel Module
try {
    Import-Module -Name ($ScriptDirectory + "/library/Posh-ACME/Posh-ACME")
}
catch {
    Write-Host "Error while loading supporting PowerShell Scripts"
    break
}

Set-PAServer LE_PROD

$CheckPAAccount = Get-PAAccount -List -Contact $ContactEmail

if($CheckPAAccount.status -ne "valid") {
    New-PAAccount -Contact $ContactEmail -AcceptTOS
}

Set-PAAccount -Contact $ContactEmail 



# Check if Certificate already exists
$Path = Get-PACertificate $Domains[0] | select -ExpandProperty CertFile

$FriendlyName = "LetsEncrypt_$((Get-Date).AddDays(90).ToString('yyyy-MM-dd'))"
$CFParams = @{CFAuthEmail=$CFAuthEmail; CFAuthKey=$CFAuthKey}

# Create Certificate
if($Null -eq $Path -Or $Path -eq "") {
    Write-Host "New Certificate will be created" -ForegroundColor Green
    $NewCertificate = New-PACertificate $Domains -AcceptTOS -Contact $ContactEmail -DnsPlugin Cloudflare -PluginArgs $CFParams -DNSSleep 180 -PfxPass $PFXPass -Force
    $NewCertificate
} else {
    Write-Host "Renew Certificate" -ForegroundColor Green
    $NewCertificate = Submit-Renewal $Domains[0] -Force
    $NewCertificate
}

If(!(Test-Path -PathType container $DownloadPath))
{
      New-Item -ItemType Directory -Path $DownloadPath
} 

$Path = Get-PACertificate $Domains[0] | select -ExpandProperty CertFile
$Path = $Path.Substring(0,$Path.LastIndexOf('/'))
Copy-Item "$Path/cert.cer" $DownloadPath -Force
Copy-Item "$Path/cert.key" $DownloadPath -Force
Copy-Item "$Path/cert.pfx" $DownloadPath -Force

$privateKey = Get-Content -Path $Path\cert.key -Raw
$certificate = Get-Content -Path $Path\cert.cer -Raw

$LF = "`r`n";

$URLkey = "http://{0}/api/v1/files/tls/$tlsContextID/privateKey" ` -f $ip
$URLcert = "http://{0}/api/v1/files/tls/$tlsContextID/certificate" ` -f $ip
$URLsave = "http://{0}/api/v1/actions/saveConfiguration" ` -f $ip

# REST API Authentication
$authHash = [Convert]::ToBase64String( ` [Text.Encoding]::ASCII.GetBytes( ` ("{0}:{1}" -f $username,$password)))

# Body
$boundary = [System.Guid]::NewGuid().ToString(); 
$bodyLinesKey = (
    "--$boundary",
("Content-Disposition: form-data; name=`"file`";" + `
" filename=`"key.pem`""),
"Content-Type: application/octet-stream$LF", $privateKey,
"--$boundary--$LF"
) -join $LF

$uploadKey = Invoke-RestMethod -Uri $URLkey -Method Put ` -Headers @{Authorization=("Basic {0}" -f $authHash)} ` -ContentType "multipart/form-data; boundary=$boundary" ` -Body $bodyLinesKey
$uploadKey | ConvertTo-Json

# Body
$boundary = [System.Guid]::NewGuid().ToString(); 
$bodyLinesCert = (
    "--$boundary",
("Content-Disposition: form-data; name=`"file`";" + `
" filename=`"cert.pem`""),
"Content-Type: application/octet-stream$LF", $certificate,
"--$boundary--$LF"
) -join $LF

$uploadCert = Invoke-RestMethod -Uri $URLcert -Method Put ` -Headers @{Authorization=("Basic {0}" -f $authHash)} ` -ContentType "multipart/form-data; boundary=$boundary" ` -Body $bodyLinesCert
$uploadCert | ConvertTo-Json

$saveConf = Invoke-RestMethod -Uri $URLsave -Method Post -Headers @{Authorization=("Basic {0}" -f $authHash)}
$saveConf 