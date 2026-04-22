param(
    [Parameter(Mandatory)][string]$SclPath
)

# Fast static checks for SCL text before import.
# - Non-ASCII characters (common encoding corruption in TIA imports)
# - Reserved keyword collisions for declared identifiers

$ErrorActionPreference = "Stop"

$resolved = [System.IO.Path]::GetFullPath($SclPath)
if (-not (Test-Path $resolved)) {
    Write-Error "SCL file not found: $resolved"
    exit 1
}

$text = Get-Content $resolved -Raw
$lines = Get-Content $resolved

$reserved = @(
    'IF','THEN','ELSIF','ELSE','END_IF','CASE','OF','END_CASE',
    'FOR','TO','BY','DO','END_FOR','WHILE','END_WHILE','REPEAT','UNTIL','END_REPEAT',
    'CONTINUE','EXIT','RETURN','AND','OR','XOR','NOT','MOD','DIV',
    'FUNCTION','FUNCTION_BLOCK','ORGANIZATION_BLOCK','END_FUNCTION','END_FUNCTION_BLOCK','END_ORGANIZATION_BLOCK',
    'TYPE','END_TYPE','STRUCT','END_STRUCT','ARRAY','AT','VAR','VAR_INPUT','VAR_OUTPUT','VAR_IN_OUT','VAR_TEMP','VAR_STAT','END_VAR','BEGIN',
    'TRUE','FALSE','NULL','BOOL','BYTE','WORD','DWORD','LWORD','INT','DINT','LINT','UINT','UDINT','ULINT','SINT','USINT','REAL','LREAL',
    'TIME','LTIME','DATE','TIME_OF_DAY','TOD','DATE_AND_TIME','DT','CHAR','WCHAR','STRING','WSTRING',
    'IN','OUT','INOUT','VOID','ANY','POINTER','REF'
)
$reservedSet = @{}
foreach ($r in $reserved) { $reservedSet[$r] = $true }

$result = [ordered]@{
    FilePath = $resolved
    State    = "Success"
    Errors   = 0
    Warnings = 0
    Findings = @()
}

# 1) Non-ASCII scan with line/column context
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    for ($j = 0; $j -lt $line.Length; $j++) {
        $code = [int][char]$line[$j]
        if ($code -gt 127) {
            $result.Findings += [ordered]@{
                Severity = "Error"
                Rule     = "non_ascii"
                Line     = $i + 1
                Column   = $j + 1
                Message  = "Non-ASCII character U+$('{0:X4}' -f $code) found. Use ASCII equivalent."
            }
            $result.Errors++
        }
    }
}

# 2) Identifier declarations only: Name : Type
#    Ignore formal/assignment forms like IN := ...
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?![=])') {
        $name = $Matches[1]
        $upper = $name.ToUpperInvariant()
        if ($reservedSet.ContainsKey($upper)) {
            $result.Findings += [ordered]@{
                Severity = "Error"
                Rule     = "reserved_identifier"
                Line     = $i + 1
                Column   = ($line.IndexOf($name) + 1)
                Message  = "Identifier '$name' is a reserved keyword in IEC/TIA SCL. Rename it."
            }
            $result.Errors++
        }
    }
}

if ($result.Errors -gt 0) {
    $result.State = "Error"
}

$result | ConvertTo-Json -Depth 8

if ($result.Errors -gt 0) { exit 1 }
