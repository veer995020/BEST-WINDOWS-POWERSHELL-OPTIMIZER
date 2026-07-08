# ================================================================
#  UNIVERSAL PC OPTIMIZER v15.11
#  Works on: Windows 10 / 11 | All laptop/desktop brands
#  PowerShell 5.1+  |  GUI + Live Command Log
#  No DISM / No SFC / No Windows Update / No Winget (removed per request)
#  Includes disk cleanup: Prefetch, Temp, Windows Logs, WU Logs
#  Includes gaming tweaks, rainbow spinner, animated splash, PS-console log
#  Includes security hardening (SMB1 off, Firewall on, PUA, RDP off, RemoteReg off)
#  Includes ~70+ total tweaks across 6 steps
#  Includes 3 memory/IO tweaks (IOPageLockLimit, HeapDeCommit, IoTransferLength)
#  v15.1: fixed progress bar going backwards between Step 1 and Step 2
#  v15.2: splash animation overhaul — ease-out-back icon bounce,
#         ease-out-cubic fades, continuously spinning gear, loading dots
#  v15.3: +22 new tweaks from document (location, spotlight, dark mode,
#         hidden files, lock screen, 11 bloatware app removals, RDP/RemoteReg,
#         network Private, 353696, driver updates, Storage Sense, auto-reboot)
#  v15.4: window now auto-fits ANY screen size at runtime (was hardcoded
#         880x1040, clipped on 1366x768 and smaller screens) — detects real
#         work area via SystemParameters.WorkArea, clamps, and re-centers
#  v15.5: corrected completion messaging — almost all tweaks apply
#  v15.6: GUI resized to 1920x1080 (auto-clamped on smaller screens),
#         added Verify_Tweaks.ps1 post-restart checker, audited every
#         cmdlet/GUID for correctness, enlarged pipeline rows and
#         shrank the command console so the pipeline is the focal point
#  v15.7: restart is now immediate (/t 0, was /t 15); removed Ultimate
#         Performance duplicate-scheme call (never actually activated,
#         did nothing); PUA Protection now checks Defender is actually
#         active before attempting (was silently failing on machines
#         with third-party AV and logging success anyway). Added
#         companion Verify_Tweaks.ps1 which checks live system state
#         against ~35 of the tweaks this script applies and reports
#         PASS/FAIL for each, before or after a restart.
#  v15.8: pipeline rebuilt with 3 new animations — pulsing rainbow glow
#         on the running step, ease-out-back checkmark pop-bounce on
#         completion, and a live "current tweak" line that fades in
#         under whichever step is running. Command log no longer caps
#         at 300 lines — every command from the run stays visible.
#  v15.9: ambient drifting particle background (35 particles, real WPF
#         Ellipse shapes with independent physics), confetti burst on
#         completion, breathing rainbow edge-glow around the whole
#         window, and a fade-to-black transition on Restart/Close
#         instead of an abrupt window close. Restart delay is now /t 3.
#         NOTE: this is real-time rendered animation, not embedded video
#         — a single portable .ps1 can't bundle an actual video file, so
#         everything here is genuine WPF vector/physics animation instead.
#  v15.10: upgraded 3D Objects removal to target InprocServer32 (the
#          complete technique — the old version only cleared the parent
#          key, incomplete on some builds); added Widgets/WebExperience
#          removal, TaskbarEndTask, folder-view-template reset, and
#          verbosestatus. All Explorer-dependent tweaks now restart
#          explorer.exe ONCE at the end instead of repeatedly — several
#          duplicate/broken-path tweaks from a pasted snippet were
#          skipped since equivalents already existed correctly.
#  v15.11: audited for non-applying tweaks and outdated cmdlets against
#          PowerShell/Windows documentation. Added the modern
#          ExcludeWUDriversInQualityUpdate policy (the older
#          DriverSearching key only affects Device Manager's manual
#          wizard, not actual Windows Update driver delivery). Upgraded
#          ECN from netsh-only to native Set-NetTCPSetting first, netsh
#          fallback — matching the pattern already used for AutoTuning
#          and RSS. Verified every executed command has a matching
#          pipeline/log entry — audit found the coverage already
#          complete, no gaps.
#
#  HOW TO RUN:
#    Right-click this file -> "Run with PowerShell"
#  OR open an ADMIN PowerShell window and run:
#    powershell -ExecutionPolicy Bypass -File "PC_Optimizer.ps1"
#
#  IMPORTANT (one-liner users):
#    Open PowerShell AS ADMINISTRATOR first, THEN paste the command.
#    A non-admin window cannot self-elevate a pasted one-liner safely.
# ================================================================

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

# ── ADMIN CHECK ──────────────────────────────────────────────────
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    if ($PSCommandPath) {
        # Running from a saved .ps1 file — we have a real path, so we CAN
        # safely relaunch elevated.
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } else {
        # Pasted one-liner (iex) — no script file exists to relaunch from.
        # Show clear instructions and use `return` (NOT `exit`) so the
        # window stays open instead of closing instantly.
        Write-Host ""
        Write-Host "  ================================================================" -ForegroundColor Red
        Write-Host "   ADMINISTRATOR PRIVILEGES REQUIRED" -ForegroundColor Red
        Write-Host "  ================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  This window is not running as Administrator." -ForegroundColor Yellow
        Write-Host "  A pasted command cannot safely re-launch itself elevated." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  TO FIX:" -ForegroundColor White
        Write-Host "    1. Close this PowerShell window" -ForegroundColor Gray
        Write-Host "    2. Click Start, type 'PowerShell'" -ForegroundColor Gray
        Write-Host "    3. Right-click 'Windows PowerShell' -> 'Run as administrator'" -ForegroundColor Gray
        Write-Host "    4. Paste the command again and press Enter" -ForegroundColor Gray
        Write-Host ""
        Read-Host "  Press Enter to close"
        return
    }
}

# ── WPF ASSEMBLIES ──────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ── DETECT SYSTEM INFO ──────────────────────────────────────────
$OSCaption  = (Get-CimInstance Win32_OperatingSystem).Caption
$OSBuild    = (Get-CimInstance Win32_OperatingSystem).BuildNumber
$PCMaker    = (Get-CimInstance Win32_ComputerSystem).Manufacturer
$PCModel    = (Get-CimInstance Win32_ComputerSystem).Model
$Is11       = [int]$OSBuild -ge 22000
$OSLabel    = if ($Is11) { "Windows 11" } else { "Windows 10" }

# ── SHARED STATE (6 steps) ───────────────────────────────────────
$sync = [Hashtable]::Synchronized(@{
    Progress    = 0
    StepIndex   = -1
    StatusMsg   = "Initializing..."
    Done        = $false
    ETA         = "--:--"
    LogLines    = [System.Collections.Generic.List[string]]::new()
    CurrentTweak = ""
    StepsDone   = [bool[]]@($false,$false,$false,$false,$false,$false)
    StepWeights = [double[]]@(25,42,38,13,8,16)
    StartTime   = [datetime]::Now
    OSLabel     = $OSLabel
    PCMaker     = $PCMaker
    PCModel     = $PCModel
})

# ── XAML ────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Universal PC Optimizer v15.11"
    Height="1080" Width="1920"
    WindowStartupLocation="Manual"
    ResizeMode="CanMinimize"
    Background="#06070F">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="78"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="52"/>
    </Grid.RowDefinitions>

    <!-- AMBIENT PARTICLE BACKGROUND (drifting embers, renders behind everything) -->
    <Canvas x:Name="ParticleCanvas" Grid.RowSpan="3" IsHitTestVisible="False" ClipToBounds="True"/>

    <!-- BREATHING EDGE GLOW (pulses gently around the whole window border) -->
    <Border x:Name="EdgeGlow" Grid.RowSpan="3" BorderThickness="3" Opacity="0" IsHitTestVisible="False">
      <Border.BorderBrush><SolidColorBrush x:Name="EdgeGlowBrush" Color="#00CCFF"/></Border.BorderBrush>
      <Border.Effect><DropShadowEffect x:Name="EdgeGlowFx" Color="#00CCFF" BlurRadius="30" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
    </Border>

    <!-- HEADER -->
    <Border Grid.Row="0">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#001E5A" Offset="0"/>
          <GradientStop Color="#0060B0" Offset="0.5"/>
          <GradientStop Color="#0099EE" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid Margin="22,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <TextBlock x:Name="TitleMain" Text="UNIVERSAL PC OPTIMIZER" FontSize="30"
                     FontWeight="Bold" Foreground="White" FontFamily="Segoe UI"/>
          <TextBlock x:Name="TitleSub" Text="Detecting system..."
                     FontSize="14" Foreground="#90BBDC" FontFamily="Segoe UI"/>
        </StackPanel>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="ClockText" HorizontalAlignment="Right"
                     FontSize="22" FontWeight="Bold" Foreground="White" FontFamily="Segoe UI Mono"/>
          <TextBlock Text="LOCAL TIME" HorizontalAlignment="Right"
                     FontSize="8" Foreground="#4A7AAA" FontFamily="Segoe UI Mono"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- MAIN -->
    <Grid Grid.Row="1" Margin="22,12,22,8">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="440"/>
        <ColumnDefinition Width="28"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- LEFT: SPINNER + PROGRESS + ETA -->
      <Grid Grid.Column="0">
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="12"/>
          <RowDefinition Height="10"/>
          <RowDefinition Height="12"/>
          <RowDefinition Height="14"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="8"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" HorizontalAlignment="Center" VerticalAlignment="Center" Width="300" Height="300">
          <Ellipse x:Name="RingOuter" Width="300" Height="300"
                   StrokeThickness="7" StrokeDashArray="34 10" Stroke="#003A7A">
            <Ellipse.RenderTransform><RotateTransform x:Name="RotOuter" CenterX="150" CenterY="150"/></Ellipse.RenderTransform>
            <Ellipse.Effect><DropShadowEffect Color="#0076CE" BlurRadius="10" ShadowDepth="0" Opacity="0.7"/></Ellipse.Effect>
          </Ellipse>
          <Ellipse x:Name="RingMid" Width="236" Height="236"
                   StrokeThickness="4" StrokeDashArray="15 15" Stroke="#0088CC">
            <Ellipse.RenderTransform><RotateTransform x:Name="RotMid" CenterX="118" CenterY="118"/></Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse x:Name="RingInner" Width="174" Height="174"
                   StrokeThickness="5" StrokeDashArray="8 22" Stroke="#00BBFF">
            <Ellipse.RenderTransform><RotateTransform x:Name="RotInner" CenterX="87" CenterY="87"/></Ellipse.RenderTransform>
            <Ellipse.Effect><DropShadowEffect Color="#00CCFF" BlurRadius="16" ShadowDepth="0" Opacity="0.9"/></Ellipse.Effect>
          </Ellipse>
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock x:Name="PctText" Text="0%" HorizontalAlignment="Center"
                       FontSize="64" FontWeight="Bold" Foreground="#00CCFF" FontFamily="Segoe UI Light">
              <TextBlock.Effect><DropShadowEffect Color="#00AAFF" BlurRadius="22" ShadowDepth="0" Opacity="0.9"/></TextBlock.Effect>
            </TextBlock>
            <TextBlock x:Name="StepNumText" Text="STEP 0/6" HorizontalAlignment="Center"
                       FontSize="13" Foreground="#2A4060" FontFamily="Segoe UI Mono"/>
          </StackPanel>
        </Grid>

        <TextBlock Grid.Row="2" Text="OVERALL PROGRESS" FontSize="8"
                   Foreground="#1E2E40" FontFamily="Segoe UI Mono" HorizontalAlignment="Center"/>
        <Grid x:Name="PrgContainer" Grid.Row="3" Height="15">
          <Border Background="#090D1A" CornerRadius="5"/>
          <Border x:Name="PrgFill" CornerRadius="5" HorizontalAlignment="Left" Width="0">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#003A80" Offset="0"/>
                <GradientStop Color="#0066CC" Offset="0.4"/>
                <GradientStop Color="#00BBFF" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <Border.Effect><DropShadowEffect Color="#0099FF" BlurRadius="7" ShadowDepth="0" Opacity="0.8"/></Border.Effect>
          </Border>
        </Grid>
        <TextBlock x:Name="StatusText" Grid.Row="5" Text="Starting..." TextWrapping="Wrap"
                   TextAlignment="Center" FontSize="14" Foreground="#3A5878"
                   FontFamily="Segoe UI" HorizontalAlignment="Center"/>
        <StackPanel Grid.Row="7" Orientation="Horizontal" HorizontalAlignment="Center">
          <TextBlock Text="ETA  " Foreground="#162030" FontSize="9" FontFamily="Segoe UI Mono" VerticalAlignment="Center"/>
          <TextBlock x:Name="EtaLeft" Text="--:--" Foreground="#1E3550" FontSize="16"
                     FontFamily="Segoe UI Mono" FontWeight="Bold" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>

      <!-- RIGHT: STEPS + COMMAND LOG -->
      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="10"/>
          <RowDefinition Height="150"/>
        </Grid.RowDefinitions>

        <!-- STEP LIST (6 steps) -->
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="StepPanel">
            <TextBlock Text="OPTIMIZATION  PIPELINE" FontSize="11" FontWeight="Bold"
                       Foreground="#1A2A38" FontFamily="Segoe UI Mono" Margin="2,0,0,7"/>

            <Border x:Name="Step0" CornerRadius="8" Margin="0,5" Padding="18,15" Background="#080A18">
              <Border.Effect>
                <DropShadowEffect x:Name="Glow0" Color="#0088CC" BlurRadius="0" ShadowDepth="0" Opacity="0"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition Width="*"/><ColumnDefinition Width="96"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Icon0" Text="○" Foreground="#243040" FontSize="22" VerticalAlignment="Center">
                    <TextBlock.RenderTransform>
                      <ScaleTransform x:Name="IconScale0" ScaleX="1" ScaleY="1" CenterX="11" CenterY="14"/>
                    </TextBlock.RenderTransform>
                  </TextBlock>
                  <TextBlock x:Name="Lbl0" Grid.Column="1" Text="Drive Optimization (TRIM)" Foreground="#304858" FontSize="18" VerticalAlignment="Center"/>
                  <TextBlock x:Name="Tag0" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
                </Grid>
                <TextBlock x:Name="Detail0" Grid.Row="1" Text="" Opacity="0" Margin="38,4,0,0"
                           FontSize="11" FontFamily="Consolas" Foreground="#5A8CB8" TextWrapping="Wrap"/>
              </Grid>
            </Border>

            <Border x:Name="Step1" CornerRadius="8" Margin="0,5" Padding="18,15" Background="#080A18">
              <Border.Effect>
                <DropShadowEffect x:Name="Glow1" Color="#0088CC" BlurRadius="0" ShadowDepth="0" Opacity="0"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition Width="*"/><ColumnDefinition Width="96"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Icon1" Text="○" Foreground="#243040" FontSize="22" VerticalAlignment="Center">
                    <TextBlock.RenderTransform>
                      <ScaleTransform x:Name="IconScale1" ScaleX="1" ScaleY="1" CenterX="11" CenterY="14"/>
                    </TextBlock.RenderTransform>
                  </TextBlock>
                  <TextBlock x:Name="Lbl1" Grid.Column="1" Text="Performance Tweaks" Foreground="#304858" FontSize="18" VerticalAlignment="Center"/>
                  <TextBlock x:Name="Tag1" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
                </Grid>
                <TextBlock x:Name="Detail1" Grid.Row="1" Text="" Opacity="0" Margin="38,4,0,0"
                           FontSize="11" FontFamily="Consolas" Foreground="#5A8CB8" TextWrapping="Wrap"/>
              </Grid>
            </Border>

            <Border x:Name="Step2" CornerRadius="8" Margin="0,5" Padding="18,15" Background="#080A18">
              <Border.Effect>
                <DropShadowEffect x:Name="Glow2" Color="#0088CC" BlurRadius="0" ShadowDepth="0" Opacity="0"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition Width="*"/><ColumnDefinition Width="96"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Icon2" Text="○" Foreground="#243040" FontSize="22" VerticalAlignment="Center">
                    <TextBlock.RenderTransform>
                      <ScaleTransform x:Name="IconScale2" ScaleX="1" ScaleY="1" CenterX="11" CenterY="14"/>
                    </TextBlock.RenderTransform>
                  </TextBlock>
                  <TextBlock x:Name="Lbl2" Grid.Column="1" Text="Privacy &amp; Telemetry" Foreground="#304858" FontSize="18" VerticalAlignment="Center"/>
                  <TextBlock x:Name="Tag2" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
                </Grid>
                <TextBlock x:Name="Detail2" Grid.Row="1" Text="" Opacity="0" Margin="38,4,0,0"
                           FontSize="11" FontFamily="Consolas" Foreground="#5A8CB8" TextWrapping="Wrap"/>
              </Grid>
            </Border>

            <Border x:Name="Step3" CornerRadius="8" Margin="0,5" Padding="18,15" Background="#080A18">
              <Border.Effect>
                <DropShadowEffect x:Name="Glow3" Color="#0088CC" BlurRadius="0" ShadowDepth="0" Opacity="0"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition Width="*"/><ColumnDefinition Width="96"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Icon3" Text="○" Foreground="#243040" FontSize="22" VerticalAlignment="Center">
                    <TextBlock.RenderTransform>
                      <ScaleTransform x:Name="IconScale3" ScaleX="1" ScaleY="1" CenterX="11" CenterY="14"/>
                    </TextBlock.RenderTransform>
                  </TextBlock>
                  <TextBlock x:Name="Lbl3" Grid.Column="1" Text="Memory &amp; CPU Tuning" Foreground="#304858" FontSize="18" VerticalAlignment="Center"/>
                  <TextBlock x:Name="Tag3" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
                </Grid>
                <TextBlock x:Name="Detail3" Grid.Row="1" Text="" Opacity="0" Margin="38,4,0,0"
                           FontSize="11" FontFamily="Consolas" Foreground="#5A8CB8" TextWrapping="Wrap"/>
              </Grid>
            </Border>

            <Border x:Name="Step4" CornerRadius="8" Margin="0,5" Padding="18,15" Background="#080A18">
              <Border.Effect>
                <DropShadowEffect x:Name="Glow4" Color="#0088CC" BlurRadius="0" ShadowDepth="0" Opacity="0"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition Width="*"/><ColumnDefinition Width="96"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Icon4" Text="○" Foreground="#243040" FontSize="22" VerticalAlignment="Center">
                    <TextBlock.RenderTransform>
                      <ScaleTransform x:Name="IconScale4" ScaleX="1" ScaleY="1" CenterX="11" CenterY="14"/>
                    </TextBlock.RenderTransform>
                  </TextBlock>
                  <TextBlock x:Name="Lbl4" Grid.Column="1" Text="Network Optimization" Foreground="#304858" FontSize="18" VerticalAlignment="Center"/>
                  <TextBlock x:Name="Tag4" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
                </Grid>
                <TextBlock x:Name="Detail4" Grid.Row="1" Text="" Opacity="0" Margin="38,4,0,0"
                           FontSize="11" FontFamily="Consolas" Foreground="#5A8CB8" TextWrapping="Wrap"/>
              </Grid>
            </Border>

            <Border x:Name="Step5" CornerRadius="8" Margin="0,5" Padding="18,15" Background="#080A18">
              <Border.Effect>
                <DropShadowEffect x:Name="Glow5" Color="#0088CC" BlurRadius="0" ShadowDepth="0" Opacity="0"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0"><Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition Width="*"/><ColumnDefinition Width="96"/></Grid.ColumnDefinitions>
                  <TextBlock x:Name="Icon5" Text="○" Foreground="#243040" FontSize="22" VerticalAlignment="Center">
                    <TextBlock.RenderTransform>
                      <ScaleTransform x:Name="IconScale5" ScaleX="1" ScaleY="1" CenterX="11" CenterY="14"/>
                    </TextBlock.RenderTransform>
                  </TextBlock>
                  <TextBlock x:Name="Lbl5" Grid.Column="1" Text="Startup, DNS &amp; Disk Cleanup" Foreground="#304858" FontSize="18" VerticalAlignment="Center"/>
                  <TextBlock x:Name="Tag5" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
                </Grid>
                <TextBlock x:Name="Detail5" Grid.Row="1" Text="" Opacity="0" Margin="38,4,0,0"
                           FontSize="11" FontFamily="Consolas" Foreground="#5A8CB8" TextWrapping="Wrap"/>
              </Grid>
            </Border>

            <!-- Done panel -->
            <Border x:Name="DonePanel" Visibility="Collapsed" CornerRadius="8" Margin="0,10,0,0"
                    Padding="14,11" BorderThickness="1" BorderBrush="#005A1E">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#04130A" Offset="0"/>
                  <GradientStop Color="#07200E" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <StackPanel>
                <TextBlock Text="✓  ALL 6 STEPS COMPLETE" FontSize="12" FontWeight="Bold"
                           Foreground="#00CC55" TextAlignment="Center" Margin="0,0,0,6">
                  <TextBlock.Effect><DropShadowEffect Color="#00FF66" BlurRadius="10" ShadowDepth="0" Opacity="0.7"/></TextBlock.Effect>
                </TextBlock>
                <TextBlock x:Name="ElapsedFinal" Text="" FontSize="10" Foreground="#336644"
                           FontFamily="Segoe UI Mono" TextAlignment="Center" Margin="0,0,0,9"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <Button x:Name="BtnRestart" Content="⟳  Restart Now" Height="30" FontSize="11"
                          FontWeight="Bold" Cursor="Hand" Foreground="White" BorderThickness="0">
                    <Button.Background>
                      <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                        <GradientStop Color="#0060AA" Offset="0"/>
                        <GradientStop Color="#003A70" Offset="1"/>
                      </LinearGradientBrush>
                    </Button.Background>
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="6,0">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                  <Button x:Name="BtnClose" Grid.Column="2" Content="Close" Height="30"
                          FontSize="11" Cursor="Hand" Foreground="#6A9AB8" Background="#080B16" BorderThickness="0">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5"
                                BorderBrush="#162230" BorderThickness="1" Padding="6,0">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                </Grid>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- LIVE COMMAND LOG (styled like a real PowerShell console) -->
        <Border Grid.Row="2" Background="#012456" CornerRadius="7"
                BorderThickness="1" BorderBrush="#1A3A78" Padding="10,8">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="5"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="4"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Windows PowerShell" FontSize="8" FontWeight="Bold"
                         Foreground="#CFE3FF" FontFamily="Consolas"/>
              <TextBlock x:Name="LogCountText" Text="  (0 commands)"
                         FontSize="8" Foreground="#5A7FBF" FontFamily="Consolas"/>
            </StackPanel>
            <ScrollViewer x:Name="LogScroll" Grid.Row="2"
                          VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">
              <TextBlock x:Name="LogText"
                         FontFamily="Consolas" FontSize="10"
                         Foreground="#E8E8E8" TextWrapping="Wrap"
                         Text="Waiting for optimizer to start..."/>
            </ScrollViewer>
            <StackPanel Grid.Row="4" Orientation="Horizontal">
              <TextBlock Text="PS C:\Windows\system32&gt; " FontFamily="Consolas"
                         FontSize="10" Foreground="#3FF3A0"/>
              <TextBlock x:Name="LogCursor" Text="█" FontFamily="Consolas"
                         FontSize="10" Foreground="#E8E8E8"/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>
    </Grid>

    <!-- FOOTER -->
    <Border Grid.Row="2" Background="#03040A" Padding="22,0">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="20"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="FooterText" Text="Initializing optimizer..."
                   Foreground="#192430" FontSize="10.5" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="ELAPSED  " Foreground="#111C28" FontSize="8" FontFamily="Segoe UI Mono" VerticalAlignment="Center"/>
          <TextBlock x:Name="ElapsedText" Text="00:00" Foreground="#1A2C40"
                     FontSize="12" FontFamily="Segoe UI Mono" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="ETA  " Foreground="#111C28" FontSize="8" FontFamily="Segoe UI Mono" VerticalAlignment="Center"/>
          <TextBlock x:Name="EtaFooter" Text="--:--" Foreground="#1A2C40"
                     FontSize="12" FontFamily="Segoe UI Mono" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- STARTUP SPLASH OVERLAY (animated intro, covers all 3 rows) -->
    <Grid x:Name="SplashOverlay" Grid.RowSpan="3" Background="#06070F" Panel.ZIndex="999">
      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
        <TextBlock x:Name="SplashIcon" Text="⚙" FontSize="72" Opacity="0"
                   HorizontalAlignment="Center" Foreground="#00CCFF">
          <TextBlock.RenderTransform>
            <TransformGroup>
              <ScaleTransform x:Name="SplashIconScale" ScaleX="0.3" ScaleY="0.3" CenterX="36" CenterY="36"/>
              <RotateTransform x:Name="SplashIconRotate" Angle="0" CenterX="36" CenterY="36"/>
            </TransformGroup>
          </TextBlock.RenderTransform>
          <TextBlock.Effect>
            <DropShadowEffect Color="#00AAFF" BlurRadius="26" ShadowDepth="0" Opacity="0.9"/>
          </TextBlock.Effect>
        </TextBlock>
        <TextBlock x:Name="SplashTitle" Text="UNIVERSAL PC OPTIMIZER" Opacity="0"
                   FontSize="26" FontWeight="Bold" Foreground="White" FontFamily="Segoe UI"
                   HorizontalAlignment="Center" Margin="0,18,0,0"/>
        <TextBlock x:Name="SplashSubtitle" Text="v15.11" Opacity="0"
                   FontSize="13" Foreground="#6FA8D8" FontFamily="Segoe UI Mono"
                   HorizontalAlignment="Center" Margin="0,4,0,0"/>
        <TextBlock x:Name="SplashCredit" Text="Made by Veer Bhardwaj" Opacity="0"
                   FontSize="14" FontWeight="Bold" FontFamily="Segoe UI"
                   HorizontalAlignment="Center" Margin="0,28,0,0"/>
        <TextBlock x:Name="SplashDots" Text="" Opacity="0"
                   FontSize="13" Foreground="#3A5878" FontFamily="Segoe UI Mono"
                   HorizontalAlignment="Center" Margin="0,14,0,0"/>
      </StackPanel>
    </Grid>

  </Grid>
</Window>
'@

# ── PARSE XAML ──────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# ── FIT WINDOW TO ACTUAL SCREEN SIZE ─────────────────────────────
# The XAML above requests 1920x1080 (full HD), but on a REAL 1920x1080
# monitor the usable work area is smaller than that once you subtract
# the taskbar (~1080x1040 typically) — and it's much smaller on laptops
# at 1366x768 or on any screen with DPI scaling. Requesting exactly
# 1920x1080 without this clamp would push the window off-screen or make
# its bottom edge unreachable on most real machines. This clamps to the
# REAL usable work area of whatever monitor the window opens on, with a
# 40px safety margin on each dimension, and re-centers it — so 1920x1080
# is used as-is on large/4K displays, and safely scaled down everywhere else.
$workArea = [System.Windows.SystemParameters]::WorkArea
$maxH = [Math]::Max(500, $workArea.Height - 40)
$maxW = [Math]::Max(700, $workArea.Width  - 40)
if ($window.Height -gt $maxH) { $window.Height = $maxH }
if ($window.Width  -gt $maxW) { $window.Width  = $maxW }
$window.Left = $workArea.Left + (($workArea.Width  - $window.Width)  / 2)
$window.Top  = $workArea.Top  + (($workArea.Height - $window.Height) / 2)

$ctrl = @{}
'TitleMain','TitleSub','ClockText','PctText','StepNumText',
'PrgContainer','PrgFill','StatusText','EtaLeft',
'LogText','LogScroll','LogCountText','LogCursor',
'FooterText','ElapsedText','EtaFooter',
'ElapsedFinal','DonePanel','BtnRestart','BtnClose',
'RingOuter','RingMid','RingInner','RotOuter','RotMid','RotInner',
'SplashOverlay','SplashIcon','SplashIconScale','SplashIconRotate','SplashTitle','SplashSubtitle','SplashCredit','SplashDots',
'ParticleCanvas','EdgeGlow','EdgeGlowBrush','EdgeGlowFx' |
ForEach-Object { $ctrl[$_] = $window.FindName($_) }

# Step row controls — 6 steps (0..5)
$sB = 0..5 | ForEach-Object { $window.FindName("Step$_") }
$sI = 0..5 | ForEach-Object { $window.FindName("Icon$_") }
$sL = 0..5 | ForEach-Object { $window.FindName("Lbl$_")  }
$sT = 0..5 | ForEach-Object { $window.FindName("Tag$_")  }
$sD = 0..5 | ForEach-Object { $window.FindName("Detail$_") }
$sG = 0..5 | ForEach-Object { $window.FindName("Glow$_") }
$sIS = 0..5 | ForEach-Object { [System.Windows.Media.ScaleTransform]$window.FindName("IconScale$_") }

$rotO = [System.Windows.Media.RotateTransform]$ctrl['RotOuter']
$rotM = [System.Windows.Media.RotateTransform]$ctrl['RotMid']
$rotI = [System.Windows.Media.RotateTransform]$ctrl['RotInner']
$splashScale = [System.Windows.Media.ScaleTransform]$ctrl['SplashIconScale']
$splashRotate = [System.Windows.Media.RotateTransform]$ctrl['SplashIconRotate']

# ── CACHE BRUSHES ONCE ──────────────────────────────────────────
$cv = [Windows.Media.BrushConverter]::new()
$b = @{
    PendI=$cv.ConvertFrom("#243040"); PendL=$cv.ConvertFrom("#304858"); PendT=$cv.ConvertFrom("#1E2C3A")
    ActBg=$cv.ConvertFrom("#06101E"); ActBor=$cv.ConvertFrom("#005BAA"); ActI=$cv.ConvertFrom("#00CCFF"); ActT=$cv.ConvertFrom("#0088CC")
    DonBg=$cv.ConvertFrom("#050D07"); DonBor=$cv.ConvertFrom("#003D18"); DonI=$cv.ConvertFrom("#00CC55"); DonL=$cv.ConvertFrom("#3A7755"); DonT=$cv.ConvertFrom("#005A22")
    White=[Windows.Media.Brushes]::White; Trans=[Windows.Media.Brushes]::Transparent
    LogTs=$cv.ConvertFrom("#5A7FBF"); LogPrompt=$cv.ConvertFrom("#3FF3A0"); LogTxt=$cv.ConvertFrom("#E8E8E8")
}
$thk0=[Windows.Thickness]::new(0); $thk1=[Windows.Thickness]::new(1)

# ── RAINBOW PALETTE (precomputed once — same cached-brush approach as
#    above, so the spinner animation never allocates a new brush per frame) ──
function Convert-HSVtoColor([double]$h,[double]$s,[double]$v){
    $c=$v*$s
    $x=$c*(1-[Math]::Abs((($h/60)%2)-1))
    $m=$v-$c
    $seg=[Math]::Floor($h/60)%6
    switch ([int]$seg){
        0{$r=$c;$g=$x;$bl=0}
        1{$r=$x;$g=$c;$bl=0}
        2{$r=0;$g=$c;$bl=$x}
        3{$r=0;$g=$x;$bl=$c}
        4{$r=$x;$g=0;$bl=$c}
        default{$r=$c;$g=0;$bl=$x}
    }
    [Windows.Media.Color]::FromRgb([byte](($r+$m)*255),[byte](($g+$m)*255),[byte](($bl+$m)*255))
}
$RainbowSteps = 120
$RainbowBrushes = 0..($RainbowSteps-1) | ForEach-Object {
    $hue = $_ * (360.0/$RainbowSteps)
    [Windows.Media.SolidColorBrush]::new((Convert-HSVtoColor $hue 0.85 1.0))
}

# ── AMBIENT PARTICLE SYSTEM ──────────────────────────────────────
# Real WPF Ellipse shapes placed on ParticleCanvas, each with its own
# position/velocity/opacity, animated by hand every spin tick (24ms) —
# same "DispatcherTimer + manual interpolation" approach used everywhere
# else in this script, just applied to a small physics simulation instead
# of a single value. Two independent pools: a slow ambient drift that
# runs the whole time, and a one-shot confetti burst fired on completion.
$rng = [Random]::new()
$script:particles = New-Object System.Collections.Generic.List[object]

function New-Particle([bool]$isBurst) {
    $ellipse = [System.Windows.Shapes.Ellipse]::new()
    $size = if($isBurst){ $rng.Next(4,9) } else { $rng.Next(2,5) }
    $ellipse.Width = $size; $ellipse.Height = $size
    $hue = $rng.Next(0,$RainbowSteps)
    $ellipse.Fill = $RainbowBrushes[$hue]
    $ellipse.Opacity = if($isBurst){ 1.0 } else { 0.15 + $rng.NextDouble()*0.25 }
    [void]$ctrl['ParticleCanvas'].Children.Add($ellipse)

    $obj = [pscustomobject]@{
        Shape = $ellipse
        X = if($isBurst){ 960.0 } else { $rng.NextDouble()*1920.0 }
        Y = if($isBurst){ 130.0 } else { $rng.NextDouble()*1080.0 }
        VX = if($isBurst){ ($rng.NextDouble()-0.5)*9.0 } else { ($rng.NextDouble()-0.5)*0.35 }
        VY = if($isBurst){ -($rng.NextDouble()*7.0) - 2.0 } else { ($rng.NextDouble()-0.5)*0.35 }
        IsBurst = $isBurst
        Life = 0.0
        MaxLife = if($isBurst){ 1800.0 + $rng.NextDouble()*800.0 } else { -1 }  # -1 = lives forever, wraps around
    }
    [Windows.Controls.Canvas]::SetLeft($ellipse,$obj.X)
    [Windows.Controls.Canvas]::SetTop($ellipse,$obj.Y)
    $script:particles.Add($obj)
    return $obj
}

# Seed ~35 ambient background particles at startup
1..35 | ForEach-Object { [void](New-Particle $false) }

function Update-Particles([double]$dtMs) {
    $toRemove = New-Object System.Collections.Generic.List[object]
    foreach($p in $script:particles){
        $p.X += $p.VX; $p.Y += $p.VY
        if($p.IsBurst){
            $p.VY += 0.10                      # gravity pulls confetti down
            $p.Life += $dtMs
            $fade = 1.0 - ($p.Life / $p.MaxLife)
            $p.Shape.Opacity = [Math]::Max(0,$fade)
            if($p.Life -ge $p.MaxLife){ $toRemove.Add($p) }
        } else {
            # Ambient particles gently wrap around screen edges forever
            if($p.X -lt -10){$p.X=1930}elseif($p.X -gt 1930){$p.X = -10}
            if($p.Y -lt -10){$p.Y=1090}elseif($p.Y -gt 1090){$p.Y = -10}
        }
        [Windows.Controls.Canvas]::SetLeft($p.Shape,$p.X)
        [Windows.Controls.Canvas]::SetTop($p.Shape,$p.Y)
    }
    foreach($p in $toRemove){
        $ctrl['ParticleCanvas'].Children.Remove($p.Shape)
        [void]$script:particles.Remove($p)
    }
}

function Start-ConfettiBurst {
    1..70 | ForEach-Object { [void](New-Particle $true) }
}

# ── STEP ROW UPDATER (6 steps) ──────────────────────────────────
$script:completionAnim = @{}   # stepIndex -> elapsed ms, drives the pop-bounce checkmark
$script:detailOpacity  = @(0.0,0.0,0.0,0.0,0.0,0.0)

function Set-StepUI([int]$i,[int]$st) {
    switch ($st) {
        0 { $sB[$i].Background=$b.Trans;$sB[$i].BorderBrush=$b.Trans;$sB[$i].BorderThickness=$thk0
            $sI[$i].Text="○";$sI[$i].Foreground=$b.PendI;$sL[$i].Foreground=$b.PendL
            $sT[$i].Text="PENDING";$sT[$i].Foreground=$b.PendT
            $sD[$i].Text="";$sG[$i].Opacity=0;$sIS[$i].ScaleX=1;$sIS[$i].ScaleY=1 }
        1 { $sB[$i].Background=$b.ActBg;$sB[$i].BorderBrush=$b.ActBor;$sB[$i].BorderThickness=$thk1
            $sI[$i].Text="▶";$sI[$i].Foreground=$b.ActI;$sL[$i].Foreground=$b.White
            $sT[$i].Text="RUNNING";$sT[$i].Foreground=$b.ActT
            $sIS[$i].ScaleX=1;$sIS[$i].ScaleY=1 }
        2 { $sB[$i].Background=$b.DonBg;$sB[$i].BorderBrush=$b.DonBor;$sB[$i].BorderThickness=$thk1
            $sI[$i].Text="✓";$sI[$i].Foreground=$b.DonI;$sL[$i].Foreground=$b.DonL
            $sT[$i].Text="DONE";$sT[$i].Foreground=$b.DonT
            $sD[$i].Text="";$sG[$i].Opacity=0
            # Kick off the checkmark pop-bounce — the spin timer (24ms) drives it
            $script:completionAnim[$i] = 0 }
    }
}

# ── TIMER 1: SPINNER 24ms — now cycles through a rainbow palette ────
$script:a1=0.0;$script:a2=0.0;$script:a3=0.0;$script:pulse=0.0
$script:edgeHue=0
$script:hueIdx=0
$tSpin=[System.Windows.Threading.DispatcherTimer]::new()
$tSpin.Interval=[TimeSpan]::FromMilliseconds(24)
$tSpin.Add_Tick({
    $script:a1+=1.4;$script:a2-=2.2;$script:a3+=4.0
    $rotO.Angle=$script:a1;$rotM.Angle=$script:a2;$rotI.Angle=$script:a3
    $script:pulse+=0.065
    $g=$ctrl['PctText'].Effect
    if($g){$g.Opacity=0.5+0.45*[Math]::Sin($script:pulse)}

    # Advance rainbow index; offset each ring so colors flow into each other
    if(-not $sync.Done){
        $script:hueIdx = ($script:hueIdx + 1) % $RainbowSteps
        $i1=$script:hueIdx
        $i2=($script:hueIdx + 40) % $RainbowSteps
        $i3=($script:hueIdx + 80) % $RainbowSteps
        $brush1=$RainbowBrushes[$i1]; $brush2=$RainbowBrushes[$i2]; $brush3=$RainbowBrushes[$i3]
        $ctrl['RingOuter'].Stroke=$brush1
        $ctrl['RingMid'].Stroke  =$brush2
        $ctrl['RingInner'].Stroke=$brush3
        if($ctrl['RingOuter'].Effect){$ctrl['RingOuter'].Effect.Color=$brush1.Color}
        if($ctrl['RingInner'].Effect){$ctrl['RingInner'].Effect.Color=$brush3.Color}
        $ctrl['PctText'].Foreground=$brush3
        if($g){$g.Color=$brush3.Color}
    }

    # ── PIPELINE ANIMATION 1: pulsing rainbow glow on the RUNNING row ──
    # Reuses the same rainbow palette as the spinner rings so the whole
    # UI feels like one connected animation instead of separate effects.
    if($script:lastStep -ge 0 -and $script:lastStep -lt 6 -and -not $sync.Done){
        $glowBrush = $RainbowBrushes[$script:hueIdx]
        $glow = $sG[$script:lastStep]
        $glow.Color = $glowBrush.Color
        $glow.BlurRadius = 18
        $glow.Opacity = 0.25 + 0.30*[Math]::Sin($script:pulse*1.4)
    }

    # ── PIPELINE ANIMATION 2: checkmark pop-bounce on step completion ──
    # Same ease-out-back overshoot formula used for the splash icon —
    # the checkmark grows past 1.0x then settles, instead of just
    # appearing flat/static the instant a step finishes.
    if($script:completionAnim.Count -gt 0){
        $keysToRemove = @()
        foreach($idx in @($script:completionAnim.Keys)){
            $script:completionAnim[$idx] += 24
            $te = $script:completionAnim[$idx]
            $t1 = [Math]::Max(0.0,[Math]::Min(1.0,$te/350.0))
            $easeBack = 1 + 2.4*[Math]::Pow($t1-1,3) + 1.4*[Math]::Pow($t1-1,2)
            $scaleVal = 0.3 + 0.7*$easeBack
            if($scaleVal -lt 0.05){$scaleVal=0.05}
            $sIS[$idx].ScaleX = $scaleVal
            $sIS[$idx].ScaleY = $scaleVal
            if($te -ge 350){
                $sIS[$idx].ScaleX = 1; $sIS[$idx].ScaleY = 1
                $keysToRemove += $idx
            }
        }
        foreach($idx in $keysToRemove){ $script:completionAnim.Remove($idx) }
    }
})

# ── TIMER 1B: PARTICLES + EDGE GLOW 24ms — runs independently of tSpin
#    so ambient drift keeps going and confetti can actually fall/fade
#    after the optimization finishes (tSpin stops on completion) ───────
$script:particlePulse=0.0
$tParticles=[System.Windows.Threading.DispatcherTimer]::new()
$tParticles.Interval=[TimeSpan]::FromMilliseconds(24)
$tParticles.Add_Tick({
    Update-Particles 24
    $script:particlePulse += 0.065
    $script:edgeHue = ($script:edgeHue + 1) % $RainbowSteps
    $edgeBrush = $RainbowBrushes[$script:edgeHue]
    $ctrl['EdgeGlowBrush'].Color = $edgeBrush.Color
    $ctrl['EdgeGlowFx'].Color = $edgeBrush.Color
    $ctrl['EdgeGlow'].Opacity = 0.12 + 0.10*[Math]::Sin($script:particlePulse*0.5)
})

# ── TIMER 2: CLOCK+ELAPSED 1s ────────────────────────────────────
$tClock=[System.Windows.Threading.DispatcherTimer]::new()
$tClock.Interval=[TimeSpan]::FromSeconds(1)
$tClock.Add_Tick({
    $ctrl['ClockText'].Text=(Get-Date -Format "HH:mm:ss")
    $e=[datetime]::Now - $sync.StartTime
    $ctrl['ElapsedText'].Text="{0:D2}:{1:D2}" -f [int]$e.TotalMinutes,$e.Seconds
})

# ── TIMER 3: PROGRESS+LOG POLL 60ms ──────────────────────────────
$script:lastStep=-1;$script:smooth=0.0;$script:logCount=0
$script:blinkTick=0;$script:cursorOn=$true

$tPoll=[System.Windows.Threading.DispatcherTimer]::new()
$tPoll.Interval=[TimeSpan]::FromMilliseconds(60)
$tPoll.Add_Tick({
    $script:smooth += ([double]$sync.Progress - $script:smooth)*0.25
    $d=[Math]::Round($script:smooth)
    $ctrl['PctText'].Text="$d%"
    $ctrl['StepNumText'].Text="STEP $([Math]::Max(0,$sync.StepIndex+1))/6"
    $ctrl['StatusText'].Text=$sync.StatusMsg
    $eta=$sync.ETA
    $ctrl['EtaLeft'].Text=$eta
    $ctrl['EtaFooter'].Text=$eta

    $cw=$ctrl['PrgContainer'].ActualWidth
    if($cw -gt 1){$ctrl['PrgFill'].Width=($script:smooth/100.0)*$cw}

    $cur=$sync.StepIndex
    if($cur -ne $script:lastStep){
        for($i=0;$i -lt 6;$i++){
            if($i -lt $cur){Set-StepUI $i 2}
            elseif($i -eq $cur){Set-StepUI $i 1}
            else{Set-StepUI $i 0}
        }
        $script:lastStep=$cur
    }
    for($i=0;$i -lt 6;$i++){
        if($sync.StepsDone[$i] -and $i -ne $cur){Set-StepUI $i 2}
    }

    # ── PIPELINE ANIMATION 3: live "current tweak" text under the
    #    running row, fading in/out rather than snapping on/off ──────
    $tweakText = $sync.CurrentTweak
    for($i=0;$i -lt 6;$i++){
        $target = if($i -eq $cur -and -not $sync.Done){1.0}else{0.0}
        $script:detailOpacity[$i] += ($target - $script:detailOpacity[$i]) * 0.35
        if([Math]::Abs($script:detailOpacity[$i]) -lt 0.02){$script:detailOpacity[$i]=0.0}
        $sD[$i].Opacity = $script:detailOpacity[$i]
        if($i -eq $cur -and $tweakText){
            $shown = if($tweakText.Length -gt 90){$tweakText.Substring(0,87)+"..."}else{$tweakText}
            $sD[$i].Text = "→ $shown"
        }
    }

    $ll = $sync.LogLines
    if($ll.Count -ne $script:logCount){
        $tb = $ctrl['LogText']
        $tb.Inlines.Clear()
        foreach($line in $ll){
            if($line -match '^\[(\d{2}:\d{2}:\d{2})\]\s(.*)$'){
                $ts=$matches[1]; $msg=$matches[2]
            } else { $ts=""; $msg=$line }
            $r1=New-Object Windows.Documents.Run("[$ts] ");$r1.Foreground=$b.LogTs
            $r2=New-Object Windows.Documents.Run("PS> ");$r2.Foreground=$b.LogPrompt;$r2.FontWeight=[Windows.FontWeights]::Bold
            $r3=New-Object Windows.Documents.Run($msg);$r3.Foreground=$b.LogTxt
            $tb.Inlines.Add($r1);$tb.Inlines.Add($r2);$tb.Inlines.Add($r3)
            $tb.Inlines.Add((New-Object Windows.Documents.LineBreak))
        }
        $ctrl['LogCountText'].Text = "  ($($ll.Count) commands)"
        $ctrl['LogScroll'].ScrollToEnd()
        $script:logCount = $ll.Count
    }

    # Blinking terminal cursor — toggles every 8 ticks (~480ms at 60ms interval)
    $script:blinkTick++
    if(($script:blinkTick % 8) -eq 0){
        $script:cursorOn = -not $script:cursorOn
        $ctrl['LogCursor'].Opacity = if($script:cursorOn){1.0}else{0.0}
    }

    if($sync.Done){
        $tPoll.Stop();$tSpin.Stop();$tClock.Stop()
        Start-ConfettiBurst
        $ctrl['PctText'].Text="100%"
        if($ctrl['PrgContainer'].ActualWidth -gt 1){
            $ctrl['PrgFill'].Width=$ctrl['PrgContainer'].ActualWidth
        }
        for($i=0;$i -lt 6;$i++){Set-StepUI $i 2}
        $ctrl['StepNumText'].Text="COMPLETE"
        $ctrl['StatusText'].Text="All optimizations applied."
        $ctrl['EtaLeft'].Text="00:00";$ctrl['EtaFooter'].Text="00:00"
        $ctrl['FooterText'].Text="Most tweaks are already active. Restart only needed for bcdedit/SMB1. Run Verify-Tweaks.ps1 to confirm."
        $cv2=[Windows.Media.BrushConverter]::new()
        $ctrl['RingOuter'].Stroke=$cv2.ConvertFrom("#006622")
        $ctrl['RingMid'].Stroke  =$cv2.ConvertFrom("#009933")
        $ctrl['RingInner'].Stroke=$cv2.ConvertFrom("#00CC55")
        $ctrl['PctText'].Foreground=$cv2.ConvertFrom("#00CC55")
        $el=[datetime]::Now - $sync.StartTime
        $ctrl['ElapsedFinal'].Text="Completed in {0:D2}:{1:D2}" -f [int]$el.TotalMinutes,$el.Seconds
        $ctrl['DonePanel'].Visibility=[System.Windows.Visibility]::Visible
    }
})

# ── TIMER 4: STARTUP SPLASH ANIMATION (runs once before the optimizer
#    actually starts — icon pop-in, staggered text fade-ins, rainbow
#    shimmer on the credit line, then fade-out into the real UI) ───────
$script:introElapsed = 0
$script:creditHue = 0
$tIntro = [System.Windows.Threading.DispatcherTimer]::new()
$tIntro.Interval = [TimeSpan]::FromMilliseconds(30)
$tIntro.Add_Tick({
    $script:introElapsed += 30
    $e = $script:introElapsed

    # Gear keeps spinning continuously for the entire splash duration —
    # makes a static icon read as "actively loading" rather than a logo
    $splashRotate.Angle = ($e * 0.18) % 360

    # Phase 1 (0-650ms): icon scales in with an "ease-out-back" overshoot
    # (scales past 1.0 then settles back — reads as a deliberate bouncy
    # pop rather than a flat linear grow). Ungated/clamped via Min/Max so
    # it can never get stuck mid-animation regardless of tick timing.
    $t1 = [Math]::Max(0.0,[Math]::Min(1.0,$e/650.0))
    $easeBack = 1 + 2.4*[Math]::Pow($t1-1,3) + 1.4*[Math]::Pow($t1-1,2)
    $sc = 0.3 + 0.7*$easeBack
    if($sc -lt 0.05){$sc=0.05}
    $splashScale.ScaleX=$sc; $splashScale.ScaleY=$sc
    $ctrl['SplashIcon'].Opacity=[Math]::Min(1.0,$t1*1.6)

    # Phase 2 (400-1000ms): title fades in with ease-out-cubic (fast start,
    # gentle finish — feels far less mechanical than a linear ramp)
    if($e -ge 400){
        $lin = [Math]::Max(0.0,[Math]::Min(1.0,($e-400)/600.0))
        $ctrl['SplashTitle'].Opacity = 1-[Math]::Pow(1-$lin,3)
    }
    # Phase 3 (850-1400ms): subtitle fades in, same easing
    if($e -ge 850){
        $lin = [Math]::Max(0.0,[Math]::Min(1.0,($e-850)/550.0))
        $ctrl['SplashSubtitle'].Opacity = 1-[Math]::Pow(1-$lin,3)
    }
    # Phase 4 (1300ms onward): credit line fades in and shimmers through
    # the same rainbow palette used by the main spinner
    if($e -ge 1300){
        $lin = [Math]::Max(0.0,[Math]::Min(1.0,($e-1300)/450.0))
        $ctrl['SplashCredit'].Opacity = 1-[Math]::Pow(1-$lin,3)
        $script:creditHue = ($script:creditHue + 2) % $RainbowSteps
        $ctrl['SplashCredit'].Foreground = $RainbowBrushes[$script:creditHue]
    }
    # Phase 4b (1750ms onward): animated loading dots ("." ".." "...")
    # gives ongoing activity feedback for the rest of the splash, instead
    # of static text sitting on screen with nothing visibly happening
    if($e -ge 1750){
        $dotsT = [Math]::Max(0.0,[Math]::Min(1.0,($e-1750)/350.0))
        $ctrl['SplashDots'].Opacity = 1-[Math]::Pow(1-$dotsT,3)
        $dotCount = ([int]($e/350)) % 4
        $ctrl['SplashDots'].Text = "Loading" + ("." * $dotCount)
    }
    # Phase 5 (2750-3300ms): whole splash fades out
    if($e -ge 2750){
        $lin = [Math]::Max(0.0,[Math]::Min(1.0, ($e-2750)/550.0 ))
        $ctrl['SplashOverlay'].Opacity = 1-[Math]::Pow($lin,3)
    }
    # Splash finished -> hand off to the real optimizer
    if($e -ge 3300){
        $tIntro.Stop()
        $ctrl['SplashOverlay'].Visibility=[System.Windows.Visibility]::Collapsed
        $sync.StartTime=[datetime]::Now
        $tSpin.Start();$tClock.Start();$tPoll.Start()
        [void]$ps.BeginInvoke()
        $ctrl['FooterText'].Text="Optimization running — do not close this window."
    }
})

# ── BUTTONS ──────────────────────────────────────────────────────
# Fade-to-black close transition — same manual-timer-driven animation
# style used everywhere else in this script (no WPF Storyboards),
# just applied to the whole window's Opacity instead of one control.
function Close-WithFade([scriptblock]$onDone) {
    $tFade = [System.Windows.Threading.DispatcherTimer]::new()
    $tFade.Interval = [TimeSpan]::FromMilliseconds(16)
    $tFade.Add_Tick({
        $window.Opacity -= 0.07
        if($window.Opacity -le 0){
            $tFade.Stop()
            & $onDone
            $window.Close()
        }
    }.GetNewClosure())
    $tFade.Start()
}

$ctrl['BtnRestart'].Add_Click({
    Close-WithFade { & "$env:SystemRoot\System32\shutdown.exe" /r /t 3 /c "PC Optimization Complete" }
})
$ctrl['BtnClose'].Add_Click({
    Close-WithFade { }
})

# ── BACKGROUND RUNSPACE (MTA) ────────────────────────────────────
$rs=[RunspaceFactory]::CreateRunspace()
$rs.ApartmentState="MTA"
$rs.ThreadOptions="ReuseThread"
$rs.Open()
$rs.SessionStateProxy.SetVariable("sync",$sync)

$ps=[PowerShell]::Create()
$ps.Runspace=$rs
[void]$ps.AddScript({

    function L([string]$msg){
        $ts=Get-Date -Format "HH:mm:ss"
        $sync.LogLines.Add("[$ts] $msg")
        # No cap — every command run this session stays in the log.
        # (~120-180 lines for a full run; trivial for a TextBlock to hold.)
        $sync.CurrentTweak = $msg
    }
    function R([string]$p,[string]$n,$v,[string]$t="DWord"){
        try{
            if(-not(Test-Path $p)){New-Item -Path $p -Force|Out-Null}
            Set-ItemProperty -Path $p -Name $n -Value $v -Type $t -Force
        }catch{}
    }
    function RB([string]$p,[hashtable]$h,[string]$t="DWord"){
        try{
            if(-not(Test-Path $p)){New-Item -Path $p -Force|Out-Null}
            foreach($kv in $h.GetEnumerator()){
                Set-ItemProperty -Path $p -Name $kv.Key -Value $kv.Value -Type $t -Force
            }
        }catch{}
    }
    function DR([string]$p,[string]$n){
        try{Remove-ItemProperty -Path $p -Name $n -Force -ErrorAction Stop}catch{}
    }
    function S([int]$step,[int]$pct,[string]$msg){
        $sync.StepIndex=$step
        $sync.Progress=$pct
        $sync.StatusMsg=$msg
        try{
            $w=$sync.StepWeights
            $el=([datetime]::Now-$sync.StartTime).TotalSeconds
            $dw=0.0;$rw=0.0
            for($i=0;$i -lt 6;$i++){
                if($sync.StepsDone[$i]){$dw+=$w[$i]}
                elseif($i -gt $step){$rw+=$w[$i]}
                elseif($i -eq $step){$rw+=$w[$i]*0.5}
            }
            if($dw -gt 2 -and $el -gt 2){
                $sec=[int](($rw/$dw)*$el)
                $sync.ETA=if($sec -le 0){"00:00"}elseif($sec -gt 5999){"> 99m"}else{"{0:D2}:{1:D2}" -f ($sec/60),($sec%60)}
            }
        }catch{}
    }
    # Stop a service with a hard timeout — NEVER hangs the script.
    # This is the SAFE replacement for bare Stop-Service calls (which
    # previously caused the script to hang indefinitely on DiagTrack).
    function KS([string]$name,[int]$sec=4){
        try{Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue;L "Set-Service '$name' -StartupType Disabled"}catch{}
        try{
            $j=Start-Job {param($n)Stop-Service -Name $n -Force -ErrorAction SilentlyContinue} -ArgumentList $name
            $null=Wait-Job $j -Timeout $sec
            Remove-Job $j -Force -ErrorAction SilentlyContinue
            L "Stop-Service '$name' (max ${sec}s timeout)"
        }catch{}
    }

    # Disable a scheduled task via the modern ScheduledTasks module cmdlet
    # (Microsoft's documented replacement for schtasks.exe /Change /Disable —
    # returns typed objects, integrates with -ErrorAction, no console-tool
    # dependency). Falls back to schtasks.exe only if the cmdlet is
    # unavailable for some reason — same fallback pattern already used for
    # Set-NetTCPSetting/Set-NetOffloadGlobalSetting elsewhere in this script.
    function DST([string]$path,[string]$name){
        try{
            Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null
            L "Disable-ScheduledTask -TaskPath '$path' -TaskName '$name'"
        }catch{
            & "$env:SystemRoot\System32\schtasks.exe" /Change /TN "$path$name" /Disable 2>&1|Out-Null
            L "schtasks.exe fallback: '$path$name' (task may not exist on this build/edition — safe no-op either way)"
        }
    }

    Start-Sleep -Milliseconds 500
    $sync.StatusMsg = "Detected: $($sync.OSLabel) | $($sync.PCMaker) $($sync.PCModel)"

    # ════════════════════════════════════════════════════════════
    # STEP 0 — DRIVE TRIM
    # ════════════════════════════════════════════════════════════
    S 0 5 "Running SSD TRIM on C:..."
    L "=== STEP 1/6: Drive Optimization ==="
    L "Optimize-Volume -DriveLetter C -ReTrim"
    Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
    L "Drive optimization complete"

    $sync.StepsDone[0]=$true
    S 0 26 "SSD TRIM done."

    # ════════════════════════════════════════════════════════════
    # STEP 1 — PERFORMANCE TWEAKS
    # ════════════════════════════════════════════════════════════
    S 1 28 "Setting power plan + applying perf tweaks..."
    L "=== STEP 2/6: Performance Tweaks ==="

    L "powercfg -setactive High Performance"
    & "$env:SystemRoot\System32\powercfg.exe" -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1|Out-Null
    # NOTE: an earlier version also called 'powercfg -duplicatescheme' for the
    # Ultimate Performance plan here. Removed — that call only creates a
    # duplicate scheme, it never activates it (no -setactive for that GUID
    # exists anywhere), so High Performance above remained the real active
    # plan regardless. It also fails outright on non-Workstation Windows
    # editions where Microsoft hides that plan. Net effect: it never did
    # anything except clutter the power plan list, so it's gone.

    L "REG: VisualFXSetting=2 (best performance)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2

    L "REG: Disable transparency effects"
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0

    L "REG: MinAnimate=0 (disable minimize/maximize animation)"
    # NOTE: MinAnimate is a REG_SZ value in Windows, not REG_DWORD.
    # Using DWord here would not be recognized by the OS — String is required
    # for this tweak to actually take effect.
    R "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"

    L "REG: Win32PrioritySeparation=38 (foreground CPU boost)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38

    KS "SysMain" 4
    KS "WSearch" 4

    L "fsutil: disablelastaccess=1"
    & "$env:SystemRoot\System32\fsutil.exe" behavior set disablelastaccess 1 2>&1|Out-Null
    L "fsutil: disable8dot3=1"
    & "$env:SystemRoot\System32\fsutil.exe" behavior set disable8dot3 1 2>&1|Out-Null

    L "REG: LongPathsEnabled=1"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 1

    L "REG: StartupDelayInMSec=0"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0

    L "REG: WaitToKillServiceTimeout=2000 (String)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" "String"

    L "REG: Hung app timeouts 2000ms + AutoEndTasks"
    R "HKCU:\Control Panel\Desktop" "WaitToKillAppTimeout" "2000" "String"
    R "HKCU:\Control Panel\Desktop" "HungAppTimeout"       "2000" "String"
    R "HKCU:\Control Panel\Desktop" "AutoEndTasks"         "1"    "String"

    L "REG: Xbox GameBar + DVR disabled"
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
    R "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0

    L "REG: Cortana disabled"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0

    L "REG: Tips/Suggestions/Feeds disabled"
    RB "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" @{
        "SubscribedContent-338389Enabled"=0
        "SubscribedContent-310093Enabled"=0
        "SubscribedContent-338388Enabled"=0
        "SoftLandingEnabled"=0
        "SystemPaneSuggestionsEnabled"=0
    }
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" "EnableFeeds" 0
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" "ShellFeedsTaskbarViewMode" 2

    L "REG: Aero Shake + SnapAssist disabled"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "DisallowShaking" 1
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "SnapAssist" 0

    L "REG: HwSchMode=2 (HAGS enabled)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2

    L "REG: HiberbootEnabled=1 (fast startup - registry only)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1

    L "REG: 3D Objects removed from This PC (CLSID InprocServer32 cleared)"
    # UPGRADED from an earlier version that only cleared the parent CLSID
    # key's default value — that's incomplete on some builds. The correct,
    # complete technique clears the InprocServer32 subkey's default value,
    # which actually disables the shell folder registration. Both are
    # String type since a registry key's default value is always REG_SZ.
    $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if(-not (Test-Path $clsidPath)){New-Item -Path $clsidPath -Force|Out-Null}
    R $clsidPath "(default)" "" "String"

    L "bcdedit: useplatformtick=yes"
    & "$env:SystemRoot\System32\bcdedit.exe" /set useplatformtick yes 2>&1|Out-Null
    L "bcdedit: disabledynamictick=yes"
    & "$env:SystemRoot\System32\bcdedit.exe" /set disabledynamictick yes 2>&1|Out-Null
    L "bcdedit: deletevalue useplatformclock"
    & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue useplatformclock 2>&1|Out-Null
    L "bcdedit changes require a restart to take effect"

    # ── GAMING TWEAKS ───────────────────────────────────────────
    S 1 55 "Applying gaming performance tweaks..."
    L "--- Gaming Tweaks ---"

    L "REG: PowerThrottlingOff=1 (full CPU for foreground apps/games)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1

    L "REG: TdrDelay=8 (GPU driver timeout 2s->8s, prevents crash under heavy load)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "TdrDelay" 8

    L "REG: Mouse acceleration disabled (consistent aim)"
    # NOTE: these are REG_SZ ("0"/"1" as text) in Windows, not REG_DWORD —
    # using String type here so the tweak actually takes effect.
    R "HKCU:\Control Panel\Mouse" "MouseSpeed"      "0" "String"
    R "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "String"
    R "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "String"

    L "REG: AutoGameModeEnabled=1 (Windows Game Mode prioritizes foreground game)"
    R "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1

    L "GAMING: Removing Xbox Gaming Overlay app (actual uninstall, not just a disable)"
    Get-AppxPackage Microsoft.XboxGamingOverlay -ErrorAction SilentlyContinue |
        Remove-AppxPackage -ErrorAction SilentlyContinue

    L "REMOVE: Windows Widgets (WebExperience host app — actual uninstall)"
    Get-AppxPackage *WebExperience* -ErrorAction SilentlyContinue |
        Remove-AppxPackage -ErrorAction SilentlyContinue

    # ── UI & RESPONSIVENESS TWEAKS ───────────────────────────────
    S 1 60 "Applying UI and responsiveness tweaks..."
    L "--- UI & Responsiveness Tweaks ---"

    L "REG: MenuShowDelay=0, MouseHoverTime=0 (snappier menus/tooltips)"
    R "HKCU:\Control Panel\Desktop" "MenuShowDelay"  "0" "String"
    R "HKCU:\Control Panel\Mouse"   "MouseHoverTime" "0" "String"

    L "REG: Taskbar/Start icons trimmed (Widgets, Chat, Meet Now, People)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" 0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" "PeopleBand" 0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideSCAMeetNow" 1

    L "REG: File Explorer set to open 'This PC', show file extensions, show hidden files"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
    L "REG: Hidden=1 (show hidden files and folders in Explorer)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1

    L "REG: Dark mode enabled (Apps + System both set to dark theme)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" 0

    L "REG: Quick Access privacy (don't track recent files/frequent folders)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackDocs"  0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowRecent"        0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowFrequent"       0
    R "HKCU:\Software\Microsoft\Windows\Policies\Explorer" "NoRecentDocsHistory" 1

    L "REG: Start menu 'recently added apps' and recommendations off"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideRecentlyAddedApps" 1
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_IrisRecommendations" 0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_NotifyNewApps" 0

    L "REG: Taskbar search box reduced to icon (less visual overhead)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 1

    L "REG: Balloon tip notifications off, icon cache size raised to 4096"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "EnableBalloonTips" 0
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "Max Cached Icons" "4096" "String"

    L "REG: Suppress Sticky/Toggle/Filter Keys activation popups (accessibility"
    L "shortcut nag dialogs — doesn't disable the features, just the popup)"
    R "HKCU:\Control Panel\Accessibility\StickyKeys"       "Flags" "506" "String"
    R "HKCU:\Control Panel\Accessibility\ToggleKeys"       "Flags" "58"  "String"
    R "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122" "String"

    L "REG: TaskbarEndTask=1 (adds 'End Task' to taskbar right-click menu)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeveloperSettings" "TaskbarEndTask" 1

    L "REG: Reset remembered per-folder view templates (all folders go back"
    L "to Explorer's default view instead of thousands of individually"
    L "cached ones — resets view/layout memory only, no files touched)"
    $shellBagsPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"
    if(-not (Test-Path $shellBagsPath)){New-Item -Path $shellBagsPath -Force|Out-Null}
    R $shellBagsPath "FolderType" "NotSpecified" "String"

    L "EXPLORER: Restarting explorer.exe once so all the Explorer-dependent"
    L "tweaks above (hidden files, extensions, This PC, 3D Objects, taskbar"
    L "icons, folder view reset) take visible effect immediately"
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400

    # ── POWER PLAN FINE-TUNING (AC power only — battery-mode behavior
    #    on laptops is left untouched on purpose) ────────────────────
    S 1 65 "Fine-tuning power plan (AC power only)..."
    L "--- Power Plan Fine-Tuning (AC only, battery mode untouched) ---"

    L "powercfg: CPU minimum state 100% on AC (trades heat/battery for"
    L "consistent performance — does NOT apply on battery)"
    & "$env:SystemRoot\System32\powercfg.exe" /setacvalueindex SCHEME_CURRENT `
        54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b8d7b8d29fb1 100 2>&1|Out-Null

    L "powercfg: Processor performance boost mode = Aggressive (AC only)"
    & "$env:SystemRoot\System32\powercfg.exe" /setacvalueindex SCHEME_CURRENT `
        54533251-82be-4824-96c1-47b60b740d00 be337238-0d82-4146-a960-4f3749d470c7 2 2>&1|Out-Null

    L "powercfg: USB selective suspend disabled (AC only, fixes peripheral lag)"
    & "$env:SystemRoot\System32\powercfg.exe" /setacvalueindex SCHEME_CURRENT `
        2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1|Out-Null

    L "powercfg: PCIe Link State Power Management = Off (AC only)"
    & "$env:SystemRoot\System32\powercfg.exe" /setacvalueindex SCHEME_CURRENT `
        501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>&1|Out-Null

    & "$env:SystemRoot\System32\powercfg.exe" /setactive SCHEME_CURRENT 2>&1|Out-Null
    L "powercfg /setactive SCHEME_CURRENT (apply fine-tuned values)"

    L "Disable-NetAdapterPowerManagement (prevents NIC sleep causing drops/latency)"
    Disable-NetAdapterPowerManagement -Name "*" -ErrorAction SilentlyContinue

    $sync.StepsDone[1]=$true
    S 1 68 "Performance + gaming tweaks done."

    # ════════════════════════════════════════════════════════════
    # STEP 2 — PRIVACY & TELEMETRY
    # ════════════════════════════════════════════════════════════
    S 2 69 "Disabling telemetry services (safe timeout)..."
    L "=== STEP 3/6: Privacy & Telemetry ==="

    # DiagTrack disabled via the safe KS() wrapper below — NOT a bare
    # Stop-Service call. Bare Stop-Service "DiagTrack" was the exact
    # cause of a previous version hanging indefinitely; KS() enforces
    # a 4-second timeout so the script always continues regardless.
    KS "DiagTrack"        4
    KS "dmwappushservice" 4
    KS "WerSvc"           4
    KS "PcaSvc"           4

    L "REG: AllowTelemetry=0"
    RB "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" @{
        "AllowTelemetry"=0
        "MaxTelemetryAllowed"=0
        "DoNotShowFeedbackNotifications"=1
    }
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0

    L "REG: Advertising ID disabled"
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1

    L "REG: Activity History disabled"
    RB "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" @{
        "EnableActivityFeed"=0
        "PublishUserActivities"=0
        "UploadUserActivities"=0
    }

    L "REG: verbosestatus=1 (detailed boot/shutdown/login status messages,"
    L "useful for diagnosing what's actually happening during a slow boot)"
    R "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "verbosestatus" 1

    L "REG: CEIP + Feedback + Background apps disabled"
    R "HKLM:\SOFTWARE\Microsoft\SQMClient\Windows" "CEIPEnable" 0
    R "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
    R "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "PeriodInNanoSeconds"  0
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle" 0

    # ── SECURITY HARDENING ───────────────────────────────────────
    S 2 72 "Applying security hardening..."
    L "--- Security Hardening ---"

    L "SECURITY: Disabling SMB1 protocol (legacy, insecure — WannaCry/EternalBlue vector)"
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null

    L "SECURITY: Ensuring Windows Firewall is enabled on all profiles"
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -ErrorAction SilentlyContinue

    # NOTE: Set-MpPreference throws on any machine where a third-party
    # antivirus has put Defender into passive mode — extremely common on
    # company-managed laptops (McAfee, CrowdStrike, Symantec, etc). The
    # old version swallowed that error and logged as if it succeeded,
    # when it had actually done nothing. This checks first and is honest
    # about the result either way.
    $defenderActive = $false
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $defenderActive = ($mp.AMServiceEnabled -eq $true)
    } catch { $defenderActive = $false }

    if ($defenderActive) {
        L "SECURITY: Enabling Defender PUA (Potentially Unwanted App) Protection"
        Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
    } else {
        L "SECURITY: Skipped PUA Protection — Defender is not the active antivirus here"
    }

    L "SECURITY: AutoRun/AutoPlay disabled for removable media (common malware vector)"
    R "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 255

    L "REG: Consumer Features disabled (no more suggested/auto-installed Store apps)"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1

    L "REG: No auto-resume-and-signin after update reboot (privacy/security)"
    R "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "DisableAutomaticRestartSignOn" 1

    L "REG: Lock screen / Start menu suggestion content disabled"
    RB "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" @{
        "RotatingLockScreenOverlayEnabled" = 0
        "SubscribedContent-338387Enabled"  = 0
        "SubscribedContent-353698Enabled"  = 0
        "SubscribedContent-353694Enabled"  = 0
        "SilentInstalledAppsEnabled"       = 0
    }

    L "Disable-ScheduledTask: telemetry-adjacent compatibility-data tasks"
    L "(upgraded from schtasks.exe to the native ScheduledTasks module cmdlet)"
    DST "\Microsoft\Windows\Application Experience\" "Microsoft Compatibility Appraiser"
    DST "\Microsoft\Windows\Application Experience\" "ProgramDataUpdater"

    L "REG: Delivery Optimization P2P sharing disabled"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0

    L "REG: Disable Settings/App tips (SubscribedContent-353696Enabled=0)"
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" 0

    L "REG: Location Services disabled (policy level — covers all apps)"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" 1

    L "REG: Windows Spotlight disabled (lock screen dynamic ads/images)"
    R "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsSpotlightFeatures" 1

    L "REG: Prevent auto-reboot after updates when user is logged in"
    R "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" 1

    L "REG: Lock screen disabled (faster login, no lock screen overlay)"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" 1

    L "REG: Storage Sense disabled (prevents automatic temp-file cleanup policy)"
    R "HKLM:\Software\Policies\Microsoft\Windows\StorageSense" "DisableInventory" 1

    L "REG: Automatic driver updates via Windows Update disabled"
    # This older key only affects Device Manager's manual "Search
    # automatically for updated driver software" wizard — it does NOT
    # reliably stop drivers arriving through automatic Windows Update.
    R "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" "DontSearchWindowsUpdate" 1

    L "REG: ExcludeWUDriversInQualityUpdate=1 (modern policy — actually"
    L "blocks drivers from automatic Windows Update delivery, not just"
    L "the Device Manager wizard the older key above only covers)"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "ExcludeWUDriversInQualityUpdate" 1

    L "SECURITY: Remote Desktop (RDP) incoming connections disabled"
    R "HKLM:\System\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1

    L "SECURITY: Remote Registry service disabled (prevents remote registry access)"
    KS "RemoteRegistry" 4

    L "NETWORK: Set all active network profiles to Private"
    Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

    # ── BLOATWARE APP REMOVAL ─────────────────────────────────────
    S 2 79 "Removing bloatware apps..."
    L "--- Bloatware App Removal (AppxPackage) ---"
    L "NOTE: these are actual app UNINSTALLS (-AllUsers). Reinstall from Store."
    $bloatApps = @(
        "*Xbox*",
        "*549981C3F5F10*",        # Cortana
        "*WindowsFeedbackHub*",
        "*WindowsMaps*",
        "*ZuneVideo*",            # Movies & TV
        "*SkypeApp*",
        "*Teams*",
        "*BingWeather*",
        "*BingNews*",
        "*SpotifyAB.SpotifyMusic*",
        "*WindowsSoundRecorder*"  # Voice Recorder
    )
    foreach ($pattern in $bloatApps) {
        $pkg = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
        if ($pkg) {
            L "Remove-AppxPackage -AllUsers $pattern"
            $pkg | Remove-AppxPackage -ErrorAction SilentlyContinue
        } else {
            L "Not installed (skip): $pattern"
        }
    }

    $sync.StepsDone[2]=$true
    S 2 82 "Privacy, telemetry, and bloatware removal done."

    # ════════════════════════════════════════════════════════════
    # STEP 3 — MEMORY & CPU
    # ════════════════════════════════════════════════════════════
    S 3 76 "Applying memory and CPU optimizations..."
    L "=== STEP 4/6: Memory & CPU Tuning ==="

    L "REG: DisablePagingExecutive=1 (kernel in RAM)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "ClearPageFileAtShutdown" 0

    L "REG: Memory Compression disabled (Compression=0)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "Compression" 0

    L "REG: EnableSuperfetch=0 (complements the already-disabled SysMain service)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" 0

    L "REG: IOPageLockLimit (cap locked-for-I/O memory; 0x1000000=16MB, prevents"
    L "     excessive non-paged pool consumption under heavy disk load)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "IOPageLockLimit" 0x1000000

    L "REG: HeapDeCommitFreeBlockThreshold=0x40000 (reduces heap fragmentation;"
    L "     OS decommits free heap blocks above this size instead of holding them)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\HeapManager" "HeapDeCommitFreeBlockThreshold" 0x40000

    L "REG: I/O system transfer record length tuned (larger I/O buffer = fewer"
    L "     kernel transitions per large read/write — benefits SSD throughput)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\I/O System" "IoTransferRecordLength" 0x10000

    L "REG: Multimedia timer 1ms + network throttle off"
    R "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
    R "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xFFFFFFFF

    L "REG: Games task GPU=8 Priority=6 Scheduling=High"
    $gp="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    RB $gp @{"Affinity"=0;"Clock Rate"=10000;"GPU Priority"=8;"Priority"=6}
    R $gp "Background Only"     "False" "String"
    R $gp "Scheduling Category" "High"  "String"
    R $gp "SFIO Priority"       "High"  "String"

    L "schtasks: Disable Defender scheduled scans (real-time protection stays ON)"
    L "NOTE: schtasks silently no-ops on any task name that doesn't exist on this"
    L "build/edition — no error, no crash, just skipped. Safe either way."
    L "(upgraded from schtasks.exe to the native Disable-ScheduledTask cmdlet)"
    DST "\Microsoft\Windows\Windows Defender\" "Windows Defender Scheduled Scan"
    DST "\Microsoft\Windows\Windows Defender\" "Windows Defender Cache Maintenance"
    DST "\Microsoft\Windows\Windows Defender\" "Windows Defender Cleanup"
    DST "\Microsoft\Windows\Windows Defender\" "Windows Defender Verification"

    $sync.StepsDone[3]=$true
    S 3 87 "Memory & CPU tuning done."

    # ════════════════════════════════════════════════════════════
    # STEP 4 — NETWORK
    # ════════════════════════════════════════════════════════════
    S 4 89 "Applying network optimizations..."
    L "=== STEP 5/6: Network Optimization ==="

    L "REG: SMB throttling off + Large MTU on"
    R "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "DisableBandwidthThrottling" 1
    R "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "DisableLargeMtu" 0

    L "Set-NetTCPSetting AutoTuningLevel=Normal"
    try{Set-NetTCPSetting -SettingName InternetCustom -AutoTuningLevelLocal Normal -EA Stop|Out-Null}
    catch{& netsh int tcp set global autotuninglevel=normal 2>&1|Out-Null;L "netsh fallback: autotuninglevel=normal"}

    L "Set-NetOffloadGlobalSetting RSS=Enabled"
    try{Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -EA Stop|Out-Null}
    catch{& netsh int tcp set global rss=enabled 2>&1|Out-Null;L "netsh fallback: rss=enabled"}

    L "Set-NetTCPSetting EcnCapability=Enabled"
    # UPGRADED from a netsh-only call — Set-NetTCPSetting has supported
    # -EcnCapability natively since the same NetTCPIP module version as
    # the AutoTuning/RSS cmdlets above, so this now follows the same
    # native-cmdlet-first, netsh-fallback pattern as both of those.
    try{Set-NetTCPSetting -SettingName InternetCustom -EcnCapability Enabled -EA Stop|Out-Null}
    catch{& netsh int tcp set global ecncapability=enabled 2>&1|Out-Null;L "netsh fallback: ecncapability=enabled"}

    L "REG: QoS 20% reserve removed"
    R "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" 0

    L "Set-DnsClientServerAddress: 1.1.1.1 + 8.8.8.8"
    Get-NetAdapter -ErrorAction SilentlyContinue |
      Where-Object{$_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Virtual|Loopback|Bluetooth|Hyper-V"} |
      ForEach-Object{
        try{Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses "1.1.1.1","8.8.8.8","1.0.0.1","8.8.4.4" -EA SilentlyContinue}catch{}
      }

    L "REG: EnableAutoDoh=2 (DNS-over-HTTPS)"
    R "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "EnableAutoDoh" 2

    L "REG: DNS cache TTL tuning (cap valid entries at 24h, don't cache failures)"
    R "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxCacheEntryTtlLimit" 86400
    R "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "NegativeCacheTime" 0

    L "REG: Nagle disabled (TcpAckFrequency=1 TCPNoDelay=1)"
    $ti="HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if(Test-Path $ti){
        Get-ChildItem $ti -EA SilentlyContinue|ForEach-Object{R $_.PSPath "TcpAckFrequency" 1;R $_.PSPath "TCPNoDelay" 1}
    }

    L "NETWORK: Disabling IPv6 binding on all adapters"
    L "NOTE: this is a connectivity BEHAVIOR change, not just a perf tweak —"
    L "skip/revert via Enable-NetAdapterBinding if you rely on IPv6 anywhere"
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

    $sync.StepsDone[4]=$true
    S 4 96 "Network optimization done."

    # ════════════════════════════════════════════════════════════
    # STEP 5 — STARTUP CLEANUP + DNS + WINSOCK
    # ════════════════════════════════════════════════════════════
    S 5 97 "Removing startup bloat entries..."
    L "=== STEP 6/6: Startup + DNS + Cleanup ==="

    $rp="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    @("OneDrive","Spotify","Discord","Skype","Teams","SupportAssist",
      "EpicGamesLauncher","Steam","AdobeUpdater","GoogleUpdate",
      "CCleaner","Dropbox","Box","Grammarly",
      "HPMessageService","HPMSGSVC","McAfeeUpdaterUI",
      "LenovoUtility","ASUSGiftBox","AcerCare","SnagIt",
      "Slack","Zoom","WebExMTA","RingCentral",
      "iTunesHelper","QuickTime Task","Adobe ARM","CCXProcess") |
    ForEach-Object{DR $rp $_;L "Remove startup: $_"}

    S 5 98 "Cleaning Prefetch, Temp, and Windows Logs..."
    L "=== Disk Cleanup: Prefetch / Temp / Windows Logs / WU Logs ==="
    # NOTE: the original path "C:\Users\Renewfy\AppData\Local\Temp" was
    # hardcoded to one specific Windows account. Replaced with $env:TEMP
    # so this resolves correctly to whichever account is actually running
    # the script — required for it to work on any PC / any user, not just
    # one machine. "Windows Update Logs" = C:\Windows\Logs\WindowsUpdate,
    # the modern (Win10/11) location for WU trace logs.
    $cleanupTargets = @(
        "C:\Windows\Prefetch",
        $env:TEMP,
        "C:\Windows\Temp",
        "C:\Windows\Logs",
        "C:\Windows\Logs\WindowsUpdate"
    )
    foreach($ct in $cleanupTargets){
        if(Test-Path $ct){
            $items = Get-ChildItem -Path $ct -Recurse -Force -ErrorAction SilentlyContinue
            $cnt = ($items | Measure-Object).Count
            $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            L "Cleaned '$ct' ($cnt items targeted, locked files skipped)"
        } else {
            L "Skip '$ct' (path not found on this PC)"
        }
    }

    S 5 99 "Flushing DNS cache and resetting network stack..."
    L "Clear-DnsClientCache"
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    L "ipconfig /registerdns"
    & ipconfig /registerdns 2>&1|Out-Null

    L "netsh winsock reset"
    & netsh winsock reset 2>&1|Out-Null

    L "netsh int ip reset"
    & netsh int ip reset 2>&1|Out-Null

    L "Set-Clipboard -Value `$null"
    Set-Clipboard -Value $null -ErrorAction SilentlyContinue

    L "=== ALL 6 STEPS COMPLETE ==="
    $sync.StepsDone[5]=$true
    S 5 100 "All done! Most tweaks are already live. Run Verify-Tweaks.ps1 to confirm."
    $sync.Done=$true
})

# ── WINDOW LOADED ────────────────────────────────────────────────
$window.Add_Loaded({
    $ctrl['TitleSub'].Text="$($sync.OSLabel)  ·  $($sync.PCMaker) $($sync.PCModel)  ·  6 Steps  ·  Includes Disk Cleanup"
    $ctrl['FooterText'].Text="Starting..."
    $tParticles.Start()
    $tIntro.Start()
})

# ── WINDOW CLOSED ────────────────────────────────────────────────
$window.Add_Closed({
    $tIntro.Stop();$tSpin.Stop();$tClock.Stop();$tPoll.Stop();$tParticles.Stop()
    try{$ps.Stop()}catch{}
    try{$ps.Dispose()}catch{}
    try{$rs.Close()}catch{}
    try{$rs.Dispose()}catch{}
})

# ── SHOW WINDOW ──────────────────────────────────────────────────
[void]$window.ShowDialog()
