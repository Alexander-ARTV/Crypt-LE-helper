param (
	$Domain = $False,
	[int]$Renew = $False,
	[switch]$Unattended,
	[switch]$KeepChallenges,
	[switch]$AutoDistribute,
	[switch]$KeepLogs
)

function Exit-Script {
	param (
		$Message
	)
	Write-Host $Message
	Exit
}

function Test-Folders {
	param (
		[array]$Folders
	)
	foreach ($Folder in $Folders) {
		if (!(Test-Path "$PSScriptRoot/$Folder")) {
			try {New-Item "$PSScriptRoot/$Folder" -ItemType 'Directory'}
			catch {
				Write-Host $_
				Return $False
			}
		}
	}
	Return $True
}

function Clear-Logs {
	$DateLimit = (Get-Date).AddDays(-180)
	if (Test-Path $DirLog) {$DirLog | Get-ChildItem | Where-Object -FilterScript {Test-Path $_ -OlderThan $DateLimit} | Remove-Item}
}

function Start-Crypt-LE {
	param (
		$Domain,
		$CertName,
		$PathPrefix,
		$Renew,
		$Live,
		$Pass
	)
	$global:LASTEXITCODE = 0
	Invoke-Expression "docker compose run -u $(id -u) --rm Crypt-LE -debug -log-config /log.conf -key .$PathPrefix/account_keys/$CertName.account.key -csr .$PathPrefix/$CertName.csr -csr-key .$PathPrefix/$CertName.key -crt .$PathPrefix/$CertName.crt -domains `"*.$Domain, $Domain`" -email tekniken@alandsradio.ax -handle-as dns -generate-missing $Renew $Live $Pass"
	Write-Host "last exit code is $LASTEXITCODE"
	Return ($LASTEXITCODE -eq 0 ? $True : $False)
}

function Write-CloudflareIDs {
	$Challenges = Get-ChildItem $DirChallenges

	$Challenges | Foreach-Object {
		$Content = Get-Content $_
		$Hostname = $content[0]
		$Value = $content[1]
		if (($Value -eq '') -or ($Hostname -eq '')) {
			Write-Host "Missing information in challenge file $_, please check and re-run this script."
			Return $False
		}
		$Response = curl -X POST "$CloudflareURL"`
			-H "Authorization: $CloudflareAuth"`
			-H "Content-Type:application/json"`
			-d "{`"comment`": `"Test`",`"content`": `"\`"$Value\`"`",`"name`": `"$Hostname`",`"proxied`": false,`"ttl`": 240,`"type`": `"TXT`"}"

		if ($Null -eq $Response -or !($Response | Test-Json)) {
			Write-Host "Connection issue when contacting Cloudflare."
			Return $False
		}
		
		$ResponseJSON = $Response | ConvertFrom-Json
		if (!($ResponseJSON.success)) {
			Write-Host "Failed to write the challenge post to Cloudflare."
			Return $False
		}
		if ($Null -ne $ResponseJSON.result.id) {$CloudflareIDs.Add($ResponseJSON.result.id)}
		$Response | Out-File "$DirLog/$Date cloudflare.txt" -Append
		if (!$KeepChallenges -or !$Live) {Remove-Item $_}
	}
	Return $True
}

function Clear-CloudflareIDs {
	if ($CloudflareIDs.Count -eq 0) {Return}
	foreach ($ID in $CloudFlareIDs) {
		$DeleteURL = "$CloudflareURL/$ID"
		if (!$Unattended) {Read-Host "Removing DNS post with the following URL: $DeleteURL, confirm or exit"}
		$Response = curl -X DELETE "$DeleteURL"`
			-H "Authorization: $CloudflareAuth"
		Write-Host $Response
	}
	$CloudflareIDs.Clear()
}

function New-Certificate {
	param (
		$Domain,
		$CertName,
		$PathPrefix,
		$Renew,
		$Live
	)

	if (Test-Path "$DirData$PathPrefix/$CertName.crt") {
		if (!$Unattended) {
			$Choice = Read-Host "Certificate $CertName.crt already exists, enter r to remove and continue, s to skip to certificate distribution (or run Crypt LE live in case we are in test mode), or nothing to exit"
			if ($Choice.ToLower() -eq 's') {Return $True}
			if ($Choice.ToLower() -ne 'r') {Exit-Script}
		}
		Remove-Item "$DirData$PathPrefix/$CertName.crt"
	}

	Write-Host "Creating challenge in Crypt LE for $CertName"

	if (!(Start-Crypt-LE $Domain $CertName $PathPrefix $Renew $Live '--delayed')) {
		Write-Host "Crypt LE failed to run, a certificate for $CertName has not been created."
		Return $False
	}

	if (Test-Path "$DirData$PathPrefix/$CertName.crt") {
		Write-Host 'The certificate could be created early, skipping the challenge and verification step.'
		Return $True
	}

	Write-Host "Writing challenges to Cloudflare for $CertName"

	if (!(Write-CloudflareIDs)) {Return $False}

	Write-Host "Waiting for five seconds before starting the verification process of $CertName"
	
	Start-Sleep -Seconds 5

	if (!(Start-Crypt-LE $Domain $CertName $PathPrefix $Renew $Live '--resume')) {
		Write-Host "Could not verify $Domain with Crypt LE. $CertName har NOT been created."
		Return $False
	}
	Return $True
}


# Early setup

$DirData = "$PSScriptRoot/data"
$DirLog = "$PSScriptRoot/log"
$DirChallenges = "$DirData/challenges"
$DirTest = "$DirData/test"
$FileSecrets = "$PSScriptRoot/secrets.txt"
$FileTargets = "$PSScriptRoot/targets.txt"
$FileCompose = "$PSScriptRoot/compose.yaml"
$CloudflareIDs = [System.Collections.Generic.List[string]]::new()
$Folders = 'data', 'log', 'webroot', 'data/test', 'data/test/account_keys'
$Date = Get-Date -Format 'yyyyMMdd'
if (!(Test-Folders $Folders)) {Exit-Script "Could not create needed folders, check permissions."}
Clear-Logs
Start-Transcript -OutputDirectory $DirLog

if ($Unattended -and !$Domain) {Exit-Script "Domain must be set in unattended mode."}

if ((Get-Content $FileCompose) -match '^#\s*image') {Exit-Script "Please update compose.yaml with a usable docker image."}

if (!(Test-Path $FileSecrets)) {
	if ($Unattended) {Exit-Script "Secrets file must be created before running this script unattended. Run this script again without the -Unattended-switch."}
	Write-Output 'Cloudflare secrets file missing, please enter information for creation.'
	$URL = Read-Host 'Enter URL (https://api.cloudflare.com/client/v4/zones/abcdef123456789.../dns_records)'
	$Auth = Read-Host 'Enter Auth (Bearer xyz123...)'
	$URL, $Auth | Out-File $FileSecrets;
}
$Secrets = Get-Content $FileSecrets
$CloudflareURL = $Secrets[0]
$CloudflareAuth = $Secrets[1]
$SkipTest = 'n'

# Meat and potatoes

Write-Output "
This is a wrapper script for Crypt LE with automatic DNS verification to Cloudflare. It will request a certificate for root and wildcard. 
The script can also perform basic automatic distribution of the created certificates. Prerequisites:
	-A Docker environment
	-A Docker image with a custom version of Crypt LE with two pass capability (custom as of July 2025)
The wrapper can perform a test round from the staging environment of Let's Encrypt before attempting to get a production certificate.
"


if ($Renew) {$Renew = "--Renew $Renew"}

if (!$Unattended) {
	while (!$Domain) {$Domain = Read-Host "Specify domain to use"}
	$RenewChoice = Read-Host "
If you want to renew a certificate, enter max number of days allowed until old cert expiry. 
A new certificate will not be issued if the date is beyond this time window. 
Leave blank to use the value from the command line or issue certificate immediately if no value was given
"
	if ($RenewChoice) {$Renew = "--Renew $([int]$RenewChoice)"}
	$SkipTest = Read-Host "Do you want to skip the test against the staging environment and attempt to get a production certificate immediately? (y/n)"
}

$CertName = "star.$Domain"

if ($SkipTest.ToLower() -ne 'y') {
	if (!$Unattended) {Read-Host "Beware! All files in the subfolder $DirTest will be removed.`n"}
	Get-ChildItem $DirTest -File -Recurse | Remove-Item
	$CertName = "test.$Domain"
	$PathPrefix = '/test'
	$CreateSuccess = New-Certificate $Domain $CertName $PathPrefix $Renew
	Clear-CloudflareIDs
	if (!$CreateSuccess) {Exit-Script "Creation of test certificate failed, did not attempt to create a production certificate."}
	if (!$Unattended) {Write-Output "Test successful, generating production certificate.`n"}
}

$CreateSuccess = New-Certificate $Domain $CertName $PathPrefix $Renew '-Live'
if (!$KeepChallenges) {Clear-CloudflareIDs}
if (!$CreateSuccess) {Exit-Script "Failed to get a production certificate."}


# Automatic distribution

if (!$Unattended) {$Continue = Read-Host 'Continue with automatic distribution? (y/n)'}
if ($Continue -eq 'y' -or $AutoDistribute) {
	Get-Content "$DirData/$CertName.key" | Out-File "$DirData/$CertName.full.pem"
	Get-Content "$DirData/$CertName.crt" | Out-File -Append "$DirData/$CertName.full.pem"

	openssl pkcs12 -export -legacy -keypbe NONE -certpbe NONE -passout pass: -inkey "$DirData/$CertName.key" -in "$DirData/$CertName.crt" -out "$DirData/$CertName.pfx" 

	Write-Output "Done formatting certificates, continuing with distribution."
	if (!(Test-Path $FileTargets)) {Exit-Script "$FileTargets is missing, copy targets_example.txt to targets.txt, read the comments and modify the content to use the automatic distribution feature."}
	$Targets = Get-Content $FileTargets

	foreach ($Target in $Targets) {
		if ($Target.StartsWith('#') -or $Target -eq '') {continue}
		if ($Target.StartsWith('@')) {
			$Prefix = "$PSScriptRoot/data/$CertName"
			$CertificateTypes = $Target.Substring(1) -Split ' '
			$CertificateFiles = "$Prefix$($certificateTypes -join " $Prefix")"
			Write-Output "Files that will be copied: $CertificateFiles"
			continue
		}
		if ($Target.StartsWith('&')) {
			$Command = $Target.Substring(1)
			Write-Output "Running command: $Command"
			Invoke-Expression $Command
			continue
		}	
		Write-Output "Copying over scp: $CertificateFiles $Target"
		Invoke-Expression "scp $CertificateFiles $Target"
	}
}