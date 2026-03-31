# Whistle.el - Emacs Whistle Proxy Editor

一个全功能的 Emacs whistle 规则和值编辑器，为你提供最佳的 whistle 编辑体验。

## 功能特性

### 核心功能
- ✅ **Rules 管理** - 完整的 CRUD 操作（创建、查看、编辑、删除）
- ✅ **Values 管理** - 完整的 CRUD 操作
- ✅ **语法高亮** - Whistle 规则专用语法高亮
- ✅ **自动补全** - Whistle 协议自动补全
- ✅ **规则模板** - 快速插入常用规则模板
- ✅ **搜索过滤** - 快速定位规则/值
- ✅ **错误处理** - 完善的网络错误处理
- ✅ **导入导出** - 规则和值的备份功能
- ✅ **多实例支持** - 管理多个 whistle 实例

### 编辑体验
- 🎨 语法高亮（协议、URL、IP、端口、变量等）
- 📝 自动补全（支持所有 whistle 协议）
- 📋 规则模板（Proxy、Host mapping、CORS、Mock 等）
- 🔍 实时搜索和过滤
- ⌨️  完整的快捷键支持

## 安装

将 `whistle.el` 放入你的 load-path，然后在配置中添加：

```elisp
(require 'whistle)

;; 可选：配置 whistle 服务器地址
(setq whistle-base-url "http://127.0.0.1:8899")

;; 可选：配置多个 whistle 实例
(setq whistle-instances
      '((:name "本地开发" :url "http://127.0.0.1:8899")
        (:name "测试环境" :url "http://test-server:8899")))
```

## 使用方法

### 主入口

```elisp
M-x whistle  ; 显示菜单选择 Rules/Values/Web UI
```

或者直接打开：

```elisp
M-x whistle-rules   ; 打开 Rules 管理
M-x whistle-values  ; 打开 Values 管理
```

### Rules 管理快捷键

在 Rules 列表模式（`*Whistle Rules*`）：

| 快捷键 | 功能 |
|--------|------|
| `RET` | 打开选中的规则进行编辑 |
| `c` | 创建新规则 |
| `d` | 删除选中的规则 |
| `r` | 重命名规则 |
| `t` 或 `SPC` | 激活/停用规则 |
| `g` | 刷新列表 |
| `/` | 过滤规则 |
| `C-c C-c` | 清除过滤 |
| `E` | 导出规则到文件 |
| `I` | 从文件导入规则 |
| `w` | 在浏览器打开 Whistle Web UI |
| `s` | 切换 Whistle 实例 |
| `q` | 退出窗口 |

### 规则编辑模式快捷键

在规则编辑模式（`*Whistle Rule Content*`）：

| 快捷键 | 功能 |
|--------|------|
| `C-c C-c` | 保存规则 |
| `C-c C-a` | 激活当前规则 |
| `C-c C-k` | 取消编辑并关闭 |
| `C-c C-t` | 插入规则模板 |
| `TAB` | 自动补全协议 |

### Values 管理快捷键

在 Values 列表模式（`*Whistle Values*`）：

| 快捷键 | 功能 |
|--------|------|
| `RET` | 打开选中的值进行编辑 |
| `c` | 创建新值 |
| `d` | 删除选中的值 |
| `r` | 重命名值 |
| `g` | 刷新列表 |
| `/` | 过滤值 |
| `C-c C-c` | 清除过滤 |
| `E` | 导出值到文件 |
| `I` | 从文件导入值 |
| `w` | 在浏览器打开 Whistle Web UI |
| `s` | 切换 Whistle 实例 |
| `q` | 退出窗口 |

### 值编辑模式快捷键

在值编辑模式（`*Whistle Value Content*`）：

| 快捷键 | 功能 |
|--------|------|
| `C-c C-c` | 保存值 |
| `C-c C-k` | 取消编辑并关闭 |
| `C-c C-j` | 格式化 JSON（需要 Python）|

## 规则模板

按 `C-c C-t` 可快速插入以下模板：

1. **Proxy** - 代理请求
2. **Host mapping** - 域名映射到 IP
3. **Mock data** - 用本地文件模拟响应
4. **CORS** - 启用 CORS
5. **Delay** - 添加延迟
6. **Header** - 添加响应头
7. **Redirect** - 重定向
8. **Status code** - 修改状态码

## 语法高亮支持

支持高亮的元素：

- **注释** - `# 这是注释`
- **协议** - `host`, `proxy`, `file`, `statusCode` 等
- **URL** - `http://`, `https://`, `ws://`, `wss://`
- **IP 地址** - `192.168.1.1`
- **端口** - `:8080`
- **变量** - `$variable`
- **文件路径** - `{path/to/file}`
- **通配符** - `*`, `?`, `^`, `$`

## 自动补全

在编辑规则时，输入协议名按 `TAB` 可自动补全所有 whistle 协议：

- `host`, `proxy`, `file`, `statusCode`, `redirect`
- `reqHeaders`, `resHeaders`, `resCors`
- `reqDelay`, `resDelay`, `reqSpeed`, `resSpeed`
- 等等 40+ 个协议

## 配置选项

```elisp
;; Whistle 服务器地址
(setq whistle-base-url "http://127.0.0.1:8899")

;; 配置多个实例
(setq whistle-instances
      '((:name "Local" :url "http://127.0.0.1:8899")
        (:name "Remote" :url "http://remote-host:8899")))

;; 操作后自动刷新列表（默认: t）
(setq whistle-auto-refresh t)

;; 删除前确认（默认: t）
(setq whistle-confirm-delete t)
```

## 使用场景示例

### 场景 1：创建代理规则

1. `M-x whistle-rules` 打开规则列表
2. 按 `c` 创建新规则，输入名称 "dev-proxy"
3. 按 `RET` 打开编辑
4. 按 `C-c C-t` 选择 "Proxy" 模板
5. 修改为：`*.example.com proxy://127.0.0.1:8080`
6. 按 `C-c C-c` 保存
7. 按 `C-c C-a` 激活规则

### 场景 2：Mock API 响应

1. `M-x whistle-values` 打开值管理
2. 按 `c` 创建新值 "user-data"
3. 按 `RET` 打开编辑
4. 输入 JSON 数据
5. 按 `C-c C-j` 格式化 JSON
6. 按 `C-c C-c` 保存
7. 切换到 Rules，创建规则：`/api/user file://{user-data}`

### 场景 3：快速过滤规则

1. 在规则列表按 `/`
2. 输入关键词如 "api"
3. 只显示包含 "api" 的规则
4. 按 `C-c C-c` 清除过滤

## 相比其他编辑器的优势

- ✅ 完整的 Emacs 编辑能力（Evil、Org-mode 等集成）
- ✅ 语法高亮和自动补全
- ✅ 规则模板快速插入
- ✅ 键盘操作，无需鼠标
- ✅ 导入导出备份功能
- ✅ 多实例管理
- ✅ 可扩展和自定义

## 待办/规划功能

- [ ] 规则语法验证
- [ ] 历史版本管理
- [ ] 规则匹配预览
- [ ] 批量激活/停用
- [ ] 更丰富的代码片段
- [ ] 集成 company-mode

## Whistle API 端点参考

本插件使用的 Whistle v2.x API 端点：

### Rules API
- `GET /cgi-bin/rules/list` - 获取规则列表
- `POST /cgi-bin/rules/add` - 创建规则 (参数: name, value)
- `POST /cgi-bin/rules/update` - 更新规则 (参数: name, rules)
- `POST /cgi-bin/rules/remove` - 删除规则 (参数: name)
- `POST /cgi-bin/rules/rename` - 重命名规则 (参数: name, newName)
- `POST /cgi-bin/rules/select` - 激活规则 (参数: name)
- `POST /cgi-bin/rules/unselect` - 停用规则 (参数: name)

### Values API
- `GET /cgi-bin/values/list` - 获取值列表
- `POST /cgi-bin/values/add` - 创建值 (参数: name, value)
- `POST /cgi-bin/values/update` - 更新值 (参数: name, value)
- `POST /cgi-bin/values/remove` - 删除值 (参数: name)
- `POST /cgi-bin/values/rename` - 重命名值 (参数: name, newName)

## 版本兼容性

- ✅ Whistle v2.x (测试版本: v2.10.2)
- ⚠️ Whistle v1.x 可能需要调整 API 端点

如果遇到 API 错误，请检查你的 Whistle 版本。

## 问题反馈

如有问题或建议，请提交 Issue。

## License

MIT
