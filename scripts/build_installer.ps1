# AMMDS 客户端安装包一键生成脚本（Windows PowerShell）
#
# 命名规范：AMMDS-{系统类型}-{全架构all/指定架构}-{版本号}.{扩展类型}
#   * 系统类型：Android / Windows（后续可扩展 Linux / macOS / iOS）
#   * 架构：all 表示通用包（覆盖全部 ABI）；分包用具体架构名（arm64-v8a /
#     armeabi-v7a / x86_64 等），安装体积最小
#   * 版本号：取自 pubspec.yaml 的 version 字段（不含 build 号）
#   * 扩展类型：apk（Android）/ zip（Windows 绿色包，整体打包分发）
#
# 产物（集中输出到 dist）：
#   * Android：通用包 + 按 ABI 拆分的三个分包，共四个文件
#       AMMDS-Android-all-<版本>.apk
#       AMMDS-Android-arm64-v8a-<版本>.apk
#       AMMDS-Android-armeabi-v7a-<版本>.apk
#       AMMDS-Android-x86_64-<版本>.apk
#   * Windows：绿色安装包（可执行文件 + Flutter/插件运行库，必须整体打包分发）
#       AMMDS-Windows-all-<版本>.zip
#
# 使用方式：
#   pwsh -File scripts/build_installer.ps1
#   pwsh -File scripts/build_installer.ps1 -Targets android
#   pwsh -File scripts/build_installer.ps1 -Clean
#   pwsh -File scripts/build_installer.ps1 -Proxy http://127.0.0.1:7897   # 受限网络
#
# 前置条件（脚本会先做检查并给出可执行的提示）：
#   1. Flutter SDK：`flutter` 在 PATH 中；
#   2. Android：SDK（platform-tools、platforms;android-36、build-tools;36.0.0、
#      ndk;28.2.13676358）与 JDK 17~21（AGP 要求）；
#   3. Windows：Visual Studio 的「使用 C++ 的桌面开发」工作负载；
#   4. 受限网络（github.com 不可达）下 Gradle 下载依赖会失败：Maven Central
#      会把部分构件 301 重定向到 GitHub releases，用 -Proxy 指定本地代理即可；
#      首次构建还会自动安装 CMake（Android 原生构建需要）。

[CmdletBinding()]
param(
    # 要构建的目标平台，可多选
    [ValidateSet('android', 'windows')]
    [string[]]$Targets = @('android', 'windows'),

    # 构建前执行 flutter clean（依赖变动或产物异常时建议开启）
    [switch]$Clean,

    # 跳过 flutter pub get
    [switch]$SkipPubGet,

    # 受限网络下的本地代理（形如 http://127.0.0.1:7897 或 127.0.0.1:7897），
    # 仅注入给 Gradle 下载依赖使用
    [string]$Proxy
)

$ErrorActionPreference = 'Stop'

# 仓库根目录（脚本位于 scripts/）
$repoRoot = Split-Path -Parent $PSScriptRoot
$distDir = Join-Path $repoRoot 'dist'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "未找到命令 $Name：请先安装 Flutter SDK 并将其加入 PATH"
    }
}

function Assert-AndroidSdk {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    $localProperties = Join-Path $repoRoot 'android\local.properties'
    if (Test-Path $localProperties) {
        $sdkLine = Select-String -Path $localProperties -Pattern '^sdk\.dir=' |
            Select-Object -First 1
        if ($sdkLine) {
            $candidates += ($sdkLine.Line -replace '^sdk\.dir=', '').Trim()
        }
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate 'platform-tools'))) {
            return
        }
    }
    throw @'
未找到 Android SDK。请任选其一：
  1) 安装 Android Studio / 命令行工具后设置环境变量 ANDROID_HOME；
  2) 在 android/local.properties 中写入 sdk.dir=<SDK 路径>。
需要的组件：platform-tools、platforms;android-36、build-tools;36.0.0、ndk;28.2.13676358；
可先用 `flutter doctor` 确认 Android 工具链状态。
'@
}

function Get-JavaMajorVersion {
    param([string]$JavaPath)
    # `java -version` 输出到 stderr，首行形如：openjdk version "21.0.8" 2025-07-15
    $line = & $JavaPath -version 2>&1 | Select-Object -First 1
    if ("$line" -match 'version "(\d+)(?:\.(\d+))?') {
        $first = [int]$Matches[1]
        # 1.8 这类旧版本号取第二段
        if ($first -eq 1 -and $Matches[2]) {
            return [int]$Matches[2]
        }
        return $first
    }
    return 0
}

function Test-AndroidJdk {
    param([string]$JdkHome)
    # 必须是带 jmods / jlink 的标准 JDK：AGP 的 JdkImageTransform 依赖 jlink，
    # GraalVM 发行版与 JRE 都不带 jmods，会出现 JdkImageTransform 失败。
    if (-not (Test-Path (Join-Path $JdkHome 'bin\java.exe'))) {
        return $false
    }
    if (-not (Test-Path (Join-Path $JdkHome 'bin\jlink.exe'))) {
        return $false
    }
    $major = Get-JavaMajorVersion (Join-Path $JdkHome 'bin\java.exe')
    return @(17, 18, 19, 20, 21) -contains $major
}

function Resolve-AndroidJdk {
    # Android 构建（AGP）只支持 JDK 17~21：JAVA_HOME 指向更高版本时，
    # JdkImageTransform 会失败（表现为 Flutter 抛出 AGP 兼容性提示）。
    # 这里优先沿用合规的 JAVA_HOME，否则在常见安装位置里自动选一个兼容 JDK。
    if ($env:JAVA_HOME -and (Test-AndroidJdk $env:JAVA_HOME)) {
        Write-Host "Android 构建使用 JDK：$env:JAVA_HOME" -ForegroundColor Cyan
        return
    }
    if ($env:JAVA_HOME) {
        Write-Host "当前 JAVA_HOME（$env:JAVA_HOME）不适合 Android 构建，" -ForegroundColor Yellow
        Write-Host "需要 JDK 17~21 且带 jmods/jlink（GraalVM、JRE 均不满足），正在自动查找..." -ForegroundColor Yellow
    }

    $roots = @(
        'C:\Program Files\Java',
        'C:\Program Files\Eclipse Adoptium',
        (Join-Path $env:LOCALAPPDATA 'Programs\Eclipse Adoptium'),
        'C:\Program Files\Android\Android Studio\jbr',
        'C:\Program Files\Android\Android Studio\jre'
    )
    $jdkHomes = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) {
            continue
        }
        if (Test-Path (Join-Path $root 'bin\java.exe')) {
            # Android Studio 的 jbr / jre 本身就是 JDK 根目录
            $jdkHomes += $root
            continue
        }
        $jdkHomes += (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
    }
    # 优先标准 JDK（jdk-xx / Temurin），其次再试 GraalVM 等发行版
    $ranked = $jdkHomes | Sort-Object -Unique |
        Sort-Object @{ Expression = { if ($_ -match 'graalvm') { 1 } else { 0 } } }, @{ Expression = { $_ } }
    foreach ($jdkHome in $ranked) {
        if (Test-AndroidJdk $jdkHome) {
            $env:JAVA_HOME = $jdkHome
            Write-Host "已自动改用兼容的 JDK：$jdkHome" -ForegroundColor Cyan
            return
        }
    }
    throw @'
Android 构建需要 JDK 17~21 且带 jmods/jlink（AGP 的 JdkImageTransform 依赖 jlink，
GraalVM 发行版与 JRE 都不满足）。请任选其一：
  1) 设置环境变量 JAVA_HOME 指向标准 JDK 17/21 后重跑；
  2) 执行 flutter config --jdk-dir=<JDK 17/21 路径>；
  3) 安装 Android Studio，脚本会自动使用其自带 JBR。
'@
}

function Enable-GradleProxy {
    param([string]$ProxyUrl)
    $value = $ProxyUrl.Trim()
    if ($value -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $value = "http://$value"
    }
    $uri = [System.Uri]$value
    $hostName = $uri.Host
    $port = if ($uri.Port -gt 0 -and -not $uri.IsDefaultPort) { $uri.Port } else { 7890 }
    $options = "-Dhttps.proxyHost=$hostName -Dhttps.proxyPort=$port " +
        "-Dhttp.proxyHost=$hostName -Dhttp.proxyPort=$port"
    $previous = $env:JAVA_TOOL_OPTIONS
    $env:JAVA_TOOL_OPTIONS = if ([string]::IsNullOrWhiteSpace($previous)) {
        $options
    } else {
        "$previous $options"
    }
    Write-Host "Gradle 已配置代理：$hostName`:$port" -ForegroundColor Cyan
    return $previous
}

function Restore-JavaToolOptions {
    param([string]$Previous)
    if ([string]::IsNullOrWhiteSpace($Previous)) {
        Remove-Item Env:JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
    } else {
        $env:JAVA_TOOL_OPTIONS = $Previous
    }
}

function Get-AppVersion {
    if (-not (Test-Path $pubspecPath)) {
        throw "未找到 pubspec.yaml：$pubspecPath"
    }
    $match = Select-String -Path $pubspecPath -Pattern '^version:\s*(.+)$' |
        Select-Object -First 1
    if (-not $match) {
        throw 'pubspec.yaml 中缺少 version 字段'
    }
    # 1.0.0+1 → 1.0.0
    return ($match.Matches[0].Groups[1].Value.Trim() -split '\+')[0]
}

function Invoke-FlutterBuild {
    param([string[]]$FlutterArguments)
    Write-Host "> flutter $($FlutterArguments -join ' ')" -ForegroundColor Cyan
    & flutter @FlutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($FlutterArguments -join ' ') 执行失败（退出码 $LASTEXITCODE）"
    }
}

function New-GreenInstallerZip {
    param([string]$SourceDir, [string]$DestinationZip)
    if (Test-Path $DestinationZip) {
        Remove-Item $DestinationZip -Force
    }
    # 只打包运行期文件：`flutter test -d windows` 等命令会在 Flutter 的暂存目录里
    # 留下调试用 kernel_blob.bin（约 90MB），release 构建会把它一并复制到产物目录，
    # 直接压缩会让绿色安装包体积翻三倍并夹带调试信息（release 运行并不需要它）。
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) "ammds-win-pkg-$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        Get-ChildItem $SourceDir -Recurse -File | Where-Object {
            $_.Name -ne 'kernel_blob.bin' -and $_.Extension -ne '.pdb'
        } | ForEach-Object {
            $relative = $_.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
            $destination = Join-Path $staging $relative
            New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
            Copy-Item $_.FullName $destination -Force
        }
        # 只压缩目录内容：解压后即为可直接运行的绿色目录，不会多套一层父目录
        Compress-Archive -Path (Join-Path $staging '*') `
            -DestinationPath $DestinationZip -CompressionLevel Optimal
    }
    finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Build-AndroidInstaller {
    param([string]$Version, [string]$OutputDir)
    $apkDir = Join-Path $repoRoot 'build\app\outputs\flutter-apk'
    $abiSuffixes = @('arm64-v8a', 'armeabi-v7a', 'x86_64')

    # 先出按 ABI 拆分的包（每个包只含一个架构，安装体积最小）；
    # 再出通用包（一次安装适配所有架构）。两条命令的产物文件名不同，互不覆盖。
    Invoke-FlutterBuild -FlutterArguments @('build', 'apk', '--release', '--split-per-abi')
    Invoke-FlutterBuild -FlutterArguments @('build', 'apk', '--release')

    $artifacts = @()
    $universal = Join-Path $apkDir 'app-release.apk'
    if (-not (Test-Path $universal)) {
        throw "未找到 Android 通用包：$universal"
    }
    # 命名规范：AMMDS-{系统类型}-{全架构all/指定架构}-{版本号}.{扩展类型}
    # 通用包覆盖所有 ABI，用 all 标识；分包按 ABI 拆分，体积最小。
    $artifacts += @{ Source = $universal; Name = "AMMDS-Android-all-$Version.apk" }
    foreach ($abi in $abiSuffixes) {
        $source = Join-Path $apkDir "app-$abi-release.apk"
        if (-not (Test-Path $source)) {
            throw "未找到 Android 分包：$source（--split-per-abi 未产出该架构？）"
        }
        $artifacts += @{ Source = $source; Name = "AMMDS-Android-$abi-$Version.apk" }
    }

    # 逐个校验并复制：任何缺件都直接失败，避免「脚本成功但产物不全」
    foreach ($artifact in $artifacts) {
        $target = Join-Path $OutputDir $artifact.Name
        Copy-Item $artifact.Source $target -Force
        $sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 1)
        Write-Host "已生成 $target（$sizeMb MB）" -ForegroundColor Green
    }
}

function Build-WindowsInstaller {
    param([string]$Version, [string]$OutputDir)
    $releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    # 先清空上一次的产物目录：`flutter test -d windows` 等命令会把调试产物
    # （如 data/flutter_assets/kernel_blob.bin，可达 90MB）写进同一个目录，
    # 不清空就会被打进绿色安装包，体积翻三倍还夹带调试信息。
    if (Test-Path $releaseDir) {
        Remove-Item $releaseDir -Recurse -Force
    }
    Invoke-FlutterBuild -FlutterArguments @('build', 'windows', '--release')
    if (-not (Test-Path $releaseDir)) {
        throw "未找到 Windows 构建产物目录：$releaseDir"
    }
    # Windows 绿色包覆盖 x64 架构（Flutter 当前 windows 构建仅产 x64），
    # 沿用规范用 all 标识全架构；后续多架构时改为对应 ABI 名。
    $target = Join-Path $OutputDir "AMMDS-Windows-all-$Version.zip"
    New-GreenInstallerZip -SourceDir $releaseDir -DestinationZip $target
    Write-Host "已生成 $target" -ForegroundColor Green
}

Assert-Command -Name 'flutter'
$version = Get-AppVersion
Write-Host "AMMDS 客户端版本：$version" -ForegroundColor Cyan

if ($Targets -contains 'android') {
    Assert-AndroidSdk
    Resolve-AndroidJdk
}

# 产物集中输出：先清空再重建，保证 dist 内只有本次生成的文件
if (Test-Path $distDir) {
    Remove-Item $distDir -Recurse -Force
}
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

$previousJavaToolOptions = $null
$proxyEnabled = $false
Push-Location $repoRoot
try {
    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        $previousJavaToolOptions = Enable-GradleProxy -ProxyUrl $Proxy
        $proxyEnabled = $true
    }
    if ($Clean) {
        Invoke-FlutterBuild -FlutterArguments @('clean')
    }
    if (-not $SkipPubGet) {
        Invoke-FlutterBuild -FlutterArguments @('pub', 'get')
    }
    foreach ($target in $Targets) {
        switch ($target) {
            'android' { Build-AndroidInstaller -Version $version -OutputDir $distDir }
            'windows' { Build-WindowsInstaller -Version $version -OutputDir $distDir }
        }
    }
}
finally {
    if ($proxyEnabled) {
        Restore-JavaToolOptions -Previous $previousJavaToolOptions
    }
    Pop-Location
}

Write-Host ''
Write-Host "安装包目录：$distDir" -ForegroundColor Green
Get-ChildItem $distDir | Sort-Object Name | ForEach-Object {
    '  {0}  ({1:N1} MB)' -f $_.Name, ($_.Length / 1MB)
}
