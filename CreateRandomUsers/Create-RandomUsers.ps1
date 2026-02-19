[CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1,500000)]
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
        "mai","ne","ko","ru","to","na", "ku", "ichigo" ,"bra", "bruh", "plea" 
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

    $Emails = [System.Collections.Generic.HashSet[string]]::new()

# ====================== FUNCTIONS =======================================================


function Create-NamefromSyllables{

    $nameSyllables = Get-Random -Minimum 1 -Maximum 4
    $word = ""
    for(  $i = 1; $i -le $nameSyllables; $i++){
        $word += ($Syllables | Get-Random)
    }
        $word.Substring(0,1).ToUpper() + $word.Substring(1)

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

    $outcome = Get-Random -Minimum 1 -Maximum 101

    $sNameWeight = $twoNameWeight/100.0 

    if($outcome -le $oneNameWeight) {

        $nameCount = 1
        #Write-Host "One"

    }elseif($outcome -le ($oneNameWeight +((100 - $oneNameWeight)*$sNameWeight))) { #if outcome is within this range 

        $nameCount = 2 
        #Write-Host "Two"

    }else {

        $nameCount = 3
        #Write-Host "Three"
    }

    $name = for($i = 1; $i -le $nameCount; $i++ ){ Create-NamefromSyllables }
    $name -join " "
    #Write-Host $name
}

#Create-Name

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

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$DepartmentNames = $DepartmentTitles.Keys

$Users = foreach($i in 1..$c){
    $GivenName = Create-Name
    $MiddleName = Create-Name -oneNameWeight 75 -twoNameWeight 90
    $Surname = Create-Name -oneNameWeight 75 -twoNameWeight 70
    $EmailAddress = Create-EmailAdd -firstName $GivenName -lastName $Surname -domain $DomainFqdn -existingEmails $Emails
    $Department = $DepartmentNames | Get-Random
    $Title = $DepartmentTitles[$Department] | Get-Random 

    [PSCustomObject]@{
            EmployeeID = "{0}{1:D6}" -f (Get-Date -Format "yy"), $i
            GivenName = $GivenName
            MiddleName = $MiddleName
            Surname = $Surname
            EmailAddress = $EmailAddress
            Department = $Department
            Title = $Title
            Office = $Office
            Company = $Company
            PhoneNumber = $Phone
    }
    
}


$Date = Get-Date -Format "yy-MM-dd-HHmmss"
$csvFile = Join-Path -Path $OutputPath -ChildPath "users-$Date.csv"

$Users | Export-Csv -Path $csvFile -NoTypeInformation 
Write-Host "Written to $csvFile."

