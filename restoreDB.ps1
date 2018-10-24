$p = Resolve-Path ".\AirlineTestDB.bak"
Restore-SqlDatabase -ServerInstance $Env:SERVER -Database "AirlineTestDB" -BackupFile $p