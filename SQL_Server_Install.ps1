<#
.SYNOPSIS
SQL_Install Installs SQL Server 2012SP2 or 2014SP1(Standard or Enterprise edition).
.DESCRIPTION
SQL_Install can be used to install different version of SQL Server (2012 or 2014).
This script will first do the following (in order)
- Checks if current user is "ssadmin" and if "D,E,T,L" Drive letters are present
- Ask for user input for following
     - SQL Version
     - SQL Edition
     - Instance Name
     - Collation
     - TCP Port #
     - Max Memory to allocate to instance
     - SQL Server components to install
     - "ssadmin" password (Password not displayed)
     - SA password
- Copy over appropriate ISO files and mounts it
- Start installing SQL Server
- Change Max Memory allocated to newly created instance
- Disable dynamic port and Enable Static port(Port provided by user-input)
     - If instance type is Default(MSSQLSERVER) then named pipes are enabled
- Change/Creates following
     - Changes Recovery Model to SIMPLE
     - Change Model mdf file to 10MB and auto growth of 250MB
     - Change Model ldf file to 10MB and auto growth of 100MB
     - Changes Log Rotations to 30 Logs
     - Creates "DBA_management" database
     - Create Monitoruser account
     - Creates index rebuilds stored procedure
     - Creates a new SQL Server job for index rebuild (Runs weekly on Sunday 6PM Server time)
- Restart SQL Server
- Dismounts ISO, Remove ISO
.PARAMETER sqlversion
SQL Server version to install(NO DEFATUL SET), Script will exit if 2012 or 2014 is not the input
.PARAMETER edition
SQL Server edition to install(Standard or Enterprise)
.PARAMETER instance
SQL Server instance name(Default is MSSQLSERVER)
.PARAMETER collation
SQL Server collation type(Default is SQL_Latin1_General_CP1_CI_AS)
.PARAMETER port
Port number for the SQL Server instance(Default is 1433)
.PARAMETER maxmem
Max Memory allocated to this instance in MB(Default is 2048MB)
.PARAMETER featurelist
List of SQL SERVER components to install(Default is "SQLENGINE,FULLTEXT,CONN,IS,BC,SSMS,ADV_SSMS,SDK")
.PARAMETER ServiceAccountPassword
Password for "ssadmin" account under which SQL Install starts
.PARAMETER SaPassword
New Password for SA
.EXAMPLE

Can Run Below if needed (But password is exposed)
.\SQL_Install  -sqlversion 2012 -edition enterprise -instance test -collation '' -port 57100 -maxmem 2000m -featurelist '' -ServiceAccountPassword XXXXXXX -saPassword XXXXXX

Recommended Way to run is below, Copy/Paste the contents of this file and save it as SQL_Install.ps1
and then pass in inputs at the prompt(This way password is not shown)
.\SQL_Install

# Modifications:        Abdul Mohammed (March-2016)
                - Added CORE version to this script with appropriate location of ISO
                    - Added elseif to bound all variable name(ISO file name, location, Imagename, MsIntVer etc..)
                - Added Check to Make sure you have 2014 selected when the input is CORE edition
#>

param (
    [int] $sqlversion,
    [string] $edition,
    [string] $instance,
    [string] $collation,
    [int] $port,
    [int] $maxmem,
    [string] $featurelist,
    $ServiceAccountPassword,
    $saPassword

)

##################################################################
# Function to make sure script is being ran as ssadmin account
# And also to make sure D, E, L, T drive letters are present
##################################################################
function pre_check{
    if ([Environment]::UserName -eq 'ssadmin')
    { "Running Script as 'ssadmin' account"
    }
    else
    {
        "###############################################################";
        "        Please run script using 'ssadmin' account"
        "###############################################################";
        exit
    }

    ""
    "Looking for Standard Drive letter for SQL SERVER INSTALL"
    "Looking for D, E, L, T Drive Letters"
    if (-not(get-psdrive | where { $_.Name -eq 'D' }))
    { "###################"
        "  Missing D Drive"
        "###################";
        exit }
    if (-not(get-psdrive | where { $_.Name -eq 'E' }))
    { "###################"
        "  Missing E Drive"
        "###################";
        exit }
    if (-not(get-psdrive | where { $_.Name -eq 'L' }))
    { "###################"
        "  Missing L Drive"
        "###################";
        exit }
    if (-not(get-psdrive | where { $_.Name -eq 'T' }))
    { "###################"
        "  Missing T Drive"
        "###################";
        exit }
    "Found D, E, L, T Drive Letters"
}

#################################################
# Getting Parameters, cannot wrap below
# in its own function due to variable scoping
#################################################
function get_parameters{
    if (-not $script:sqlversion){ $script:sqlversion = Read-Host 'Enter SQL version to install - 2012 or 2014?' }
    if (($script:sqlversion -eq '2012') -or ($script:sqlversion -eq '2014')){
        "SQL Server $sqlversion will be installed"
    }
    else
    {
        Write-Host -ForegroundColor red "Please enter 2012 or 2014(re-run script), Aborting script..."
        exit
    }
    ""
    if (-not $script:edition){ $script:edition = Read-Host 'Enter SQL edition - Enterprise or Standard or Core(only select core if using 2014)' }
    $script:edition = $edition.ToUpper()
    if (($script:edition -eq 'ENTERPRISE') -or ($script:edition -eq 'STANDARD') -or ($script:edition -eq 'CORE')){
        "SQL Server $edition edition will be installed"
    }
    else
    {
        Write-Host -ForegroundColor red "Please enter either Enterprise or Standard or Core, Aborting script(re-run script with right parameters)..."
        exit
    }
    ""
    if ($script:edition -eq 'CORE') {

        if ($script:sqlversion -eq '2014'){
        "CORE edition was selected, Making sure you selected 2014 as version..."
        }
        else
        {
        Write-Host -ForegroundColor red "You selected CORE edition, which is ONLY available for 2014.  You select version of $sqlversion, Aborting script(re-run script with right parameters)...."
        exit
        }
    }

    ""
    if (-not $script:instance){ $script:instance = Read-Host 'Instance Name [Hit enter to keep default SQL Instance name of: MSSQLSERVER]?' }
    if (-not $script:instance){ $script:instance = "MSSQLSERVER" }
    ""
    # SQL_Latin1_General_CP1_CI_AS default collation
    "*******************************************************************************"
    "MAKE SURE YOU HAVE THE RIGHT COLLATION, IF COLLATION IS DIFFERENT THAN DEFAULT"
    "COPY/PASTE COLLATION TO PREVENT TYPOS"
    "*******************************************************************************"
    if (-not $script:collation){ $script:collation = Read-Host 'Collation [Hit enter to keep default of: SQL_Latin1_General_CP1_CI_AS]?' }
    if (-not $script:collation){ $script:collation = "SQL_Latin1_General_CP1_CI_AS" }

    ""
    if (-not $script:port){ $script:port = Read-Host 'TCP Port [Hit Enter to keep default port of: 57000]? ' }
    if (-not $script:port){ $script:port = "57000" }
    ""
    # Get the allocated amount of Memory on the box, so it can be displayed
    # No need to set "script" level variable scope as this is not being called any were else
    $gwmios = Get-WmiObject Win32_OperatingSystem
    $mem_round = ($gwmios.TotalVisibleMemorySize / 1024 / 1024)
    $total_mem = [math]::Round($mem_round)
    "Total Memory allocated to this server is $total_mem GB"
    if (-not $script:maxmem){ $script:maxmem = Read-Host 'Max Memory Allocated to this Instance(in MB), default 2GB? ' }
    if (-not $script:maxmem){ $script:maxmem = "2048" }
    ""
    "*******************************************************************************"
    "Below is the SQL SERVER Feature list that can be installed"
    "*******************************************************************************"
    "SQLENGINE = SQL Server Engine"
    "REPLICATION = Replication"
    "FULLTEXT = Full text Search"
    "DQ = Data Quality Services"
    "AS = Analysis Services"
    "RS = Reporting Services - Native"
    "RS_SHP = Reporting Services - SharePoint"
    "RS_SHPWFE = Reporting Services Add-in for SharePoint Productsa"
    "DQC = Data Quality Client"
    "BIDS = SQL Server Data Tools"
    "CONN = Client Tools Connectivity"
    "IS = Integration Services"
    "BC = Client Tools Backward Compatibility"
    "SDK = Client Tools SDK"
    "BOL = Documentation Components"
    "SSMS = Management Tools -Basic"
    "ADV_SSMS = Management Tools - Complete"
    "DREPLAY_CTLR = Distributed Replay Controller"
    "DREPLAY_CLT = Distributed Replay Client"
    "SNAC_SDK = SQL Client Connectivity SDK"
    "MDS = Master Data Services"
    "*******************************************************************************"
    "Default list includes below components"
    ""
    "SQLENGINE,FULLTEXT,CONN,IS,BC,SSMS,ADV_SSMS,SDK"
    "*******************************************************************************"
    ""
    "Hit Enter to keep default components listed above"
    "If you need to install additional components besides the one listed above"
    "Enter all components including the defaults listed above"
    ""
    if (-not $script:featurelist){ $script:featurelist = Read-Host 'Components [Hit Enter for default or comma separated list eg..SQLENGINE,CONN,IS,BC] ' }
    if (-not $script:featurelist){ $script:featurelist = "SQLENGINE,FULLTEXT,CONN,IS,BC,SSMS,ADV_SSMS,SDK" }
    ""

    if (-not $script:ServiceAccountPassword){
        [System.Security.SecureString] $script:ServiceAccountPassword = Read-Host "Enter the password for ssadmin" -AsSecureString ;
        [String] $script:syncSvcAccountPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:ServiceAccountPassword));
    } else {[String] $script:syncSvcAccountPassword = $script:ServiceAccountPassword; }

    ""
    if (-not $script:saPassword){
        [System.Security.SecureString] $script:saPasswordSec = Read-Host "Enter the sa password" -AsSecureString ;
        [String] $script:saPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:saPasswordSec));
    } else {[String] $script:saPassword = $script:ServiceAccountPassword; }


    # Set Variables Based on SQL Version selected
    if ($edition -eq 'ENTERPRISE'){
    if ($sqlversion -eq '2012'){
        $script:IsoSource = "\\software\SQL_Server\SQL_Server_2012\64-bit\Enterprise_Edition"
        $script:FileName = "en_sql_server_2012_enterprise_edition_with_service_pack_2_x64.iso"
        $script:IsoMountImageName = "SQLServer"
        $script:MsIntVer = "110"
        $script:DirVer = "11"
    }
    if ($sqlversion -eq '2014'){
        $script:IsoSource = "\\software\SQL_Server\SQL_Server_2014\Enterprise_edition"
        $script:FileName = "en_sql_server_2014_enterprise_edition_with_service_pack_1_x64_dvd.iso"
        $script:IsoMountImageName = "SQL2014_x64_ENU"
        $script:MsIntVer = "120"
        $script:DirVer = "12"
    }
    }
    elseif ($edition -eq 'STANDARD'){
    if ($sqlversion -eq '2012'){
        $script:IsoSource = "\\software\SQL_Server\SQL_Server_2012\64-bit\Standard_edition"
        $script:FileName = "en_sql_server_2012_standard_edition_with_service_pack_2_x64_dvd_4692562.iso"
        $script:IsoMountImageName = "SQLServer"
        $script:MsIntVer = "110"
        $script:DirVer = "11"
    }
    if ($sqlversion -eq '2014'){
        $script:IsoSource = "\\software\SQL_Server\SQL_Server_2014\Standard_edition"
        $script:FileName = "en_sql_server_2014_standard_edition_with_service_pack_1_x64_dvd.iso"
        $script:IsoMountImageName = "SQL2014_x64_ENU"
        $script:MsIntVer = "120"
        $script:DirVer = "12"
    }
    }
    elseif ($edition -eq 'CORE'){
    if ($sqlversion -eq '2014'){
        $script:IsoSource = "\\software\SQL_Server\SQL_Server_2014\Enterprise_core_edition"
        $script:FileName = "en_sql_server_2014_enterprise_core_edition_with_service_pack_1_x64_dvd.iso"
        $script:IsoMountImageName = "SQL2014_x64_ENU"
        $script:MsIntVer = "120"
        $script:DirVer = "12"
    }
    }
    # change INSTANCE name to upper case
    $script:instance = $instance.ToUpper()
    $script:hostName = get-content env:computername

    # Derive an SQL instance name based of if it either default instance or named instance
    if ($instance -eq "MSSQLSERVER")
    { $script:instanceName = "$hostName" }
    else {
        $script:instanceName = "$hostName\$instance"
    }
}

############################################
# Function to copy ISO file and 2 SQL files
############################################
function copyiso{
    "Copying SQL Server Image file from \\software To Localhost(downloads dir) ......."
    robocopy $IsoSource C:\Users\ssadmin\Downloads $FileName /NP
    robocopy \\software\SQLServer\AutomaticIndexRebuild C:\Users\ssadmin\Downloads index_defrag.sql /NP
    robocopy \\software\SQLServer\AutomaticIndexRebuild C:\Users\ssadmin\Downloads AutomaticIndexRebuildJob.sql /NP
    robocopy \\software\SQLServer\AutomaticIndexRebuild C:\Users\ssadmin\Downloads mon_user.sql /NP

    #Check to see if file exist
    if (Test-Path C:\Users\ssadmin\Downloads\$FileName)
    { "File has been copied over to localhost...";
        "Mounting ISO File...";
        Mount-DiskImage -ImagePath C:\Users\ssadmin\downloads\$FileName
    }
    else
    {
        "###############################################################";
        "  Encountered some error during copy, Please investigate....";
        "###############################################################";
        # Dismounting ISO file
        Get-Volume | where { $_.FileSystemLabel -eq $IsoMountImageName } | Get-DiskImage | Dismount-DiskImage
        exit
    }
}

############################################
# Function to prep ini files for SQL install
############################################
function prepini([String] $instance, [String] $collation){
    $inifile = "[OPTIONS]
ACTION=""Install""
ENU=""True""
QUIETSIMPLE=""True""
UpdateEnabled=""True""
ERRORREPORTING=""False""
FEATURES=$featurelist
UpdateSource=""MU""
HELP=""False""
INDICATEPROGRESS=""False""
X86=""False""
INSTALLSHAREDDIR=""D:\Program Files\Microsoft SQL Server""
INSTALLSHAREDWOWDIR=""D:\Program Files (x86)\Microsoft SQL Server""
INSTANCEDIR=""D:\Program Files\Microsoft SQL Server""
INSTANCENAME=""$instance""
INSTANCEID=""$instance""
SQMREPORTING=""False""
AGTSVCACCOUNT=""US\ssadmin""
AGTSVCSTARTUPTYPE=""Automatic""
ISSVCSTARTUPTYPE=""Automatic""
ISSVCACCOUNT=""US\ssadmin""
COMMFABRICPORT=""0""
COMMFABRICNETWORKLEVEL=""0""
COMMFABRICENCRYPTION=""0""
MATRIXCMBRICKCOMMPORT=""0""
SQLSVCSTARTUPTYPE=""Automatic""
FILESTREAMLEVEL=""0""
ENABLERANU=""False""
SQLCOLLATION=""$collation""
SQLSVCACCOUNT=""US\ssadmin""
SQLSYSADMINACCOUNTS=""US\ssadmin"" ""US\DBATEAM""
SECURITYMODE=""SQL""
INSTALLSQLDATADIR=""E:\SQL_DATA""
SQLUSERDBDIR=""E:\SQL_DATA\MSSQL$DirVer." + $instance + "\Data""
SQLUSERDBLOGDIR=""L:\SQL_LOGS\MSSQL$DirVer." + $instance + "\Logs""
SQLTEMPDBDIR=""T:\SQL_TEMP\MSSQL$DirVer." + $instance + "\Data""
SQLTEMPDBLOGDIR=""L:\SQL_LOGS\MSSQL$DirVer." + $instance + "\Logs""
ADDCURRENTUSERASSQLADMIN=""False""
TCPENABLED=""1""
NPENABLED=""0""
BROWSERSVCSTARTUPTYPE=""Automatic""
FTSVCACCOUNT=""US\ssadmin""
IACCEPTSQLSERVERLICENSETERMS=""True"""
    $inifile
}

#######################################################################
# Function to start SQL install, which in turn calls prepini function
#######################################################################
function sql_install{
    ""
    "Creating Ini File for Installation..."
    $configIniFile = "$workDir\$sqlversion" + $instance + "_install.ini"

    prepini $instance $collation | Out-File $configIniFile

    "SQL Server Install Configuration File written to: " + $configIniFile

    # Get the driver letter name that has the ISO mounted, as we cannot assume F drive letter will always mount ISO
    $dl = (Get-Volume | where { $_.FileSystemLabel -eq $IsoMountImageName } | select -expand DriveLetter)
    $St = "setup.exe"
    $setupcmd = "$dl" + ":\" + "$st"

    ""
    "Starting SQL $sqlversion Base Installation..."
    ""

    $startinstall = "$setupcmd /SQLSVCPASSWORD=""$syncSvcAccountPassword"" /AGTSVCPASSWORD=""$syncSvcAccountPassword"" /ISSVCPASSWORD=""$syncSvcAccountPassword"" /SAPWD=""$saPassword"" /ConfigurationFile=""$configIniFile"""

    Invoke-Expression $startinstall
}

##################################################################
# Function to register SQL Server SNAPIN
# Starting SQL Server 2012, you have to manually register snapin
# Also Load Assembly for SMO to work
##################################################################
function reg_sqlsnap{
    if ((Get-PSSnapin -Registered -Name sqlserverprovidersnapin$MsIntVer -ErrorAction SilentlyContinue) -eq $null)
    {
        set-alias installutil $env:windir\microsoft.net\Framework64\v4.0.30319\installutil
        installutil "D:\Program Files (x86)\Microsoft SQL Server\$MsIntVer\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll" | out-null
        installutil "D:\Program Files (x86)\Microsoft SQL Server\$MsIntVer\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll" | out-null
        #"Below are the registered SNAPIN"
        #get-PSSnapin -registered
        add-PSSnapin SqlServerProviderSnapin$MsIntVer
        add-PSSnapin SqlServerCmdletSnapin$MsIntVer
        ## Load assembly
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo.Extended") | out-null
    }
    else
    {
        #"No Need to install SQL Server SNAPIN, Below are the registered SNAPIN"
        #get-PSSnapin -registered
        ## Load assembly
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo.Extended") | out-null
    }
}

######################################################################
# Function to get some basic SQL Server info like version and DB name
######################################################################
function get_sql_info{
    reg_sqlsnap
    Add-PSSnapin sqlserver*$MsIntVer
    Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query "SELECT @@SERVERNAME Instance_name, SERVERPROPERTY('productversion') Version, SERVERPROPERTY ('productlevel') SP_Level, SERVERPROPERTY ('edition') Edition" | Format-Table -AutoSize
    Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query 'select name, recovery_model_desc from sys.databases' | Format-Table -AutoSize
}

# # Can also do below which uses SMO - Shared Management Object
# function get_sql_info2{
# reg_sqlsnap
# Add-PSSnapin sqlserver*$MsIntVer
# if ($instance -eq "MSSQLSERVER")
# {
# $server = Get-Item SQLSERVER:\sql\$hostname\default
# }
# else {
# $server = Get-Item SQLSERVER:\sql\$instanceName
# }
# $server | Format-Table DisplayName,VersionMajor, VersionString, Collation -auto
# }
###########################################################
# Function to change SQL Server Max Memory, which uses SMO
# and hence call reg_sqlsnap function
###########################################################
function change_mem{
    reg_sqlsnap
    ## MEM changes, setting min value of 500 and Max of whatever is provided
    ## Load assembly -- Dependent
    "changing Max Memory for Instance $instanceName to $maxmem MB"
    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $instanceName
    $server.Configuration.MinServerMemory.ConfigValue = 500
    $server.Configuration.MaxServerMemory.ConfigValue = $maxmem
    $server.Configuration.Alter()
}

##########################################################
# Function to change TempDB size based on number of cores
##########################################################
function add_tempfile{
    reg_sqlsnap
    $procs = Get-WmiObject Win32_Processor
    $totalCores = 0

    #count the total number of cores across all processors
    foreach ($proc in $procs)
    {
        $totalCores = $totalCores + $proc.NumberOfCores
    }
    # Set Max limit of 8 files, no matter how many CPU are on the Box,
    # As team decided to cap of max number of tempfile to 8
    if ($totalCores -gt 8)
    {
        $totalCores = 8
    }

    "Total Number of TempDB file being added = $totalCores to $instanceName"
    $Connection = New-Object System.Data.SQLClient.SQLConnection

    $Connection.ConnectionString = "Server=$instanceName;Database=master;uid=sa;Pwd=$saPassword;"
    $Connection.Open()

    $Command = New-Object System.Data.SQLClient.SQLCommand
    $Command.Connection = $Connection

    $Command.CommandText = "ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, SIZE = 1024MB, filegrowth = 10%, maxsize=unlimited);"
    $Command.ExecuteNonQuery() | out-null
    $Command.CommandText = "ALTER DATABASE tempdb MODIFY FILE (NAME = templog, SIZE = 512MB, filegrowth = 10%, maxsize=unlimited);"
    $Command.ExecuteNonQuery() | out-null

    for ($i = 2; $i -le $totalCores; $i++)
    {
        $Command.CommandText = "ALTER DATABASE tempdb ADD FILE (NAME = tempdev$i, FILENAME = 'T:\SQL_TEMP\MSSQL$DirVer."+$instance +"\Data\tempdb$i.ndf', SIZE = 1024MB, filegrowth = 10%, maxsize=unlimited);"
        $Command.ExecuteNonQuery() | out-null
    }

    $Connection.Close()
}

################################################
# Function to get rid of dynamic port(index 0)
# And add Static port, if this is default instance
# Enable Named Pipes when port is set to static
# and Default instance name(MSSQLSERVER)
################################################
function change_tcp_port{
    reg_sqlsnap
    "Changing TCP port to $port"
    if ($instance -eq "MSSQLSERVER")
    {
    # Enable Named pipes
    $smo = 'Microsoft.SqlServer.Management.Smo.'
    $wmi = new-object ($smo + 'Wmi.ManagedComputer')
    $uri = "ManagedComputer[@Name='$hostName']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Np']"
    "Enabling Named Pipes for the SQL Service Instance on $instance"
    $Np = $wmi.GetSmoObject($uri)
    $Np.IsEnabled = $true
    $Np.Alter()
    # Change to static port
    $smo = 'Microsoft.SqlServer.Management.Smo.'
    $wmi = new-object ($smo + 'Wmi.ManagedComputer')
    $uri = "ManagedComputer[@Name='$hostName']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
    $Tcp = $wmi.GetSmoObject($uri)
    # Disable dynamic port
    $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties[0].Value = ""
    # Set Static port
    $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value = "$port"
    $Tcp.Alter()
    "Below are the TCP Port setting after changes"
    # Check TCP Port setting after changes
    $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties | select name, value | Format-Table -AutoSize
    }
    else
    {
    # Change to static port, No need to enable Named pipe for NAMED instance
    $smo = 'Microsoft.SqlServer.Management.Smo.'
    $wmi = new-object ($smo + 'Wmi.ManagedComputer')
    $uri = "ManagedComputer[@Name='$hostName']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
    $Tcp = $wmi.GetSmoObject($uri)
    # Disable dynamic port
    $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties[0].Value = ""
    # Set Static port
    $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value = "$port"
    $Tcp.Alter()
    "Below are the TCP Port setting after changes"
    # Check TCP Port setting after changes
    $wmi.GetSmoObject($uri + "/IPAddress[@Name='IPAll']").IPAddressProperties | select name, value | Format-Table -AutoSize
    }
}

########################################################
# Function to change multiple things like
# - Change recovery model to SIMPLE
# - Change Model mdf file to 10MB and auto growth of 250MB
# - Change Model ldf file to 10MB and auto growth of 100MB
# - Change number of logs to be kept for SQL SERVER
# - Create DBA_management databases
# - Create Monitoruser account
# - create index defrag stored procedure
# - Schedule SQL Server Agent Job
########################################################
function chng_recovery_logs_index_job{
    reg_sqlsnap
    Add-PSSnapin sqlserver*$MsIntVer
    if ((Test-Path C:\Users\ssadmin\Downloads\AutomaticIndexRebuildJob.sql) -and (Test-Path C:\Users\ssadmin\Downloads\index_defrag.sql) -and (Test-Path C:\Users\ssadmin\Downloads\mon_user.sql))
    {
        "Changing Recovery Model to SIMPLE"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query 'ALTER DATABASE [model] SET RECOVERY SIMPLE WITH NO_WAIT'
        "Changing Model Database mdf file to 10MB and auto growth of 250MB"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query "ALTER DATABASE [model] MODIFY FILE ( NAME = N'modeldev', SIZE = 10MB , FILEGROWTH = 250MB )"
        "Changing Model Database ldf file to 10MB and auto growth of 100MB"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query "ALTER DATABASE [model] MODIFY FILE ( NAME = N'modellog', SIZE = 10MB , FILEGROWTH = 100MB )"
        "Changing Logs retention to 30 logs"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD, 30"
        "Creating database DBA_management"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database master –Query 'CREATE DATABASE [DBA_management]'
        "Creating Kmonitor00 user account...."
        Invoke-Sqlcmd -ServerInstance $instanceName -Database master -InputFile C:\Users\ssadmin\Downloads\mon_user.sql
        "Creating index defrag stored procedure"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database DBA_management -InputFile C:\Users\ssadmin\Downloads\index_defrag.sql
        "Creating SQL AGENT Job for Index rebuild"
        Invoke-Sqlcmd -ServerInstance $instanceName -Database msdb -InputFile C:\Users\ssadmin\Downloads\AutomaticIndexRebuildJob.sql | out-null
    }
    else
    {
        "#########################################################################################################################";
        "  AutomaticIndexRebuildJob.sql/index_defrag.sql/mon_user.sql file is missing, Please investigate....";
        "#########################################################################################################################";
        exit
    }
}

##################################
# Function to restart SQL Server
##################################
function restart_sql{
    if ($instance -eq "MSSQLSERVER")
    {
        $serviceName = "MSSQLSERVER"
        $agentName = "SQLSERVERAGENT"
    }
    else
    {
        $serviceName = "MSSQL`$$instance"
        $agentName = "SQLAgent`$$instance"
    }
    # Have to use force, so the dependent service(sql agent) restart as well
    "stopping sql server service $servicename and agent..."
    get-service -Name $serviceName | stop-service -force
    "starting sql server service $servicename..."
    get-service -Name $serviceName | start-service
    "starting sql server agent $servicename..."
    get-service -Name $agentName | start-service
}

###########################################################################
###########################################################################
#
#              Oo      oO    Oo    ooOoOOo o.     O
#              O O    o o   o  O      O    Oo     o
#              o  o  O  O  O    o     o    O O    O
#              O   Oo   O oOooOoOo    O    O  o   o
#              O        o o      O    o    O   o  O
#              o        O O      o    O    o    O O
#              o        O o      O    O    o     Oo
#              O        o O.     O ooOOoOo O     `o
#
###########################################################################
###########################################################################
# BELOW IS MAIN TRY/CATCH/FINALLY BLOCK AND ALL FUNCTIONS ARE CALLED HERE #
###########################################################################
###########################################################################

try {
    "Running pre_check function"
    pre_check
    ""
    "Running get_parameters function"
    get_parameters
    "start time......"
    (get-date).datetime
    ""
    "Running copyiso function"
    copyiso
    ""
    $workDir = pwd

    "Running sql_install function"
    sql_install

    set-location $workDir

    ""
    "Getting SQL Server version info"
    get_sql_info
    ""
    "Running Change_mem function"
    change_mem
    ""
    "Running add_tempfile function"
    add_tempfile
    ""
    "Running change_tcp_port function"
    change_tcp_port
    ""
    "Running chng_recovery_logs_index_job function"
    chng_recovery_logs_index_job
    ""
    "Restarting SQL related services....."
    restart_sql
    ""
    #delete ISO file
    Get-Volume | where { $_.FileSystemLabel -eq $IsoMountImageName } | Get-DiskImage | Dismount-DiskImage
    Remove-Item C:\Users\ssadmin\Downloads\$FileName
    Remove-Item C:\Users\ssadmin\Downloads\AutomaticIndexRebuildJob.sql
    Remove-Item C:\Users\ssadmin\Downloads\index_defrag.sql
    Remove-Item C:\Users\ssadmin\Downloads\mon_user.sql
    "Getting SQL Server version info"
    get_sql_info
    "end time......"
    (get-date).datetime
}
catch
{
    Write-Host -ForegroundColor DarkYellow ""
    Write-Host -ForegroundColor DarkYellow "Errors Encountered....."
    Write-Host -ForegroundColor DarkYellow ""
    Write-Host -ForegroundColor Magenta write-error $error[0]
    exit
}
finally
{
    # Dismount Image not matter what the out come is, so we do not have multiple mounts(if same script ran again)
    Get-Volume | where { $_.FileSystemLabel -eq $IsoMountImageName } | Get-DiskImage | Dismount-DiskImage
}