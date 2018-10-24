$p = Resolve-Path ".\AirlineTestDB.bak"
$p
$Server = $Env:SERVER
Restore-SqlDatabase -ServerInstance $Server -Database "AirlineTestDB" -BackupFile $p