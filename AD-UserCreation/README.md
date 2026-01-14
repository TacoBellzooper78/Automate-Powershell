#Create-ADUsers.ps1 

This simple script references [JackedProgrammer's](https://www.youtube.com/@jackedprogrammer "JackedProgrammer Youtube") [youtube playlist](https://youtube.com/playlist?list=PLnK11SQMNnE4_mlkNufhyI4n-zOcqKqfr&si=THRzQvZhbGZqwQZW "Create Users Playlist") on powershell automation, 
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


##Notes

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

