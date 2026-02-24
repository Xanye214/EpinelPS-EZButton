# ======================= 脚本前置校验 - 管理员权限兼容 =======================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "    ⚠ 警告：脚本正在以管理员身份运行！" -ForegroundColor Yellow
    Write-Host "    💡 提示：管理员模式可能导致桌面文件生成到管理员账户，建议以普通用户运行" -ForegroundColor Cyan
    Write-Host "    📌 3秒后继续...（按Ctrl+C终止）" -ForegroundColor Gray
    Start-Sleep -Seconds 3
}
# ======================= 脚本设置 =======================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
# ... 其他代码保持不变
$ErrorActionPreference = 'Continue'
$scriptVersion = "1.0"  # 更新版本号
# ======================== 新增：TUN模式验证核心函数（整合Check-TUN.ps1） ========================
function Test-TUNEnvironment {
    <# 整合Check-TUN.ps1的核心逻辑，返回布尔值：$true=TUN生效，$false=TUN未生效 #>
    $ErrorActionPreference = "Continue"
    
    # 检测管理员权限（Get-NetRoute需要）
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "    ⚠ 提示：检测TUN路由需要管理员权限，结果可能不准确！" -ForegroundColor Yellow
    }
    
    # 1. 检测TUN相关网络适配器（复用Check-TUN.ps1的筛选规则）
    $tunAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "TUN|WireGuard|Clash|V2Ray" -or $_.InterfaceDescription -match "TUN|WireGuard|Virtual"
    }
    
    # 2. 检测默认路由是否指向TUN适配器
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    $isTunRoute = $false
    if ($defaultRoutes -and $tunAdapters) {
        $isTunRoute = [bool]($defaultRoutes | Where-Object { $tunAdapters.Name -contains $_.InterfaceAlias })
    }

    # 3. 输出可视化结果（修复原Check-TUN.ps1的乱码）
    Write-Host "`n    🔍 TUN模式环境检测结果：" -ForegroundColor Blue
    if ($tunAdapters) {
        Write-Host "    ✅ 检测到TUN相关适配器：$($tunAdapters.Name -join ', ')" -ForegroundColor Green
        if ($isTunRoute) {
            Write-Host "    ✅ 默认路由指向TUN适配器，TUN模式已生效！" -ForegroundColor Green
            return $true
        } else {
            Write-Host "    ⚠ TUN适配器存在，但默认路由未指向该适配器！" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "    ❌ 未检测到TUN相关适配器，TUN模式未启用！" -ForegroundColor Red
        return $false
    }
}

function Invoke-TUNValidation {
    <# 循环验证TUN模式，直到通过或用户退出 #>
    while ($true) {
        $tunValid = Test-TUNEnvironment
        if ($tunValid) { break }
        
        # 验证失败，提示用户重试/退出
        Write-Host "`n    ⚠ TUN模式验证未通过！无法启动EpinelPS。" -ForegroundColor Yellow
        $confirm = Read-Host "    确认已开启TUN模式后输入 Y 重新验证（输入其他键退出脚本）"
        
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-Host "    ❌ 用户终止操作，脚本退出。" -ForegroundColor Red
            Read-Host "    按任意键退出"
            exit
        }
        Write-Host "`n    🔍 重新验证TUN网络环境..." -ForegroundColor Blue
    }
}
# ======================== TUN验证函数结束 ========================


# ======================= 全局变量 =======================
$global:paths = @{
    EpinelPS = $null
    ServerSelector = $null
    NikkeLauncher = $null
}

$null = $global:paths # 保证全局变量已初始化

# ======================= 核心修复：补充缺失的 Get-PathValidationStatus 函数 =======================
function Get-PathValidationStatus {
    $statusLines = @()
    if ($global:paths.EpinelPS) {
        if (Test-Path $global:paths.EpinelPS -PathType Leaf) {
            $statusLines += "  ✅ EpinelPS.exe: 文件存在且有效"
        } else {
            $statusLines += "  ❌ EpinelPS.exe: 文件不存在或路径无效 ($($global:paths.EpinelPS))"
        }
    } else {
        $statusLines += "  ⚠ EpinelPS.exe: 未配置路径"
    }
    if ($global:paths.ServerSelector) {
        if (Test-Path $global:paths.ServerSelector -PathType Leaf) {
            $statusLines += "  ✅ ServerSelector.Desktop.exe: 文件存在且有效"
        } else {
            $statusLines += "  ❌ ServerSelector.Desktop.exe: 文件不存在或路径无效 ($($global:paths.ServerSelector))"
        }
    } else {
        $statusLines += "  ⚠ ServerSelector.Desktop.exe: 未配置路径"
    }
    if ($global:paths.NikkeLauncher) {
        if (Test-Path $global:paths.NikkeLauncher -PathType Leaf) {
            $statusLines += "  ✅ nikke_launcher.exe: 文件存在且有效"
        } else {
            $statusLines += "  ❌ nikke_launcher.exe: 文件不存在或路径无效 ($($global:paths.NikkeLauncher))"
        }
    } else {
        $statusLines += "  ⚠ nikke_launcher.exe: 未配置路径"
    }
    return $statusLines -join "`n"
}
$oneDrivePath = [Environment]::GetEnvironmentVariable("OneDrive", "User")
$isOneDriveLoggedIn = $false
if ($oneDrivePath -and (Test-Path (Join-Path -Path $oneDrivePath -ChildPath "Desktop"))) {
    $isOneDriveLoggedIn = $true
}

# 定义真实桌面路径和文件夹路径
if ($isOneDriveLoggedIn) {
    $realDesktopPath = Join-Path -Path $oneDrivePath -ChildPath "Desktop"
} else {
    $realDesktopPath = [Environment]::GetFolderPath("Desktop")
}
$windowsPathFile = Join-Path -Path $realDesktopPath -ChildPath "NIKKE_Windows路径.txt"
$resourceFolder = Join-Path -Path $realDesktopPath -ChildPath "私服资源管理"

# 显示识别结果（可选，方便验证）
Write-Host "    ℹ 桌面路径识别完成：" -ForegroundColor Cyan
Write-Host "      OneDrive登录状态: $(if ($isOneDriveLoggedIn) { "✅ 已登录" } else { "❌ 未登录" })" -ForegroundColor Gray
Write-Host "      当前使用桌面路径: $realDesktopPath" -ForegroundColor Gray
Write-Host ""

# ======================= 路径配置功能（移到前面） =======================

function Load-Paths {
    param([switch]$Silent = $false)
    
    if (Test-Path $windowsPathFile) {
        try {
            if (-not $Silent) {
                Write-Host "    🔄 正在加载Windows路径文件..." -ForegroundColor Cyan
            }
            
            $content = Get-Content $windowsPathFile -Encoding UTF8 -Raw
            Write-Host "    📄 文件内容长度: $($content.Length) 字符" -ForegroundColor Gray
            
            $lines = $content -split "`n"
            Write-Host "    📋 文件总行数: $($lines.Count)" -ForegroundColor Gray
            
            foreach ($line in $lines) {
                $originalLine = $line
                # 规范化空格与制表符，去除行首尾空白
                $normalized = $line -replace "\u00A0", " " -replace "`t", " "
                $normalized = $normalized.Trim()
                Write-Host "    🔍 检查行: '$originalLine' -> 规范化后: '$normalized'" -ForegroundColor DarkGray

                # 跳过注释和空行
                if ($normalized -match "^#" -or $normalized -eq "") { continue }

                # 定义匹配模式并在整行中查找（允许路径中包含空格）
                $patterns = @{
                    EpinelPS = '([A-Z]:\\[^\r\n]*?EpinelPS\.exe)'
                    ServerSelector = '([A-Z]:\\[^\r\n]*?ServerSelector\.Desktop\.exe)'
                    NikkeLauncher = '([A-Z]:\\[^\r\n]*?nikke_launcher\.exe)'
                }

                foreach ($key in $patterns.Keys) {
                    $pat = $patterns[$key]
                    $m = [regex]::Matches($normalized, $pat)
                    if ($m.Count -gt 0) {
                        $found = $m[0].Groups[1].Value.Trim()
                        switch ($key) {
                            'EpinelPS' { $global:paths.EpinelPS = $found; Write-Host "      💾 已设置EpinelPS路径: $found" -ForegroundColor Green }
                            'ServerSelector' { $global:paths.ServerSelector = $found; Write-Host "      💾 已设置ServerSelector路径: $found" -ForegroundColor Green }
                            'NikkeLauncher' { $global:paths.NikkeLauncher = $found; Write-Host "      💾 已设置NikkeLauncher路径: $found" -ForegroundColor Green }
                        }
                    }
                }
            }
            
            $count = 0
            if ($global:paths.EpinelPS) { $count++ }
            if ($global:paths.ServerSelector) { $count++ }
            if ($global:paths.NikkeLauncher) { $count++ }
            
            if ($count -gt 0 -and -not $Silent) {
                Write-Host "    ✅ 从Windows路径文件加载了 $count 个路径" -ForegroundColor Green
                return $true
            } else {
                Write-Host "    ⚠ 加载了 $count 个路径，可能格式不正确" -ForegroundColor Yellow
                return $false
            }
        }
        catch {
            if (-not $Silent) {
                Write-Host "    ⚠ 加载Windows路径文件失败: $_" -ForegroundColor Yellow
            }
            return $false
        }
    } else {
        Write-Host "    ℹ Windows路径文件不存在: $windowsPathFile" -ForegroundColor Gray
        return $false
    }
}

# ======================= 初始化脚本 - 创建资源文件夹 =======================
function Initialize-Script {
    Write-Host "正在初始化脚本..." -ForegroundColor Cyan
    Write-Host ""
    
    # 刷新文件系统缓存，避免残留
    try { $null = Get-ChildItem -Path $realDesktopPath -Force -ErrorAction Stop }
    catch { Write-Host "    ⚠ 刷新缓存失败，已忽略" -ForegroundColor Yellow; Write-Host "" }
    
    # 三重校验文件夹真实状态
    $folderRealExists = $false
    if (Test-Path $resourceFolder) {
        try {
            $folderItem = Get-Item -Path $resourceFolder -Force -ErrorAction Stop
            if ($folderItem.PSIsContainer) {
                $null = Get-ChildItem -Path $resourceFolder -Force -ErrorAction Stop
                $folderRealExists = $true
            }
        }
        catch { $folderRealExists = $false }
    }
    
    # 创建/提示文件夹状态
    if (-not $folderRealExists) {
        try {
            New-Item -ItemType Directory -Path $resourceFolder -Force | Out-Null
            Write-Host "✅ 已创建私服资源管理文件夹" -ForegroundColor Green
            Write-Host "   位置: $resourceFolder" -ForegroundColor Gray
        }
        catch {
            Write-Host "⚠ 无法创建文件夹: $_" -ForegroundColor Yellow
            Write-Host "   位置: $resourceFolder" -ForegroundColor Gray
        }
        Write-Host ""
    }
    else {
        Write-Host "✅ 私服资源管理文件夹已存在" -ForegroundColor Green
        Write-Host "   位置: $resourceFolder" -ForegroundColor Gray
        Write-Host ""
    }
    
    # 检查文件夹内容（仅当真实存在时）
    if ($folderRealExists) {
        try {
            $files = Get-ChildItem -Path $resourceFolder -Force -ErrorAction Stop
            if ($files.Count -gt 0) {
                Write-Host "📁 文件夹内有 $($files.Count) 个文件" -ForegroundColor Cyan
                $files | ForEach-Object {
                    $sizeMB = [math]::Round($_.Length / 1MB, 2)
                    Write-Host "      • $($_.Name) (${sizeMB}MB)" -ForegroundColor DarkGray
                }
            }
            else { Write-Host "📁 文件夹为空，可通过下载功能添加文件" -ForegroundColor Gray }
        }
        catch { Write-Host "⚠ 无法访问文件夹内容: $_" -ForegroundColor Yellow }
        Write-Host ""
    }
    else { Write-Host "📁 私服资源管理文件夹不存在或无法访问" -ForegroundColor Gray; Write-Host "" }
    
    # 路径文件加载逻辑（保持不变）
    if (Test-Path $windowsPathFile) {
        Write-Host "📄 发现桌面路径文件，正在加载配置..." -ForegroundColor Cyan
        $loaded = Load-Paths -Silent:$false
        if ($loaded) { Write-Host "✅ 已从桌面路径文件加载配置" -ForegroundColor Green }
        else { Write-Host "⚠ 未能从桌面路径文件加载配置" -ForegroundColor Yellow }
    } else {
        Write-Host "📄 桌面路径文件未找到: NIKKE_Windows路径.txt" -ForegroundColor Gray
        Write-Host "   请使用路径配置功能生成此文件" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "脚本初始化完成！" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# ======================= 执行初始化 =======================
Initialize-Script

# ======================= 界面美化函数 =======================

function Show-Header {
    param([string]$Title)
    
    Clear-Host
    Write-Host ""
    
    # 精美的边框设计
    Write-Host "    " -NoNewline
    Write-Host "╔" -NoNewline -ForegroundColor Magenta
    Write-Host "══════════════════════════════════════════════════════════════════" -NoNewline -ForegroundColor Cyan
    Write-Host "╗" -ForegroundColor Magenta
    
    Write-Host "    " -NoNewline
    Write-Host "║" -NoNewline -ForegroundColor Magenta
    Write-Host "                                                                  " -NoNewline
    Write-Host "║" -ForegroundColor Magenta
    
    # NIKKE 艺术字设计
    $nikkeArt = @(
        "    ║        ███╗   ██╗██╗██╗  ██╗██╗  ██╗███████╗                     ║",
        "    ║        ████╗  ██║██║██║ ██╔╝██║ ██╔╝██╔════╝                     ║",
        "    ║        ██╔██╗ ██║██║█████╔╝ █████╔╝ █████╗                       ║",
        "    ║        ██║╚██╗██║██║██╔═██╗ ██╔═██╗ ██╔══╝                       ║",
        "    ║        ██║ ╚████║██║██║  ██╗██║  ██╗███████╗                     ║"
    )
    
    foreach ($line in $nikkeArt) {
        Write-Host $line -ForegroundColor Cyan
    }
    
    # 副标题装饰
    Write-Host "    " -NoNewline
    Write-Host "║" -NoNewline -ForegroundColor Magenta
    Write-Host "                                                                  " -NoNewline
    Write-Host "║" -ForegroundColor Magenta
    
    Write-Host "    " -NoNewline
    Write-Host "║" -NoNewline -ForegroundColor Magenta
    Write-Host "                ██████╗ ██████╗ ██╗   ██╗██████╗                  " -NoNewline -ForegroundColor Yellow
    Write-Host "║" -ForegroundColor Magenta
    
    Write-Host "    " -NoNewline
    Write-Host "║" -NoNewline -ForegroundColor Magenta
    Write-Host "                ╚═════╝ ╚═════╝ ╚═╝   ╚═╝╚═════╝                  " -NoNewline -ForegroundColor Yellow
    Write-Host "║" -ForegroundColor Magenta
    
    Write-Host "    ║" -NoNewline -ForegroundColor Magenta
    Write-Host "                                                                  " -NoNewline
    Write-Host "║" -ForegroundColor Magenta
    
    # 版本信息
    Write-Host "    ║" -NoNewline -ForegroundColor Magenta
    Write-Host "                 私服一键启动管理器 v$scriptVersion                          " -NoNewline -ForegroundColor Green
    Write-Host "║" -ForegroundColor Magenta
    
    Write-Host "    ║" -NoNewline -ForegroundColor Magenta
    Write-Host "                                                                  " -NoNewline
    Write-Host "║" -ForegroundColor Magenta
    
    # 如果有子标题，显示分隔线和子标题
    if ($Title) {
        Write-Host "    ╠" -NoNewline -ForegroundColor Magenta
        Write-Host "══════════════════════════════════════════════════════════════════" -NoNewline -ForegroundColor DarkCyan
        Write-Host "╣" -ForegroundColor Magenta
        
        # 计算子标题的居中位置
        $titleLength = "✦ $Title ✦".Length
        $totalWidth = 62 # 边框内宽度
        $padding = [math]::Max(0, [math]::Floor(($totalWidth - $titleLength) / 2))
        
        Write-Host "    ║" -NoNewline -ForegroundColor Magenta
        Write-Host (" " * $padding) -NoNewline
        Write-Host "✦ $Title ✦" -ForegroundColor Yellow -NoNewline
        Write-Host (" " * ($totalWidth - $padding - $titleLength)) -NoNewline
        Write-Host "║" -ForegroundColor Magenta
    }
    
    Write-Host "    ╚" -NoNewline -ForegroundColor Magenta
    Write-Host "══════════════════════════════════════════════════════════════════" -NoNewline -ForegroundColor Cyan
    Write-Host "╝" -ForegroundColor Magenta
    
    Write-Host ""
}

function Show-Separator {
    param([string]$Type = "normal")
    
    switch ($Type) {
        "thick" { 
            Write-Host "    " -NoNewline
            Write-Host "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓" -ForegroundColor DarkCyan 
        }
        "thin" { 
            Write-Host "    " -NoNewline
            Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Gray 
        }
        "star" { 
            Write-Host "    " -NoNewline
            Write-Host "✧･ﾟ: *✧･ﾟ:* *:･ﾟ✧*:･ﾟ✧ *:･ﾟ✧*:･ﾟ✧ *:･ﾟ✧*:･ﾟ✧" -ForegroundColor Magenta 
        }
        "dash" { 
            Write-Host "    " -NoNewline
            Write-Host "---------------------------------------------------------------" -ForegroundColor DarkGray 
        }
        "wave" { 
            Write-Host "    " -NoNewline
            Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan 
        }
        default { 
            Write-Host "    " -NoNewline
            Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray 
        }
    }
    Write-Host ""
}

function Save-WindowsPaths {
    param([switch]$Silent = $false)
    
    $count = 0
    if ($global:paths.EpinelPS) { $count++ }
    if ($global:paths.ServerSelector) { $count++ }
    if ($global:paths.NikkeLauncher) { $count++ }
    
    if ($count -eq 0) {
        if (-not $Silent) {
            Write-Host "    ⚠ 无路径配置，跳过生成Windows路径文件" -ForegroundColor Yellow
        }
        return $false
    }
    
    try {
        $windowsContent = @"
# ======================= NIKKE Windows可用路径 =======================
# 自动生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# 启动器版本: v$scriptVersion
# 注意：这些路径可以直接在Windows资源管理器中使用
# ====================================================================
📁 配置文件路径:
$(if ($global:paths.EpinelPS) { 
    "EpinelPS.exe (服务器组件)"
    "  $($global:paths.EpinelPS)"
    ""
} else { "# EpinelPS.exe 未配置`n" })
$(if ($global:paths.ServerSelector) { 
    "ServerSelector.Desktop.exe (服务器选择器)"
    "  $($global:paths.ServerSelector)"
    ""
} else { "# ServerSelector.Desktop.exe 未配置`n" })
$(if ($global:paths.NikkeLauncher) { 
    "nikke_launcher.exe (游戏启动器)"
    "  $($global:paths.NikkeLauncher)"
    ""
} else { "# nikke_launcher.exe 未配置`n" })
📋 路径验证状态:
$(Get-PathValidationStatus)
# ======================= 使用说明 =======================
# 1. 这些路径可以直接在Windows资源管理器中使用
# 2. 可以复制路径粘贴到地址栏或运行对话框
# 3. 右键点击文件 -> 属性 -> 复制"目标"路径
# 4. 确保这些路径的文件实际存在
# =======================================================
💡 提示:
- ✅ 绿色: 文件存在且可用
- ❌ 红色: 文件不存在，请检查路径
- ⚠ 黄色: 路径未配置或有问题
- 建议将相关文件放在同一目录中
"@
        
        [System.IO.File]::WriteAllText($windowsPathFile, $windowsContent, [System.Text.Encoding]::UTF8)
        
        # ↓↓↓ 修复点：新增文件存在校验 + 错误提示 ↓↓↓
        if (-not $Silent) {
            Write-Host "    ✅ 已生成Windows可用路径文件" -ForegroundColor Green
            Write-Host "    📄 文件位置: $windowsPathFile" -ForegroundColor Gray
        }

        # 新增：验证文件是否真的存在（核心修复）
        if (Test-Path $windowsPathFile) {
            if (-not $Silent) {
                Write-Host "    ✔ 验证：文件已实际生成" -ForegroundColor Green
            }
            return $true
        } else {
            if (-not $Silent) {
                Write-Host "    ⚠ 警告：文件提示生成，但实际路径不存在！" -ForegroundColor Yellow
                Write-Host "    📍 实际尝试生成路径: $windowsPathFile" -ForegroundColor Red
                Write-Host "    💡 建议：检查桌面路径权限，或关闭管理员模式运行脚本" -ForegroundColor Cyan
            }
            return $false
        }
    }
    catch {
        if (-not $Silent) {
            Write-Host "    ⚠ 生成Windows路径文件失败: $_" -ForegroundColor Yellow
            Write-Host "    📍 尝试生成路径: $windowsPathFile" -ForegroundColor Red  # 新增：显示失败时的尝试路径
        }
        return $false
    }
}

# ======================= 全盘搜索增强函数 =======================

function Get-AllLocalDrives {
    # 获取所有本地驱动器（排除网络驱动器）
    $drives = Get-PSDrive -PSProvider FileSystem | 
               Where-Object { $_.Used -gt 0 -and $_.DisplayRoot -notlike "\\*" } | 
               Select-Object -ExpandProperty Root
    
    # 如果获取失败，使用备选方法
    if (-not $drives) {
        $drives = @()
        $letters = "C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"
        foreach ($letter in $letters) {
            $drivePath = $letter + ":\"
            if (Test-Path $drivePath) {
                $drives += $drivePath
            }
        }
    }
    
    return $drives
}

function Search-File-Enhanced {
    param(
        [string]$Drive,
        [string]$FileName,
        [int]$MaxDepth = 10  # 增加深度到10
    )
    
    $results = @()
    $driveRoot = if ($Drive.EndsWith('\')) { $Drive } else { $Drive + '\' }
    
    try {
        # 使用更灵活的搜索方式
        $searchPattern = "*" + [System.IO.Path]::GetFileNameWithoutExtension($FileName) + "*" + [System.IO.Path]::GetExtension($FileName)
        
        # 先尝试在指定深度内搜索
        $files = Get-ChildItem -Path $driveRoot -Filter $searchPattern -Recurse -Depth $MaxDepth -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like "*$FileName*" -or $_.Name -eq $FileName }
        
        # 如果没找到，尝试在整个驱动器中搜索（速度较慢但更彻底）
        if ($files.Count -eq 0) {
            Write-Host "      使用深度搜索..." -ForegroundColor DarkGray
            $files = Get-ChildItem -Path $driveRoot -Filter $searchPattern -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like "*$FileName*" -or $_.Name -eq $FileName }
        }
        
        foreach ($file in $files) {
            if ($file.Name -like "*$FileName*" -or $file.Name -eq $FileName) {
                $results += $file.FullName
            }
        }
    }
    catch {
        Write-Host "      ⚠ 搜索时出错: $_" -ForegroundColor DarkGray
    }
    
    return $results
}

function Search-NIKKE-Software {
    Show-Header -Title "全盘搜索NIKKE软件"
    
    Write-Host "    🎯 开始全盘搜索NIKKE私服软件" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    这将搜索所有本地驱动器，可能需要几分钟..." -ForegroundColor Yellow
    Write-Host "    ⏱️ 搜索可能需要 5-15 分钟，请耐心等待..." -ForegroundColor Yellow
    Write-Host "    ⚡ 提示：请确保脚本以管理员权限运行以提高搜索速度" -ForegroundColor Cyan
    Write-Host ""
    
    # 先搜索常见位置（桌面、下载、文档等）
    Write-Host "    🔍 优先搜索常见位置..." -ForegroundColor Cyan
    $commonLocations = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\桌面",  # 中文系统
        "$env:USERPROFILE\下载",  # 中文系统
        "$env:USERPROFILE\文档"   # 中文系统
    )
    
    $epinelPaths = @()
    $selectorPaths = @()
    $launcherPaths = @()
    
    foreach ($location in $commonLocations) {
        if (Test-Path $location) {
            Write-Host "      搜索: $location" -ForegroundColor DarkGray
            
            # 搜索 EpinelPS.exe
            $epinelResults = Get-ChildItem -Path $location -Filter "*EpinelPS*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue
            if ($epinelResults.Count -gt 0) {
                $epinelPaths += $epinelResults.FullName
            }
            
            # 搜索 ServerSelector.Desktop.exe
            $selectorResults = Get-ChildItem -Path $location -Filter "*ServerSelector.Desktop*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue
            if ($selectorResults.Count -gt 0) {
                $selectorPaths += $selectorResults.FullName
            }
            
            # 搜索 nikke_launcher.exe
            $launcherResults = Get-ChildItem -Path $location -Filter "*nikke_launcher*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue
            if ($launcherResults.Count -gt 0) {
                $launcherPaths += $launcherResults.FullName
            }
        }
    }
    
    Write-Host "    ✅ 完成常见位置搜索" -ForegroundColor Green
    Write-Host ""
    
    # 获取所有本地驱动器
    Write-Host "    📊 正在检测本地驱动器..." -ForegroundColor Cyan
    $allDrives = Get-AllLocalDrives
    
    if ($allDrives.Count -eq 0) {
        Write-Host "    ❌ 未找到可用的驱动器" -ForegroundColor Red
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return $false
    }
    
    Write-Host "    ✅ 发现 $($allDrives.Count) 个驱动器: $($allDrives -join ', ')" -ForegroundColor Green
    Write-Host ""
    
    # 搜索三个关键文件（继续使用增强搜索函数）
    foreach ($drive in $allDrives) {
        Write-Host "    ──────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "    🔍 正在搜索驱动器: $drive" -ForegroundColor Yellow
        Write-Host ""
        
        # 搜索 EpinelPS.exe (使用深度10)
        $epinelResults = Search-File-Enhanced -Drive $drive -FileName "EpinelPS.exe" -MaxDepth 10
        if ($epinelResults.Count -gt 0) {
            $epinelPaths += $epinelResults
            Write-Host "      ✅ 找到 $($epinelResults.Count) 个 EpinelPS.exe" -ForegroundColor Green
        } else {
            Write-Host "      ❌ 未找到 EpinelPS.exe" -ForegroundColor DarkGray
        }
        
        # 搜索 ServerSelector.Desktop.exe (使用深度10)
        $selectorResults = Search-File-Enhanced -Drive $drive -FileName "ServerSelector.Desktop.exe" -MaxDepth 10
        if ($selectorResults.Count -gt 0) {
            $selectorPaths += $selectorResults
            Write-Host "      ✅ 找到 $($selectorResults.Count) 个 ServerSelector.Desktop.exe" -ForegroundColor Green
        } else {
            Write-Host "      ❌ 未找到 ServerSelector.Desktop.exe" -ForegroundColor DarkGray
        }
        
        # 搜索 nikke_launcher.exe (使用深度10)
        $launcherResults = Search-File-Enhanced -Drive $drive -FileName "nikke_launcher.exe" -MaxDepth 10
        if ($launcherResults.Count -gt 0) {
            $launcherPaths += $launcherResults
            Write-Host "      ✅ 找到 $($launcherResults.Count) 个 nikke_launcher.exe" -ForegroundColor Green
        } else {
            Write-Host "      ❌ 未找到 nikke_launcher.exe" -ForegroundColor DarkGray
        }
        
        Write-Host ""
    }
    
    # 分析搜索结果
    Write-Host "    🔄 正在分析搜索结果..." -ForegroundColor Cyan
    Write-Host ""
    
    # 寻找最佳的文件组合（ServerSelector和EpinelPS必须在同一文件夹）
    $foundCombinations = @()
    
    # 寻找EpinelPS.exe和ServerSelector.Desktop.exe在同一目录的组合
    foreach ($epinelPath in $epinelPaths) {
        $epinelDir = [System.IO.Path]::GetDirectoryName($epinelPath)
        
        foreach ($selectorPath in $selectorPaths) {
            $selectorDir = [System.IO.Path]::GetDirectoryName($selectorPath)
            
            # 严格条件：必须在同一目录
            if ($epinelDir -eq $selectorDir) {
                $foundCombinations += @{
                    EpinelPS = $epinelPath
                    ServerSelector = $selectorPath
                    Directory = $epinelDir
                    SameDirectory = $true
                }
            }
        }
    }
    
    # 处理搜索结果
    if ($foundCombinations.Count -gt 0) {
        # 选择最佳组合（第一个找到的）
        $selectedCombination = $foundCombinations | Select-Object -First 1
        
        Write-Host "    🎉 找到 $($foundCombinations.Count) 组在同一文件夹的软件组合" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "    📁 找到在同一文件夹的软件：" -ForegroundColor Green
        Write-Host "    文件夹: $($selectedCombination.Directory)" -ForegroundColor Cyan
        
        Write-Host "    🖥️  EpinelPS.exe: $($selectedCombination.EpinelPS)" -ForegroundColor White
        Write-Host "    🔗  ServerSelector.Desktop.exe: $($selectedCombination.ServerSelector)" -ForegroundColor White
        Write-Host ""
        
        # 更新全局变量
        $global:paths.EpinelPS = $selectedCombination.EpinelPS
        $global:paths.ServerSelector = $selectedCombination.ServerSelector
        
        # 选择nikke_launcher.exe
        Write-Host "    🔄 正在选择 NIKKE游戏启动器..." -ForegroundColor Cyan
        
        if ($launcherPaths.Count -gt 0) {
            # 如果有多个启动器，让用户选择
            if ($launcherPaths.Count -gt 1) {
                Write-Host "    ⚠ 找到 $($launcherPaths.Count) 个启动器，请选择：" -ForegroundColor Yellow
                Write-Host ""
                
                for ($i = 0; $i -lt $launcherPaths.Count; $i++) {
                    Write-Host "    $($i+1). $($launcherPaths[$i])" -ForegroundColor Gray
                }
                Write-Host ""
                Write-Host "    请选择 (1-$($launcherPaths.Count)) 或按回车选择第一个: " -NoNewline -ForegroundColor Cyan
                $choice = Read-Host
                
                if ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $launcherPaths.Count) {
                    $selectedLauncher = $launcherPaths[[int]$choice - 1]
                } else {
                    $selectedLauncher = $launcherPaths[0]
                }
            } else {
                $selectedLauncher = $launcherPaths[0]
            }
            
            $global:paths.NikkeLauncher = $selectedLauncher
            Write-Host "    ✅ 选择启动器: $selectedLauncher" -ForegroundColor Green
        } else {
            Write-Host "    ℹ 未找到 nikke_launcher.exe，可以稍后手动配置" -ForegroundColor Yellow
        }
        
        Write-Host ""
        
        # 保存配置
        if (Save-WindowsPaths) {
            Write-Host "    💾 Windows路径文件已生成" -ForegroundColor Green
        }
        
        Write-Host ""
        Show-Separator -Type "wave"
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        
        return $true
    } else {
        Write-Host "    ❌ 未找到在同一文件夹的ServerSelector和EpinelPS" -ForegroundColor Red
        Write-Host ""
        
        # 显示找到的所有文件
        if ($epinelPaths.Count -gt 0 -or $selectorPaths.Count -gt 0 -or $launcherPaths.Count -gt 0) {
            Write-Host "    ℹ 找到了以下文件，但ServerSelector和EpinelPS不在同一文件夹:" -ForegroundColor Yellow
            
            if ($epinelPaths.Count -gt 0) {
                Write-Host ""
                Write-Host "    EpinelPS.exe 位置:" -ForegroundColor Cyan
                foreach ($path in $epinelPaths) {
                    $dir = [System.IO.Path]::GetDirectoryName($path)
                    Write-Host "      $dir" -ForegroundColor Gray
                }
            }
            
            if ($selectorPaths.Count -gt 0) {
                Write-Host ""
                Write-Host "    ServerSelector.Desktop.exe 位置:" -ForegroundColor Cyan
                foreach ($path in $selectorPaths) {
                    $dir = [System.IO.Path]::GetDirectoryName($path)
                    Write-Host "      $dir" -ForegroundColor Gray
                }
            }
            
            if ($launcherPaths.Count -gt 0) {
                Write-Host ""
                Write-Host "    nikke_launcher.exe 位置:" -ForegroundColor Cyan
                foreach ($path in $launcherPaths) {
                    $dir = [System.IO.Path]::GetDirectoryName($path)
                    Write-Host "      $dir" -ForegroundColor Gray
                }
            }
            
            Write-Host ""
            Write-Host "    💡 建议:" -ForegroundColor Yellow
            Write-Host "    1. 确保ServerSelector.Desktop.exe和EpinelPS.exe在同一文件夹" -ForegroundColor Gray
            Write-Host "    2. 或者使用手动配置功能" -ForegroundColor Gray
        } else {
            Write-Host "    ℹ 未找到任何NIKKE软件文件" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    💡 建议:" -ForegroundColor Yellow
            Write-Host "    1. 先使用下载功能获取软件" -ForegroundColor Gray
            Write-Host "    2. 解压文件到同一文件夹" -ForegroundColor Gray
            Write-Host "    3. 或者使用手动配置功能" -ForegroundColor Gray
        }
        
        Write-Host ""
        Show-Separator -Type "wave"
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        
        return $false
    }
}

function Manual-PathConfig {
    Show-Header -Title "手动配置路径"
    
    Write-Host "    📝 手动配置软件路径" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    请依次输入三个关键文件的完整路径：" -ForegroundColor White
    Write-Host ""
    
    # 1. EpinelPS.exe
    Write-Host "    1️⃣ EpinelPS.exe (服务器组件)" -ForegroundColor Yellow
    if ($global:paths.EpinelPS) {
        Write-Host "    当前路径: $($global:paths.EpinelPS)" -ForegroundColor Gray
    }
    Write-Host "    请输入完整路径 (如 C:\Games\NIKKE\EpinelPS.exe)" -ForegroundColor Gray
    Write-Host "    或按回车跳过保持现有配置: " -NoNewline -ForegroundColor Gray
    $path1 = Read-Host
    
    if ($path1 -and (Test-Path $path1)) {
        $global:paths.EpinelPS = $path1
        Write-Host "    ✅ 已更新 EpinelPS.exe 路径" -ForegroundColor Green
    } elseif ($path1) {
        Write-Host "    ⚠ 路径无效，保持原有配置" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # 2. ServerSelector.Desktop.exe
    Write-Host "    2️⃣ ServerSelector.Desktop.exe (服务器选择器)" -ForegroundColor Yellow
    if ($global:paths.ServerSelector) {
        Write-Host "    当前路径: $($global:paths.ServerSelector)" -ForegroundColor Gray
    }
    Write-Host "    请输入完整路径 (如 C:\Games\NIKKE\ServerSelector.Desktop.exe)" -ForegroundColor Gray
    Write-Host "    或按回车跳过保持现有配置: " -NoNewline -ForegroundColor Gray
    $path2 = Read-Host
    
    if ($path2 -and (Test-Path $path2)) {
        $global:paths.ServerSelector = $path2
        Write-Host "    ✅ 已更新 ServerSelector.Desktop.exe 路径" -ForegroundColor Green
    } elseif ($path2) {
        Write-Host "    ⚠ 路径无效，保持原有配置" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # 3. nikke_launcher.exe
    Write-Host "    3️⃣ nikke_launcher.exe (游戏启动器)" -ForegroundColor Yellow
    if ($global:paths.NikkeLauncher) {
        Write-Host "    当前路径: $($global:paths.NikkeLauncher)" -ForegroundColor Gray
    }
    Write-Host "    请输入完整路径 (如 C:\Games\NIKKE\nikke_launcher.exe)" -ForegroundColor Gray
    Write-Host "    或按回车跳过保持现有配置: " -NoNewline -ForegroundColor Gray
    $path3 = Read-Host
    
    if ($path3 -and (Test-Path $path3)) {
        $global:paths.NikkeLauncher = $path3
        Write-Host "    ✅ 已更新 nikke_launcher.exe 路径" -ForegroundColor Green
    } elseif ($path3) {
        Write-Host "    ⚠ 路径无效，保持原有配置" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # 保存配置
    if (Save-WindowsPaths) {
        Write-Host "    💾 Windows路径文件已更新" -ForegroundColor Green
    }
    
    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

# ======================= 软件启动函数 =======================
# ======================= TUN模式检测函数（新增） =======================
function Test-TUNMode {
    $tunAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "TUN|WireGuard|Clash|V2Ray" -or $_.InterfaceDescription -match "TUN|WireGuard|Virtual"
    }
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    $isTunRoute = $false
    if ($defaultRoutes -and $tunAdapters) {
        $isTunRoute = $defaultRoutes | Where-Object { $tunAdapters.Name -contains $_.InterfaceAlias }
    }

    Write-Host ""
    Write-Host "===== TUN模式检测结果 ====="
    Write-Host ""
    Write-Host "1. 虚拟网卡检测："
    if ($tunAdapters) {
        Write-Host "   [√] 检测到TUN相关虚拟网卡"
    } else {
        Write-Host "   [×] 未检测到TUN虚拟网卡"
    }
    Write-Host ""
    Write-Host "2. 路由转发检测："
    if ($tunAdapters -and $isTunRoute) {
        Write-Host "   [√] TUN模式已启用"
        return 0
    } elseif ($tunAdapters -and -not $isTunRoute) {
        Write-Host "   [！] TUN网卡存在但流量未走该网卡"
        return 1
    } else {
        Write-Host "   [×] TUN模式未启用"
        return 2
    }
}

function Show-TunRetryMenu {
    Write-Host ""
    Write-Host "    [R] 重试检测" -ForegroundColor Yellow
    Write-Host "    [S] 跳过（不推荐）" -ForegroundColor Red
    Write-Host "    [Q] 退出当前操作" -ForegroundColor Gray
    Write-Host ""
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    return $key.ToString().ToUpper()
}

function Launch-EpinelPS {
    if (-not $global:paths.EpinelPS) {
        Show-Header -Title "EpinelPS 启动失败"
        Write-Host "    ❌ 错误: 未配置 EpinelPS.exe 路径" -ForegroundColor Red
        Write-Host "    💡 请先配置软件路径" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }
    
    Show-Header -Title "第 1 步: 启动服务器组件"
    Write-Host ""
    
    $path = $global:paths.EpinelPS
    
    if (Test-Path $path) {
        Write-Host "    🚀 正在启动 EpinelPS 服务器组件..." -ForegroundColor Cyan
        Write-Host ""
        
        try {
            Start-Process -FilePath $path
            Write-Host "    ✅ EpinelPS 启动成功！" -ForegroundColor Green
            Write-Host ""
            Write-Host "    💡 提示: 第一步完成！建议接下来启动 ServerSelector。" -ForegroundColor Cyan
        }
        catch {
            Write-Host "    ❌ 启动失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    ❌ 文件不存在: $path" -ForegroundColor Red
    }
    
    Write-Host ""
    Show-Separator -Type "thin"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

function Launch-ServerSelector {
    if (-not $global:paths.ServerSelector) {
        Show-Header -Title "ServerSelector 启动失败"
        Write-Host "    ❌ 错误: 未配置 ServerSelector.Desktop.exe 路径" -ForegroundColor Red
        Write-Host "    💡 请先配置软件路径" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }
    
    Show-Header -Title "第 2 步: 启动服务器选择器"
    Write-Host ""
    
    $path = $global:paths.ServerSelector
    
    if (Test-Path $path) {
        Write-Host "    ⚠️  注意: 此软件可能需要管理员权限" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    🚀 正在启动 ServerSelector 服务器选择器..." -ForegroundColor Cyan
        Write-Host ""
        
        try {
            Write-Host "    ⚠️  注意: 正在请求管理员权限..." -ForegroundColor Yellow
            Start-Process -FilePath $path -Verb RunAs
            Write-Host "    ✅ ServerSelector 启动成功！" -ForegroundColor Green
            Write-Host ""
            Write-Host "    💡 提示: 第二步完成！建议接下来启动 NIKKE 游戏启动器。" -ForegroundColor Cyan
        }
        catch {
            Write-Host "    ❌ 启动失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    ❌ 文件不存在: $path" -ForegroundColor Red
    }
    
    Write-Host ""
    Show-Separator -Type "thin"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

function Launch-NIKKELauncher {
    if (-not $global:paths.NikkeLauncher) {
        Show-Header -Title "NIKKE 启动器启动失败"
        Write-Host "    ❌ 错误: 未配置 nikke_launcher.exe 路径" -ForegroundColor Red
        Write-Host "    💡 请先配置软件路径" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }
    
    Show-Header -Title "第 3 步: 启动游戏启动器"
    Write-Host ""
    
    $path = $global:paths.NikkeLauncher
    
    if (Test-Path $path) {
        Write-Host "    🎮 正在启动 NIKKE 游戏启动器..." -ForegroundColor Cyan
        Write-Host ""
        
        try {
            Start-Process -FilePath $path
            Write-Host "    ✅ NIKKE 游戏启动器启动成功！" -ForegroundColor Green
            Write-Host ""
            Show-Separator -Type "star"
            Write-Host ""
            Write-Host "    🎉 恭喜！所有组件已启动完成！ 🎉" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "    🎮 私服环境已准备就绪，祝您游戏愉快！" -ForegroundColor Cyan
        }
        catch {
            Write-Host "    ❌ 启动失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    ❌ 文件不存在: $path" -ForegroundColor Red
    }
    
    Write-Host ""
    Show-Separator -Type "thin"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

# ======================= 一键启动所有组件函数 =======================

function Launch-AllSoftware {
    Show-Header -Title "一键启动所有组件"
    
    Write-Host "    ⚡ 一键启动所有组件" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    # 检查所有组件状态
    $allReady = $true
    $missingComponents = @()
    
    if (-not $global:paths.EpinelPS -or -not (Test-Path $global:paths.EpinelPS)) {
        $allReady = $false
        $missingComponents += "EpinelPS.exe"
    }
    
    if (-not $global:paths.ServerSelector -or -not (Test-Path $global:paths.ServerSelector)) {
        $allReady = $false
        $missingComponents += "ServerSelector.Desktop.exe"
    }
    
    if (-not $global:paths.NikkeLauncher -or -not (Test-Path $global:paths.NikkeLauncher)) {
        $allReady = $false
        $missingComponents += "nikke_launcher.exe"
    }
    
    if (-not $allReady) {
        Write-Host "    ❌ 无法一键启动，缺少以下组件:" -ForegroundColor Red
        Write-Host ""
        foreach ($component in $missingComponents) {
            Write-Host "      • $component" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "    💡 请先使用路径配置功能配置缺失的组件" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }
    
    Write-Host "    ✅ 所有组件已配置并可用" -ForegroundColor Green
    Write-Host ""
    Write-Host "    🚀 开始按顺序启动组件..." -ForegroundColor Cyan
    Write-Host ""
    
    # 1. 启动 EpinelPS
    Write-Host "    1️⃣ 启动 EpinelPS 服务器组件..." -ForegroundColor White
    try {
        Start-Process -FilePath $global:paths.EpinelPS
        Write-Host "    ✅ EpinelPS 启动成功" -ForegroundColor Green
    }
    catch {
        Write-Host "    ⚠ EpinelPS 启动失败: $_" -ForegroundColor Yellow
    }
    Write-Host "    等待3秒..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    Write-Host ""
    
    # 2. 启动 ServerSelector
    Write-Host "    2️⃣ 启动 ServerSelector 服务器选择器..." -ForegroundColor White
    try {
        Write-Host "    ⚠ 正在请求管理员权限..." -ForegroundColor Yellow
        Start-Process -FilePath $global:paths.ServerSelector -Verb RunAs
        Write-Host "    ✅ ServerSelector 启动成功" -ForegroundColor Green
    }
    catch {
        Write-Host "    ⚠ ServerSelector 启动失败: $_" -ForegroundColor Yellow
        Write-Host "    请手动以管理员身份运行" -ForegroundColor Gray
    }
    Write-Host "    等待3秒..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    Write-Host ""
    
    # 3. 启动 NIKKE Launcher
    Write-Host "    3️⃣ 启动 NIKKE 游戏启动器..." -ForegroundColor White
    try {
        Start-Process -FilePath $global:paths.NikkeLauncher
        Write-Host "    ✅ NIKKE 游戏启动器启动成功" -ForegroundColor Green
    }
    catch {
        Write-Host "    ⚠ NIKKE 游戏启动器启动失败: $_" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    🎉 所有组件已启动完成！" -ForegroundColor Magenta
    Write-Host "    🎮 私服环境已准备就绪，祝您游戏愉快！" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "thin"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

# ======================= 新增的首次使用选项函数 =======================

function Launch-FirstTimeSetup {
    Show-Header -Title "首次使用选项 - 按顺序配置环境"
    
    Write-Host "    🔄 首次使用选项 - 按顺序配置环境" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    🎯 此选项将引导您按正确顺序启动三个必备软件" -ForegroundColor White
    Write-Host "    📋 启动顺序: 1 → 2 → 3" -ForegroundColor White
    Write-Host ""
    
    # 检查所有组件状态
    $allReady = $true
    $missingComponents = @()
    
    if (-not $global:paths.EpinelPS -or -not (Test-Path $global:paths.EpinelPS)) {
        $allReady = $false
        $missingComponents += "EpinelPS.exe"
    }
    
    if (-not $global:paths.ServerSelector -or -not (Test-Path $global:paths.ServerSelector)) {
        $allReady = $false
        $missingComponents += "ServerSelector.Desktop.exe"
    }
    
    if (-not $global:paths.NikkeLauncher -or -not (Test-Path $global:paths.NikkeLauncher)) {
        $allReady = $false
        $missingComponents += "nikke_launcher.exe"
    }
    
    if (-not $allReady) {
        Write-Host "    ❌ 无法继续，缺少以下组件:" -ForegroundColor Red
        Write-Host ""
        foreach ($component in $missingComponents) {
            Write-Host "      • $component" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "    💡 请先使用路径配置功能配置缺失的组件" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }
    
    Write-Host "    ✅ 所有组件已配置并可用" -ForegroundColor Green
    Write-Host "    🚀 开始按顺序引导启动..." -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "thin"
    Write-Host ""
        # ===== TUN 模式强制验证循环 =====
    $tunCheckPassed = $false
    while (-not $tunCheckPassed) {
        $tunStatus = Test-TUNMode  # 返回 0=正常,1=路由未走TUN,2=未启用
        switch ($tunStatus) {
            0 {
                Write-Host "    ✅ TUN 模式验证通过，继续启动..." -ForegroundColor Green
                $tunCheckPassed = $true
            }
            1 {
                Write-Host "    ⚠ TUN 网卡存在但流量未走该网卡" -ForegroundColor Yellow
                Write-Host "    💡 请检查 VPN 路由设置或重新连接 VPN（确保使用 TUN 模式）" -ForegroundColor Cyan
                $choice = Show-TunRetryMenu
                switch ($choice) {
                    'R' { continue }           # 重试
                    'S' { 
                        Write-Host "    ⚠ 已跳过 TUN 验证，可能无法连接私服！" -ForegroundColor Red
                        $tunCheckPassed = $true
                        break
                    }
                    'Q' { return }              # 退出
                }
            }
            2 {
                Write-Host "    ❌ TUN 模式未启用" -ForegroundColor Red
                Write-Host "    💡 请开启 VPN 的 TUN 模式（如 Clash TUN / WireGuard）" -ForegroundColor Cyan
                $choice = Show-TunRetryMenu
                switch ($choice) {
                    'R' { continue }
                    'S' { 
                        Write-Host "    ⚠ 已跳过 TUN 验证，可能无法连接私服！" -ForegroundColor Red
                        $tunCheckPassed = $true
                        break
                    }
                    'Q' { return }
                }
            }
        }
    }
    # ===== 结束 TUN 验证 =====
    # 第1步：启动 EpinelPS
    Write-Host "    🎯 第1步: 启动 EpinelPS 服务器组件" -ForegroundColor Yellow
    Write-Host ""
    
    $path1 = $global:paths.EpinelPS
    
    if (Test-Path $path1) {
        Write-Host "    🖥️  正在启动 EpinelPS 服务器组件..." -ForegroundColor Cyan
        Write-Host ""
        
        try {
            Start-Process -FilePath $path1
            Write-Host "    ✅ EpinelPS 启动成功！" -ForegroundColor Green
            Write-Host "    💡 第一步完成！请等待控制台窗口显示后继续" -ForegroundColor Gray
        }
        catch {
            Write-Host "    ❌ 启动失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    ❌ 文件不存在: $path1" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "    ⏎ 按回车键继续第2步..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
    Write-Host ""
    
    # 第2步：启动 ServerSelector
    Write-Host "    🎯 第2步: 启动 ServerSelector 服务器选择器" -ForegroundColor Yellow
    Write-Host ""
    
    $path2 = $global:paths.ServerSelector
    
    if (Test-Path $path2) {
        Write-Host "    ⚠️  注意: 此软件可能需要管理员权限" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    🔗 正在启动 ServerSelector 服务器选择器..." -ForegroundColor Cyan
        Write-Host ""
        
        try {
            Write-Host "    ⚠️  正在请求管理员权限..." -ForegroundColor Yellow
            Start-Process -FilePath $path2 -Verb RunAs
            Write-Host "    ✅ ServerSelector 启动成功！" -ForegroundColor Green
            Write-Host "    💡 第二步完成！请选择服务器并保持运行" -ForegroundColor Gray
        }
        catch {
            Write-Host "    ❌ 启动失败: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "    💡 请手动以管理员身份运行 ServerSelector" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    ❌ 文件不存在: $path2" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "    ⏎ 按回车键继续第3步..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
    Write-Host ""
    
    # 第3步：启动 NIKKE Launcher
    Write-Host "    🎯 第3步: 启动 NIKKE 游戏启动器" -ForegroundColor Yellow
    Write-Host ""
    
    $path3 = $global:paths.NikkeLauncher
    
    if (Test-Path $path3) {
        Write-Host "    🎮 正在启动 NIKKE 游戏启动器..." -ForegroundColor Cyan
        Write-Host ""
        
        try {
            Start-Process -FilePath $path3
            Write-Host "    ✅ NIKKE 游戏启动器启动成功！" -ForegroundColor Green
            Write-Host "    💡 第三步完成！所有组件已启动" -ForegroundColor Gray
        }
        catch {
            Write-Host "    ❌ 启动失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "    ❌ 文件不存在: $path3" -ForegroundColor Red
    }
    
    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    🎉 恭喜！按顺序启动环境配置完成！ 🎉" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "    🎮 私服环境已准备就绪，祝您游戏愉快！" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "wave"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

# ======================= 下载进度显示函数（增强版） =======================

function Show-EnhancedDownloadProgress {
    param(
        [int]$Percent,
        [string]$FileName,
        [double]$CurrentMB,
        [double]$TotalMB,
        [double]$SpeedMBps
    )
    
    $barLength = 40
    $filled = [math]::Round($barLength * $Percent / 100)
    $bar = ("█" * $filled) + ("░" * ($barLength - $filled))
    
    # 格式化数据
    $currentFormatted = "{0:F1}" -f $CurrentMB
    $totalFormatted = "{0:F1}" -f $TotalMB
    $speedFormatted = "{0:F2}" -f $SpeedMBps
    
    Write-Host "`r    [" -NoNewline -ForegroundColor Cyan
    Write-Host $bar -NoNewline -ForegroundColor $(if ($Percent -eq 100) { "Green" } else { "Yellow" })
    Write-Host "] " -NoNewline -ForegroundColor Cyan
    Write-Host "$Percent%" -NoNewline -ForegroundColor White
    Write-Host " │ " -NoNewline -ForegroundColor Gray
    Write-Host "${currentFormatted}MB/${totalFormatted}MB" -NoNewline -ForegroundColor Cyan
    Write-Host " │ " -NoNewline -ForegroundColor Gray
    Write-Host "${speedFormatted}MB/s" -NoNewline -ForegroundColor $(if ($SpeedMBps -gt 0.5) { "Green" } else { "Yellow" })
    Write-Host " │ " -NoNewline -ForegroundColor Gray
    Write-Host $FileName -NoNewline -ForegroundColor White
}

function Download-File-Enhanced {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$FileName
    )
    
    try {
        # 显示初始进度
        Show-EnhancedDownloadProgress -Percent 0 -FileName $FileName -CurrentMB 0 -TotalMB 0 -SpeedMBps 0
        
        # 创建WebClient并添加事件
        $webClient = New-Object System.Net.WebClient
        $global:downloadPercent = 0
        $global:downloadCurrentBytes = 0
        $global:downloadTotalBytes = 0
        $global:downloadStartTime = [DateTime]::Now
        $global:lastBytes = 0
        $global:lastTime = $global:downloadStartTime
        $global:downloadSpeedMBps = 0
        
        # 进度事件处理程序（增强版）
        $eventHandler = {
            param($sender, $e)
            
            $currentTime = [DateTime]::Now
            $global:downloadPercent = [math]::Round($e.BytesReceived * 100 / $e.TotalBytesToReceive)
            $global:downloadCurrentBytes = $e.BytesReceived
            $global:downloadTotalBytes = $e.TotalBytesToReceive
            
            # 计算下载速度（MB/s）
            $timeSpan = ($currentTime - $global:lastTime).TotalSeconds
            if ($timeSpan -gt 0.5) {  # 每0.5秒更新一次速度
                $bytesDelta = $global:downloadCurrentBytes - $global:lastBytes
                $speedBps = $bytesDelta / $timeSpan
                $global:downloadSpeedMBps = $speedBps / 1MB
                $global:lastBytes = $global:downloadCurrentBytes
                $global:lastTime = $currentTime
            }
            
            # 显示进度
            $currentMB = $global:downloadCurrentBytes / 1MB
            $totalMB = $global:downloadTotalBytes / 1MB
            
            Show-EnhancedDownloadProgress -Percent $global:downloadPercent `
                -FileName $FileName `
                -CurrentMB $currentMB `
                -TotalMB $totalMB `
                -SpeedMBps $global:downloadSpeedMBps
        }
        
        # 注册事件
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action $eventHandler | Out-Null
        
        # 开始下载
        $webClient.DownloadFileAsync([Uri]$Url, $OutputPath)
        
        # 等待下载完成
        while ($webClient.IsBusy) {
            Start-Sleep -Milliseconds 100
        }
        
        # 显示完成
        $totalMB = $global:downloadTotalBytes / 1MB
        Show-EnhancedDownloadProgress -Percent 100 -FileName $FileName -CurrentMB $totalMB -TotalMB $totalMB -SpeedMBps 0
        Write-Host ""
        
        # 清理
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event
        $webClient.Dispose()
        
        return $true
    }
    catch {
        Write-Host ""
        Write-Host "    ❌ 下载失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ======================= 确认下载界面（数字键选择） =======================

function Show-DownloadConfirm {
    param(
        [string]$Title,
        [string]$FileName,
        [string]$Description,
        [string]$FileType,
        [string]$OfficialWebsite,
        [string]$SavePath
    )
    
    Show-Header -Title $Title
    
    Write-Host "    📋 下载确认" -ForegroundColor Cyan
    Show-Separator -Type "dash"
    Write-Host ""
    
    # 文件信息
    Write-Host "    📄 文件信息:" -ForegroundColor White
    Write-Host "      名称: $FileName" -ForegroundColor Gray
    Write-Host "      类型: $FileType" -ForegroundColor Gray
    Write-Host "      保存位置: $SavePath" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    📝 描述:" -ForegroundColor White
    Write-Host "      $Description" -ForegroundColor Gray
    Write-Host ""
    
    # 下载方式提示
    Write-Host "    💡 其他下载方式:" -ForegroundColor Yellow
    Write-Host "      如果您不想使用脚本下载，可以访问官方网站手动下载:" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "      🌐 官方网站: " -NoNewline -ForegroundColor White
    Write-Host $OfficialWebsite -ForegroundColor Cyan
    Write-Host ""
    
    Show-Separator -Type "thin"
    Write-Host ""
    
    Write-Host "    📋 请选择操作:" -ForegroundColor White
    Write-Host ""
    Write-Host "    1️⃣ 确认下载到私服资源管理文件夹" -ForegroundColor Green
    Write-Host "    2️⃣ 打开官方网站" -ForegroundColor Blue
    Write-Host "    3️⃣ 复制官方网站链接" -ForegroundColor Yellow
    Write-Host "    4️⃣ 返回上一级" -ForegroundColor Red
    Write-Host ""
    
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    请选择操作 [1-4]: " -ForegroundColor Yellow -NoNewline
    
    $choice = Read-Host
    
    switch ($choice) {
        "1" { return 1 }
        "2" {
            try {
                Write-Host ""
                Write-Host "    🌐 正在打开官方网站..." -ForegroundColor Cyan
                Start-Process $OfficialWebsite
                Write-Host "    ✅ 已启动浏览器" -ForegroundColor Green
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            catch {
                Write-Host "    ⚠ 无法打开浏览器: $_" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            return 2
        }
        "3" {
            try {
                Write-Host ""
                Write-Host "    📋 正在复制链接..." -ForegroundColor Cyan
                Set-Clipboard -Value $OfficialWebsite
                Write-Host "    ✅ 官方网站链接已复制到剪贴板" -ForegroundColor Green
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            catch {
                Write-Host "    ⚠ 无法复制链接: $_" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            return 3
        }
        "4" { return 4 }
        default {
            Write-Host ""
            Write-Host "    ⚠ 无效选择，请输入 1-4 之间的数字" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
            return 4
        }
    }
}

function Initialize-ResourceFolder {
    if (-not (Test-Path $resourceFolder)) {
        try {
            New-Item -ItemType Directory -Path $resourceFolder -Force | Out-Null
            Write-Host "    📁 已创建私服资源管理文件夹" -ForegroundColor Green
            Write-Host "    位置: $resourceFolder" -ForegroundColor Gray
            return $true
        }
        catch {
            Write-Host "    ⚠ 无法创建文件夹: $_" -ForegroundColor Yellow
            return $false
        }
    }
    return $true
}

function Show-ResourceFolderInfo {
    Show-Header -Title "私服资源管理文件夹"
    
    Write-Host "    📁 私服资源管理文件夹" -ForegroundColor Cyan
    Show-Separator -Type "dash"
    Write-Host ""
    
    if (Test-Path $resourceFolder) {
        $folderInfo = Get-Item $resourceFolder
        $files = Get-ChildItem -Path $resourceFolder
        
        Write-Host "    文件夹信息:" -ForegroundColor White
        Write-Host "      位置: $resourceFolder" -ForegroundColor Gray
        Write-Host "      创建时间: $($folderInfo.CreationTime)" -ForegroundColor Gray
        Write-Host "      最后修改: $($folderInfo.LastWriteTime)" -ForegroundColor Gray
        Write-Host ""
        
        if ($files.Count -eq 0) {
            Write-Host "    当前文件夹为空" -ForegroundColor Yellow
            Write-Host "    您可以通过上方下载功能将文件保存到此文件夹" -ForegroundColor Gray
        }
        else {
            Write-Host "    文件夹内容 ($($files.Count) 个文件):" -ForegroundColor White
            
            $files | ForEach-Object {
                $sizeMB = [math]::Round($_.Length / 1MB, 2)
                Write-Host "      • $($_.Name) (${sizeMB}MB)" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "    ⚠ 私服资源管理文件夹不存在" -ForegroundColor Yellow
        Write-Host "    正在创建..." -ForegroundColor Cyan
        
        if (Initialize-ResourceFolder) {
            Write-Host "    ✅ 文件夹创建成功" -ForegroundColor Green
            Write-Host "    位置: $resourceFolder" -ForegroundColor Gray
        }
        else {
            Write-Host "    ❌ 文件夹创建失败" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    
    Write-Host "    操作选项:" -ForegroundColor White
    Write-Host "    1️⃣ 打开文件夹" -ForegroundColor Green
    Write-Host "    2️⃣ 返回上一级" -ForegroundColor Red
    Write-Host ""
    Write-Host "    请选择操作 [1-2]: " -ForegroundColor Yellow -NoNewline
    
    $choice = Read-Host
    
    switch ($choice) {
        "1" {
            try {
                Write-Host ""
                Write-Host "    📁 正在打开文件夹..." -ForegroundColor Cyan
                Start-Process explorer.exe -ArgumentList $resourceFolder
                Write-Host "    ✅ 已打开私服资源管理文件夹" -ForegroundColor Green
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            catch {
                Write-Host "    ⚠ 无法打开文件夹: $_" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
        }
        "2" { return }
        default {
            Write-Host ""
            Write-Host "    ⚠ 无效选择，请输入 1-2 之间的数字" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
    }
}

function Download-ServerPackage {
    # ================== 动态获取最新下载链接 ==================
    $repo = "EpinelPS/EpinelPS"
    $apiUrl = "https://api.github.com/repos/$repo/readme"
    Write-Host "    🔍 正在从 GitHub 获取最新下载链接..." -ForegroundColor Cyan

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{ Accept = "application/vnd.github.v3+json" } -ErrorAction Stop
        $base64 = $response.content -replace "`n|`r", ""
        $bytes = [System.Convert]::FromBase64String($base64)
        $readme = [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        Write-Host "    ❌ 无法获取 README，将使用预设链接。" -ForegroundColor Yellow
        # 预设链接作为后备
        $url = "https://nightly.link/EpinelPS/EpinelPS/workflows/dotnet-desktop/main/Server%20and%20Server%20selector.zip"
    }

    if ($readme) {
        # 匹配常见压缩包格式的链接
        $pattern = 'https?://[^\s\)]+?\.(zip|7z|rar|tar\.gz|tgz|exe|msi|dmg|apk|jar)(\?[^\s\)]*)?(?=[\s\)]|$)'
        $matches = [regex]::Matches($readme, $pattern, 'IgnoreCase')
        $links = @()
        foreach ($match in $matches) { $links += $match.Value }
        $links = $links | Sort-Object -Unique

        if ($links.Count -eq 0) {
            # 后备：尝试匹配 nightly.link 链接（可能没有扩展名）
            $nightlyMatches = [regex]::Matches($readme, 'https?://[^\s\)]*nightly\.link[^\s\)]*', 'IgnoreCase')
            foreach ($match in $nightlyMatches) { $links += $match.Value }
            $links = $links | Sort-Object -Unique
        }

        if ($links.Count -gt 0) {
            # 优先选择包含 Server%20and%20Server%20selector 的链接，否则取第一个
            $selectedUrl = $links | Where-Object { $_ -match 'Server(%20|\+)and(%20|\+)Server(%20|\+)selector' } | Select-Object -First 1
            if (-not $selectedUrl) {
                $selectedUrl = $links[0]
            }
            Write-Host "    ✅ 获取到最新下载链接: $selectedUrl" -ForegroundColor Green
            $url = $selectedUrl
        } else {
            Write-Host "    ⚠ 未在 README 中找到任何下载链接，将使用预设链接。" -ForegroundColor Yellow
            $url = "https://nightly.link/EpinelPS/EpinelPS/workflows/dotnet-desktop/main/Server%20and%20Server%20selector.zip"
        }
    } elseif (-not $url) {
        # 如果 $readme 不存在且 $url 未设置（例如 API 成功但无链接），回退
        $url = "https://nightly.link/EpinelPS/EpinelPS/workflows/dotnet-desktop/main/Server%20and%20Server%20selector.zip"
    }

    # 从 URL 解析文件名
    try {
        $uri = [System.Uri]::new($url)
        $fileName = [System.IO.Path]::GetFileName($uri.LocalPath)
        if ([string]::IsNullOrEmpty($fileName)) {
            $fileName = "Server_and_Server_selector.zip"
        }
    } catch {
        $fileName = "Server_and_Server_selector.zip"
    }

    $savePath = "$resourceFolder\$fileName"
    $officialWebsite = "https://github.com/EpinelPS/EpinelPS"
    $displaySavePath = "桌面\私服资源管理\$fileName"

    # ================== 原有的下载确认和下载流程 ==================
    if (-not (Test-Path $resourceFolder)) {
        if (-not (Initialize-ResourceFolder)) {
            Write-Host "    ❌ 无法创建私服资源管理文件夹" -ForegroundColor Red
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
            return
        }
    }

    $choice = Show-DownloadConfirm -Title "下载私服资源包" `
        -FileName $fileName `
        -Description "包含私服服务器组件和服务器选择器，是运行私服的核心文件" `
        -FileType "压缩包 (ZIP)" `
        -OfficialWebsite $officialWebsite `
        -SavePath $displaySavePath

    if ($choice -ne 1) {
        return
    }

    Show-Header -Title "下载私服资源包"

    Write-Host "    📦 下载信息" -ForegroundColor Cyan
    Show-Separator -Type "dash"
    Write-Host ""

    Write-Host "    文件名称: " -NoNewline -ForegroundColor White
    Write-Host $fileName -ForegroundColor Cyan
    Write-Host "    保存位置: " -NoNewline -ForegroundColor White
    Write-Host $displaySavePath -ForegroundColor Gray
    Write-Host "    估计大小: " -NoNewline -ForegroundColor White
    Write-Host "约 50-100MB" -ForegroundColor Gray
    Write-Host ""

    Show-Separator -Type "thin"
    Write-Host ""

    Write-Host "    🌐 正在检查网络连接..." -ForegroundColor Cyan

    try {
        if (-not (Test-Connection -ComputerName "github.com" -Count 1 -Quiet)) {
            Write-Host "    ❌ 无法连接到互联网" -ForegroundColor Red
            Write-Host "    💡 提示: 请检查网络连接或使用VPN" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
            return
        }
        Write-Host "    ✅ 网络连接正常" -ForegroundColor Green
    }
    catch {
        Write-Host "    ❌ 网络连接检查失败" -ForegroundColor Red
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }

    Write-Host ""
    Write-Host "    🚀 开始下载私服资源包..." -ForegroundColor Cyan
    Write-Host ""

    Write-Host "    文件将保存到: " -NoNewline -ForegroundColor White
    Write-Host $displaySavePath -ForegroundColor Cyan
    Write-Host "    请勿关闭此窗口，下载中..." -ForegroundColor Yellow
    Write-Host ""

    if (Download-File-Enhanced -Url $url -OutputPath $savePath -FileName $fileName) {
        Write-Host ""
        Write-Host "    ✅ 下载完成！" -ForegroundColor Green
        Write-Host ""

        if (Test-Path $savePath) {
            $size = [math]::Round((Get-Item $savePath).Length / 1MB, 2)
            Write-Host "    文件信息:" -ForegroundColor Cyan
            Write-Host "    📁 保存位置: $displaySavePath" -ForegroundColor White
            Write-Host "    📊 文件大小: ${size} MB" -ForegroundColor Gray
            Write-Host "    📅 下载时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
            Write-Host ""
            Write-Host "    💡 提示: 请解压文件后使用路径配置功能" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

function Download-NIKKEPackage {
    $fileName = "nikkeminiloader0.0.6.346.exe"
    $savePath = "$resourceFolder\$fileName"
    $url = "https://nikke-en.com/nikkeminiloader0.0.6.346.exe"
    $officialWebsite = "https://nikke-en.com/"
    $displaySavePath = "桌面\私服资源管理\$fileName"
    
    if (-not (Test-Path $resourceFolder)) {
        if (-not (Initialize-ResourceFolder)) {
            Write-Host "    ❌ 无法创建私服资源管理文件夹" -ForegroundColor Red
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
            return
        }
    }
    
    $choice = Show-DownloadConfirm -Title "下载NIKKE游戏资源包" `
        -FileName $fileName `
        -Description "NIKKE官服游戏启动器，私服需要通过此启动器运行" `
        -FileType "可执行程序 (EXE)" `
        -OfficialWebsite $officialWebsite `
        -SavePath $displaySavePath
    
    if ($choice -ne 1) {
        return
    }
    
    Show-Header -Title "下载NIKKE游戏资源包"
    
    Write-Host "    🎮 下载信息" -ForegroundColor Cyan
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    文件名称: " -NoNewline -ForegroundColor White
    Write-Host $fileName -ForegroundColor Cyan
    Write-Host "    保存位置: " -NoNewline -ForegroundColor White
    Write-Host $displaySavePath -ForegroundColor Gray
    Write-Host "    估计大小: " -NoNewline -ForegroundColor White
    Write-Host "约 10-50MB" -ForegroundColor Gray
    Write-Host ""
    
    Show-Separator -Type "thin"
    Write-Host ""
    
    Write-Host "    🌐 正在检查网络连接..." -ForegroundColor Cyan
    
    try {
        if (-not (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet)) {
            Write-Host "    ❌ 无法连接到互联网" -ForegroundColor Red
            Write-Host "    💡 提示: 请检查网络连接或使用VPN" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
            return
        }
        Write-Host "    ✅ 网络连接正常" -ForegroundColor Green
    }
    catch {
        Write-Host "    ❌ 网络连接检查失败" -ForegroundColor Red
        Write-Host ""
        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
        $null = Read-Host
        return
    }
    
    Write-Host ""
    Write-Host "    🚀 开始下载NIKKE游戏资源包..." -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "    文件将保存到: " -NoNewline -ForegroundColor White
    Write-Host $displaySavePath -ForegroundColor Cyan
    Write-Host "    请勿关闭此窗口，下载中..." -ForegroundColor Yellow
    Write-Host ""
    
    if (Download-File-Enhanced -Url $url -OutputPath $savePath -FileName $fileName) {
        Write-Host ""
        Write-Host "    ✅ 下载完成！" -ForegroundColor Green
        Write-Host ""
        
        if (Test-Path $savePath) {
            $size = [math]::Round((Get-Item $savePath).Length / 1MB, 2)
            Write-Host "    文件信息:" -ForegroundColor Cyan
            Write-Host "    📁 保存位置: $displaySavePath" -ForegroundColor White
            Write-Host "    📊 文件大小: ${size} MB" -ForegroundColor Gray
            Write-Host "    📅 下载时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
            Write-Host ""
            Write-Host "    💡 提示: 下载完成后可直接运行此文件安装游戏" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
    $null = Read-Host
}

# ======================= 新增蓝奏云手动下载功能 =======================

function Show-LanzouyunManualDownload {
    Show-Header -Title "蓝奏云手动下载"
    
    Write-Host "    ☁️ 蓝奏云手动下载资源" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    📋 功能说明：" -ForegroundColor White
    Write-Host "    如果通过官方网站下载速度较慢，可以使用蓝奏云链接手动下载" -ForegroundColor Gray
    Write-Host "    蓝奏云为国内用户提供了更快的下载速度" -ForegroundColor Gray
    Write-Host ""
    
    Show-Separator -Type "star"
    Write-Host ""
    
    Write-Host "    📋 操作选项：" -ForegroundColor White
    Write-Host ""
    Write-Host "    1️⃣ 打开私服资源包链接" -ForegroundColor Blue
    Write-Host "    2️⃣ 打开NIKKE游戏资源包链接" -ForegroundColor Blue
    Write-Host "    3️⃣ 打开蓝奏云官网" -ForegroundColor Green
    Write-Host "    4️⃣ 返回上一级" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "    📝 请选择操作 [1-4]: " -ForegroundColor Yellow -NoNewline
    
    $choice = Read-Host
    
    switch ($choice) {
        "1" {
            # 打开私服资源包链接
            $serverUrl = "https://wwbkv.lanzouu.com/irRpX3gg115i"
            try {
                Write-Host ""
                Write-Host "    🌐 正在打开私服资源包链接..." -ForegroundColor Cyan
                Start-Process $serverUrl
                Write-Host "    ✅ 已启动浏览器打开私服资源包链接" -ForegroundColor Green
                Write-Host "    链接: $serverUrl" -ForegroundColor Gray
                Write-Host "    提取密码: 无" -ForegroundColor Gray
            }
            catch {
                Write-Host "    ⚠ 无法打开链接，请手动复制: $serverUrl" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "    ⏎ 按回车键继续..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
        "2" {
            # 打开NIKKE游戏资源包链接
            $nikkeUrl = "https://wwbkv.lanzouu.com/ib73O3gg0t4j"
            try {
                Write-Host ""
                Write-Host "    🌐 正在打开NIKKE游戏资源包链接..." -ForegroundColor Cyan
                Start-Process $nikkeUrl
                Write-Host "    ✅ 已启动浏览器打开NIKKE游戏资源包链接" -ForegroundColor Green
                Write-Host "    链接: $nikkeUrl" -ForegroundColor Gray
                Write-Host "    提取密码: 无" -ForegroundColor Gray
            }
            catch {
                Write-Host "    ⚠ 无法打开链接，请手动复制: $nikkeUrl" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "    ⏎ 按回车键继续..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
        "3" {
            # 打开蓝奏云官网
            try {
                Write-Host ""
                Write-Host "    🌐 正在打开蓝奏云官网..." -ForegroundColor Cyan
                Start-Process "https://lanzouy.com"
                Write-Host "    ✅ 已启动浏览器打开蓝奏云官网" -ForegroundColor Green
            }
            catch {
                Write-Host "    ⚠ 无法打开浏览器: $_" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "    ⏎ 按回车键继续..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
        "4" {
            # 返回上一级
            return
        }
        default {
            Write-Host ""
            Write-Host "    ⚠ 无效选择，请输入 1-4 之间的数字" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    ⏎ 按回车键继续..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
    }
}

# ======================= 单页首页说明书 =======================

function Show-FullInstructions {
    Show-Header -Title "使用说明书"
    
    Write-Host "    📖 NIKKE私服一键启动器 - 快速开始指南" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "thin"
    Write-Host ""
    
    Write-Host "    🎯 核心功能简介" -ForegroundColor Green
    Show-Separator -Type "dash"
    Write-Host ""
    Write-Host "    本脚本是为NIKKE私服设计的懒人启动器，主要功能包括：" -ForegroundColor White
    Write-Host "    • 自动全盘搜索私服软件位置" -ForegroundColor Cyan
    Write-Host "    • 一键配置私服组件路径" -ForegroundColor Cyan
    Write-Host "    • 按正确顺序启动私服组件" -ForegroundColor Cyan
    Write-Host "    • 生成Windows格式路径文件" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "    ⚠️  重要注意事项" -ForegroundColor Yellow
    Show-Separator -Type "dash"
    Write-Host ""
    Write-Host "    1. 全盘搜索说明：" -ForegroundColor White
    Write-Host "       • 脚本会对全盘进行扫描，查找已下载解压的私服软件" -ForegroundColor Gray
    Write-Host "       • 仅用于搜索私服软件，不会修改或删除任何文件" -ForegroundColor Gray
    Write-Host "       • 搜索到的路径将作为一键启动的基础配置" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    2. 管理员权限说明：" -ForegroundColor White
    Write-Host "       • 启动某些组件需要管理员权限（如ServerSelector）" -ForegroundColor Gray
    Write-Host "       • 脚本部分功能需要以管理员身份运行" -ForegroundColor Gray
    Write-Host "       • 如果您不接受管理员权限运行，请立即退出使用本脚本" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    🚀 三分钟快速教程" -ForegroundColor Cyan
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    📥 第一步：获取资源" -ForegroundColor Yellow
    Write-Host "    1. 下载私服软件包（包含服务器组件和选择器）" -ForegroundColor White
    Write-Host "    2. 下载NIKKE游戏客户端" -ForegroundColor White
    Write-Host "    3. 将下载的文件解压到任意位置" -ForegroundColor White
    Write-Host ""
    
    Write-Host "    🔍 第二步：配置路径" -ForegroundColor Yellow
    Write-Host "    1. 使用脚本的【智能搜索】功能自动查找文件" -ForegroundColor White
    Write-Host "    2. 或手动指定三个关键文件位置：" -ForegroundColor White
    Write-Host "       • EpinelPS.exe（服务器核心）" -ForegroundColor Gray
    Write-Host "       • ServerSelector.Desktop.exe（服务器选择器）" -ForegroundColor Gray
    Write-Host "       • nikke_launcher.exe（游戏启动器）" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    🎮 第三步：启动游戏" -ForegroundColor Yellow
    Write-Host "    🔴 必须按以下顺序启动：" -ForegroundColor Red
    Write-Host "    1. 启动 EpinelPS（等待控制台窗口显示）" -ForegroundColor White
    Write-Host "    2. 启动 ServerSelector（选择服务器并保持运行）" -ForegroundColor White
    Write-Host "    3. 启动 NIKKE Launcher（开始游戏）" -ForegroundColor White
    Write-Host ""
    
    Write-Host "    🌐 网络要求" -ForegroundColor Cyan
    Show-Separator -Type "dash"
    Write-Host ""
    Write-Host "    • 必须使用VPN或代理连接私服" -ForegroundColor White
    Write-Host "    • 推荐支持TUN模式的专业VPN" -ForegroundColor White
    Write-Host "    • ❌ 避免使用会修改hosts文件的加速器" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "    📋 使用须知" -ForegroundColor Green
    Show-Separator -Type "dash"
    Write-Host ""
    Write-Host "    • 脚本不会收集或上传任何个人信息" -ForegroundColor White
    Write-Host "    • 全盘搜索仅用于定位已存在的文件" -ForegroundColor White
    Write-Host "    • 所有操作均可手动完成，脚本仅为自动化工具" -ForegroundColor White
    Write-Host "    • 如不接受上述说明，请勿继续使用" -ForegroundColor White
    Write-Host ""
    
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    💡 提示：继续使用即表示您已了解并接受上述说明" -ForegroundColor Green
    Write-Host ""
    Write-Host "    ✅ 按任意键开始使用本启动器..." -ForegroundColor Cyan -NoNewline
}

# ======================= 修改后的下载资源菜单 =======================

function Show-DownloadMenu {
    Show-Header -Title "下载资源"
    
    Write-Host "    📥 下载资源板块" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    功能简介：" -ForegroundColor White
    Write-Host "    • 下载私服资源包到私服资源管理文件夹" -ForegroundColor Gray
    Write-Host "    • 下载NIKKE游戏客户端到私服资源管理文件夹" -ForegroundColor Gray
    Write-Host "    • 蓝奏云地址手动下载（国内用户加速）" -ForegroundColor Gray
    Write-Host "    • 管理已下载的文件和文件夹" -ForegroundColor Gray
    Write-Host ""
    
    # 菜单选项（调整顺序）
    $menuItems = @(
        @("1️⃣", "下载私服资源包", "🖥️ 私服启动器", "文件: Server and Server selector.zip", "Blue"),
        @("2️⃣", "下载NIKKE游戏资源包", "🎮 NIKKE官服游戏包", "文件: nikkeminiloader0.0.6.346.exe", "Blue"),
        @("3️⃣", "蓝奏云手动下载", "☁️ 国内用户加速下载", "备注：如果不想网站下载过慢可以在蓝奏云下载资源包", "Green"),
        @("4️⃣", "私服资源管理文件夹", "📁 打开和管理下载的文件", "位置: 桌面\私服资源管理", "Cyan"),
        @("5️⃣", "返回主菜单", "⬅️ 返回上一级菜单", "", "Red")
    )
    
    foreach ($item in $menuItems) {
        Write-Host "    " -NoNewline
        Write-Host "$($item[0])" -NoNewline -ForegroundColor $item[4]
        Write-Host " $($item[1].PadRight(20))" -NoNewline -ForegroundColor White
        Write-Host "│ " -NoNewline -ForegroundColor DarkGray
        Write-Host $item[2] -ForegroundColor $item[4]
        
        if ($item[3]) {
            Write-Host "            " -NoNewline
            Write-Host $item[3] -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Show-Separator -Type "wave"
    Write-Host ""
    
    Write-Host "    📁 文件保存位置: " -NoNewline -ForegroundColor Cyan
    Write-Host "$realDesktopPath\私服资源管理\" -ForegroundColor Green
    Write-Host "    ⚠️  注意: 下载需要网络连接，请确保网络通畅" -ForegroundColor Yellow
    Write-Host "    🌐 官网: 不想使用脚本下载？可选择官方网站下载" -ForegroundColor Cyan
    Write-Host "    ☁️ 蓝奏云: 国内用户如官网下载慢，可使用蓝奏云加速" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "    📝 请选择操作 [1-5]: " -ForegroundColor Yellow -NoNewline
}

# ======================= 新的路径配置子菜单 =======================

function Show-PathConfigSubMenu {
    Show-Header -Title "路径配置选项"
    
    Write-Host "    🔧 路径配置选项" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    # 显示当前配置状态
    $count = 0
    if ($global:paths.EpinelPS) { $count++ }
    if ($global:paths.ServerSelector) { $count++ }
    if ($global:paths.NikkeLauncher) { $count++ }
    
    Write-Host "    📊 当前配置状态: " -NoNewline -ForegroundColor White
    Write-Host "$count/3" -ForegroundColor $(if ($count -eq 0) { "Red" } elseif ($count -eq 3) { "Green" } else { "Yellow" })
    Write-Host ""
    
    # 菜单选项
    Write-Host "    📋 请选择操作:" -ForegroundColor White
    Write-Host ""
    
    Write-Host "    1️⃣ 智能全盘搜索软件路径" -ForegroundColor Blue
    Write-Host "       🤖 全盘深度搜索（需要5-15分钟）" -ForegroundColor Gray
    Write-Host "       🎯 自动查找同一文件夹的ServerSelector和EpinelPS" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    2️⃣ 手动配置路径" -ForegroundColor Yellow
    Write-Host "       📝 手动输入三个关键文件的完整路径" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    3️⃣ 生成Windows路径文件" -ForegroundColor Green
    Write-Host "       📄 生成Windows格式路径文件到桌面" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    4️⃣ 查看Windows路径文件" -ForegroundColor Cyan
    Write-Host "       📋 查看和复制已生成的路径信息" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    5️⃣ 返回上一级" -ForegroundColor Red
    Write-Host ""
    
    Show-Separator -Type "wave"
    Write-Host ""
    Write-Host "    💡 提示: 建议先使用智能搜索，再手动配置缺失的路径" -ForegroundColor Cyan
    Write-Host "    📄 Windows路径文件: " -NoNewline -ForegroundColor Cyan
    Write-Host "桌面\NIKKE_Windows路径.txt" -ForegroundColor $(if (Test-Path $windowsPathFile) { "Green" } else { "Gray" })
    Write-Host ""
    Write-Host "    📝 请选择操作 [1-5]: " -ForegroundColor Yellow -NoNewline
}

# ======================= 新的软件启动子菜单 =======================

function Show-SoftwareLaunchSubMenu {
    Show-Header -Title "软件启动选项"
    
    Write-Host "    🚀 软件启动选项" -ForegroundColor Magenta
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    🚫 启动顺序 (必须按此顺序执行):" -ForegroundColor Red
    Write-Host "    1. EpinelPS → 2. ServerSelector → 3. NIKKE Launcher" -ForegroundColor White
    Write-Host ""
    
    # 显示各软件状态
    Write-Host "    📊 软件状态检查:" -ForegroundColor Cyan
    Write-Host ""
    
    $softwareStatus = @(
        @{
            Key = "1"
            Name = "EpinelPS 服务器组件"
            Path = $global:paths.EpinelPS
            Required = "第1步"
        },
        @{
            Key = "2"
            Name = "ServerSelector 服务器选择器"
            Path = $global:paths.ServerSelector
            Required = "第2步"
        },
        @{
            Key = "3"
            Name = "NIKKE 游戏启动器"
            Path = $global:paths.NikkeLauncher
            Required = "第3步"
        }
    )
    
    foreach ($software in $softwareStatus) {
        if ($software.Path -and (Test-Path $software.Path)) {
            Write-Host "    ✅ $($software.Name): 已配置 ($($software.Required))" -ForegroundColor Green
            Write-Host "        路径: $($software.Path)" -ForegroundColor Gray
        } else {
            Write-Host "    ❌ $($software.Name): 未配置 ($($software.Required))" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    📋 请选择要启动的软件:" -ForegroundColor White
    Write-Host ""
    
    # 选项1：首次使用选项 - 按顺序配置环境
    Write-Host "    1️⃣ 首次使用选项 - 按顺序配置环境" -ForegroundColor Green
    Write-Host "       🔄 按顺序启动三个必备软件（推荐首次使用）" -ForegroundColor Gray
    Write-Host "       🖥️  EpinelPS → 🔗 ServerSelector → 🎮 NIKKE Launcher" -ForegroundColor Gray
    Write-Host ""
    
    # 选项2：一键启动所有组件
    Write-Host "    2️⃣ 一键启动所有组件" -ForegroundColor Blue
    Write-Host "       ⚡ 按顺序启动所有已配置的软件" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    3️⃣ 返回上一级" -ForegroundColor Red
    Write-Host ""
    
    Show-Separator -Type "wave"
    Write-Host ""
    Write-Host "    💡 提示: 请确保所有软件已正确配置路径" -ForegroundColor Cyan
    Write-Host "    ⚠️  注意: ServerSelector需要管理员权限" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    📝 请选择操作 [1-3]: " -ForegroundColor Yellow -NoNewline
}

# ======================= 修改路径配置菜单 =======================

function Show-PathConfigMenu {
    Show-Header -Title "路径配置与启动"
    
    Write-Host "    🔧 路径配置与启动板块" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    # 计算配置状态
    $count = 0
    if ($global:paths.EpinelPS) { $count++ }
    if ($global:paths.ServerSelector) { $count++ }
    if ($global:paths.NikkeLauncher) { $count++ }
    
    # 显示配置状态
    Write-Host "    📊 当前配置状态: " -NoNewline -ForegroundColor White
    Write-Host "$count/3" -ForegroundColor $(if ($count -eq 0) { "Red" } elseif ($count -eq 3) { "Green" } else { "Yellow" })
    Write-Host ""
    
    # 显示各个软件状态
    if ($global:paths.EpinelPS) {
        $status = if (Test-Path $global:paths.EpinelPS) { "✅" } else { "❌" }
        Write-Host "    $status EpinelPS.exe: " -NoNewline -ForegroundColor $(if (Test-Path $global:paths.EpinelPS) { "Green" } else { "Red" })
        Write-Host $global:paths.EpinelPS -ForegroundColor Gray
    } else {
        Write-Host "    ⚠ EpinelPS.exe: 未配置" -ForegroundColor Yellow
    }
    
    if ($global:paths.ServerSelector) {
        $status = if (Test-Path $global:paths.ServerSelector) { "✅" } else { "❌" }
        Write-Host "    $status ServerSelector.Desktop.exe: " -NoNewline -ForegroundColor $(if (Test-Path $global:paths.ServerSelector) { "Green" } else { "Red" })
        Write-Host $global:paths.ServerSelector -ForegroundColor Gray
    } else {
        Write-Host "    ⚠ ServerSelector.Desktop.exe: 未配置" -ForegroundColor Yellow
    }
    
    if ($global:paths.NikkeLauncher) {
        $status = if (Test-Path $global:paths.NikkeLauncher) { "✅" } else { "❌" }
        Write-Host "    $status nikke_launcher.exe: " -NoNewline -ForegroundColor $(if (Test-Path $global:paths.NikkeLauncher) { "Green" } else { "Red" })
        Write-Host $global:paths.NikkeLauncher -ForegroundColor Gray
    } else {
        Write-Host "    ⚠ nikke_launcher.exe: 未配置" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Show-Separator -Type "star"
    Write-Host ""
    
    Write-Host "    🚀 启动顺序 (必须按此顺序执行):" -ForegroundColor Red
    Write-Host "    1. EpinelPS → 2. ServerSelector → 3. NIKKE Launcher" -ForegroundColor White
    Write-Host ""
    
    Write-Host "    📋 主菜单选项:" -ForegroundColor White
    Write-Host ""
    
    # 主菜单选项
    Write-Host "    1️⃣ 路径配置选项" -ForegroundColor Cyan
    Write-Host "       🔧 搜索、配置和管理软件路径" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    2️⃣ 软件启动选项" -ForegroundColor Magenta
    Write-Host "       🚀 启动已配置的私服软件" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "    3️⃣ 返回主菜单" -ForegroundColor Red
    Write-Host ""
    
    Show-Separator -Type "wave"
    Write-Host ""
    Write-Host "    💡 提示: 首次使用请先配置路径，再启动软件" -ForegroundColor Cyan
    Write-Host "    📄 Windows路径文件: " -NoNewline -ForegroundColor Cyan
    Write-Host "桌面\NIKKE_Windows路径.txt" -ForegroundColor $(if (Test-Path $windowsPathFile) { "Green" } else { "Gray" })
    Write-Host ""
    Write-Host "    📝 请选择操作 [1-3]: " -ForegroundColor Yellow -NoNewline
}

function Show-WindowsPaths {
    Show-Header -Title "Windows可用路径"
    
    if (Test-Path $windowsPathFile) {
        Write-Host "    📄 Windows格式路径文件内容：" -ForegroundColor Cyan
        Write-Host ""
        Show-Separator -Type "thin"
        Write-Host ""
        
        $content = Get-Content $windowsPathFile -Raw
        $lines = $content -split "`n"
        
        foreach ($line in $lines) {
            if ($line -match "^# ==") {
                Write-Host "    $line" -ForegroundColor DarkCyan
            }
            elseif ($line -match "^📁|^📋|^💡") {
                Write-Host "    $line" -ForegroundColor Cyan
            }
            elseif ($line -match "^EpinelPS|^ServerSelector|^nikke_launcher") {
                Write-Host "    $line" -ForegroundColor Yellow
            }
            elseif ($line -match "^  [A-Z]:\\") {
                Write-Host "    $line" -ForegroundColor White
            }
            elseif ($line -match "✅|❌|⚠") {
                $color = if ($line -match "✅") { "Green" } 
                         elseif ($line -match "❌") { "Red" } 
                         else { "Yellow" }
                Write-Host "    $line" -ForegroundColor $color
            }
            elseif ($line -match "^# ") {
                Write-Host "    $line" -ForegroundColor DarkGray
            }
            else {
                Write-Host "    $line" -ForegroundColor Gray
            }
        }
        
        Write-Host ""
        Show-Separator -Type "thin"
        Write-Host ""
        
        Write-Host "    操作选项：" -ForegroundColor White
        Write-Host ""
        Write-Host "    1. 打开文件" -ForegroundColor Yellow
        Write-Host "    2. 复制到剪贴板" -ForegroundColor Yellow
        Write-Host "    3. 返回" -ForegroundColor Red
        Write-Host ""
        Write-Host "    请选择操作 [1-3]: " -NoNewline -ForegroundColor Green
        
        $choice = Read-Host
        
        switch ($choice) {
            "1" {
                Start-Process notepad.exe $windowsPathFile
                Write-Host "    ✅ 已使用记事本打开文件" -ForegroundColor Green
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            "2" {
                $pathsToCopy = @()
                foreach ($line in $lines) {
                    if ($line -match "^  [A-Z]:\\") {
                        $pathsToCopy += $line.Trim()
                    }
                }
                
                if ($pathsToCopy.Count -gt 0) {
                    $clipboardText = $pathsToCopy -join "`n"
                    Set-Clipboard -Value $clipboardText
                    Write-Host "    ✅ 路径已复制到剪贴板" -ForegroundColor Green
                } else {
                    Write-Host "    ⚠ 未找到可复制的路径" -ForegroundColor Yellow
                }
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
            "3" { return }
            default {
                Write-Host "    ⚠ 无效的选择" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                $null = Read-Host
            }
        }
    } else {
        Write-Host "    ❌ Windows路径文件不存在" -ForegroundColor Red
        Write-Host ""
        Write-Host "    💡 提示: 请先配置软件路径，系统会自动生成此文件" -ForegroundColor Cyan
        
        if ($global:paths.EpinelPS -or $global:paths.ServerSelector -or $global:paths.NikkeLauncher) {
            Write-Host ""
            Write-Host "    是否立即生成Windows路径文件？[Y/N]: " -NoNewline -ForegroundColor Yellow
            $generateChoice = Read-Host
            
            if ($generateChoice -eq 'Y' -or $generateChoice -eq 'y') {
                Save-WindowsPaths
                
                if (Test-Path $windowsPathFile) {
                    Write-Host "    ✅ 已生成Windows路径文件" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "    ⏎ 按回车键查看..." -ForegroundColor Cyan -NoNewline
                    $null = Read-Host
                    Show-WindowsPaths
                }
            }
        } else {
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
    }
}

# ======================= 其他板块 =======================

function Show-SystemMenu {
    Show-Header -Title "系统工具"
    
    Write-Host "    ⚙️  系统工具板块" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    功能简介：" -ForegroundColor White
    Write-Host "    • 检查系统环境" -ForegroundColor Gray
    Write-Host "    • 网络连接测试" -ForegroundColor Gray
    Write-Host "    • 管理员权限管理" -ForegroundColor Gray
    Write-Host "    • 脚本设置和配置" -ForegroundColor Gray
    Write-Host ""
    
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    📝 此板块功能待进一步开发..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    1️⃣ 返回主菜单" -ForegroundColor Red
    Write-Host ""
    
    Show-Separator -Type "wave"
    Write-Host ""
    Write-Host "    📝 请选择操作 [1]: " -ForegroundColor Yellow -NoNewline
    
    $choice = Read-Host
    if ($choice -ne "1") {
        Write-Host "    ⚠ 无效输入，返回主菜单" -ForegroundColor Yellow
    }
}

function Show-HelpMenu {
    Show-Header -Title "帮助支持"
    
    Write-Host "    ❓ 帮助支持板块" -ForegroundColor Cyan
    Write-Host ""
    Show-Separator -Type "dash"
    Write-Host ""
    
    Write-Host "    功能简介：" -ForegroundColor White
    Write-Host "    • 查看详细使用说明书" -ForegroundColor Gray
    Write-Host "    • 常见问题解答" -ForegroundColor Gray
    Write-Host "    • 联系技术支持" -ForegroundColor Gray
    Write-Host "    • 查看脚本版本信息" -ForegroundColor Gray
    Write-Host ""
    
    Show-Separator -Type "star"
    Write-Host ""
    Write-Host "    📝 此板块功能待进一步开发..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    1️⃣ 返回主菜单" -ForegroundColor Red
    Write-Host ""
    
    Show-Separator -Type "wave"
    Write-Host ""
    Write-Host "    📝 请选择操作 [1]: " -ForegroundColor Yellow -NoNewline
    
    $choice = Read-Host
    if ($choice -ne "1") {
        Write-Host "    ⚠ 无效输入，返回主菜单" -ForegroundColor Yellow
    }
}

# ======================= 主菜单 =======================

function Show-MainMenu {
    Show-Header -Title "主菜单"
    
    Write-Host "    🎮 请选择功能板块：" -ForegroundColor White
    Write-Host ""
    
    # 计算配置状态
    $count = 0
    if ($global:paths.EpinelPS) { $count++ }
    if ($global:paths.ServerSelector) { $count++ }
    if ($global:paths.NikkeLauncher) { $count++ }
    
    # 三个主功能板块（移除后）
    $menuItems = @(
        @("1️⃣", "下载资源", "📥 获取私服和游戏文件", "首次使用从此开始", "Blue"),
        @("2️⃣", "路径配置", "🔧 搜索和启动管理", "配置状态: $count/3 | 含启动功能", $(if ($count -eq 3) { "Green" } elseif ($count -gt 0) { "Yellow" } else { "Gray" })),
        @("3️⃣", "退出程序", "🚪 安全关闭启动管理器", "", "Red")
    )
    
    foreach ($item in $menuItems) {
        Write-Host "    " -NoNewline
        Write-Host "$($item[0])" -NoNewline -ForegroundColor $item[4]
        Write-Host " $($item[1].PadRight(10))" -NoNewline -ForegroundColor White
        Write-Host "│ " -NoNewline -ForegroundColor DarkGray
        Write-Host $item[2] -ForegroundColor $item[4]
        
        if ($item[3]) {
            Write-Host "            " -NoNewline
            Write-Host $item[3] -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Show-Separator -Type "wave"
    Write-Host ""
    
    Write-Host "    💡 提示: " -NoNewline -ForegroundColor Cyan
    Write-Host "首次使用建议按 1 → 2 顺序操作" -ForegroundColor White
    Write-Host "    📁 文件保存: " -NoNewline -ForegroundColor Cyan
    Write-Host "桌面\私服资源管理\" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "    📝 请选择功能 [1-3]: " -ForegroundColor Yellow -NoNewline
}

# ======================= 主程序 =======================

# 显示完整的单页说明书
Show-FullInstructions
$null = Read-Host

# 主程序循环
while ($true) {
    Show-MainMenu
    $choice = Read-Host
    
    switch ($choice) {
        "1" {
            # 下载资源板块
            while ($true) {
                Show-DownloadMenu
                $downloadChoice = Read-Host
                
                if ($downloadChoice -eq "5") {
                    # 选项5：返回主菜单
                    break
                }
                
                switch ($downloadChoice) {
                    "1" { 
                        Download-ServerPackage 
                    }
                    "2" { 
                        Download-NIKKEPackage 
                    }
                    "3" { 
                        # 新增的蓝奏云手动下载功能
                        Show-LanzouyunManualDownload 
                    }
                    "4" { 
                        Show-ResourceFolderInfo 
                    }
                    default {
                        Show-Header -Title "错误报告"
                        Write-Host "    ❌ 无效的输入: '$downloadChoice'" -ForegroundColor Red
                        Write-Host "    💡 提示: 请输入 1-5 之间的数字" -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                        $null = Read-Host
                    }
                }
            }
        }
        "2" {
            # 路径配置与启动板块（新版）
            while ($true) {
                Show-PathConfigMenu
                $configChoice = Read-Host
                
                if ($configChoice -eq "3") {
                    # 返回主菜单
                    break
                }
                
                switch ($configChoice) {
                    "1" {
                        # 进入路径配置子菜单
                        while ($true) {
                            Show-PathConfigSubMenu
                            $pathConfigChoice = Read-Host
                            
                            if ($pathConfigChoice -eq "5") {
                                # 返回上一级
                                break
                            }
                            
                            switch ($pathConfigChoice) {
                                "1" { 
                                    Search-NIKKE-Software 
                                }
                                "2" { 
                                    Manual-PathConfig 
                                }
                                "3" { 
                                    Save-WindowsPaths 
                                    Write-Host ""
                                    Write-Host "    ⏎ 按回车键继续..." -ForegroundColor Cyan -NoNewline
                                    $null = Read-Host
                                }
                                "4" { 
                                    Show-WindowsPaths 
                                }
                                default {
                                    Show-Header -Title "错误报告"
                                    Write-Host "    ❌ 无效的输入: '$pathConfigChoice'" -ForegroundColor Red
                                    Write-Host "    💡 提示: 请输入 1-5 之间的数字" -ForegroundColor Yellow
                                    Write-Host ""
                                    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                                    $null = Read-Host
                                }
                            }
                        }
                    }
                    "2" {
                        # 进入软件启动子菜单
                        while ($true) {
                            Show-SoftwareLaunchSubMenu
                            $launchChoice = Read-Host
                            
                            if ($launchChoice -eq "3") {
                                # 返回上一级
                                break
                            }
                            
                            switch ($launchChoice) {
                                "1" { 
                                    Launch-FirstTimeSetup  # 新增的首次使用选项函数
                                }
                                "2" { 
                                    Launch-AllSoftware  # 一键启动所有组件
                                }
                                default {
                                    Show-Header -Title "错误报告"
                                    Write-Host "    ❌ 无效的输入: '$launchChoice'" -ForegroundColor Red
                                    Write-Host "    💡 提示: 请输入 1-3 之间的数字" -ForegroundColor Yellow
                                    Write-Host ""
                                    Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                                    $null = Read-Host
                                }
                            }
                        }
                    }
                    default {
                        Show-Header -Title "错误报告"
                        Write-Host "    ❌ 无效的输入: '$configChoice'" -ForegroundColor Red
                        Write-Host "    💡 提示: 请输入 1-3 之间的数字" -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "    ⏎ 按回车键返回..." -ForegroundColor Cyan -NoNewline
                        $null = Read-Host
                    }
                }
            }
        }
        "3" {
            # 退出程序
            Show-Header -Title "退出程序"
            Write-Host ""
            Write-Host "    👋 感谢使用 NIKKE私服一键启动器 v$scriptVersion" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "    🎮 祝您游戏愉快！" -ForegroundColor Green
            Write-Host ""
            Write-Host "    程序将在3秒后退出..." -ForegroundColor Gray
            Start-Sleep -Seconds 3
            exit
        }
        default {
            Show-Header -Title "错误输入"
            Write-Host ""
            Write-Host "    ❌ 错误: 无效的选择 '$choice'" -ForegroundColor Red
            Write-Host ""
            Write-Host "    💡 提示: 请输入 1-3 之间的数字" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "    ⏎ 按回车键返回主菜单..." -ForegroundColor Cyan -NoNewline
            $null = Read-Host
        }
    }
}