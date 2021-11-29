using namespace System
using namespace System.Reflection
using namespace Serilog
using namespace Kerberos.NET.Client
using namespace Kerberos.NET.Credentials
using namespace Kerberos.NET.Transport
using namespace Microsoft.Extensions.Logging

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrEmpty($env:TEMP)) {
    $env:TEMP = '/tmp'
}

$currentPath = Get-Location
Set-Location -Path $env:TEMP
$localPath = Join-Path ((Get-Location).Path) "\AzureADKerberosChecker"

function LoadDependency([String] $assemblyName, [String] $version){
    $nugetPath = Join-Path $localPath "\packages"
    $assemblyPath = Join-Path $nugetPath "\$assemblyName.$version\lib\netstandard2.0\$assemblyName.dll"
    return [Assembly]::LoadFrom($assemblyPath)
}

function InstallDependency([String] $assemblyName, [String] $version){
    $nugetPath = Join-Path $localPath "\packages"
    $assemblyPath = Join-Path $nugetPath "\$assemblyName.$version\lib\netstandard2.0\$assemblyName.dll"
    if((Test-Path -Path $assemblyPath) -eq $False){
        Install-Package $assemblyName -RequiredVersion $version -Destination $nugetPath -Source https://www.nuget.org/api/v2 -Force -SkipDependencies | Out-Null
    }
}

function ResolveDependency([String] $assemblyName, [String] $version){
    InstallDependency $assemblyName $version
    LoadDependency $assemblyName $version | Out-Null
}

function RegisterPackageManager(){
    $_nugetUrl = "https://api.nuget.org/v3/index.json"

    $packageSources = Get-PackageSource
    if(@($packageSources).Where{$_.location -eq $_nugetUrl}.count -eq 0)
    {
        Register-PackageSource -Name AzureADKerberosCheckerNuGet -Location $_nugetUrl -ProviderName NuGet | Out-Null
    }
}

function LoadKerberosNETDependencies() {
    InstallDependency "System.Runtime.CompilerServices.Unsafe" "4.7.1"
    InstallDependency "System.Buffers" "4.5.1"
    InstallDependency "Microsoft.Extensions.Logging.Abstractions" "2.0.0"
    
    ResolveDependency "System.Memory" "4.5.4"
    ResolveDependency "System.Threading.Tasks.Extensions" "4.5.4"
    ResolveDependency "Kerberos.NET" "4.5.124"

}

function LoadLoggerDependencies(){
    ResolveDependency "Microsoft.Extensions.Options" "2.0.0"
    ResolveDependency "Microsoft.Extensions.Logging" "2.0.0"
    ResolveDependency "Serilog" "2.9.0"
    ResolveDependency "Serilog.Extensions.Logging" "3.1.0"
    ResolveDependency "Serilog.Sinks.Console" "4.0.1"    
}

$OnAssemblyResolve = [System.ResolveEventHandler] {
  param($sender, $e)

  if ($e.Name -eq "System.Buffers, Version=4.0.2.0, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51") 
  {     
    return LoadDependency "System.Buffers" "4.5.1"
  }

  if($e.Name -eq "System.Runtime.CompilerServices.Unsafe, Version=4.0.4.1, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a")
  {
    return LoadDependency "System.Runtime.CompilerServices.Unsafe" "4.7.1"
  }

  if($e.Name -eq "Microsoft.Extensions.Logging.Abstractions, Version=5.0.0.0, Culture=neutral, PublicKeyToken=adb9793829ddae60")
  {
    return LoadDependency "Microsoft.Extensions.Logging.Abstractions" "2.0.0"
  }

  if($e.Name -eq "Microsoft.Extensions.Logging.Abstractions, Version=2.0.0.0, Culture=neutral, PublicKeyToken=adb9793829ddae60")
  {
    return LoadDependency "Microsoft.Extensions.Logging.Abstractions" "2.0.0"
  }
  

  foreach($a in [System.AppDomain]::CurrentDomain.GetAssemblies())
  {
    if ($a.FullName -eq $e.Name)
    {
      return $a
    }
  }
  return $null
}


$parameters = $args[0]

$userName = $parameters['User']
$password = $parameters['Password']
$spn = $parameters['SPN']
$tenantId = $parameters['TenantID']
$authority = $parameters['Authority']

if ([string]::IsNullOrEmpty($authority)) {
    $authority = 'https://login.microsoftonline.com/'
}

Clear-Host
Write-Host '******************************************' -ForegroundColor Green
Write-Host '  Azure AD Kerberos Checker v0.9          ' -ForegroundColor Green
Write-Host '******************************************' -ForegroundColor Green
Write-Host

$domainPathsUri = "$authority$tenantId/kerberos"

Write-Host 'Loading dependencies ...          ' -ForegroundColor Yellow
RegisterPackageManager
LoadKerberosNETDependencies

[AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)

LoadLoggerDependencies

Write-Host

Write-Host 'Obtaining the ticket ...          ' -ForegroundColor Yellow

$loggerFactory = [LoggerFactory]::new()
$loggerConfig = [LoggerConfiguration]::new()
$sinkConfiguration = $loggerConfig.MinimumLevel.Verbose().WriteTo
$loggerConfig = [ConsoleLoggerConfigurationExtensions]::Console($sinkConfiguration).CreateLogger()
[SerilogLoggerFactoryExtensions]::AddSerilog($loggerFactory, $loggerConfig, $false) | Out-Null

$httpsTransport = [HttpsKerberosTransport]::new($loggerFactory)
$httpsTransport.DomainPaths["kerberos.microsoftonline.com"] = [Uri]::new($domainPathsUri)

$tcpTransport = [TcpKerberosTransport]::new($loggerFactory)

$client = [KerberosClient]::new($null, $loggerFactory, @($tcpTransport, $httpsTransport))

$kerbCred = [KerberosPasswordCredential]::new($userName, $password)

try
{
    Write-Host
    $client.Authenticate($kerbCred).Wait()

    $ticket = $client.GetServiceTicket($spn).Result 

    Write-Host
    [Convert]::ToBase64String($ticket.EncodeApplication().ToArray())
}
catch
{
    Write-Host
    Write-Host "Errors at obtaining Kerberos ticket:" -Foreground Red
    foreach ($ex in $_.Exception.InnerException.InnerException.InnerExceptions)
    {
        Write-Host $ex.Message -Foreground Red
    }
    
}

[AppDomain]::CurrentDomain.remove_AssemblyResolve($OnAssemblyResolve)

Set-Location $currentPath
Write-Host
