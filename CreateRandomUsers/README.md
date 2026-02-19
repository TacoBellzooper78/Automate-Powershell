# **Create-RandomUsers and Create-RandomUsersStream**
## Overview
These scripts generate randomized user records and export them to a CSV file.
The purpose of these two scripts is to practice powershell and make an easier to edit csv generator for more powershell practice.

## Usage
*-c indicates* the number of random users to generate.
*-OutputPath* specifies the **folder** where the file will be written.
```Powershell
.\Create-RandomUsersStream -c <number_of_users> [-OutputPath <folder_name>]
```
If *<folder_name>* does not exist, it will be created automatically.

## Create-RandomUsers vs Create-RandomUsersStream
Create-RandomUsersStream is a more efficient version of Create-RandomUsers; However, the difference between the two scripts is only noticeable when generating larger datasets (~100,000+).

Below are some improvements  made in **Create-RandomUsersStream**.

#### StreamWriter instead of Export-Csv
The first script created a large *$Users* collection and it gets piped to **Export-Csv**, this creates objects for every row, and does additional enumeration from piping. To improve efficiency, **StreamWriter** was implemented  in **Create-RandomUsersStream** to write the lines directly to the disk with no additional overhead.

```Powershell
$sw = [System.IO.StreamWriter]::new($csvFile, $false, [System.Text.Encoding]::UTF8)
```

#### One System.Random instance
**Create-RandomUsers** has multiple calls to **Get-Random**, This gets called thousands of times and it gets expensive within the loop and multiple function calls.
So constructing *$Random = [System.Random]::new()* once and reusing it can avoid repeated allocation and the other overhead from repeatedly calling **Get-Random**.
```Powershell
$Random = [System.Random]::new()
```
#### StringBuilder 
StringBuilder was used to prevent creating a new string each time with:
```PowerShell
$word += ($Syllables | Get-Random)
```
This causes alot of string allocations and new string objects on every concatenation. **StringBuilder** appends in-place, this minimizes string allocations and improves performance.

#### Others
- for loop instead of foreach.
  - foreach allocates an entire intiger array to memory, then enumerates.
- Some variables are computed once instead of in loop.
- Added **Write-Progress** and a stopwatch.


