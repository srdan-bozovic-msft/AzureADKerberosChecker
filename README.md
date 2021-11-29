# Azure AD Kerberos Checker

This PowerShell script will run some connectivity checks from this machine to the server and database.  

**In order to run it you need to:**
1. Open Windows PowerShell ISE

2. Open a New Script window

3. Paste the following in the script window:

```powershell
$parameters = @{
    User = 'jane@contoso.com' # Set the login username you wish to use in UPN format
    Password = 'g6sBG?69H)TC(C.4'  # Set the login password you wish to use, and don't use weak passwords ;)
    SPN = 'MSSQLSvc/azslqsrv.80c60e3f113a0.database.windows.net:1433'  # Set the SPN of Azure resource you want to get kerberos ticket for
    TenantID = '6bfc1ce4-0fdc-4c82-adf4-59bd9c0285d1'  # Set the Tenat Id of the Azure AD tenant Azure resource belongs to

    ## Optional parameters (default values will be used if omitted)
    Authority = 'https://login.microsoftonline.com/'  # Set Azure AD Authority url for the Azure Environment. Use Get-AzEnvironment to learn values for different environments
}

$scriptUrlBase = 'https://raw.githubusercontent.com/srdan-bozovic-msft/AzureADKerberosChecker/master'

Invoke-Command -ScriptBlock ([Scriptblock]::Create((iwr ($scriptUrlBase+'/getKerberosTicket.ps1?t='+ [DateTime]::Now.Ticks)).Content)) -ArgumentList $parameters
```
4. Set the parameters on the script. 

5. Run it. Results are displayed in the output window. 

6. Examine the output for any issues detected, and recommended steps to resolve the issue.
