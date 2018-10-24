$p = Resolve-Path ".\AirlineTestDB.bak"
Restore-SqlDatabase -ServerInstance "localhost\\SQL2017" -Database "AirlineTestDB" -BackupFile $p