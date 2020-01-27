[DscResource()]
class jGit_FileMonitor {

    #region input
    [DscProperty(key)]
    [ValidateNotNullOrEmpty()]
    [string]$File_URL

    [DscProperty(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination
    #endregion input

    jGit_FileMonitor() {
        # Create Environment Path Variables
        [string]$Global:Root = "$((Split-Path -parent $PSScriptRoot).ToString())"
    }

    #region main
    [jGit_FileMonitor]Get(){
        return $this
    }
    [bool]Test(){
        #region Verify Input Values
        $Valid = @()
        if(-not (Test-Path "$($this.Destination)")){
            Write-Verbose "[$($this.Destination)] isn't a valid location!"
            $Valid += $False
        }
        if(-not ($this.File_URL -like '*/blob/*')){
            Write-Verbose "[$($this.File_URL)]'s Path Must Include [/blob/]!"
            $Valid += $False
        }
        $File = [IO.Path]::GetExtension("$($this.File_URL)")
        if(-not ($File -like ".*")){
            Write-Verbose "[$($this.File_URL)] must be a file!"
            $Valid += $False
        }
        #endregion Verify Input Values

        if($Valid -notcontains $False){
            $this.Git_File_Test()

            return $False
        }
        else{
            return $True
        }
    }
    [void]Set(){
    }
    #endregion main

    #region functions
    [void] PerformanceTrigger([bool]$Active){
        if(-not $Active){
            $global:ProgressPreference = 'Continue'
        }
        else{
            $global:ProgressPreference = 'SilentlyContinue'
        }
    }
    [void] Git_File_Test(){

        # Functions
        function Convert-UTCtoLocal{
            param(
            [parameter(Mandatory=$true)]
            [String] $UTCTime
            )
            $strCurrentTimeZone = (Get-WmiObject win32_timezone).StandardName
            $TZ = [System.TimeZoneInfo]::FindSystemTimeZoneById($strCurrentTimeZone)
            $LocalTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($UTCTime, $TZ)
            return $LocalTime
        }

        # Assembly
        Add-Type -AssemblyName System.Web # Add System.Web for HttpUtility

        # Turn on > preformance trigger
        $this.PerformanceTrigger($true)

        # Main Variable
        $FileMonitor = New-Object pscustomobject
        $FileMonitor | Add-Member NoteProperty 'Domain' ([string]((((((Get-WmiObject win32_computersystem).Domain).split('.')) | select -Skip 1) -join '.')))

        # Convert & Attach Domain
        $Correct_URL = ((($this.File_URL).split('/') | where {$_ -notlike "http*" -and $_ -notlike "*.mil"}).trim() -join '/')
        if($Correct_URL -like "/*"){
            $Project_URL = [string]("https://git.resource.$($FileMonitor.Domain)"+$Correct_URL)
        }
        else{
            $Project_URL = [string]("https://git.resource.$($FileMonitor.Domain)/"+$Correct_URL)
        }
        $ProjectURL = (($Project_URL -split 'blob') | select -first 1).trimend('/')
        $Project = ($Project_URL -split 'blob') | select -Last 1

        # Lookup Project
        $GitRepos = ((Invoke-WebRequest -Uri "https://git.resource.$($FileMonitor.Domain)/api/v4/projects" -UseBasicParsing).content | ConvertFrom-Json)

        # Fix Destination Path
        $FinalDestination = $this.Destination
        if($FinalDestination -like "*\"){
            [string]$Fix = ($FinalDestination).Substring(0,($FinalDestination).Length-1)
            $FinalDestination = $Fix
        }

        # Values 
        $FileMonitor | Add-Member NoteProperty 'ID' ($GitRepos | where {$_.web_url -like "*$ProjectURL*"}).ID
        $FileMonitor | Add-Member NoteProperty 'Branch' (((($Project).split("/") | select -Skip 1 -First 1)) -join "/")
        $FileMonitor | Add-Member NoteProperty 'Path' ((($Project).split("/") | select -Skip 2) -join "/")
        $FileMonitor | Add-Member NoteProperty 'FileName' (($Project).split('/') | select -Last 1)
        $FileMonitor | Add-Member NoteProperty 'ProjectURL' ("https://git.resource.$($FileMonitor.Domain)/api/v4/projects/$($FileMonitor.ID)/repository")
        $FileMonitor | Add-Member NoteProperty 'Project_FileURL' "$($FileMonitor.ProjectURL)/files/$($FileMonitor.FileHTML)?ref=$($FileMonitor.Branch)"

        $URL = "$($($FileMonitor.ProjectURL)+'/files/'+$([System.Web.HttpUtility]::UrlEncode("$($FileMonitor.Path)"))+'?ref='+$($FileMonitor.Branch))"

        function fixuri($uri){
          $UnEscapeDotsAndSlashes = 0x2000000;
          $SimpleUserSyntax = 0x20000;

          $type = $uri.GetType();
          $fieldInfo = $type.GetField("m_Syntax", ([System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic));

          $uriParser = $fieldInfo.GetValue($uri);
          $typeUriParser = $uriParser.GetType().BaseType;
        $fieldInfo = $typeUriParser.GetField("m_Flags", ([System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::FlattenHierarchy));
        $uriSyntaxFlags = $fieldInfo.GetValue($uriParser);

        $uriSyntaxFlags = $uriSyntaxFlags -band (-bnot $UnEscapeDotsAndSlashes);
        $uriSyntaxFlags = $uriSyntaxFlags -band (-bnot $SimpleUserSyntax);
        $fieldInfo.SetValue($uriParser, $uriSyntaxFlags);
        }
        $uri = New-Object System.Uri -ArgumentList ("$URL")
        fixuri $uri

        $Request = (Invoke-WebRequest $uri -UseBasicParsing).content | ConvertFrom-Json

        $FileMonitor | Add-Member NoteProperty 'LastCommitID' ($Request.last_commit_id)
        
        Write-Verbose "Test2: $($FileMonitor.ProjectURL)/commits/$($FileMonitor.LastCommitID)"

        $FileMonitor | Add-Member NoteProperty 'LastWriteTime' (((Invoke-WebRequest -Uri "$($FileMonitor.ProjectURL)/commits/$($FileMonitor.LastCommitID)" -UseBasicParsing).content | ConvertFrom-Json)).committed_date
        $FileMonitor | Add-Member NoteProperty 'FileData' ($Request.content)
        
        # Output the Data To Module JSON
        $FileMonitor | ConvertTo-Json | Out-File "$($this.Destination)\FileMonitor.json"
    }
    #endregion functions
}

