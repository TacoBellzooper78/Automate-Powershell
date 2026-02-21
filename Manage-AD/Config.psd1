@{
    Domain = "nico.lab"
    BaseOU="OU=LabArea,DC=nico,DC=Lab"

    UserDefaults = @{
        PasswordLength = 16
        Enabled = $true
        ChangePasswordAtLogon = $true
    }

    OUs = @(
        "HR"
        "IT"
        "Finance"
        "Sales"
        "Others"
    )
    PerOUChild = @(
        "Workstation"
        "Users"
    )

    SecurityGroups = @(
        @{
            Name = "HR-Users"
            OU   = "HR"
        },
        @{
            Name = "IT-Admins"
            OU   = "IT"
        },
        @{
            Name = "Finance-Managers"
            OU = "Finance"
        },
        @{
            Name = "Sales-Managers"
            OU = "Sales"
        },
        @{
            Name = "Others-Managers"
            OU = "Sales"
        }
    )
}
