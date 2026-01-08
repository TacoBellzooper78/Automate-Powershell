<#
.SYNOPSIS
Creates, Synchronizes, Disables, and Removes 
Active Directory users according to an employee CSV file.

Referenced from JackedProgrammer on Youtube 
(https://youtu.be/e-gHIX67CsY?si=VI1A7-i9-_rZNCol)

.DESCRIPTION
This script imports employee data from a CSV file and
compares it against existing AD users using a unique Identifier
(Currently EmployeeID). 

The script does the following:
    - Creates new AD users if their UniqueID is not yet on AD.
    - Updates existing AD users based on the CSV file.
    - Disables users not present on the CSV file.
    - Removes users past the account expirey date.
    - Validates and creates required Organizational Units.
    - Logs Changes made in AD to log files named by the date.
    - Securely stores temporary credentials for new users 
    (planning to update this script, or make a new one, to email 
    the passwords to each user.)

The script has a few additions/differences to the youtube video
including: 
    - Logging
    - Storing Passwords
    - Additional Delimiter 

$SyncFieldMap is an important variable that changes with the csv file.
The Key(left side) of the hashtable must always match the columns of the csv file.
The Value(right side) must always match the corresponding attribute of AD.

.PARAMETER DryRun
This parameter simulates changes using -WhatIf.
No changes are made to Active Directory

.Example
.\Create-ADUsers.ps1
.\Create-ADUsers.ps1 -DryRun



.NOTES
Created: 2026-January
Requires: ActiveDirectory module, and permissions
#>

[CmdletBinding(SupportsShouldProcess=$true)]
Param(
    [switch]$DryRun
)
if ($DryRun)
{
    $WhatIfPreference = $true
}
else
{
    $WhatIfPreference = $false 
}
Add-Type -AssemblyName System.Security

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# editable fields 

$FilePath="C:\EmployeeFiles\EmployeesTest.csv"

$Delimiter=","

$SecondDelimiter=":"

$uniqueID="EmployeeID"

$Domain="nico.lab"

$OUProperty="Department"


$OUPath="OU=LabArea,DC=nico,DC=Lab"

$KeepDisabledForDays=7

$SyncFieldMap=@{  # CSV columns <=> AD User attributes

    id="EmployeeID" 
    firstName="GivenName"
    lastName="SurName"
    job_dept="Title:Department"  # CsvColumname=": : : : " if seperated by colon
}

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#

$Date = Get-Date -Format "yyyy-MM-dd"
$LogRoot = "C:\AutomationLogs\AD_UserAutomation"
$LogFile = "$LogRoot\$Date.log"
$ServerName = $env:COMPUTERNAME


$CredentialRoot ="C:\AutomationLogs\Passwords"
$RootPaths = @($LogRoot,$CredentialRoot)
$CredentialFile = "$CredentialRoot\$Date.dat"
$script:TempCredentials = @()


function Write-Log{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter()]
        [ValidateSet("INFO","ERROR","WARN")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "HH:mm:ss"
    $LogEntry = "$Timestamp $ServerName [$Level] $Message"

    Add-Content -Path $LogFile -Value $LogEntry -WhatIf:$false
}

if ($DryRun)
{
    Write-Log -Message "<START> {DRYRUN} Running Create-ADUsers.ps1 Script with $FilePath" -Level "INFO"
    Write-Host "<START> {DRYRUN} Running Create-ADUsers.ps1 Script with $FilePath"
}
else
{
    Write-Log -Message "<START> Running Create-ADUsers.ps1 Script with $FilePath" -Level "INFO"
    Write-Host "<START> Running Create-ADUsers.ps1 Script with $FilePath"
}



foreach($RootPath in $RootPaths){
    if(!(Test-Path $RootPath)) 
    {
        New-Item -ItemType Directory -Path $RootPath -Force | Out-Null
        Write-Verbose "Created Directory {$RootPath}"
        Write-Log -Message "Created Directory {$RootPath}" -Level "INFO" 
    } 
}







#Converts original FieldMap into a 
function Convert-SyncFieldMap{
[CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [Parameter(Mandatory)]
        [string]$SecondDelimiter
    )
    try{
        $NormalizedMap = @{}
        foreach($Property in $SyncFieldMap.GetEnumerator()){

            if($Property.value -match $SecondDelimiter){
                $names= $Property.Value -split $SecondDelimiter
                for($i =0;$i -lt $names.Count; $i++){
                    $NormalizedMap[$names[$i].Trim()] = @{
                    Source = $Property.Key ; Index = $i
                    }
                }
            }
            else{
                $NormalizedMap[$Property.Value] =@{
                    Source = $Property.Key ; Index = 0
                }
            }

           
       }
    }catch{
        $msg = "Convert-SyncFieldMap failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
       
    return $NormalizedMap
}
$SyncFieldNormalized = Convert-SyncFieldMap -SyncFieldMap $SyncFieldMap -SecondDelimiter $SecondDelimiter


#makes object properties from the Map
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

#import csv file
function Get-EmployeeCsv{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath, 
        [Parameter(Mandatory=$true)]
        [string]$Delimiter, 
        [Parameter(Mandatory=$true)]
        [string]$SecondDelimiter, 
        [Parameter(Mandatory=$true)]
        [hashtable]$SyncFieldNormalized
    )

    try{
         $Properties = Select-PropertiesFromMap -SyncFieldNormalized $SyncFieldNormalized -SecondDelimiter $SecondDelimiter
         Import-Csv -Path $FilePath -Delimiter $Delimiter | Select-Object -Property $Properties

    }catch{
        $msg = "Get-EmployeesCSV failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
    
}



function Get-EmployeesAD{
    [CmdletBinding()]
    param(
    [Parameter(Mandatory)]
    [hashtable]$SyncFieldNormalized,
    [Parameter(Mandatory)]
    [string]$Domain,
    [Parameter(Mandatory)]
    [string]$uniqueID
    )
    try{
        Get-ADUser -Filter {$uniqueID-like "*"} -Server $Domain `
        -Properties @($SyncFieldNormalized.Keys)

    }catch{
        $msg = "Get-EmployeesAD failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
}


#Compare CSV with current Users
function Compare-CsvToAd{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldNormalized,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter()]
        [string]$Delimiter=",",
        [Parameter(Mandatory)]
        [string]$SecondDelimiter,
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$uniqueID
    )
    $CSVUsers=Get-EmployeeCsv -FilePath $FilePath -Delimiter $Delimiter -SecondDelimiter $SecondDelimiter -SyncFieldNormalized $SyncFieldNormalized
    $ADUsers=Get-EmployeesAD -SyncFieldNormalized $SyncFieldNormalized -Domain $Domain -uniqueID $uniqueID

    Compare-Object -ReferenceObject $ADUsers -DifferenceObject $CSVUsers -Property $uniqueID -IncludeEqual 

}

#get users to add, and disabled
function Get-SyncedData{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldNormalized,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter()]
        [string]$Delimiter=",",
        [Parameter(Mandatory)]
        [string]$SecondDelimiter,
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$uniqueID,
        [Parameter(Mandatory)]
        [string]$OUProperty,
        [Parameter(Mandatory)]
        [string]$OUPath

    )
    try{
        $CompareData=Compare-CsvToAd -SyncFieldNormalized $SyncFieldNormalized -FilePath $FilePath `
                -Delimiter $Delimiter -SecondDelimiter $SecondDelimiter `
                -Domain $Domain -uniqueID $uniqueID

        $NewUsersID=$CompareData | where SideIndicator -eq "=>"
        $SyncedUsersID=$CompareData | where SideIndicator -eq "=="
        $DisableUsersID=$CompareData | where SideIndicator -eq "<=" #users found on AD only not necessarily to be deleted

        $ExcludedEmployeeIDs= @('1','3','4') #Employees to NOT disable

        $NewUsers = Get-EmployeeCsv -FilePath $FilePath -Delimiter $Delimiter `
        -SecondDelimiter $SecondDelimiter `
        -SyncFieldNormalized $SyncFieldNormalized | where $uniqueID -In $NewUsersID.$uniqueID


        $SyncedUsers = Get-EmployeeCsv -FilePath $FilePath -Delimiter $Delimiter `
        -SecondDelimiter $SecondDelimiter `
        -SyncFieldNormalized $SyncFieldNormalized | where $uniqueID -In $SyncedUsersID.$uniqueID 

        $DisableUsers = Get-EmployeesAD -SyncFieldNormalized $SyncFieldNormalized -Domain $Domain `
        -uniqueID $uniqueID | Where-Object{ 
            $_.$uniqueID -in  $DisableUsersID.$uniqueID -and
            $_.$uniqueID -notin $ExcludedEmployeeIDs } 
        @{
            New=$NewUsers
            Synced=$SyncedUsers
            Disable=$DisableUsers
            Domain=$Domain
            UniqueID=$uniqueID
            OUProperty=$OUProperty
            OUPath=$OUPath
         }
    }catch{
        $msg = "Get-SyncedData Failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
    

}


#create users
       #make a unique username | will be initials plus last 3 digits of employee ID
       #place a user in the correct OU
       # create the users
       #add them to proper group

 function New-Username{
    [cmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GivenName,
        [Parameter(Mandatory)]
        [string]$Surname,
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$employeeID
       
    )

    try{
        $last4ID= 
            if($employeeID.Length -ge 4){
                $employeeID.Substring($employeeID.Length - 4)
            }else{
                $employeeID
            }
        $FirstInitials = ($GivenName -split '[-\s]+') | ForEach-Object{$_.Substring(0,1).ToUpper()}
        $LastInitials =  ($Surname -split '[-\s]+') | ForEach-Object{$_.Substring(0,1).ToUpper()}
   

        $Username="$($FirstInitials.Trim())$($LastInitials.Trim())$last4ID"
        $Username = $Username -replace "[-'\s]", ''

        $UniqueUsername = $Username
        $counter = 1

   
            while (Get-ADUser -Filter "sAMAccountName -eq '$UniqueUsername'" -Server $Domain -ErrorAction SilentlyContinue) {
                $UniqueUsername = "$counter$Username"
                $counter++
            }
            if((Get-ADUser -Filter "sAMAccountName -eq '$UniqueUsername'" -Server $Domain)){
                throw "No usernames available for this USER!"
            }else{
                $UniqueUsername
            }
    }catch{
        $msg = "New-Username Failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
    
   
   
   
 }
 

 function Validate-OU{
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath, 
        [Parameter(Mandatory=$true)]
        [string]$Delimiter, 
        [Parameter(Mandatory=$true)]
        [string]$SecondDelimiter, 
        [Parameter(Mandatory=$true)]
        [hashtable]$SyncFieldNormalized,
        [Parameter(Mandatory=$true)]
        [string]$Domain, 
        [Parameter(Mandatory=$true)]
        [string]$OUPath,
        [Parameter(Mandatory=$true)]
        [string]$OUProperty
    )
   
    try{
        $OUNames = Get-EmployeeCSV -FilePath $FilePath -Delimiter $Delimiter `
        -SecondDelimiter $SecondDelimiter `
        -SyncFieldNormalized $SyncFieldNormalized | Select -Property $OUProperty 

        foreach($OUName in $OUNames){
            $OUName=$OUName.$OUProperty
            
            if( -not (Get-ADOrganizationalUnit -Filter "name -eq '$OUName'" -Server $Domain `
            -SearchBase $OUPath))
            {
                if($PSCmdlet.ShouldProcess($OUName,"Create AD Organizational Unit"))
                {
                    New-ADOrganizationalUnit -Name $OUName -Path "$OUPath" #$OUPath="OU=LabArea,DC=nico,DC=Lab"
                    Write-Verbose "Created {$OUName} in {$OUPath}"
                    Write-Log -Message "Created {$OUName} in {$OUPath}" -Level "INFO"
                }

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
                

            }


        }
    }catch{
        $msg = "Validate-OU Failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }  
 }



function Create-NewUser{
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UserData 
    )
    try{
        $NewUsers=$UserData.New

        foreach($NewUser in $NewUsers){
            Write-Verbose "Creating User: {$($NewUser.givenname)$($NewUser.surname)}"
            $Username=New-Username -GivenName $NewUser.Givenname -Surname $NewUser.Surname -employeeID $NewUser.EmployeeID -Domain $UserData.Domain
            Write-Verbose "Creating User: {$($NewUser.givenname)$($NewUser.surname)} with username: {$Username}"
            if( -not ($OU=Get-ADOrganizationalUnit -Filter "name -eq '$($NewUser.$($UserData.OUProperty))'" -Server $UserData.Domain `
                -SearchBase $OUPath))
                {
                    if($PSCmdlet.ShouldProcess($($NewUser.$($UserData.OUProperty)),"ERROR THROWN {$($NewUser.$($UserData.OUProperty)) does not exist}"))
                    {#first time using -whatif here
                        throw "The Organizational unit {$($NewUser.$($UserData.OUProperty))} does not exist"
                        Write-Log -Message "The Organizational unit {$($NewUser.$($UserData.OUProperty))} does not exist" -Level "WARN"
                    }
                }
            Write-Verbose "Creating User: {$($NewUser.givenname)$($NewUser.surname)} with username: {$Username}, {OU=Users,$OU}"
            Add-Type -AssemblyName 'System.Web'
            $Password=[System.Web.Security.Membership]::GeneratePassword(12,(Get-Random -Minimum 3 -Maximum 7))
            $SecuredPassword=ConvertTo-SecureString -String $Password -AsPlainText -Force

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

            if($PSCmdlet.ShouldProcess($NewUser.Givenname,"creating user"))
            {
                
                New-AdUser @NewADUserParams
                $script:TempCredentials += [PSCustomObject]@{
                    Username = $Username
                    Password = $Password
                }
                Write-Verbose "Created user: {$($NewUser.Givenname)$($NewUser.Surname)} EmpID: {$($NewUser.EmployeeID) Username: {$Username}"
                Write-Log -Message "Created user: {$($NewUser.Givenname)$($NewUser.Surname)} EmpID: {$($NewUser.EmployeeID) Username: {$Username}" -Level "INFO"
            }
        }
    #writing users to encrypted file
    $PlainText = ( $script:TempCredentials | ForEach-Object { "$($_.Username),$($_.Password)" }) -join "`n"
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $Encrypted = [System.Security.Cryptography.ProtectedData]::Protect($Bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($CredentialFile, $Encrypted)
    Write-Log -Message "Created Password File" -Level "INFO"

    }
    Catch{
        $msg = "Create-NewUser Failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
}



function Check-Username{
    [cmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GivenName,
        [Parameter(Mandatory)]
        [string]$Surname,
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$employeeID,
        [Parameter(Mandatory)]
        [string]$CurrentUserName
       
    )


    $last4ID = 
        if($employeeID.Length -ge 4){
            $employeeID.Substring($employeeID.Length - 4)
        }else{
            $employeeID
        }
    $FirstInitials = ($GivenName -split '[-\s]+') | ForEach-Object{$_.Substring(0,1).ToUpper()}
    $LastInitials =  ($Surname -split '[-\s]+') | ForEach-Object{$_.Substring(0,1).ToUpper()}
   

    $Username="$($FirstInitials.Trim())$($LastInitials.Trim())$last4ID"
    $Username = $Username -replace "[-'\s]", ''

    $UniqueUsername = $Username
    $counter = 1

   
        while ((Get-ADUser -Filter "sAMAccountName -eq '$UniqueUsername'" -Server $Domain) -and `
        ($Username -ne $CurrentUserName)){
            $UniqueUsername = "$counter$Username"
            $counter++
        }
        if((Get-ADUser -Filter "sAMAccountName -eq '$UniqueUsername'" -Server $Domain)-and ($Username -ne $CurrentUserName)){
            throw "No usernames available for this USER!"
        }else{
            $UniqueUsername
        }
 }
 

function Sync-ExistingUsers{
    [CmdletBinding(SupportsShouldProcess=$True)]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$UserData,
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldNormalized

    )
    try{
        $SyncedUsers=$UserData.Synced

        foreach($SyncedUser in $SyncedUsers){
        
            $CsvOUPath = "OU=Users,OU=$($SyncedUser.Department),$($UserData.OUPath)"

            Write-Verbose "Loading data for $($SyncedUser.GivenName) $($SyncedUser.Surname)"
            $ADuser= Get-ADUser -Filter "$($UserData.UniqueID) -eq $($SyncedUser.$($UserData.uniqueID))" -Server $UserData.Domain -Properties *
       
            if( -not ($OU=Get-ADOrganizationalUnit -Filter "name -eq '$($SyncedUser.$($UserData.OUProperty))'" -Server $UserData.Domain `
                    -SearchBase $UserData.OUPath ))
            {
                throw "the organizational unit {$($SyncedUser.$($UserData.OUProperty))}"
            }
            Write-Verbose "User is currently in $($ADuser.distinguishedname) but should be in $OU"
            
            if((($ADUser.distinguishedname).split(",")[1..$($ADUser.DistinguishedName.Length)] -join ",") -ne ($CsvOUPath))
            {
                Write-Log -Message "$($ADUser.name)[$($ADuser.$($UniqueID))] is currently in $($ADuser.distinguishedname) but should be in $OU" -Level "INFO"
                Write-verbose "OU needs to be changed for {$($SyncedUser.GivenName) $($SyncedUser.Surname)}"
                if($PSCmdlet.ShouldProcess($ADuser.distinguishedname,"Moving AD object {$($ADuser.Givenname) $($ADuser.Surname)}"))
                {
                    Move-ADObject -Identity $ADuser -TargetPath $CsvOUPath  -Server $UserData.Domain 
                    Write-Log -Message "Moved $($ADUser.name)($($ADuser.Givenname) $($ADuser.Surname))[$($ADuser.$($UniqueID))] to {$CsvOUPath}" -Level "INFO"
                }
            
      
            }

            $ADuser= Get-ADUser -Filter "$($UserData.UniqueID) -eq $($SyncedUser.$($UserData.uniqueID))" -Server $UserData.Domain -Properties *
           
            $Username= Check-Username -GivenName $SyncedUser.GivenName -Surname $SyncedUser.SurName -CurrentUserName $ADuser.SamAccountName -employeeID $SyncedUser.EmployeeID -Domain $UserData.Domain

            if($ADuser.SamAccountName -ne $Username)
            {
                Write-Verbose "Username needs to be changed"

                if($PSCmdlet.ShouldProcess($ADuser),"Renaming User")
                {
                    Write-verbose "Renamed $($ADUser.name)[$($ADUser.$($UniqueID))] to $Username"
                    Write-Log -Message "Renamed $($ADUser.name)[$($ADUser.$($UniqueID))] to $Username" -Level "INFO"

                    Set-ADuser -Identity $ADuser -Replace @{userprincipalname="$Username@$($UserData.Domain)"} -Server $UserData.Domain
                    Set-ADUser -Identity $ADuser -Replace @{SamAccountName="$Username"} -Server $UserData.Domain
                    Rename-ADObject -Identity $ADuser -NewName $Username -Server $UserData.Domain
                    
                    
                }
            
            }
             $SetADUserParams=@{
                    Identity=$Username
                    Server=$UserData.Domain
             }
             foreach($Property in $SyncFieldNormalized.Keys)
             {
                $SetADUserParams[$Property]=$SyncedUser.$Property 
             }

             if($PSCmdlet.ShouldProcess($ADuser),"setting user properties")
             {
                Set-ADUser @SetADUserParams
             }
        }
    }catch{
        $msg = "Sync-ExistingUsers Failed: $($_.Exception.Message)"
        Write-Error $msg
        Write-Log -Message $msg -Level "ERROR"
    }
    
 }

 function Remove-Users {
       [CmdletBinding(SupportsShouldProcess=$True)]
       param(
            [Parameter(Mandatory)]
            [hashtable]$UserData,
            [Parameter()]
            [int]$KeepDisabledForDays=7
       )

       try {
        $DisableUsers =$UserData.Disable
         
        foreach($DisableUser in $DisableUsers) {
            Write-Verbose "Fetching data for $($DisableUser.Name)"
            $ADUser=Get-ADUser $DisableUser -Properties * -Server $UserData.Domain
            if($ADUser.Enabled -eq $true) {
                if($PSCmdlet.ShouldProcess($($ADUser.Name), "Disabling User"))
                {
                    Write-Log -Message "Disabling user $($ADUser.Name)[$($ADUser.$($UniqueID))]" -Level "INFO"
                    Write-Verbose "Disabling user $($ADUser.Name)[$($ADUser.$($UniqueID))]"
                    Set-ADUser -Identity $ADUser -Enabled $false -AccountExpirationDate (Get-Date).AddDays($KeepDisabledForDays) -Server $UserData.Domain -Confirm:$false
                }
            }
            else
            {
                if($ADUser.AccountExpirationDate -lt (Get-Date)) {
                    if($PSCmdlet.ShouldProcess($($ADUser.Name), "Removing User")){
                        Write-Log -Message "Deleting account $($ADUser.Name)[$($ADUser.$($DisableUser.UniqueID))]" -Level "INFO"
                        Write-Verbose "Deleting account $($ADUser.Name)[$($ADUser.$($DisableUser.UniqueID))]"
                        Remove-ADUser -Identity $ADUser -Server $UserData.Domain -Confirm:$false
                    }
                }
                else {
                    Write-Verbose "Account $($ADUser.Name)[$($ADUser.$($UniqueID))] is still within retention period"
                    Write-Log -Message "Account $($ADUser.Name)[$($ADUser.$($UniqueID))] is still within retention period" -Level "INFO"
                }
            }
        }

       }catch {
            $msg = "Remove-Users: $($_.Exception.Message)"
            Write-Error $msg
            Write-Log -Message $msg -Level "ERROR"
       }
 }

$UserData= Get-SyncedData -SyncFieldNormalized $SyncFieldNormalized `
-FilePath $FilePath -Delimiter $Delimiter -SecondDelimiter $SecondDelimiter `
-Domain $Domain -uniqueID $uniqueID -Verbose `
-OUProperty $OUProperty -OUPath $OUPath

 Validate-OU -FilePath $FilePath -Delimiter $Delimiter -SecondDelimiter $SecondDelimiter `
 -SyncFieldNormalized $SyncFieldNormalized -Domain $Domain `
 -OUPath $OUPath -OUProperty $OUProperty #-WhatIf



Create-NewUser -UserData $UserData -Verbose #-WhatIf


Sync-ExistingUsers -UserData $UserData -SyncFieldNormalized $SyncFieldNormalized -Verbose #-WhatIf

Remove-Users -UserData $UserData -KeepDisabledForDays $KeepDisabledForDays -Verbose 
if ($DryRun) {
    Write-Log -Message "<END> {DRYRUN} Finished running Create-ADUsers.ps1 Script" -Level "INFO"
    Write-host "<END> {DRYRUN} Finished running Create-ADUsers.ps1 Script"
}
else {
    Write-Log -Message "<END> Finished running Create-ADUsers.ps1 Script" -Level "INFO"
    Write-host "<END> Finished running Create-ADUsers.ps1 Script"
}

