# Whistle.el - Emacs Whistle Proxy Editor

一个全功能的 Emacs whistle 规则和值编辑器，为你提供最佳的 whistle 编辑体验。

## ✨ 核心特性

### 统一文件编辑
- 📄 **单文件格式** - 规则和值在同一个 `.whistle` 文件中编辑
- 💾 **本地存储** - 规则自动保存到本地文件系统 (`~/.whistle/rules/`)
- 🔄 **智能同步** - 本地文件与 Whistle 服务器双向同步
- 📝 **Markdown 风格** - 使用熟悉的 ` ```name ... ``` ` 语法定义值

### 强大的编辑体验
- 🎨 **Tree-sitter 语法高亮** - 使用 tree-sitter 提供精确的语法解析
- 🌈 **多语言支持** - Whistle 规则 + JSON 值块混合高亮
- 📝 **智能补全** - 协议和值名称自动补全（大小写不敏感）
- ⚡ **快速插入** - 规则模板和值块快速插入
- 🔍 **规则列表** - 浏览和管理所有规则
- ⌨️  **Vim 友好** - 完整的 Evil mode 支持

## 📦 安装

使用 tree-sitter 获得更好的语法高亮和编辑体验：

```elisp
;; 加载 tree-sitter 模式（需要 Emacs 29.1+）
(require 'whistle-ts-mode)

;; whistle-ts-mode 会自动用于 .whistle 文件
;; 需要安装 tree-sitter-whistle grammar

;; 可选：配置 whistle 服务器地址（默认: http://127.0.0.1:8899）
(setq whistle-base-url "http://127.0.0.1:8899")

;; 可选：配置本地存储目录（默认: ~/.whistle/rules/）
(setq whistle-rules-directory "~/.whistle/rules/")

;; 可选：自动同步到服务器（默认: t）
(setq whistle-auto-sync t)
```

**安装 tree-sitter grammar：**

参考 [tree-sitter-whistle](https://github.com/yourusername/tree-sitter-whistle) 安装说明。

## 🚀 快速开始

### 打开规则列表

```elisp
M-x whistle  ; 打开规则列表视图
```

在规则列表中：
- `RET` - 打开选中的规则进行编辑
- `c` - 创建新规则
- `d` - 删除规则
- `t` 或 `SPC` - 激活/停用规则
- `g` - 刷新列表
- `q` - 退出

### 编辑规则文件

```elisp
M-x whistle-edit-rule  ; 选择或创建规则进行编辑
```

或者直接打开 `.whistle` 文件：

```elisp
;; 会自动使用 whistle-ts-mode（如果可用）
C-x C-f ~/.whistle/rules/my-rule.whistle
```

## 📝 文件格式

Whistle.el 使用统一的文件格式，将规则和值组合在一个文件中：

````whistle
# Whistle 规则部分
# 使用标准 Whistle 语法

# 代理所有 example.com 请求
example.com proxy://127.0.0.1:8080

# 使用值块模拟 API 响应
/api/user resBody://{user-data}

# 添加 CORS 头
/api/* resCors://

# 值块部分
# 使用 Markdown 风格的代码块语法

```user-data
{
  "id": 123,
  "name": "Test User",
  "email": "test@example.com"
}
```

```api-headers
x-custom-header: value
authorization: Bearer token123
```
````

**要点：**
- 规则部分在前，使用标准 Whistle 语法
- 值块使用 ` ```name ... ``` ` 语法（类似 Markdown）
- 规则中使用 `{value-name}` 引用值块
- 支持多个值块，每个有独立的名称

## ⌨️ 快捷键

### 规则列表模式

| 快捷键 | 功能 |
|--------|------|
| `RET` | 打开选中的规则进行编辑 |
| `c` | 创建新规则 |
| `d` | 删除选中的规则 |
| `r` | 重命名规则 |
| `t` 或 `SPC` | 激活/停用规则 |
| `g` | 刷新列表 |
| `m` | 显示 Emacs 管理的规则状态 |
| `C` | 清理孤立的值（属于已删除规则的值）|
| `D` | 删除所有 Emacs 管理的规则 |
| `q` | 退出窗口 |

### 规则编辑模式

| 快捷键 | 功能 |
|--------|------|
| `C-c C-c` 或 `C-x C-s` | 保存到本地文件（可选同步到服务器）|
| `C-c C-s` | 仅同步到服务器 |
| `C-c C-l` | 从服务器加载规则 |
| `C-c C-a` | 激活当前规则 |
| `C-c C-n` | 设置规则名称 |
| `C-c C-v` | 插入值块模板 |
| `C-c C-t` | 插入规则模板 |
| `TAB` | 自动补全协议或值名称 |
| `` ` `` (行首输入 ` ``` `) | 自动展开为值块 |

### Evil Mode 支持

如果使用 Evil mode，额外支持：

| 快捷键 | 功能 |
|--------|------|
| `, ,` | 保存规则 |
| `, s` | 同步到服务器 |
| `, l` | 从服务器加载 |
| `, a` | 激活规则 |
| `, v` | 插入值块 |
| `, t` | 插入模板 |

## 🎨 语法高亮

### Whistle 规则语法

支持高亮的元素：
- **注释** - `# 这是注释`
- **协议关键字** - `host`, `proxy`, `file`, `statusCode`, `resBody` 等 40+ 个协议
- **URL 模式** - `http://`, `https://`, `ws://`, `wss://`
- **正则表达式** - `/pattern/`, `/pattern/i`
- **通配符** - `*`, `?`, `^`, `$`
- **IP 地址** - `192.168.1.1`, `[::1]`
- **端口** - `:8080`
- **值引用** - `{value-name}`
- **宏和变量** - `$variable`, `@reference`

### JSON 值块语法

在 ` ```name ... ``` ` 块中支持完整的 JSON 高亮：
- 字符串、数字、布尔值
- 对象键名高亮
- 括号和分隔符
- 转义序列

## 📋 规则模板

按 `C-c C-t` 可快速插入以下模板：

1. **Proxy** - 代理请求
2. **Host mapping** - 域名映射到 IP
3. **Mock with value** - 使用值块模拟响应
4. **Mock with file** - 使用本地文件模拟响应
5. **CORS** - 启用 CORS
6. **Delay** - 添加延迟
7. **Header** - 添加响应头
8. **Redirect** - 重定向

## 🔄 同步机制

Whistle.el 提供灵活的本地文件与服务器同步：

### 自动同步模式（默认）

```elisp
(setq whistle-auto-sync t)  ; 保存时自动同步到服务器
```

保存规则时（`C-c C-c` 或 `C-x C-s`）：
1. ✅ 保存到本地文件 `~/.whistle/rules/rule-name.whistle`
2. ✅ 自动同步到 Whistle 服务器
3. ✅ 更新元数据记录（哈希值、同步时间等）

### 手动同步模式

```elisp
(setq whistle-auto-sync nil)  ; 仅保存到本地文件
```

需要手动同步：
- `C-c C-s` - 手动同步到服务器
- `C-c C-l` - 从服务器加载最新版本

### 服务器端组织

Emacs 管理的规则在服务器上统一放在 `\remacs` 组中：
- **规则名称**：在组内使用原始名称（如 `my-rule`）
- **值名称**：自动添加前缀（如 `emacs-my-rule-value-name`）
- **值引用转换**：本地的 `{value-name}` 自动转换为服务器的 `{emacs-my-rule-value-name}`

这种设计避免了不同来源的规则和值名称冲突。

## 📚 使用场景示例

### 场景 1：创建代理规则

```elisp
M-x whistle-edit-rule RET dev-proxy RET
```

在编辑器中输入：
```whistle
# 代理所有 example.com 的请求到本地
*.example.com proxy://127.0.0.1:8080
```

按 `C-c C-c` 保存，按 `C-c C-a` 激活规则。

### 场景 2：Mock API 响应

```elisp
M-x whistle-edit-rule RET api-mock RET
```

创建规则和值块：
```whistle
# Mock user API
/api/user resBody://{user-data}

# Mock list API
/api/users resBody://{users-list}

```user-data
{
  "id": 123,
  "name": "Test User",
  "email": "test@example.com",
  "role": "admin"
}
```

```users-list
[
  {"id": 1, "name": "User 1"},
  {"id": 2, "name": "User 2"}
]
```
```

### 场景 3：添加自定义响应头

```whistle
# 为所有 API 请求添加 CORS 和自定义头
/api/* resHeaders://{api-headers}

```api-headers
access-control-allow-origin: *
access-control-allow-methods: GET, POST, PUT, DELETE
x-custom-header: my-value
```
```

### 场景 4：组合多个功能

```whistle
# 复杂的调试场景

# 1. 代理特定域名
*.example.com proxy://127.0.0.1:8080

# 2. Mock 登录 API
/api/login resBody://{login-response} statusCode://200

# 3. 添加延迟模拟慢网络
/api/slow-endpoint resDelay://2000

# 4. 启用 CORS
/api/* resCors://

# 5. 重写特定请求
/old-api/(.*)  redirect://https://new-api.com/$1

```login-response
{
  "token": "fake-jwt-token",
  "user": {
    "id": 1,
    "username": "testuser"
  }
}
```
```

## ⚙️ 配置选项

```elisp
;; === 基础配置 ===

;; Whistle 服务器地址（默认: http://127.0.0.1:8899）
(setq whistle-base-url "http://127.0.0.1:8899")

;; 本地规则存储目录（默认: ~/.whistle/rules/）
(setq whistle-rules-directory "~/.whistle/rules/")

;; 元数据文件路径（默认: ~/.whistle/metadata.json）
(setq whistle-metadata-file "~/.whistle/metadata.json")

;; === 同步配置 ===

;; 保存时自动同步到服务器（默认: t）
(setq whistle-auto-sync t)

;; 自动保存到本地文件（默认: t）
(setq whistle-auto-save t)

;; 同步前自动备份（默认: t）
(setq whistle-auto-backup t)

;; 备份目录（默认: ~/.whistle/backups/）
(setq whistle-backup-directory "~/.whistle/backups/")

;; === 冲突处理 ===

;; 冲突解决策略（默认: 'prompt）
;; 'prompt - 询问用户
;; 'server-wins - 服务器版本优先
;; 'local-wins - 本地版本优先
(setq whistle-conflict-strategy 'prompt)

;; === 命名配置 ===

;; 默认规则名称（默认: "Default"）
(setq whistle-default-rule-name "Default")

;; Emacs 管理规则的前缀（默认: "emacs"）
;; 服务器上会创建 \remacs 组
(setq whistle-rule-prefix "emacs")

;; === Tree-sitter 配置 ===

;; 缩进空格数（默认: 2）
(setq whistle-ts-mode-indent-offset 2)
```

## 🔧 高级功能

### 查看同步状态

```elisp
M-x whistle-list-managed-rules  ; 显示所有 Emacs 管理的规则及其同步状态
```

显示信息包括：
- ✓ synced - 已同步
- 📝 not synced - 本地有修改未同步
- ⚠️ no local file - 服务器上有但本地缺失
- ❓ no metadata - 没有元数据记录

### 清理孤立的值

```elisp
M-x whistle-cleanup-orphaned-values  ; 查找并删除属于已删除规则的值
```

当你删除规则后，相关的值可能还保留在服务器上。此命令可以清理这些孤立的值。

### 批量删除 Emacs 管理的规则

```elisp
M-x whistle-delete-all-managed-rules  ; 删除所有 Emacs 创建的规则和值
```

谨慎使用！这会删除所有带 `emacs` 前缀的规则和值。

## 📖 与 Whistle Web UI 的关系

Whistle.el 可以与 Whistle Web UI 共存：

- **Emacs 管理的规则**：在 `\remacs` 组中，通过 Emacs 编辑
- **Web UI 创建的规则**：在其他位置，通过 Web UI 编辑
- **互不干扰**：两种方式创建的规则名称空间分离

你可以：
1. 在 Emacs 中用 `M-x whistle-open-web-ui` 打开 Web UI
2. 在 Web UI 中查看所有规则（包括 Emacs 创建的）
3. 在 Emacs 中管理代码相关的规则
4. 在 Web UI 中管理临时调试规则

## 🎯 最佳实践

1. **本地文件优先**：始终保持本地 `.whistle` 文件作为主要编辑源
2. **版本控制**：将 `~/.whistle/rules/` 加入 Git，团队共享规则配置
3. **命名规范**：使用有意义的规则名称，如 `dev-api-mock`, `staging-proxy`
4. **值块复用**：常用的响应数据做成值块，多个规则可以引用
5. **注释充分**：在规则文件中添加注释说明用途和生效条件
6. **定期清理**：使用 `whistle-cleanup-orphaned-values` 清理不用的值

## 📦 支持的 Whistle 协议

完整支持 40+ 个 Whistle 协议，包括：

**代理和转发：**
- `proxy`, `http`, `https`, `socks`, `pac`, `tunnel`

**域名和路径：**
- `host`, `redirect`, `method`, `referer`

**请求/响应修改：**
- `reqHeaders`, `resHeaders`, `reqBody`, `resBody`
- `reqPrepend`, `resPrepend`, `reqAppend`, `resAppend`
- `reqReplace`, `resReplace`, `headerReplace`

**性能和延迟：**
- `reqDelay`, `resDelay`, `reqSpeed`, `resSpeed`

**CORS 和缓存：**
- `reqCors`, `resCors`, `cache`, `attachment`

**脚本和插件：**
- `reqScript`, `resScript`, `weinre`, `plugin`

**其他：**
- `statusCode`, `file`, `log`, `mark`, `exports`
- `enable`, `disable`, `filter`, `ignore`, `pipe`

输入协议名按 `TAB` 自动补全，大小写不敏感。

## 🔌 Whistle API 端点参考

### Rules API
- `GET /cgi-bin/rules/list` - 获取规则列表
- `POST /cgi-bin/rules/add` - 创建规则 (参数: `name`, `value`, 可选 `groupName`)
- `POST /cgi-bin/rules/update` - 更新规则 (参数: `name`, `rules`)
- `POST /cgi-bin/rules/remove` - 删除规则 (参数: `name`)
- `POST /cgi-bin/rules/rename` - 重命名规则 (参数: `name`, `newName`)
- `POST /cgi-bin/rules/select` - 激活规则 (参数: `name`)
- `POST /cgi-bin/rules/unselect` - 停用规则 (参数: `name`)

### Values API
- `GET /cgi-bin/values/list` - 获取值列表
- `POST /cgi-bin/values/add` - 创建值 (参数: `name`, `value`, 可选 `groupName`)
- `POST /cgi-bin/values/update` - 更新值 (参数: `name`, `value`)
- `POST /cgi-bin/values/remove` - 删除值 (参数: `name`)
- `POST /cgi-bin/values/rename` - 重命名值 (参数: `name`, `newName`)

**注意**：`groupName` 参数用于 V3 实现的组织功能，Emacs 管理的规则使用 `\remacs` 组。

## 🐛 故障排除

### Tree-sitter 语法高亮不工作

1. 检查 Emacs 版本：`M-x emacs-version`（需要 29.1+）
2. 检查 grammar 是否安装：
   ```elisp
   (treesit-ready-p 'whistle t)  ; 应返回 t
   (treesit-ready-p 'json t)     ; 应返回 t
   ```
3. 检查 grammar 文件位置：
   ```bash
   ls ~/.emacs.d/.local/cache/tree-sitter/
   # 应该有 whistle.so 和 json.so（或 .dylib / .dll）
   ```

### 同步到服务器失败

1. 检查服务器是否运行：
   ```bash
   curl http://127.0.0.1:8899/cgi-bin/rules/list
   ```
2. 检查 `whistle-base-url` 配置
3. 查看 `*Messages*` 缓冲区的错误信息

### 值引用找不到

确保：
- 值块名称使用 `[a-zA-Z0-9._-]+` 字符
- 规则中使用 `{value-name}` 格式引用
- 保存并同步后再激活规则

## 🔮 未来计划

- [ ] 规则语法实时验证
- [ ] 冲突自动解决
- [ ] 历史版本管理（基于 Git）
- [ ] 规则匹配预览
- [ ] Company-mode 集成
- [ ] LSP 支持

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 License

MIT
