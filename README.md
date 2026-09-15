# PowerShell Modern for Windows

这是 Bash Modern Server 的 Windows PowerShell 复刻版，面向日常 Windows 开发环境。第一版只使用 PowerShell 与 Windows 自带能力，不安装第三方软件，也不包含 Docker、systemd、MTR 或第三方提示符等相关命令。

支持 Windows PowerShell 5.1 与 PowerShell 7。两者使用各自的 `$PROFILE.CurrentUserAllHosts`，因此请用日常实际使用的 PowerShell 执行安装器。
安装只写入当前用户目录，不需要也不建议使用“以管理员身份运行”的终端。

## 包含内容

- 在当前用户的 PowerShell Profile 中维护单一、可识别的加载块，不覆盖其他配置。
- 安装和卸载前自动完整备份，可列出备份或回滚。
- 使用 PSReadLine 保存增量历史、忽略重复项，并在版本支持时显示历史行内建议。
- 使用空格或回车即时展开 `abbr` 缩写；个人缩写持久化为 JSON。
- 按“公开通用、私有命令包、单机配置”三层加载命令，个人缩写优先。
- 通过 `# @cmd 分类 | 用法 | 说明` 元数据发现和搜索命令。
- 提供带路径缩写和 Git 状态的纯 PowerShell 原生提示符，以及 `ports`、`mem`、`winlog` 等 Windows 原生命令。

## 安装

在 Windows PowerShell 或 PowerShell 7 中进入项目目录：

```powershell
.\install.ps1
```

如果系统因执行策略阻止本次运行，可只为当前进程临时放行后再安装：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

重新打开 PowerShell，或在当前会话加载 Profile：

```powershell
. $PROFILE.CurrentUserAllHosts
powershell-modern doctor
```

默认配置位置为：

```text
$HOME\.config\powershell-modern\
├── profile.ps1
├── powershell.d\
├── commands.d\
├── bin\
└── user\
```

本文中的 `$HOME` 指 PowerShell 的用户主目录变量；在 Windows 上通常对应 `C:\Users\<用户名>`。

安装结果是项目文件的副本，不依赖原项目目录。重复运行安装器会更新受管代码，同时保留 `user\` 内容和 Profile 中的非受管配置。

可用以下环境变量覆盖路径，便于定制安装或测试：

```text
POWERSHELL_MODERN_HOME
POWERSHELL_MODERN_BACKUP_ROOT
POWERSHELL_MODERN_PROFILE
POWERSHELL_MODERN_COMMANDS_HOME
```

## 历史与编辑

PSReadLine 使用增量保存历史，最多保留 50,000 条，并忽略重复项。支持相应 PSReadLine 版本和终端时，历史建议会以内联形式显示。

- `→`、`Ctrl+F`、`End`：接受建议的字符、单词或整行。
- `Alt+F`：接受下一个词。
- `Alt+Backspace`：删除前一个词。

如果当前 Windows PowerShell 5.1 自带的 PSReadLine 较旧，不支持预测选项，加载器会跳过行内建议，其他功能不受影响。

## 提示符

提示符会保留当前目录名，并将上级目录缩写为首字符，例如 `$HOME\projects\powershell-modern` 会显示为 `~\p\powershell-modern`。这里的 `~` 只是提示符用来表示用户主目录的显示标记，不是传给 Windows 程序的文件路径。在 Git 仓库中还会显示分支及以下状态标记：

- `+`：有已暂存的改动。
- `!`：有未暂存的改动。
- `?`：有未跟踪文件。
- `↑n` / `↓n`：相对上游领先或落后的提交数。

## 即时缩写

缩写会在按空格或回车时展开为仍可编辑的完整命令：

```powershell
abbr gs Get-Service
abbr -Add proc Get-Process
abbr -Show
abbr -Erase gs
```

个人缩写保存在 `$HOME\.config\powershell-modern\user\abbreviations.json`，项目更新时会保留。命令包中应使用只对当前会话声明的形式：

```powershell
abbr -Define docs 'Set-Location C:\src\docs'
```

同名个人缩写优先；删除个人缩写后，会恢复命令包中的同名声明。

## 分层命令库

| 层级 | 默认位置 | 用途 |
|---|---|---|
| 公开通用 | `$HOME\.config\powershell-modern\commands.d\` | 随项目更新的 Windows 原生命令 |
| 私有命令包 | `$HOME\.config\powershell-modern-commands\` | 跨电脑同步的私有命令 |
| 单机配置 | `$HOME\.config\powershell-modern\user\local.ps1` | 本机路径与本机函数 |

后加载的函数可以覆盖前一层。私有命令包的目录结构为：

```text
powershell-modern-commands\
├── abbreviations.ps1
└── commands.d\
    ├── navigation.ps1
    └── services.ps1
```

Windows 上加载私有代码前会检查所有者与 ACL；如果目录或文件允许 Everyone、Authenticated Users 或内置 Users 组写入，则跳过并显示警告。

命令元数据格式如下：

```powershell
# @cmd Navigation | cdev | Change to the development directory
function cdev {
    Set-Location -LiteralPath 'C:\src'
}
```

查看、搜索及审计来源：

```powershell
cmds
cmds network
cmds --sources
```

单机配置模板位于 `examples\local.example.ps1`，私有命令包示例位于 `examples\private-commands\`。

## 原生命令

```powershell
ll                   # 显示当前目录，包括隐藏项
la                   # 同上，保留与 Bash 版相近的肌肉记忆
ports                # 显示监听中的 TCP 与 UDP 端点
mem                  # 显示物理内存总量、已用量与使用率
winlog System 100    # 显示最近 100 条 System 事件日志
```

## 备份、回滚与卸载

```powershell
powershell-modern backup
powershell-modern backups
powershell-modern rollback
powershell-modern rollback <备份目录名或完整路径>
```

不带目标的 `rollback` 恢复最新备份。恢复前会先备份当前状态，因此误回滚也可撤销。

卸载：

```powershell
.\uninstall.ps1
.\uninstall.ps1 -KeepConfig
```

卸载器会移除 Profile 中的受管加载块；默认同时删除配置目录，但不会删除备份。

## 验证

### 启动耗时

排查启动慢时，更新安装后，在现有 PowerShell 中执行：

```powershell
$env:POWERSHELL_MODERN_TRACE_STARTUP = '1'
pwsh -NoLogo
```

在新打开的会话中查看各模块耗时（毫秒）：

```powershell
$PowerShellModernStartupTimings | Format-Table -AutoSize
```

Windows PowerShell 5.1 请将 `pwsh` 换成 `powershell`。每次比较都启动新进程；同一会话重复加载会被防重入检查跳过，无法测到真实启动耗时。

`Total (powershell-modern)` 是本项目加载器的耗时，包含模块查找和加载。PowerShell 启动时显示的 Profile 总耗时还可能包含其他 Profile；首次提示符中的 `git status` 不计入这里的模块加载时间。不要将各模块与 Total 再相加。

- `00-PSReadLine.ps1`：PSReadLine 导入、历史选项和按键配置。
- `35-NativePrompt.ps1`：提示符定义与 Git 可执行文件查找。
- `40-Abbreviations.ps1`：个人缩写读取与权限检查。
- `45-CommandLibrary.ps1`：通用命令、私有命令包和 `user\local.ps1` 的加载。

计时默认关闭，不会输出启动信息。排查结束后先 `exit` 返回原会话，再执行 `Remove-Item Env:POWERSHELL_MODERN_TRACE_STARTUP`。

### 功能测试

测试只使用临时 HOME 和 Profile，不修改真实用户配置：

```powershell
.\tests\test.ps1
```
