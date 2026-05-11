# Kistler Faceplate Screen Type creator - TIA Portal V20 Openness
# Uses assembly resolver to handle missing HMI DLL dependencies

$apiDir = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20"

# Register assembly resolver so TIA can find its own dependencies
$resolverCode = @'
using System;
using System.Reflection;
using System.IO;
public class TiaResolver {
    public static void Register(string baseDir) {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) => {
            string name = new AssemblyName(e.Name).Name + ".dll";
            string path = Path.Combine(baseDir, name);
            if (File.Exists(path)) return Assembly.LoadFrom(path);
            // Also search TIA binary dir
            string bin = @"C:\Program Files\Siemens\Automation\Portal V20\bin";
            string p2 = Path.Combine(bin, name);
            if (File.Exists(p2)) return Assembly.LoadFrom(p2);
            return null;
        };
    }
}
'@
Add-Type -TypeDefinition $resolverCode
[TiaResolver]::Register($apiDir)

# Now load assemblies
Write-Host "Loading Siemens.Engineering.dll..."
Add-Type -Path "$apiDir\Siemens.Engineering.dll" -ErrorAction SilentlyContinue
Write-Host "Loading Siemens.Engineering.Hmi.dll..."
Add-Type -Path "$apiDir\Siemens.Engineering.Hmi.dll" -ErrorAction SilentlyContinue

# Attach to running TIA Portal
Write-Host "Attaching to TIA Portal..."
$processes = [Siemens.Engineering.TiaPortal]::GetProcesses()
if ($processes.Count -eq 0) { throw "No TIA Portal process found." }
$tia = $processes[0].Attach()
Write-Host "  Attached to PID $($processes[0].Id)"

# Get project
$project = $null
if ($tia.LocalSessions.Count -gt 0) {
    $project = $tia.LocalSessions[0].Project
} else {
    $project = $tia.Projects[0]
}
Write-Host "  Project: $($project.Name)"

# Find WinCC Unified HMI software
Write-Host "Finding WinCC Unified HMI device..."
$hmiSoft = $null
$hmiDeviceName = ""

foreach ($device in $project.Devices) {
    foreach ($item in $device.DeviceItems) {
        try {
            $sc = $item.GetService([Siemens.Engineering.HW.Software.SoftwareContainer])
            if ($sc -ne $null) {
                $soft = $sc.Software
                $typeName = $soft.GetType().FullName
                Write-Host "  Software found in '$($device.Name)/$($item.Name)': $typeName"
                # Accept any HMI Unified software
                if ($typeName -like "*HmiSoftware*" -or $typeName -like "*Unified*") {
                    $hmiSoft = $soft
                    $hmiDeviceName = $device.Name
                    break
                }
            }
        } catch {}
    }
    if ($hmiSoft -ne $null) { break }
}

if ($hmiSoft -eq $null) {
    Write-Warning "No WinCC Unified HMI software found via GetService. Trying HMI_RT items directly..."
    foreach ($device in $project.Devices) {
        if ($device.Name -notlike "*HMI*" -and $device.Name -notlike "*TOOL*") { continue }
        foreach ($item in $device.DeviceItems) {
            if ($item.Name -notlike "HMI_RT*") { continue }
            Write-Host "  Trying $($device.Name)/$($item.Name)..."
            try {
                $sc = $item.GetService([Siemens.Engineering.HW.Software.SoftwareContainer])
                if ($sc -ne $null) {
                    $soft = $sc.Software
                    Write-Host "    Type: $($soft.GetType().FullName)"
                    $hmiSoft = $soft
                    $hmiDeviceName = $device.Name
                    break
                }
            } catch { Write-Host "    Error: $_" }
        }
        if ($hmiSoft -ne $null) { break }
    }
}

if ($hmiSoft -eq $null) { throw "Cannot find WinCC Unified HMI software in project." }
Write-Host "  Using HMI device: $hmiDeviceName"
Write-Host "  HMI type: $($hmiSoft.GetType().FullName)"

# List available members on the HMI software object
Write-Host ""
Write-Host "HMI Software members:"
$hmiSoft.GetType().GetMembers() | ForEach-Object { Write-Host "  $($_.MemberType.ToString().PadRight(12)) $($_.Name)" } | Sort-Object

Write-Host ""
Write-Host "Probe complete."
