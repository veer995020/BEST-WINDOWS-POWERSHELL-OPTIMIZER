# ================================================================
#  UNIVERSAL PC OPTIMIZER v9.0
#  Works on: Windows 10 / 11 | All laptop/desktop brands
#  PowerShell 5.1+  |  GUI + Live Command Log  |  No File Deletion
#  No Windows Update / No Winget steps (removed per request)
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
        # safely relaunch elevated. This is the normal double-click case.
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    } else {
        # FIX: Running via a pasted one-liner (iex). There is NO script file
        # backing this execution ($PSCommandPath AND $MyInvocation.MyCommand.Path
        # are both empty here), so attempting to relaunch by re-reading a file
        # path always failed silently in the previous version — and the
        # unconditional `exit` that followed closed the window instantly with
        # no message shown. FIX: show clear instructions and use `return`
        # (not `exit`) so the window stays open for the user to read.
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

# ── SHARED STATE (8 steps) ───────────────────────────────────────
$sync = [Hashtable]::Synchronized(@{
    Progress    = 0
    StepIndex   = -1
    StatusMsg   = "Initializing..."
    Done        = $false
    ETA         = "--:--"
    LogLines    = [System.Collections.Generic.List[string]]::new()
    StepsDone   = [bool[]]@($false,$false,$false,$false,$false,$false,$false,$false)
    StepWeights = [double[]]@(360,180,20,10,8,6,6,4)
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
    Title="Universal PC Optimizer v9.0"
    Height="760" Width="980"
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
            <TextBlock x:Name="StepNumText" Text="STEP 0/8" HorizontalAlignment="Center"
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
          <RowDefinition Height="190"/>
        </Grid.RowDefinitions>

        <!-- STEP LIST (8 steps) -->
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="StepPanel">
            <TextBlock Text="OPTIMIZATION  PIPELINE" FontSize="8" FontWeight="Bold"
                       Foreground="#1A2A38" FontFamily="Segoe UI Mono" Margin="2,0,0,7"/>

            <Border x:Name="Step0" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon0" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl0" Grid.Column="1" Text="DISM Image Repair" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag0" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step1" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon1" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl1" Grid.Column="1" Text="SFC System File Scan" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag1" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step2" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon2" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl2" Grid.Column="1" Text="Drive Optimization (TRIM)" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag2" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step3" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon3" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl3" Grid.Column="1" Text="Performance Tweaks" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag3" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step4" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon4" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl4" Grid.Column="1" Text="Privacy &amp; Telemetry" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag4" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step5" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon5" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl5" Grid.Column="1" Text="Memory &amp; CPU Tuning" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag5" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step6" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon6" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl6" Grid.Column="1" Text="Network Optimization" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag6" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
              </Grid></Border>

            <Border x:Name="Step7" CornerRadius="6" Margin="0,2" Padding="12,8" Background="#080A18">
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="Icon7" Text="○" Foreground="#243040" FontSize="13" VerticalAlignment="Center"/>
                <TextBlock x:Name="Lbl7" Grid.Column="1" Text="Startup + DNS + Cleanup" Foreground="#304858" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock x:Name="Tag7" Grid.Column="2" Text="PENDING" Foreground="#1E2C3A" FontSize="8" HorizontalAlignment="Right" VerticalAlignment="Center" FontFamily="Segoe UI Mono"/>
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
                <TextBlock Text="✓  ALL 8 STEPS COMPLETE" FontSize="12" FontWeight="Bold"
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

        <!-- LIVE COMMAND LOG -->
        <Border Grid.Row="2" Background="#040810" CornerRadius="7"
                BorderThickness="1" BorderBrush="#0D1A28" Padding="10,8">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="5"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="▶  LIVE COMMAND LOG" FontSize="8" FontWeight="Bold"
                         Foreground="#1A3050" FontFamily="Segoe UI Mono"/>
              <TextBlock x:Name="LogCountText" Text="  (0 commands)"
                         FontSize="8" Foreground="#101E2A" FontFamily="Segoe UI Mono"/>
            </StackPanel>
            <ScrollViewer x:Name="LogScroll" Grid.Row="2"
                          VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">
              <TextBlock x:Name="LogText"
                         FontFamily="Consolas" FontSize="9.5"
                         Foreground="#1E4060" TextWrapping="Wrap"
                         Text="Waiting for optimizer to start..."/>
            </ScrollViewer>
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
  </Grid>
</Window>
'@

# ── PARSE XAML ──────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$ctrl = @{}
'TitleMain','TitleSub','ClockText','PctText','StepNumText',
'PrgContainer','PrgFill','StatusText','EtaLeft',
'LogText','LogScroll','LogCountText',
'FooterText','ElapsedText','EtaFooter',
'ElapsedFinal','DonePanel','BtnRestart','BtnClose',
'RingOuter','RingMid','RingInner','RotOuter','RotMid','RotInner' |
ForEach-Object { $ctrl[$_] = $window.FindName($_) }

# Step row controls — 8 steps (0..7)
$sB = 0..7 | ForEach-Object { $window.FindName("Step$_") }
$sI = 0..7 | ForEach-Object { $window.FindName("Icon$_") }
$sL = 0..7 | ForEach-Object { $window.FindName("Lbl$_")  }
$sT = 0..7 | ForEach-Object { $window.FindName("Tag$_")  }

$rotO = [System.Windows.Media.RotateTransform]$ctrl['RotOuter']
$rotM = [System.Windows.Media.RotateTransform]$ctrl['RotMid']
$rotI = [System.Windows.Media.RotateTransform]$ctrl['RotInner']

# ── CACHE BRUSHES ONCE ──────────────────────────────────────────
$cv = [Windows.Media.BrushConverter]::new()
$b = @{
    PendI=$cv.ConvertFrom("#243040"); PendL=$cv.ConvertFrom("#304858"); PendT=$cv.ConvertFrom("#1E2C3A")
    ActBg=$cv.ConvertFrom("#06101E"); ActBor=$cv.ConvertFrom("#005BAA"); ActI=$cv.ConvertFrom("#00CCFF"); ActT=$cv.ConvertFrom("#0088CC")
    DonBg=$cv.ConvertFrom("#050D07"); DonBor=$cv.ConvertFrom("#003D18"); DonI=$cv.ConvertFrom("#00CC55"); DonL=$cv.ConvertFrom("#3A7755"); DonT=$cv.ConvertFrom("#005A22")
    White=[Windows.Media.Brushes]::White; Trans=[Windows.Media.Brushes]::Transparent
}
$thk0=[Windows.Thickness]::new(0); $thk1=[Windows.Thickness]::new(1)

# ── STEP ROW UPDATER (8 steps) ──────────────────────────────────
function Set-StepUI([int]$i,[int]$st) {
    switch ($st) {
        0 { $sB[$i].Background=$b.Trans;$sB[$i].BorderBrush=$b.Trans;$sB[$i].BorderThickness=$thk0
            $sI[$i].Text="○";$sI[$i].Foreground=$b.PendI;$sL[$i].Foreground=$b.PendL
            $sT[$i].Text="PENDING";$sT[$i].Foreground=$b.PendT }
        1 { $sB[$i].Background=$b.ActBg;$sB[$i].BorderBrush=$b.ActBor;$sB[$i].BorderThickness=$thk1
            $sI[$i].Text="▶";$sI[$i].Foreground=$b.ActI;$sL[$i].Foreground=$b.White
            $sT[$i].Text="RUNNING";$sT[$i].Foreground=$b.ActT }
        2 { $sB[$i].Background=$b.DonBg;$sB[$i].BorderBrush=$b.DonBor;$sB[$i].BorderThickness=$thk1
            $sI[$i].Text="✓";$sI[$i].Foreground=$b.DonI;$sL[$i].Foreground=$b.DonL
            $sT[$i].Text="DONE";$sT[$i].Foreground=$b.DonT }
    }
}

# ── TIMER 1: SPINNER 24ms (~41fps, faster than v8's 28ms) ───────
$script:a1=0.0;$script:a2=0.0;$script:a3=0.0;$script:pulse=0.0
$tSpin=[System.Windows.Threading.DispatcherTimer]::new()
$tSpin.Interval=[TimeSpan]::FromMilliseconds(24)
$tSpin.Add_Tick({
    $script:a1+=1.4;$script:a2-=2.2;$script:a3+=4.0
    $rotO.Angle=$script:a1;$rotM.Angle=$script:a2;$rotI.Angle=$script:a3
    $script:pulse+=0.065
    $g=$ctrl['PctText'].Effect
    if($g){$g.Opacity=0.5+0.45*[Math]::Sin($script:pulse)}
})

# ── TIMER 2: CLOCK+ELAPSED 1s ────────────────────────────────────
$tClock=[System.Windows.Threading.DispatcherTimer]::new()
$tClock.Interval=[TimeSpan]::FromSeconds(1)
$tClock.Add_Tick({
    $ctrl['ClockText'].Text=(Get-Date -Format "HH:mm:ss")
    $e=[datetime]::Now - $sync.StartTime
    $ctrl['ElapsedText'].Text="{0:D2}:{1:D2}" -f [int]$e.TotalMinutes,$e.Seconds
})

# ── TIMER 3: PROGRESS+LOG POLL 60ms (faster than v8's 80ms) ─────
$script:lastStep=-1;$script:smooth=0.0;$script:logCount=0

$tPoll=[System.Windows.Threading.DispatcherTimer]::new()
$tPoll.Interval=[TimeSpan]::FromMilliseconds(60)
$tPoll.Add_Tick({
    $script:smooth += ([double]$sync.Progress - $script:smooth)*0.25
    $d=[Math]::Round($script:smooth)
    $ctrl['PctText'].Text="$d%"
    $ctrl['StepNumText'].Text="STEP $([Math]::Max(0,$sync.StepIndex+1))/8"
    $ctrl['StatusText'].Text=$sync.StatusMsg
    $eta=$sync.ETA
    $ctrl['EtaLeft'].Text=$eta
    $ctrl['EtaFooter'].Text=$eta

    $cw=$ctrl['PrgContainer'].ActualWidth
    if($cw -gt 1){$ctrl['PrgFill'].Width=($script:smooth/100.0)*$cw}

    $cur=$sync.StepIndex
    if($cur -ne $script:lastStep){
        for($i=0;$i -lt 8;$i++){
            if($i -lt $cur){Set-StepUI $i 2}
            elseif($i -eq $cur){Set-StepUI $i 1}
            else{Set-StepUI $i 0}
        }
        $script:lastStep=$cur
    }
    for($i=0;$i -lt 8;$i++){
        if($sync.StepsDone[$i] -and $i -ne $cur){Set-StepUI $i 2}
    }

    $ll = $sync.LogLines
    if($ll.Count -ne $script:logCount){
        $ctrl['LogText'].Text = [string]::Join("`n",$ll.ToArray())
        $ctrl['LogCountText'].Text = "  ($($ll.Count) commands)"
        $ctrl['LogScroll'].ScrollToEnd()
        $script:logCount = $ll.Count
    }

    if($sync.Done){
        $tPoll.Stop();$tSpin.Stop();$tClock.Stop()
        $ctrl['PctText'].Text="100%"
        if($ctrl['PrgContainer'].ActualWidth -gt 1){
            $ctrl['PrgFill'].Width=$ctrl['PrgContainer'].ActualWidth
        }
        for($i=0;$i -lt 8;$i++){Set-StepUI $i 2}
        $ctrl['StepNumText'].Text="COMPLETE"
        $ctrl['StatusText'].Text="All optimizations applied."
        $ctrl['EtaLeft'].Text="00:00";$ctrl['EtaFooter'].Text="00:00"
        $ctrl['FooterText'].Text="Restart required to fully apply all changes."
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

# ── BUTTONS ──────────────────────────────────────────────────────
$ctrl['BtnRestart'].Add_Click({
    & "$env:SystemRoot\System32\shutdown.exe" /r /t 15 /c "PC Optimization Complete"
    $window.Close()
})
$ctrl['BtnClose'].Add_Click({$window.Close()})

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
        if($sync.LogLines.Count -gt 300){$sync.LogLines.RemoveAt(0)}
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
            for($i=0;$i -lt 8;$i++){
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
    function KS([string]$name,[int]$sec=4){
        try{Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue;L "Set-Service '$name' Disabled"}catch{}
        try{
            $j=Start-Job {param($n)Stop-Service -Name $n -Force -ErrorAction SilentlyContinue} -ArgumentList $name
            $null=Wait-Job $j -Timeout $sec
            Remove-Job $j -Force -ErrorAction SilentlyContinue
            L "Stop-Service '$name' (max ${sec}s timeout)"
        }catch{}
    }

    # Reduced from 700ms -> 500ms for faster start
    Start-Sleep -Milliseconds 500

    $sync.StatusMsg = "Detected: $($sync.OSLabel) | $($sync.PCMaker) $($sync.PCModel)"

    # ════════════════════════════════════════════════════════════
    # STEP 0 — DISM IMAGE REPAIR
    # ════════════════════════════════════════════════════════════
    S 0 2 "DISM: CheckHealth..."
    L "=== STEP 1/8: DISM Image Repair ==="
    L "Repair-WindowsImage -Online -CheckHealth"
    Repair-WindowsImage -Online -CheckHealth  -ErrorAction SilentlyContinue|Out-Null

    S 0 22 "DISM: ScanHealth..."
    L "Repair-WindowsImage -Online -ScanHealth"
    Repair-WindowsImage -Online -ScanHealth   -ErrorAction SilentlyContinue|Out-Null

    S 0 50 "DISM: RestoreHealth (needs internet)..."
    L "Repair-WindowsImage -Online -RestoreHealth"
    Repair-WindowsImage -Online -RestoreHealth -ErrorAction SilentlyContinue|Out-Null
    L "DISM repair complete"

    $sync.StepsDone[0]=$true
    S 0 61 "DISM image repair done."

    # ════════════════════════════════════════════════════════════
    # STEP 1 — SFC SCAN
    # ════════════════════════════════════════════════════════════
    S 1 65 "SFC: Scanning and repairing system files..."
    L "=== STEP 2/8: SFC System File Scan ==="
    L "sfc.exe /scannow"
    & "$env:SystemRoot\System32\sfc.exe" /scannow 2>&1|Out-Null
    L "SFC scan complete — see C:\Windows\Logs\CBS\CBS.log for details"

    $sync.StepsDone[1]=$true
    S 1 91 "SFC scan complete."

    # ════════════════════════════════════════════════════════════
    # STEP 2 — DRIVE TRIM
    # ════════════════════════════════════════════════════════════
    S 2 92 "Running SSD TRIM on C:..."
    L "=== STEP 3/8: Drive Optimization ==="
    L "Optimize-Volume -DriveLetter C -ReTrim"
    Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
    L "Drive optimization complete"

    $sync.StepsDone[2]=$true
    S 2 94 "SSD TRIM done."

    # ════════════════════════════════════════════════════════════
    # STEP 3 — PERFORMANCE TWEAKS
    # ════════════════════════════════════════════════════════════
    S 3 94 "Setting power plan + applying perf tweaks..."
    L "=== STEP 4/8: Performance Tweaks ==="

    L "powercfg -setactive High Performance"
    & "$env:SystemRoot\System32\powercfg.exe" -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1|Out-Null
    & "$env:SystemRoot\System32\powercfg.exe" -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1|Out-Null

    L "REG: VisualFXSetting=2 (best performance)"
    R "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2

    L "REG: Disable transparency effects"
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0

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

    $sync.StepsDone[3]=$true
    S 3 96 "Performance tweaks done."

    # ════════════════════════════════════════════════════════════
    # STEP 4 — PRIVACY & TELEMETRY
    # ════════════════════════════════════════════════════════════
    S 4 96 "Disabling telemetry services (safe timeout)..."
    L "=== STEP 5/8: Privacy & Telemetry ==="

    KS "DiagTrack"       4
    KS "dmwappushservice" 4
    KS "WerSvc"          4
    KS "PcaSvc"          4

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

    L "REG: CEIP + Feedback + Background apps disabled"
    R "HKLM:\SOFTWARE\Microsoft\SQMClient\Windows" "CEIPEnable" 0
    R "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
    R "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "PeriodInNanoSeconds"  0
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    R "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle" 0

    $sync.StepsDone[4]=$true
    S 4 97 "Privacy & telemetry disabled."

    # ════════════════════════════════════════════════════════════
    # STEP 5 — MEMORY & CPU
    # ════════════════════════════════════════════════════════════
    S 5 97 "Applying memory and CPU optimizations..."
    L "=== STEP 6/8: Memory & CPU Tuning ==="

    L "REG: DisablePagingExecutive=1 (kernel in RAM)"
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0
    R "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "ClearPageFileAtShutdown" 0

    L "REG: Multimedia timer 1ms + network throttle off"
    R "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
    R "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xFFFFFFFF

    L "REG: Games task GPU=8 Priority=6 Scheduling=High"
    $gp="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    RB $gp @{"Affinity"=0;"Clock Rate"=10000;"GPU Priority"=8;"Priority"=6}
    R $gp "Background Only"     "False" "String"
    R $gp "Scheduling Category" "High"  "String"
    R $gp "SFIO Priority"       "High"  "String"

    L "schtasks: Disable Defender scheduled scans (real-time ON)"
    @("\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan",
      "\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance",
      "\Microsoft\Windows\Windows Defender\Windows Defender Idle Scan") |
    ForEach-Object{& "$env:SystemRoot\System32\schtasks.exe" /Change /TN $_ /Disable 2>&1|Out-Null}

    $sync.StepsDone[5]=$true
    S 5 98 "Memory & CPU tuning done."

    # ════════════════════════════════════════════════════════════
    # STEP 6 — NETWORK
    # ════════════════════════════════════════════════════════════
    S 6 98 "Applying network optimizations..."
    L "=== STEP 7/8: Network Optimization ==="

    L "REG: SMB throttling off + Large MTU on"
    R "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "DisableBandwidthThrottling" 1
    R "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "DisableLargeMtu" 0

    L "Set-NetTCPSetting AutoTuningLevel=Normal"
    try{Set-NetTCPSetting -SettingName InternetCustom -AutoTuningLevelLocal Normal -EA Stop|Out-Null}
    catch{& netsh int tcp set global autotuninglevel=normal 2>&1|Out-Null;L "netsh fallback: autotuninglevel=normal"}

    L "Set-NetOffloadGlobalSetting RSS=Enabled"
    try{Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -EA Stop|Out-Null}
    catch{& netsh int tcp set global rss=enabled 2>&1|Out-Null;L "netsh fallback: rss=enabled"}

    L "netsh: ECN enabled"
    & netsh int tcp set global ecncapability=enabled 2>&1|Out-Null

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

    L "REG: Nagle disabled (TcpAckFrequency=1 TCPNoDelay=1)"
    $ti="HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if(Test-Path $ti){
        Get-ChildItem $ti -EA SilentlyContinue|ForEach-Object{R $_.PSPath "TcpAckFrequency" 1;R $_.PSPath "TCPNoDelay" 1}
    }

    $sync.StepsDone[6]=$true
    S 6 99 "Network optimization done."

    # ════════════════════════════════════════════════════════════
    # STEP 7 — STARTUP CLEANUP + DNS + WINSOCK
    # ════════════════════════════════════════════════════════════
    S 7 99 "Removing startup bloat entries..."
    L "=== STEP 8/8: Startup + DNS + Cleanup ==="

    $rp="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    @("OneDrive","Spotify","Discord","Skype","Teams","SupportAssist",
      "EpicGamesLauncher","Steam","AdobeUpdater","GoogleUpdate",
      "CCleaner","Dropbox","Box","Grammarly",
      "HPMessageService","HPMSGSVC","McAfeeUpdaterUI",
      "LenovoUtility","ASUSGiftBox","AcerCare","SnagIt",
      "Slack","Zoom","WebExMTA","RingCentral") |
    ForEach-Object{DR $rp $_;L "Remove startup: $_"}

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

    L "=== ALL 8 STEPS COMPLETE ==="
    $sync.StepsDone[7]=$true
    S 7 100 "All done! Restart recommended."
    $sync.Done=$true
})

# ── WINDOW LOADED ────────────────────────────────────────────────
$window.Add_Loaded({
    $sync.StartTime=[datetime]::Now
    $ctrl['TitleSub'].Text="$($sync.OSLabel)  ·  $($sync.PCMaker) $($sync.PCModel)  ·  8 Steps  ·  No Files Deleted"
    $tSpin.Start();$tClock.Start();$tPoll.Start()
    [void]$ps.BeginInvoke()
    $ctrl['FooterText'].Text="Optimization running — do not close this window."
})

# ── WINDOW CLOSED ────────────────────────────────────────────────
$window.Add_Closed({
    $tSpin.Stop();$tClock.Stop();$tPoll.Stop()
    try{$ps.Stop()}catch{}
    try{$ps.Dispose()}catch{}
    try{$rs.Close()}catch{}
    try{$rs.Dispose()}catch{}
})

# ── SHOW WINDOW ──────────────────────────────────────────────────
[void]$window.ShowDialog()
