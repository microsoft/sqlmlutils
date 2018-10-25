$sqlInstance = $Env:SERVER
$dbPath = Resolve-Path ".\AirlineTestDB.bak"
sqlcmd -S "$sqlInstance" -Q "RESTORE DATABASE AirlineTestDB FROM DISK = '$dbPath' WITH REPLACE"