# Whistle V2 - 统一编辑器

全新设计的 Whistle 编辑器，将 Rules 和 Values 统一在一个 buffer 中管理。

## ✨ 核心特性

### 🎯 统一的文件格式
- **上半部分**：标准 Whistle 规则
- **下半部分**：Markdown 风格的 Value 定义块
- **一键同步**：自动同步到 Whistle 服务器
- **智能补全**：在规则中引用 value 时自动补全

### 📝 文件格式示例

```whistle
# ===== Rules Section =====
# 这里写标准的 whistle 规则

# 代理所有 example.com 的请求
*.example.com proxy://127.0.0.1:8080

# 使用 value mock API 响应
/api/user resBody://{user-data}
/api/posts resBody://{posts-list}

# Host 映射
test.local host://192.168.1.100

# ===== Values Section =====
# 使用 markdown 代码块定义 values

```user-data
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com"
}
```

```posts-list
{
  "posts": [
    {"id": 1, "title": "First Post"},
    {"id": 2, "title": "Second Post"}
  ]
}
```

```html-template
<html>
  <head><title>Test</title></head>
  <body>
    <h1>Hello World</h1>
  </body>
</html>
```
```

## 🚀 快速开始

### 安装

```elisp
;; 在你的 Emacs 配置中添加
(add-to-list 'load-path "~/.doom.d/extensions/whistle")
(require 'whistle-v2)

;; 可选配置
(setq whistle-base-url "http://127.0.0.1:8899")
(setq whistle-default-rule-name "Default")
(setq whistle-auto-sync t)
```

### 基本使用

```elisp
;; 编辑默认规则
M-x whistle-edit-rule

;; 编辑指定规则
M-x whistle-edit-rule RET my-rule

;; 或者直接
(whistle-edit-rule "my-project-rules")
```

## ⌨️ 快捷键

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `C-c C-c` | 同步到服务器 | 保存当前 buffer 到 Whistle |
| `C-c C-l` | 从服务器加载 | 加载服务器上的规则和值 |
| `C-c C-n` | 设置规则名称 | 修改当前 buffer 关联的规则名 |
| `C-c C-a` | 激活规则 | 在 Whistle 中激活当前规则 |
| `C-c C-v` | 插入 value 块 | 快速插入 value 定义模板 |
| `C-c C-t` | 插入规则模板 | 选择并插入常用规则模板 |
| `TAB` | 自动补全 | 补全协议或 value 名称 |

## 📖 详细功能

### 1. 编辑工作流

```
打开/创建规则
    ↓
M-x whistle-edit-rule
    ↓
编辑规则和 values
    ↓
C-c C-c 同步到服务器
    ↓
C-c C-a 激活规则
```

### 2. Value 块语法

Value 块使用 markdown 代码块语法：

```
```value-name
内容
```
```

**命名规则**：
- 支持字母、数字、点(.)、下划线(_)、连字符(-)
- 推荐使用语义化命名：`api-user-response`、`mock.data.json`

**示例**：

```whistle
```api.user.list
{
  "users": [
    {"id": 1, "name": "Alice"},
    {"id": 2, "name": "Bob"}
  ]
}
```

```error-response
{
  "error": "Not found",
  "code": 404
}
```

```custom-headers
content-type: application/json
x-custom-header: test-value
cache-control: no-cache
```
```

### 3. 在规则中引用 Values

使用 `{value-name}` 语法引用：

```whistle
# Mock API 响应
/api/users resBody://{api.user.list}
/api/error resBody://{error-response}

# 添加自定义 headers
*.example.com resHeaders://{custom-headers}
```

**智能补全**：
- 输入 `{` 后按 `TAB` 会自动列出所有可用的 value 名称
- 补全时会显示 `<value>` 标记

### 4. 规则模板

按 `C-c C-t` 可快速插入以下模板：

1. **Proxy** - 代理请求
   ```
   pattern proxy://host:port
   ```

2. **Host mapping** - 域名映射
   ```
   pattern host://ip
   ```

3. **Mock with value** - 使用 value mock
   ```
   pattern resBody://{value-name}
   ```

4. **Mock with file** - 使用文件 mock
   ```
   pattern file://{path/to/file}
   ```

5. **CORS** - 启用跨域
   ```
   pattern resCors://
   ```

6. **Delay** - 添加延迟
   ```
   pattern resDelay://1000
   ```

7. **Header** - 添加响应头
   ```
   pattern resHeaders://{header-value}
   ```

8. **Redirect** - 重定向
   ```
   pattern redirect://new-url
   ```

### 5. 语法高亮

自动高亮：
- 🟦 **Value 块名称** - 代码块的名称部分
- 🟩 **Whistle 协议** - host, proxy, resBody 等
- 🟨 **Value 引用** - `{value-name}` 中的名称
- 🟧 **URL 和域名**
- 🟥 **IP 地址和端口**
- ⬜ **注释** - `#` 开头的行

### 6. 同步机制

#### 保存到服务器 (`C-c C-c`)

1. 解析 buffer，分离 rules 和 values
2. 更新规则到服务器：`POST /cgi-bin/rules/update`
3. 逐个更新 values：`POST /cgi-bin/values/update`
4. 显示同步进度

#### 从服务器加载 (`C-c C-l`)

1. 获取指定规则：`GET /cgi-bin/rules/list`
2. 获取所有 values：`GET /cgi-bin/values/list`
3. 合并为统一格式显示

## 💡 使用场景

### 场景 1: 开发环境配置

```whistle
# Development proxy
*.dev.company.com proxy://localhost:3000
*.api.company.com proxy://dev-api.company.com

# Mock login response
/api/login resBody://{login-success}

```login-success
{
  "token": "dev-token-12345",
  "user": {
    "id": 1,
    "name": "Dev User",
    "role": "admin"
  }
}
```
```

### 场景 2: API 测试

```whistle
# Test different API responses
/api/users?success=true resBody://{users-success}
/api/users?error=true resBody://{users-error}

```users-success
{"data": [{"id": 1, "name": "Test User"}]}
```

```users-error
{"error": "Internal Server Error", "code": 500}
```
```

### 场景 3: 前端开发

```whistle
# Replace remote JS with local
cdn.example.com/app.js file:///Users/me/dev/app.js

# Mock API data
/api/* resHeaders://{cors-headers}

```cors-headers
access-control-allow-origin: *
access-control-allow-methods: GET, POST, PUT, DELETE
access-control-allow-headers: Content-Type
```
```

## 🎨 高级技巧

### 1. 多环境管理

为不同环境创建不同的规则：

```elisp
;; 开发环境
(whistle-edit-rule "dev-env")

;; 测试环境
(whistle-edit-rule "test-env")

;; 生产调试
(whistle-edit-rule "prod-debug")
```

### 2. Value 复用

同一个 value 可以在多个规则中引用：

```whistle
/api/v1/user resBody://{user-data}
/api/v2/user resBody://{user-data}
/mock/user resBody://{user-data}

```user-data
{"id": 1, "name": "Shared User Data"}
```
```

### 3. 注释组织

使用注释分组管理：

```whistle
# ========================================
# Proxy Configuration
# ========================================
*.dev.local proxy://localhost:8080

# ========================================
# API Mocking
# ========================================
/api/* resBody://{api-mock}

# ========================================
# Static Resources
# ========================================
cdn.example.com file:///path/to/local

# ========================================
# Values
# ========================================

```api-mock
{"status": "ok"}
```
```

### 4. 快速切换规则

```elisp
;; 绑定快捷键快速切换
(global-set-key (kbd "C-c w d") (lambda () (interactive) (whistle-edit-rule "dev")))
(global-set-key (kbd "C-c w t") (lambda () (interactive) (whistle-edit-rule "test")))
(global-set-key (kbd "C-c w p") (lambda () (interactive) (whistle-edit-rule "prod")))
```

## 🔧 配置选项

```elisp
;; Whistle 服务器地址
(setq whistle-base-url "http://127.0.0.1:8899")

;; 默认规则名称
(setq whistle-default-rule-name "Default")

;; 保存时自动同步（暂未实现）
(setq whistle-auto-sync t)
```

## 🆚 对比 V1 版本

| 特性 | V1 (分离式) | V2 (统一式) |
|------|------------|------------|
| 界面 | 分开的列表和编辑 buffer | 单一编辑 buffer |
| Rules 管理 | ✅ 列表操作 | ✅ 文本编辑 |
| Values 管理 | ✅ 列表操作 | ✅ Markdown 块 |
| 关联性 | ❌ 需手动关联 | ✅ 在同一文件中 |
| Value 补全 | ❌ 不支持 | ✅ 自动补全 |
| 可读性 | ⚠️ 需切换 buffer | ✅ 一目了然 |
| 适合场景 | 浏览和管理 | 编辑和开发 |

## 🐛 故障排查

### 同步失败

```elisp
;; 检查连接
(whistle--http-get "/cgi-bin/get-data"
  (lambda (data) (message "Connected: %S" data))
  (lambda (err) (message "Error: %s" err)))
```

### 查看当前规则名

```elisp
M-: whistle--current-rule-name
```

### 手动解析测试

```elisp
M-: (whistle--parse-buffer)
```

## 📚 API 参考

### 主要函数

- `whistle-edit-rule` - 打开/创建规则编辑器
- `whistle-sync-to-server` - 同步到服务器
- `whistle-load-from-server` - 从服务器加载
- `whistle-set-rule-name` - 设置规则名称
- `whistle-activate-rule` - 激活规则
- `whistle-insert-value-block` - 插入 value 块
- `whistle-insert-template` - 插入规则模板

### 内部函数

- `whistle--parse-buffer` - 解析 buffer 为规则和 values
- `whistle--format-buffer` - 格式化为统一格式
- `whistle--get-value-names` - 获取所有 value 名称
- `whistle-completion-at-point` - 补全函数

## 🎯 最佳实践

1. **语义化命名**：使用清晰的 value 名称
   - ✅ `api.user.list`, `mock-error-response`
   - ❌ `value1`, `test`, `aaa`

2. **注释分组**：用注释将相关规则分组

3. **一个规则一个用途**：不要在一个规则中混合多种场景

4. **及时同步**：编辑后使用 `C-c C-c` 及时同步

5. **版本控制**：可以将 buffer 内容保存为 `.whistle` 文件进行版本管理

## 📄 License

MIT

---

**Enjoy coding with Whistle V2!** 🚀
