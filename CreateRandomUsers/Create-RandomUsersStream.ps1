[CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1,999999)]
        [int]$c,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = "csv-output"
    )

# =========== Config =======================================================
$DomainFqdn = "nico.lab"
$Company = "NiCompany"
$Office = "Atlantis"
$Phone = "(123) 123-4567"

$Syllables = @(
        "al","an","ar","bel","cor","dan","el","fa","gar","hal",
        "is","jo","ka","lin","mar","nel","or","pa","quin","ra",
        "sel","tor","ul","val","wen","yor","zen", "giou" , "go", 
        "ga","gi" ,"guh","ni", "no" ,"co" , "mi" , "chelle",
        "mat", "thew", "tro", "jan","pat","reus" ,"son", "al","aal",
        "iy", "ah","lly","super","man","bat","brent","je","ro","me",
        "pao","aa","ron","ko","be","ken","neth","fet", "hi","hee","row",
        "sha","quille","niel","ep","jeff","bill","lin","us","ein","stien"
        ,"ja","ke","kol","finn","bu","ble","gum", "mar","ce","line","ry"
        ,"ka","rl","cas","tro","lo", "ba" , "bi", "bo", "bu", "bla","whi","te",
        "mai","ne","ko","ru","to","na", "ku", "ichi" ,"bra", "bruh", "plea" 
    )


$DepartmentTitles = @{
        IT = @(
            "IT Support Specialist",
            "Systems Administrator",
            "Network Engineer"
        )
        HR = @(
            "HR Generalist",
            "HR Manager",
            "Recruiter"
        )
        Finance = @(
            "Budget Analyst",
            "Financial Analyst",
            "Financial Manager"
        )
        Sales = @(
            "Sales Representative",
            "Business Development Representatives",
            "Sales Manager"
        )
        Operations = @(
            "Operations Analyst",
            "Operations Manager",
            "Logistics Coordinator"
        )
        Others = @(
            "Document Imaging Specialist",
            "Underwater Ceramic Technician",
            "Hygiene Associate",
            "Swim Instructor"
        )
    }

    

# ====================== Others =======================================================
$Emails = [System.Collections.Generic.HashSet[string]]::new()
$Random = [System.Random]::new()

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}


$Date = Get-Date -Format "yy-MM-dd-HHmmss"
$csvFile = Join-Path -Path $OutputPath -ChildPath "users-$Date.csv"

$DepartmentNames = @($DepartmentTitles.Keys)
$SyllablesArr    = [string[]]$Syllables #prevents repeated implicit casting
$sw = [System.IO.StreamWriter]::new($csvFile, $false, [System.Text.Encoding]::UTF8)


# ====================== FUNCTIONS =======================================================

function Create-NamefromSyllables{

    $nameSyllables = $Random.Next(2,5)
    $sb = New-Object System.Text.StringBuilder 16 #prevents creating a new string object
    
    for(  $i = 1; $i -le $nameSyllables; $i++){
        [void]$sb.Append($SyllablesArr[$Random.Next(0,$SyllablesArr.Length)])
    }
    $word = $sb.ToString()
    return $word.Substring(0,1).ToUpper() + $word.Substring(1)

}

function Create-Name{
    [CmdletBinding()]
    Param(
        [Parameter()]                              
        [ValidateRange(0,100)]
        [int]$oneNameWeight = 55, #default weighted value 1 'word' for name
        [Parameter()]                             
        [ValidateRange(0,100)]
        [int]$twoNameWeight = 80 #percent of remaining portion to be 2 'words' for the name
    ) 

    $outcome = $Random.Next(1,101)

    $sNameWeight = $twoNameWeight/100.0 

    if($outcome -le $oneNameWeight) {

        $nameCount = 1
        return (Create-NamefromSyllables)
        #Write-Host "One"

    }elseif($outcome -le ($oneNameWeight +((100 - $oneNameWeight)*$sNameWeight))) { #if outcome is within this range 

        $nameCount = 2 
        return ("{0} {1}" -f (Create-NamefromSyllables),(Create-NamefromSyllables))

    }else {

        $nameCount = 3
        return ("{0} {1} {2}" -f (Create-NamefromSyllables),(Create-NamefromSyllables),(Create-NamefromSyllables))
    }
}



function Create-EmailAdd{
    [CmdletBinding()]
    Param(

        [Parameter(Mandatory)]
        [string]$firstName,
        [Parameter(Mandatory)]
        [string]$lastName,
        [Parameter(Mandatory)]
        [string]$domain,
        [Parameter()] #did not put Mandatory to pass empty collection at first
        [System.Collections.Generic.HashSet[string]]$existingEmails

    )


    $first = ($firstName -split " ")[0]
    $last =($lastName -split " ")[0]

    $firstLastName= "{0}_{1}" -f $first.ToLower(), $last.ToLower()
    $email = "{0}@{1}" -f $firstLastName, $domain
    $counter = 1

    while ($existingEmails.Contains($email)) {
        $email = "{0}{1}@{2}" -f $firstLastName, $counter, $domain
        $counter++
    }
    [void]$existingEmails.Add($email)
    return $email
}

# ========================================================================================================



$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try{
    $sw.WriteLine("EmployeeID,GivenName,MiddleName,SurName,Email Address,Department,Title,Office,Company,Phone No.")
    $DepartmentCount = $DepartmentNames.Count
    $yy = Get-Date -Format "yy"
    

    for($i=1;$i -le $c; $i++){ #changed to for() from foreach() to not allocate more memory
 
        $EmployeeID = "{0}{1:D6}" -f $yy, $i
        $GivenName = Create-Name
        $MiddleName = Create-Name -oneNameWeight 75 -twoNameWeight 90
        $Surname = Create-Name -oneNameWeight 75 -twoNameWeight 70
        $EmailAddress = Create-EmailAdd -firstName $GivenName -lastName $Surname -domain $DomainFqdn -existingEmails $Emails
        $Department = $DepartmentNames[$Random.Next(0,$DepartmentCount)]
        $Titles = [string[]]$DepartmentTitles[$Department]
        $Title = $Titles[$Random.Next(0,$titles.Length)]

        $line = (
            "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}"-f $EmployeeID,$GivenName`
            ,$MiddleName,$Surname,$EmailAddress`
            ,$Department,$Title,$Office,$Company,$Phone
        )
        $sw.WriteLine($line)
    
        if (($i % 1000) -eq 0 -or $i -eq $c) {

            $percent = [int](($i / [double]$c) * 100)

            Write-Progress `
                -Activity "Generating Random Users" `
                -Status "$i of $c completed" `
                -PercentComplete $percent
        }
    }

}
finally{
    $sw.Dispose()
    $stopwatch.Stop()
    Write-Progress -Activity "Generating Random Users" -Completed
    Write-Host ("Written to $csvFile. Time Taken: {0}" -f $stopwatch.Elapsed.TotalSeconds)

}



