$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host "PARSE ERRORS:"
    $errors | ForEach-Object { Write-Host ("  Line $($_.Extent.StartLine): $($_.Message)") }
} else {
    Write-Host "PARSE OK"
}
