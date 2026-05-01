# Run from the folder that contains the .partXXXofYYY files
$out = "1GB.bin"
$parts = Get-ChildItem -Filter "1GB.bin.part*" | Sort-Object Name
$fs = [IO.File]::OpenWrite($out)
foreach ($p in $parts) {
    $b = [IO.File]::ReadAllBytes($p.FullName)
    $fs.Write($b, 0, $b.Length)
}
$fs.Close()
Write-Host "Done: $out"
