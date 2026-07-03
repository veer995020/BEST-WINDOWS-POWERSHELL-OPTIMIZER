    # ================================================================
#  UNIVERSAL PC OPTIMIZER v15.3
#  Works on: Windows 10 / 11 | All laptop/desktop brands
#  PowerShell 5.1+  |  GUI + Live Command Log
#  No DISM / No SFC / No Windows Update / No Winget (removed per request)
#  Includes disk cleanup: Prefetch, Temp, Windows Logs, WU Logs
#  Includes gaming tweaks, rainbow spinner, animated splash, PS-console log
#  Includes security hardening (SMB1 off, Firewall on, PUA, RDP off, RemoteReg off)
#  Includes ~70+ total tweaks across 6 steps
#  v15.1: fixed progress bar going backwards between Step 1 and Step 2
#  v15.2: splash animation overhaul — ease-out-back icon bounce,
#         ease-out-cubic fades, continuously spinning gear, loading dots
#  v15.3: +22 new tweaks from document (location, spotlight, dark mode,
#         hidden files, lock screen, 11 bloatware app removals, RDP/RemoteReg,
#         network Private, 353696, driver updates, Storage Sense, auto-reboot)
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
$OSCaption  = (Get-WmiObject Win32_OperatingSystem).Caption
$OSBuild    = (Get-WmiObject Win32_OperatingSystem).BuildNumber
$PCMaker    = (Get-WmiObject Win32_ComputerSystem).Manufacturer
$PCModel    = (Get-WmiObject Win32_ComputerSystem).Model
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
    Title="Universal PC Optimizer v15.3"
    Height="880" Width="1040"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize"
    Background="#06070F">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="78"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="52"/>
    </Grid.RowDefinitions>

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
          <TextBlock x:Name="TitleMain" Text="UNIVERSAL PC OPTIMIZER" FontSize="21"
                     FontWeight="Bold" Foreground="White" FontFamily="Segoe UI"/>
          <TextBlock x:Name="TitleSub" Text="Detecting system..."
                     FontSize="10.5" Foreground="#90BBDC" FontFamily="Segoe UI"/>
        </StackPanel>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="ClockText" HorizontalAlignment="Right"
                     FontSize="16" FontWeight="Bold" Foreground="White" FontFamily="Segoe UI Mono"/>
          <TextBlock Text="LOCAL TIME" HorizontalAlignment="Right"
                     FontSize="8" Foreground="#4A7AAA" FontFamily="Segoe UI Mono"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- MAIN -->
    <Grid Grid.Row="1" Margin="22,12,22,8">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="285"/>
        <ColumnDefinition Width="18"/>
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

        <Grid Grid.Row="0" HorizontalAlignment="Center" VerticalAlignment="Center" Width="196" Height="196">
          <Ellipse x:Name="RingOuter" Width="196" Height="196"
                   StrokeThickness="5" StrokeDashArray="28 8" Stroke="#003A7A">
            <Ellipse.RenderTransform><RotateTransform x:Name="RotOuter" CenterX="98" CenterY="98"/></Ellipse.RenderTransform>
            <Ellipse.Effect><DropShadowEffect Color="#0076CE" BlurRadius="10" ShadowDepth="0" Opacity="0.7"/></Ellipse.Effect>
          </Ellipse>
          <Ellipse x:Name="RingMid" Width="154" Height="154"
                   StrokeThickness="3" StrokeDashArray="12 12" Stroke="#0088CC">
            <Ellipse.RenderTransform><RotateTransform x:Name="RotMid" CenterX="77" CenterY="77"/></Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse x:Name="RingInner" Width="114" Height="114"
                   StrokeThickness="4" StrokeDashArray="6 18" Stroke="#00BBFF">
            <Ellipse.RenderTransform><RotateTransform x:Name="RotInner" CenterX="57" CenterY="57"/></Ellipse.RenderTransform>
            <Ellipse.Effect><DropShadowEffect Color="#00CCFF" BlurRadius="16" ShadowDepth="0" Opacity="0.9"/></Ellipse.Effect>
          </Ellipse>
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock x:Name="PctText" Text="0%" HorizontalAlignment="Center"
                       FontSize="42" FontWeight="Bold" Foreground="#00CCFF" FontFamily="Segoe UI Light">
              <TextBlock.Effect><DropShadowEffect Color="#00AAFF" BlurRadius="22" ShadowDepth="0" Opacity="0.9"/></TextBlock.Effect>
            </TextBlock>
            <TextBlock x:Name="StepNumText" Text="STEP 0/6" HorizontalAlignment="Center"
                       FontSize="9" Foreground="#2A4060" FontFamily="Segoe UI Mono"/>
          </StackPanel>
        </Grid>

        <TextBlock Grid.Row="2" Text="OVERALL PROGRESS" FontSize="8"
                   Foreground="#1E2E40" FontFamily="Segoe UI Mono" HorizontalAlignment="Center"/>
        <Grid x:Name="PrgContainer" Grid.Row="3" Height="10">
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
                   TextAlignment="Center" FontSize="10.5" Foreground="#3A5878"
                   FontFamily="Segoe UI" HorizontalAlignment="Center"/>
        <StackPanel Grid.Row="7" Orientation="Horizontal" HorizontalAlignment="Center">
          <TextBlock Text="ETA  " Foreground="#162030" FontSize="9" FontFamily="Segoe UI Mono" VerticalAlignment="Center"/>
          <TextBlock x:Name="EtaLeft" Text="--:--" Foreground="#1E3550" FontSize="12"
                     FontFamily="Segoe UI Mono" FontWeight="Bold" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>

      <!-- RIGHT: STEPS + COMMAND LOG -->
      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="10"/>
          <RowDefinition Height="280"/>
        </Grid.RowDefinitions>

        <!-- STEP LIST (6 steps) -->
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="StepPanel">
            <TextBlock Text="OPTIMIZATION  PIPELINE" FontSize="8" FontWeight="Bold"
                       Foreground="#1A2A38" FontFamily="Segoe UI Mono" Margin="2,0,0,7"/>

            <Border x:Name="Step0" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon0" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl0" Grid.Column="1" Text="Drive Optimization (TRIM)" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag0" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step1" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon1" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl1" Grid.Column="1" Text="Performance Tweaks" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag1" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step2" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon2" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl2" Grid.Column="1" Text="Privacy &amp; Telemetry" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag2" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step3" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon3" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl3" Grid.Column="1" Text="Memory &amp; CPU Tuning" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag3" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step4" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon4" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl4" Grid.Column="1" Text="Network Optimization" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag4" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step5" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon5" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl5" Grid.Column="1" Text="Startup, DNS &amp; Disk Cleanup" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag5" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

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
                         FontFamily="Consolas" FontSize="9.5"
                         Foreground="#E8E8E8" TextWrapping="Wrap"
                         Text="Waiting for optimizer to start..."/>
            </ScrollViewer>
            <StackPanel Grid.Row="4" Orientation="Horizontal">
              <TextBlock
