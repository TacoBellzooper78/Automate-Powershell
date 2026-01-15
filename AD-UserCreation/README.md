#**Create-ADUsers.ps1** 

##**Overview**
A simple script to automate Active Directory user creation, syncing, and disabling or deleting based on a CSV file. 

##**Requirements**
 - Powershell 5.1+ 
 - Windows Server with [Active Directory Module](https://learn.microsoft.com/en-us/powershell/module/activedirectory/?view=windowsserver2025-ps "AD Cmdlets")
 - Permissions
 - CSV file
###CSV Format 
Single Delimiter:
```
id, firstname, lastname, Title, Department
12500000,Theresa,Ortega,user,NormalUsers
12500001,Stanley,Russell,user,NormalUsers
12500002,Lida,Carter,Talent,HR 
12500003,Stephen,Romero,Helpdesk,IT 
12500004,Virginia,Rodgers,Talent,HR
```

Two Delimiters:
```
id, firstname, lastname, job_dept
12500000,Theresa,Ortega, user : NormalUsers
12500001,Stanley,Russell, user : NormalUsers
12500002,Lida,Carter,Talent : HR 
12500003,Stephen,Romero, Helpdesk : IT 
12500004,Virginia,Rodgers,Talent : HR
```
##**Usage**
To run the script:
```PowerShell
.\Create-ADUsers.ps1
```
To run the script with no changes made (**Dry Run**):
```PowerShell
.\Create-ADUsers.ps1 -DryRun
```
###Configuration
If any other fields are added (ex. Office, EmailAddress), edit the SyncFieldMap variable according to the fields/columns on the CSV file.
The left side of the *$SyncFieldMap* should be equated to its Active Directory [property value](https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-aduser?view=windowsserver2025-ps "New User Properties")
```PowerShell
$SyncFieldMap=@{  
    id = "EmployeeID" 
    firstName = "GivenName"
    lastName = "SurName"
    job_dept = "Title:Department"  
}
```
Additionally, the hashtable *$NewUserParams*, within the function __*Create-NewUser{}*__ must include the new fields added to *$SyncFieldMap*.
```PowerShell
$NewADuserParams=@{
                EmployeeID=$NewUser.EmployeeID
                GivenName=$NewUser.GivenName
                Surname=$NewUser.Surname
                Name=$Username
                SamAccountName=$Username
                UserPrincipalName="$Username@$($UserData.Domain)"
                AccountPassword=$SecuredPassword
                ChangePasswordAtLogon=$true
                Enabled=$true
                Title=$NewUser.Title
                Department=$NewUser.Department
                Path="OU=Users,$($OU.DistinguishedName)"
                Confirm=$false
                Server=$UserData.Domain
            }
```
Other editable variables are:

```PowerShell
$FilePath="Path to file"

$Delimiter="," #default Delimiter

$SecondDelimiter=":" #my second delimiter

$uniqueID="EmployeeID" #set to any preffered parameter

$Domain="nico.lab" #domain 

$OUProperty="Department" #property from user field I used to make OUs 


$OUPath="OU=LabArea,DC=nico,DC=Lab" 

$KeepDisabledForDays=7 #how long a user stays disabled before getting deleted if the script runs
                       #past expiry date

$LogRoot = "C:\AutomationLogs\AD_UserAutomation" #Directory for the logs

$CredentialRoot ="C:\AutomationLogs\Passwords" #encrypted passwords directory to be sent by email
```
The Script adds the new users or moves existing users to their respective *Users* folders. 
The following script portion, found in __*Validate-OU*__, can be commented out or deleted if the Users and Workstations OU
is not needed:
```PowerShell
$ChildBasePath = "OU=$OUName,$OUPath"
                foreach($ChildOU in @("Users","WorkStations"))
                {
                    if( -not(Get-ADOrganizationalUnit -Filter "Name -eq '$ChildOU'" -SearchBase $ChildBasePath))
                    {
                        if($PSCmdlet.ShouldProcess($ChildOU,"Create CHILD AD Organizational Unit"))
                        {
                            New-ADOrganizationalUnit -Name $ChildOU -Path $ChildBasePath
                            Write-Verbose "Created {$ChildOU} in {$OUName}"
                            Write-Log -Message "Created {$ChildOU} in {$OUName}" -Level "INFO"
                        }
                    }
                    
                }
```

##**Notes**
This script references [JackedProgrammer's](https://www.youtube.com/@jackedprogrammer "JackedProgrammer Youtube") [youtube playlist](https://youtube.com/playlist?list=PLnK11SQMNnE4_mlkNufhyI4n-zOcqKqfr&si=THRzQvZhbGZqwQZW "Create Users Playlist") on powershell automation, 
The script in the tutorial feautred:
  - **Importing the csv files**
  - **Error handling**
  - **Comparing users in AD and in the CSV**
  - **Creating users**
  - **Updating users**
  - **Disabling and removing users**
    
In addition to the original features on the youtube tutorial I added:
  - **.log file**
  - **.dat file to secure temporary passwords**
  - **DryRun parameter using -whatIf to simualte changes**
  - **Additional delimiter for the csv file**
  

I needed the additional delimiter because I didn't know how to generate random departments that correspond to the right titles
using the [csv generator](https://www.convertcsv.com/generate-test-data.htm) mentioned in the tutorial.

###Additional delimiter
the additional delimiter in my csv file is ':'. 
Normally without the second delimiter the *$SyncFieldMap* hashmap would only need to get the columns of the csv file as the key, and match it to the
corresponding attribute on Active Directory as its value.  

However, my csv file is formatted like this:

<img width="583" height="433" alt="image" src="https://github.com/user-attachments/assets/d7cddc8e-5dc5-4189-8ead-4ed0fe0315e6" />

This required me to make another function to "normalize" the attributes in *$SyncFieldMap*. This function is *$Convert-SyncFieldMap*, it converts 
this:
```PowerShell

$SyncFieldMap=@{  
    id = "EmployeeID" 
    firstName = "GivenName"
    lastName = "SurName"
    job_dept = "Title:Department"  
}
```
into this:
```PowerShell
$NormalizedMap = @{
    EmployeeID = @{
        Source = "id"
        Index  = 0
    }
    GivenName = @{
        Source = "firstName"
        Index  = 0
    }
    SurName = @{
        Source = "lastName"
        Index  = 0
    }
   Title = @{
        Source = "job_dept"
        Index  = 0
    }
    Department = @{
        Source = "job_dept"
        Index  = 1
    }
}
```
This change allows me to dynamically parse the second delimiter instead of repeatedly hard coding -split every time the key is job_dept.

###Select-PropertiesFromMap Function

This function Enumerates through each Entry in the Normalized Field Map. Each key is a property of a user. 
I learned that I needed the .GetNewClosure() method to save each instance of the value in the script block.

```PowerShell
function Select-PropertiesFromMap{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldNormalized,
        [Parameter(Mandatory)]
        [string]$SecondDelimiter 
    )
    try{
        foreach($Entry in $SyncFieldNormalized.GetEnumerator()){
        
            $source = $Entry.Value.Source
            #Write-Host "Source=$source Value=$($_.$source)"
            @{
                Name = $Entry.Key
                Expression =({
                    $value = $_.$source

                    if($null -eq $value){return $null}

                    if ($value -like "*$SecondDelimiter*"){
                        ($value -split $SecondDelimiter)[$Entry.Value.Index].Trim()
                    }
                    else {
                        $value
                    }
              
                }).GetNewClosure()
            }
        }
    }catch{
        $msg = "Select-PropertiesFromMap failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
}
```

###.Dat file
I'm not sure if this is a good way to store the passwords, I plan to modify the script some other time to immedietly send the credentials to each user through email after creation.
I think this could prevent having a permenent location for storing the passwords.


