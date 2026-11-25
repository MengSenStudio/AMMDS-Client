# AMMDS 客户端端到端测试数据准备脚本（Windows PowerShell）
#
# 用途：向一台**测试用** AMMDS 服务端写入客户端端到端测试所需的最小数据：
#   * 1 本小说 + 3 章正文（用于小说阅读器链路）
#   * 1 本漫画 + 3 话 + 每话 2 张图片（用于漫画阅读器链路）
#
# 使用方式：
#   $env:AMMDS_E2E_ADMIN_PASS = 'ammds-e2e-pass'
#   pwsh -File scripts/seed_e2e_content.ps1 -BaseUrl http://127.0.0.1:18099
#
# 注意：
#   1. 脚本会先删除库中同名的测试数据（标题前缀 `[E2E]`），请勿在生产库执行；
#   2. 所有请求体显式以 UTF-8 字节提交，避免中文被按 ASCII 编码写坏；
#   3. 图片由脚本在 data/images/e2e 下生成（真实文件，供图片接口读取）。

param(
    [string]$BaseUrl = 'http://127.0.0.1:18099',
    [string]$User = 'ammds',
    [string]$Password = $env:AMMDS_E2E_ADMIN_PASS
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw '缺少管理员密码：请设置环境变量 AMMDS_E2E_ADMIN_PASS'
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        $Body,
        [string]$Token
    )
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{
        Uri         = "$BaseUrl$Path"
        Method      = $Method
        Headers     = $headers
        TimeoutSec  = 60
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 8 -Compress
        $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params['ContentType'] = 'application/json; charset=utf-8'
    }
    $response = Invoke-WebRequest @params
    return ($response.Content | ConvertFrom-Json)
}

# 1) 管理员登录（服务端允许明文口令回退，无需在脚本内实现 RSA）
Write-Host '[seed] 登录测试服务端…'
$login = Invoke-Api -Method Post -Path '/api/client/v1/auth/login' -Body @{
    username = $User
    password = $Password
}
if ($login.code -ne 200 -or -not $login.data.access_token) {
    throw "登录失败：$($login.code) $($login.message)"
}
$token = $login.data.access_token

# 2) 生成测试图片（真实文件，漫画章节图片接口要求 data 目录下已存在）
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$imageDir = Join-Path $root 'data\images\e2e'
New-Item -ItemType Directory -Force -Path $imageDir | Out-Null
Add-Type -AssemblyName System.Drawing
function New-TestImage {
    param([string]$Path, [System.Drawing.Color]$Color, [string]$Label)
    $bitmap = New-Object System.Drawing.Bitmap 600, 900
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear($Color)
    $font = New-Object System.Drawing.Font('Arial', 48)
    $graphics.DrawString($Label, $font, [System.Drawing.Brushes]::White, 20, 420)
    $graphics.Dispose()
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}
Write-Host '[seed] 生成测试图片…'
New-TestImage -Path (Join-Path $imageDir 'page-1.png') -Color ([System.Drawing.Color]::FromArgb(255, 60, 90, 180)) -Label 'PAGE 1'
New-TestImage -Path (Join-Path $imageDir 'page-2.png') -Color ([System.Drawing.Color]::FromArgb(255, 180, 70, 60)) -Label 'PAGE 2'
New-TestImage -Path (Join-Path $imageDir 'novel-cover.png') -Color ([System.Drawing.Color]::FromArgb(255, 40, 140, 110)) -Label 'NOVEL'

# 3) 清理历史测试数据（标题以 [E2E] 开头）
Write-Host '[seed] 清理历史测试数据…'
$novelList = Invoke-Api -Method Get -Path '/api/admin/novel/list?current=1&size=100' -Token $token
foreach ($item in $novelList.data.data) {
    if ($item.title -like '[[]E2E]*') {
        Invoke-Api -Method Delete -Path "/api/admin/novel/$($item.id)" -Token $token | Out-Null
        Write-Host "  删除小说 $($item.title)"
    }
}
$comicList = Invoke-Api -Method Get -Path '/api/admin/comic/list?current=1&size=100' -Token $token
foreach ($item in $comicList.data.data) {
    if ($item.title -like '[[]E2E]*') {
        Invoke-Api -Method Delete -Path "/api/admin/comic/delete?id=$($item.id)" -Token $token | Out-Null
        Write-Host "  删除漫画 $($item.title)"
    }
}

# 4) 小说 + 章节正文
Write-Host '[seed] 创建小说与章节…'
Invoke-Api -Method Post -Path '/api/admin/novel/createNew' -Token $token -Body @{
    title       = '[E2E] 端到端测试小说'
    author      = '测试作者'
    description = '客户端端到端测试用小说：用于验证小说列表、详情与阅读器正文渲染。'
    cover       = 'data\images\e2e\novel-cover.png'
    tags        = @('测试', '端到端')
    genre       = '测试'
    status      = 'ongoing'
    publishYear = '2026'
    publisher   = '测试出版社'
} | Out-Null

$novels = Invoke-Api -Method Get -Path '/api/client/v1/novels?page_size=20' -Token $token
$novelId = ($novels.data.items | Where-Object { $_.title -like '*端到端测试小说*' } | Select-Object -First 1).id
if (-not $novelId) { throw '小说创建后未能查询到' }

for ($i = 1; $i -le 3; $i++) {
    Invoke-Api -Method Post -Path "/api/admin/novel/chapter/create?bookId=$novelId" -Token $token -Body @{
        title   = "第 $i 章 测试章节"
        content = "<p>这是第 $i 章的正文第一段，用于验证客户端小说阅读器的正文渲染。</p><p>这是第 $i 章的正文第二段，包含中文标点与换行。</p>"
    } | Out-Null
}
Write-Host "  小说 ID = $novelId（3 章正文）"

# 5) 漫画相册 + 章节 + 图片
Write-Host '[seed] 创建漫画与章节图片…'
Invoke-Api -Method Post -Path '/api/admin/comic/create' -Token $token -Body @{
    title       = '[E2E] 端到端测试漫画'
    author      = '测试作者'
    type        = 'comic'
    fullChapter = $false
    cover       = 'data\images\e2e\page-1.png'
    description = '客户端端到端测试用漫画：用于验证漫画列表、详情与阅读器图片渲染。'
} | Out-Null

$comics = Invoke-Api -Method Get -Path '/api/client/v1/comics?page_size=20' -Token $token
$albumId = ($comics.data.items | Where-Object { $_.title -like '*端到端测试漫画*' } | Select-Object -First 1).id
if (-not $albumId) { throw '漫画创建后未能查询到' }

for ($i = 1; $i -le 3; $i++) {
    Invoke-Api -Method Post -Path "/api/admin/comic/chapter/create?id=$albumId" -Token $token -Body @{
        title       = "第 $i 话 测试章节"
        description = "第 $i 话"
    } | Out-Null
}
$chapters = Invoke-Api -Method Get -Path "/api/admin/comic/chapter/list?id=$albumId" -Token $token
foreach ($chapter in $chapters.data) {
    foreach ($page in 1..2) {
        Invoke-Api -Method Post -Path "/api/admin/comic/chapter/image/upload?id=$($chapter.id)" -Token $token -Body @{
            image = "data\images\e2e\page-$page.png"
        } | Out-Null
    }
}
Write-Host "  漫画 ID = $albumId（$($chapters.data.Count) 话 × 2 张图片）"

# 6) 回读校验：客户端 API 输出
Write-Host '[seed] 回读校验…'
$novelDetail = Invoke-Api -Method Get -Path "/api/client/v1/novels/$novelId" -Token $token
$firstChapter = $novelDetail.data.chapters[0].id
$chapterContent = Invoke-Api -Method Get -Path "/api/client/v1/novels/$novelId/chapters/$firstChapter" -Token $token
$comicDetail = Invoke-Api -Method Get -Path "/api/client/v1/comics/$albumId" -Token $token
$pages = Invoke-Api -Method Get -Path "/api/client/v1/comics/$albumId/chapters/$($comicDetail.data.chapters[0].id)" -Token $token

Write-Host "  小说：$($novelDetail.data.title) / 章节 $($novelDetail.data.chapters.Count) / 正文长度 $($chapterContent.data.text.Length)"
Write-Host "  漫画：$($comicDetail.data.title) / 章节 $($comicDetail.data.chapters.Count) / 首页 $($pages.data.pages[0].image)"
Write-Host '[seed] 完成'
