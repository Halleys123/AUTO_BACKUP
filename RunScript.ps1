$jobs = @()
$jobs += Start-Job -ScriptBlock { E:\AUTO_BACKUP\SmartJunctionSync.ps1 -SourceRoot E:\Projects -DestRoot C:\Users\arnav\OneDrive\Projects -ExcludeFile E:\AUTO_BACKUP\excludes.txt }
$jobs += Start-Job -ScriptBlock { E:\AUTO_BACKUP\SmartJunctionSync.ps1 -SourceRoot E:\Books -DestRoot C:\Users\arnav\OneDrive\Books -ExcludeFile E:\AUTO_BACKUP\excludes.txt }
$jobs += Start-Job -ScriptBlock { E:\AUTO_BACKUP\SmartJunctionSync.ps1 -SourceRoot E:\Documents -DestRoot C:\Users\arnav\OneDrive\MoreDocuments -ExcludeFile E:\AUTO_BACKUP\excludes.txt }
$jobs += Start-Job -ScriptBlock { E:\AUTO_BACKUP\SmartJunctionSync.ps1 -SourceRoot E:\Music -DestRoot C:\Users\arnav\OneDrive\MyMusic -ExcludeFile E:\AUTO_BACKUP\excludes.txt }

$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job