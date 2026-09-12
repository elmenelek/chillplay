param()

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
try { [Console]::CursorVisible = $false } catch {}

$Width      = 60
$ArtHeight  = 11
$EqHeight   = 6
$TickMs     = 80

$Vibes = @(
    @{ Key="1"; Name="Chill";     Station="Groove Salad";    Desc="chilled ambient / downtempo";  Url="https://ice1.somafm.com/groovesalad-128-mp3" },
    @{ Key="2"; Name="Relaxing";  Station="Illstreet";       Desc="chill lounge / downtempo";     Url="https://ice1.somafm.com/illstreet-128-mp3" },
    @{ Key="3"; Name="Calming";   Station="Deep Space One";  Desc="deep ambient soundscapes";     Url="https://ice1.somafm.com/deepspaceone-128-mp3" },
    @{ Key="4"; Name="Dreamy";    Station="Lush";            Desc="mellow vocal chillout";        Url="https://ice1.somafm.com/lush-128-mp3" },
    @{ Key="5"; Name="Retro";     Station="Secret Agent";    Desc="spy jazz & exotica lounge";    Url="https://ice1.somafm.com/secretagent-128-mp3" },
    @{ Key="6"; Name="Vaporwave"; Station="Vaporwaves";      Desc="nostalgic dreamwave";          Url="https://ice1.somafm.com/vaporwaves-128-mp3" },
    @{ Key="7"; Name="Space";     Station="Space Station";   Desc="ambient space electronica";    Url="https://ice1.somafm.com/spacestation-128-mp3" },
    @{ Key="8"; Name="Drone";     Station="Drone Zone";      Desc="deep atmospheric drones";      Url="https://ice1.somafm.com/dronezone-128-mp3" },
    @{ Key="9"; Name="Rave";      Station="Beat Blender";    Desc="deep house / broken beat";     Url="https://ice1.somafm.com/beatblender-128-mp3" },
    @{ Key="0"; Name="Trance";    Station="The Trip";        Desc="psychedelic beats & trance";   Url="https://ice1.somafm.com/thetrip-128-mp3" }
)

$Themes = @("coffee", "rain", "hacker", "cyberpunk")
$GitHubUrl = "https://github.com/elmenelek"

$mpv = Get-Command mpv -ErrorAction SilentlyContinue
if (-not $mpv) {
    Write-Host "mpv not found on PATH. Install it with: scoop install mpv" -ForegroundColor Red
    exit 1
}

$mpvExe = $mpv.Source
if ($mpvExe -like '*mpv.com') {
    $candidate = $mpvExe -replace 'mpv\.com$', 'mpv.exe'
    if (Test-Path $candidate) { $mpvExe = $candidate }
}

$jobSource = @'
using System;
using System.Runtime.InteropServices;

public class ChillPlayJob
{
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public UIntPtr Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    const int JobObjectExtendedLimitInformation = 9;
    const UInt32 JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr a, string lpName);

    [DllImport("kernel32.dll")]
    static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    IntPtr handle;

    public ChillPlayJob()
    {
        handle = CreateJobObject(IntPtr.Zero, null);

        var info = new JOBOBJECT_BASIC_LIMIT_INFORMATION();
        info.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

        var extendedInfo = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        extendedInfo.BasicLimitInformation = info;

        int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr extendedInfoPtr = Marshal.AllocHGlobal(length);
        Marshal.StructureToPtr(extendedInfo, extendedInfoPtr, false);

        SetInformationJobObject(handle, JobObjectExtendedLimitInformation, extendedInfoPtr, (uint)length);
        Marshal.FreeHGlobal(extendedInfoPtr);
    }

    public bool AddProcess(IntPtr processHandle)
    {
        return AssignProcessToJobObject(handle, processHandle);
    }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'ChillPlayJob').Type) {
    Add-Type -TypeDefinition $jobSource -Language CSharp
}
$script:job = New-Object ChillPlayJob

$script:proc         = $null
$script:vibe         = $Vibes[0]
$script:theme        = "coffee"
$script:notice       = ""
$script:focusEndTime = $null
$script:timesUp      = $false

function Stop-Vibe {
    if ($script:proc) {
        try {
            Get-CimInstance Win32_Process -Filter "ParentProcessId=$($script:proc.Id)" -ErrorAction SilentlyContinue |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch {}
        if (-not $script:proc.HasExited) {
            Stop-Process -Id $script:proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    try {
        Get-CimInstance Win32_Process -Filter "Name='mpv.exe' OR Name='mpv.com'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*somafm.com*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Start-Vibe {
    param($vibe)
    Stop-Vibe
    $script:proc = Start-Process -FilePath $mpvExe `
        -ArgumentList @("--no-video", "--really-quiet", "--volume=70", $vibe.Url) `
        -WindowStyle Hidden -PassThru
    $script:job.AddProcess($script:proc.Handle) | Out-Null
    $script:vibe = $vibe
    $script:notice = "Now playing: $($vibe.Name) - $($vibe.Station)"
}

Start-Vibe -vibe $script:vibe

function Seg { param($Text, $Color = "Gray") ,@{ Text = $Text; Color = $Color } }

function Write-Row {
    param([array]$Segments)
    $len = 0
    foreach ($s in $Segments) {
        Write-Host -NoNewline -ForegroundColor $s.Color $s.Text
        $len += $s.Text.Length
    }
    if ($len -lt $Width) {
        Write-Host -NoNewline (" " * ($Width - $len))
    }
    Write-Host ""
}

function New-RainState {
    param([int]$Cols)
    $state = @()
    for ($i = 0; $i -lt $Cols; $i++) {
        $state += [PSCustomObject]@{
            Row     = Get-Random -Minimum -20 -Maximum 0
            Length  = Get-Random -Minimum 3 -Maximum 9
            Speed   = Get-Random -Minimum 1 -Maximum 4
            Counter = Get-Random -Minimum 0 -Maximum 3
        }
    }
    return $state
}

function Step-RainState {
    param($State, [int]$Height)
    foreach ($col in $State) {
        $col.Counter++
        if ($col.Counter -ge $col.Speed) {
            $col.Counter = 0
            $col.Row++
        }
        if (($col.Row - $col.Length) -gt $Height) {
            $col.Row     = Get-Random -Minimum -8 -Maximum 0
            $col.Length  = Get-Random -Minimum 3 -Maximum 9
            $col.Speed   = Get-Random -Minimum 1 -Maximum 4
            $col.Counter = 0
        }
    }
}

$hackerChars = @()
$hackerChars += [char[]]"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
for ($cp = 0x4E00; $cp -le 0x4E40; $cp++) { $hackerChars += [char]$cp }

$rainChars = @('|', '.', ':', "'")

function Get-RandomChar { param($set) $set[$rand.Next(0, $set.Count)] }

function Render-RainRows {
    param($State, [int]$Height, [char[]]$Charset, [string]$HeadColor, [string]$TailColor, [string]$BlankColor = "Gray")
    $rows = @()
    for ($r = 0; $r -lt $Height; $r++) {
        $segments = @()
        $curClass = $null
        $buf = New-Object System.Text.StringBuilder
        for ($c = 0; $c -lt $State.Count; $c++) {
            $col = $State[$c]
            $inTrail = ($r -le $col.Row) -and ($r -gt ($col.Row - $col.Length))
            if ($inTrail) {
                $class = if ($r -eq $col.Row) { "head" } else { "tail" }
                $ch = Get-RandomChar $Charset
            } else {
                $class = "blank"
                $ch = ' '
            }
            if ($class -ne $curClass) {
                if ($curClass -ne $null) {
                    $color = switch ($curClass) { "head" { $HeadColor } "tail" { $TailColor } default { $BlankColor } }
                    $segments += Seg $buf.ToString() $color
                }
                $buf = New-Object System.Text.StringBuilder
                $curClass = $class
            }
            [void]$buf.Append($ch)
        }
        if ($buf.Length -gt 0) {
            $color = switch ($curClass) { "head" { $HeadColor } "tail" { $TailColor } default { $BlankColor } }
            $segments += Seg $buf.ToString() $color
        }
        $rows += ,$segments
    }
    return $rows
}

$rand = New-Object System.Random
$script:hackerState = New-RainState -Cols $Width
$script:rainState   = New-RainState -Cols $Width

$steamTemplates = @(
    "     (  )   (   )  )        (  )   (   )  )    ",
    "      ) (   )  (  (          ) (   )  (  (     ",
    "      ( )  (    ) )          ( )  (    ) )     "
)
$cupBody = @(
"         _____________",
"        <_____________> ___",
"        |             |/ _ \",
"        |               | | |",
"        |               |_| |",
"     ___|             |\___/",
"    /    \___________/    \",
"    \_____________________/"
)

function Render-CoffeeRows {
    param([int]$Tick)
    $rows = @()
    for ($i = 0; $i -lt $steamTemplates.Count; $i++) {
        $tpl = $steamTemplates[$i]
        $half = [int]($tpl.Length / 2)
        $speed = 1 + $i
        $offset = [Math]::Floor($Tick / $speed) % $half
        $window = $tpl.Substring($offset, $half)
        $rows += ,@(Seg "     $window" "Yellow")
    }
    foreach ($line in $cupBody) {
        $rows += ,@(Seg "     $line" "Yellow")
    }
    return $rows
}

function Render-CyberpunkRows {
    param([int]$Tick)
    $rows = @()
    $rows += ,@(Seg "                .--=====--.                 " "Magenta")
    $rows += ,@(Seg "              .'   -----   '.               " "Magenta")
    $rows += ,@(Seg "             /    -------    \              " "Magenta")
    $rows += ,@(Seg "             \_______________/              " "DarkMagenta")
    $rows += ,@(Seg "   \|/                             \|/      " "DarkMagenta")
    $rows += ,@(Seg "    |                               |       " "DarkMagenta")
    $rows += ,@(Seg "   /|\                             /|\      " "DarkMagenta")
    $rows += ,@(Seg "              .--------.                    " "Magenta")
    $rows += ,@(Seg "             /__________\                   " "Magenta")
    $rows += ,@(Seg "              o        o                    " "DarkGray")

    $gridTemplate = ("--/\-" * 30)
    $offset = $Tick % 5
    $window = $gridTemplate.Substring($offset, [Math]::Min($Width - 3, $gridTemplate.Length - $offset))
    $rows += ,@(Seg $window "Cyan")

    return $rows
}

function Get-ThemeRows {
    param([string]$Theme, [int]$Tick)
    switch ($Theme) {
        "coffee" { return Render-CoffeeRows -Tick $Tick }
        "rain" {
            Step-RainState -State $script:rainState -Height ($ArtHeight - 4)
            $cloud = @(
                "            .--.    .-.",
                "         .-(    ).-(   ).--.",
                "        (___.__)____.__)__)"
            )
            $rows = @()
            foreach ($line in $cloud) { $rows += ,@(Seg $line "DarkGray") }
            $rain = Render-RainRows -State $script:rainState -Height ($ArtHeight - 4) -Charset $rainChars -HeadColor "Cyan" -TailColor "DarkBlue"
            $rows += $rain
            $rows += ,@(Seg "" "Gray")
            return $rows
        }
        "hacker" {
            Step-RainState -State $script:hackerState -Height $ArtHeight
            return Render-RainRows -State $script:hackerState -Height $ArtHeight -Charset $hackerChars -HeadColor "Green" -TailColor "DarkGreen"
        }
        "cyberpunk" { return Render-CyberpunkRows -Tick $Tick }
    }
}

$bars = @(3,5,2,6,4,7,3,5,6,2,4,3,5,7,2)

function Render-EqualizerRows {
    for ($i = 0; $i -lt $bars.Count; $i++) {
        $bars[$i] = [Math]::Max(1, [Math]::Min($EqHeight, $bars[$i] + $rand.Next(-1, 2)))
    }
    $rows = @()
    for ($h = $EqHeight; $h -ge 1; $h--) {
        $row = "   "
        foreach ($b in $bars) { $row += if ($b -ge $h) { " # " } else { "   " } }
        $rows += ,@(Seg $row "Green")
    }
    return $rows
}

function Draw-Frame {
    param([int]$Tick)

    [Console]::SetCursorPosition(0, 0)

    Write-Row @(Seg "")
    $leftTitle = "   chillplay - By Elko"
    if ($script:focusEndTime) {
        $remaining = $script:focusEndTime - (Get-Date)
        if ($remaining.TotalSeconds -lt 0) { $remaining = [TimeSpan]::Zero }
        $rightText = "Focus {0:mm\:ss}" -f $remaining
        $pad = $Width - $leftTitle.Length - $rightText.Length - 1
        if ($pad -lt 1) { $pad = 1 }
        Write-Row @((Seg $leftTitle "Cyan"), (Seg (" " * $pad) "Gray"), (Seg $rightText "Yellow"))
    } else {
        Write-Row @(Seg $leftTitle "Cyan")
    }
    Write-Row @(Seg ("   " + ("-" * 47)) "DarkGray")
    Write-Row @(Seg "")

    foreach ($row in (Get-ThemeRows -Theme $script:theme -Tick $Tick)) {
        Write-Row $row
    }

    Write-Row @(Seg "")
    Write-Row @(Seg "   Now streaming: $($script:vibe.Name) - $($script:vibe.Station) ($($script:vibe.Desc))" "Magenta")
    Write-Row @(Seg "")

    foreach ($row in (Render-EqualizerRows)) {
        Write-Row $row
    }

    Write-Row @(Seg "")
    Write-Row @(Seg ("   " + ("-" * 47)) "DarkGray")
    Write-Row @(Seg "   [1] Vibe   [2] Theme   [3] Focus   [4] GitHub" "White")
    Write-Row @(Seg "   $($script:notice)" "DarkCyan")
    Write-Row @(Seg "   press Ctrl+C to stop" "DarkGray")
}

function Show-VibeMenu {
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
    Write-Host ""
    Write-Host "   chillplay - By Elko" -ForegroundColor Cyan
    Write-Host "   -----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   Choose a vibe:" -ForegroundColor White
    foreach ($v in $Vibes) {
        Write-Host ("   [{0}] {1,-10} - {2} ({3})" -f $v.Key, $v.Name, $v.Station, $v.Desc) -ForegroundColor Magenta
    }
    Write-Host "   [b] Back" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = $k.KeyChar.ToString()
        if ($c -eq 'b' -or $c -eq 'B') { break }
        $match = $Vibes | Where-Object { $_.Key -eq $c }
        if ($match) {
            Start-Vibe -vibe $match
            break
        }
    }
    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
}

function Show-ThemeMenu {
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
    Write-Host ""
    Write-Host "   chillplay - By Elko" -ForegroundColor Cyan
    Write-Host "   -----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   Choose a theme:" -ForegroundColor White
    Write-Host "   [1] Coffee" -ForegroundColor Yellow
    Write-Host "   [2] Rain" -ForegroundColor Blue
    Write-Host "   [3] Hacker" -ForegroundColor Green
    Write-Host "   [4] Cyberpunk" -ForegroundColor Magenta
    Write-Host "   [5] Random" -ForegroundColor White
    Write-Host "   [b] Back" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = $k.KeyChar.ToString()
        switch ($c) {
            "1" { $script:theme = "coffee";    $script:notice = "Theme set to: Coffee";    $done = $true }
            "2" { $script:theme = "rain";      $script:notice = "Theme set to: Rain";      $done = $true }
            "3" { $script:theme = "hacker";    $script:notice = "Theme set to: Hacker";    $done = $true }
            "4" { $script:theme = "cyberpunk"; $script:notice = "Theme set to: Cyberpunk"; $done = $true }
            "5" {
                $pick = $Themes[$rand.Next(0, $Themes.Count)]
                $script:theme = $pick
                $script:notice = "Random theme: $pick"
                $done = $true
            }
            "b" { $done = $true }
            "B" { $done = $true }
        }
        if ($done) { break }
    }
    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
}

function Show-FocusMenu {
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
    Write-Host ""
    Write-Host "   chillplay - By Elko" -ForegroundColor Cyan
    Write-Host "   -----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "   Focus Time" -ForegroundColor White
    Write-Host "   Enter minutes (e.g. 15), 0 to clear the timer, or 'b' to cancel:" -ForegroundColor Gray
    Write-Host ""
    Write-Host -NoNewline "   Minutes: " -ForegroundColor Magenta
    $userInput = Read-Host

    if ($userInput -ne 'b' -and $userInput -ne 'B') {
        $minutes = 0
        if ([int]::TryParse($userInput, [ref]$minutes) -and $minutes -ge 0 -and $minutes -le 480) {
            if ($minutes -eq 0) {
                $script:focusEndTime = $null
                $script:notice = "Focus timer cleared"
            } else {
                $script:focusEndTime = (Get-Date).AddMinutes($minutes)
                $script:notice = "Focus timer set: $minutes min"
            }
        } else {
            $script:notice = "Invalid time - timer not changed"
        }
    }

    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
}

try {
    Clear-Host
    $tick = 0
    while (-not $script:timesUp) {
        Draw-Frame -Tick $tick
        $tick++

        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            switch ($key.KeyChar.ToString()) {
                "1" { Show-VibeMenu }
                "2" { Show-ThemeMenu }
                "3" { Show-FocusMenu }
                "4" {
                    Start-Process $GitHubUrl
                    $script:notice = "Opened GitHub: $GitHubUrl"
                }
            }
        }

        if ($script:focusEndTime -and (Get-Date) -ge $script:focusEndTime) {
            $script:timesUp = $true
        }

        Start-Sleep -Milliseconds $TickMs
    }

    Stop-Vibe
    try { [Console]::CursorVisible = $true } catch {}
    Clear-Host
    Write-Host ""
    Write-Host ""
    Write-Host "   Time's up." -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds 3
}
finally {
    if (-not $script:timesUp) {
        Stop-Vibe
        try { [Console]::CursorVisible = $true } catch {}
        Clear-Host
        Write-Host "chillplay stopped." -ForegroundColor Cyan
    }
}
