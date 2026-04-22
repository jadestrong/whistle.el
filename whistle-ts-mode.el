;;; whistle-ts-mode.el --- Tree-sitter based Whistle mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Your Name
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, whistle, proxy, debugging

;;; Commentary:

;; Tree-sitter based major mode for editing Whistle rules with embedded JSON.
;; Uses whistle tree-sitter for rules and JSON tree-sitter for code blocks.

;;; Code:

(require 'treesit)
(require 'whistle-core)  ; 复用核心功能（不依赖 polymode）

(defcustom whistle-ts-mode-indent-offset 2
  "Number of spaces for each indentation step in `whistle-ts-mode'."
  :type 'integer
  :group 'whistle)

;;; Whistle Font-lock 设置

(defvar whistle-ts-mode--whistle-font-lock-settings
  (when (treesit-ready-p 'whistle t)
    (treesit-font-lock-rules
     :language 'whistle
     :feature 'comment
     '((comment) @font-lock-comment-face)

     :language 'whistle
     :feature 'negation
     '((negation) @font-lock-negation-char-face)

     :language 'whistle
     :feature 'pattern
     '((regexp_pattern) @font-lock-regexp-face
       (regexp_pattern_no_flag) @font-lock-regexp-face
       (dollar_regexp) @font-lock-regexp-face
       (url_pattern) @font-lock-string-face
       (wildcard_pattern) @font-lock-property-name-face
       (port_pattern) @font-lock-number-face
       (ipv4_pattern) @font-lock-constant-face
       (ipv6_pattern) @font-lock-constant-face
       (ipv6_with_brackets) @font-lock-constant-face
       (local_path_windows) @font-lock-string-face
       (local_path_unix) @font-lock-property-name-face
       (macro_pattern) @font-lock-variable-use-face
       (at_reference) @font-lock-variable-use-face
       (plugin_var) @font-lock-variable-use-face
       (domain_pattern) @font-lock-string-face)

     :language 'whistle
     :feature 'operator
     '((protocol_name) @font-lock-keyword-face
       (plugin_full_name) @font-lock-function-call-face)

     :language 'whistle
     :feature 'value
     '((value_text_start) @font-lock-string-face
       (value_text) @font-lock-string-face
       (simple_value) @font-lock-string-face)

     :language 'whistle
     :feature 'reference
     :override t
     '((brace_open) @font-lock-bracket-face
       (brace_close) @font-lock-bracket-face
       (reference_name) @font-lock-variable-use-face)

     :language 'whistle
     :feature 'error
     :override t
     '((ERROR) @font-lock-warning-face)))
  "Tree-sitter font-lock settings for Whistle rules.")

;;; JSON 缩进规则（参考 json-ts-mode）

(defvar whistle-ts-mode--indent-rules
  `((json
     ;; 闭合括号回到父级缩进
     ((node-is "}") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ;; object/array 内部元素缩进
     ((parent-is "object") parent-bol ,whistle-ts-mode-indent-offset)
     ((parent-is "array") parent-bol ,whistle-ts-mode-indent-offset))
    (whistle
     ;; whistle 规则不需要缩进
     (no-node parent-bol 0)))
  "Tree-sitter indentation rules for `whistle-ts-mode'.")

;;; JSON Font-lock 设置

(defvar whistle-ts-mode--json-font-lock-settings
  (when (treesit-ready-p 'json t)
    (treesit-font-lock-rules
     :language 'json
     :feature 'bracket
     '((["[" "]" "{" "}"]) @font-lock-bracket-face)

     :language 'json
     :feature 'delimiter
     '((["," ":"]) @font-lock-delimiter-face)

     :language 'json
     :feature 'string
     '((string) @font-lock-string-face)

     :language 'json
     :feature 'number
     '((number) @font-lock-number-face)

     :language 'json
     :feature 'constant
     '((true) @font-lock-constant-face
       (false) @font-lock-constant-face
       (null) @font-lock-constant-face)

     :language 'json
     :feature 'escape-sequence
     :override t
     '((escape_sequence) @font-lock-escape-face)

     :language 'json
     :feature 'pair
     :override t
     '((pair key: (string) @font-lock-property-name-face))

     :language 'json
     :feature 'error
     :override t
     '((ERROR) @font-lock-warning-face)))
  "Tree-sitter font-lock settings for JSON in whistle-ts-mode.")

;;; Range 规则：定义 JSON 代码块区域

(defun whistle-ts-mode--json-ranges ()
  "Return ranges for JSON code blocks in the buffer."
  (let ((ranges '()))
    (save-excursion
      (goto-char (point-min))
      ;; 查找所有 ```name ... ``` 代码块
      (while (re-search-forward "^```[a-zA-Z0-9._-]*$" nil t)
        (let ((block-start (match-end 0)))
          (forward-line 1)
          (let ((content-start (point)))
            (when (re-search-forward "^```\\s-*$" nil t)
              (let ((content-end (match-beginning 0)))
                ;; 添加这个范围
                (when (< content-start content-end)
                  (push (cons content-start content-end) ranges))))))))
    (nreverse ranges)))

(defun whistle-ts-mode--whistle-ranges ()
  "Return ranges for Whistle rules (everything outside JSON code blocks)."
  (let ((json-ranges (whistle-ts-mode--json-ranges))
        (whistle-ranges '())
        (pos 1))
    (dolist (json-range json-ranges)
      ;; 添加 JSON 块之前的区域（包括 ``` 标记行）
      (when (< pos (car json-range))
        (push (cons pos (car json-range)) whistle-ranges))
      (setq pos (cdr json-range)))
    ;; 添加最后一个 JSON 块之后的区域
    (when (< pos (point-max))
      (push (cons pos (point-max)) whistle-ranges))
    (nreverse whistle-ranges)))

(defun whistle-ts-mode--language-at-point (point)
  "Return the language at POINT."
  (let ((json-ranges (whistle-ts-mode--json-ranges)))
    (if (cl-some (lambda (range)
                   (and (>= point (car range))
                        (<= point (cdr range))))
                 json-ranges)
        'json
      'whistle)))

;;;###autoload
(define-derived-mode whistle-ts-mode prog-mode "Whistle[TS]"
  "Major mode for editing Whistle rules with tree-sitter support.
Uses whistle tree-sitter for rules and JSON tree-sitter for code blocks.

\\{whistle-ts-mode-map}"
  :group 'whistle

  ;; 基本设置
  (setq-local comment-start "#")
  (setq-local comment-start-skip "#+\\s-*")

  ;; 检查并创建 parsers
  (let ((has-whistle (treesit-ready-p 'whistle t))
        (has-json (treesit-ready-p 'json t))
        (font-lock-settings nil)
        (feature-list nil))

    ;; 创建 whistle parser (主 parser)
    (when has-whistle
      (let ((whistle-parser (treesit-parser-create 'whistle)))
        ;; whistle parser 解析整个文件（包括代码块标记）
        ;; 但我们只对非 JSON 部分应用高亮
        (treesit-parser-set-included-ranges
         whistle-parser
         (whistle-ts-mode--whistle-ranges)))
      (setq font-lock-settings
            (append font-lock-settings whistle-ts-mode--whistle-font-lock-settings))
      (setq feature-list
            (append feature-list '((comment negation) (pattern operator value) (reference error)))))

    ;; 创建 JSON parser
    (when has-json
      (let ((json-parser (treesit-parser-create 'json)))
        ;; 设置 JSON parser 只在代码块范围内工作
        (treesit-parser-set-included-ranges
         json-parser
         (whistle-ts-mode--json-ranges)))
      (setq font-lock-settings
            (append font-lock-settings whistle-ts-mode--json-font-lock-settings))
      ;; JSON features 合并到 feature list
      (setq feature-list
            (if feature-list
                (cl-mapcar (lambda (a b) (append a b))
                           feature-list
                           '((string number constant) (bracket delimiter pair) (escape-sequence) (error)))
              '((string number constant) (bracket delimiter pair) (escape-sequence) (error)))))

    ;; 设置缩进
    (setq-local treesit-simple-indent-rules whistle-ts-mode--indent-rules)

    ;; 设置 font-lock
    (when font-lock-settings
      (setq-local treesit-font-lock-settings font-lock-settings))
    (when feature-list
      (setq-local treesit-font-lock-feature-list feature-list))

    ;; 设置语言检测函数
    (setq-local treesit-language-at-point-function
                #'whistle-ts-mode--language-at-point)

    ;; 启用 tree-sitter (如果有任何一个 grammar 可用)
    (when (or has-whistle has-json)
      (treesit-major-mode-setup))

    ;; 如果没有 tree-sitter 支持，回退到传统 font-lock
    (unless (or has-whistle has-json)
      (setq-local font-lock-defaults '(whistle-font-lock-keywords t))))

  ;; 复用 whistle-core 的功能
  (whistle-setup-completion)

  ;; Auto-detect rule name from file name
  (when (and buffer-file-name
             (string-match "/\\([^/]+\\)\\.whistle\\'" buffer-file-name))
    (let ((rule-name (match-string 1 buffer-file-name)))
      (setq-local whistle--current-rule-name rule-name)
      (setq-local whistle--file-path buffer-file-name)
      (message "Editing rule: %s (will sync to group %s)" rule-name whistle-rule-prefix)))

  ;; Fallback to default rule name
  (unless whistle--current-rule-name
    (when (boundp 'whistle-default-rule-name)
      (setq-local whistle--current-rule-name whistle-default-rule-name)))

  ;; 添加 buffer 变化的 hook 来更新 parser ranges
  (add-hook 'after-change-functions #'whistle-ts-mode--update-ranges nil t))

(defun whistle-ts-mode--update-ranges (&rest _)
  "Update parser ranges after buffer changes."
  (when (treesit-parser-list)
    (dolist (parser (treesit-parser-list))
      (let ((lang (treesit-parser-language parser)))
        (cond
         ((eq lang 'json)
          (treesit-parser-set-included-ranges
           parser
           (whistle-ts-mode--json-ranges)))
         ((eq lang 'whistle)
          (treesit-parser-set-included-ranges
           parser
           (whistle-ts-mode--whistle-ranges))))))))

;;; Electric value block

(defun whistle-ts-mode-electric-backtick ()
  "Insert backtick, and expand to value block when typing ``` at line beginning."
  (interactive)
  (insert "`")
  ;; 检查是否在行首输入了 ```
  (when (looking-back "^```" (line-beginning-position))
    (let ((name (read-string "Value name: " nil nil "value")))
      (insert name "\n\n```")
      (forward-line -1)
      (end-of-line))))

;; Keymap (与 whistle-mode 保持一致)
(defvar whistle-ts-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "`") #'whistle-ts-mode-electric-backtick)
    (define-key map (kbd "C-c C-c") #'whistle-save)
    (define-key map (kbd "C-c C-s") #'whistle-sync-to-server)
    (define-key map (kbd "C-c C-l") #'whistle-load-from-server)
    (define-key map (kbd "C-c C-n") #'whistle-set-rule-name)
    (define-key map (kbd "C-c C-a") #'whistle-activate-rule)
    (define-key map (kbd "C-c C-v") #'whistle-insert-value-block)
    (define-key map (kbd "C-c C-t") #'whistle-insert-template)
    (define-key map (kbd "C-c C-r") #'whistle-refresh-server-values-cache)
    (define-key map (kbd "C-x C-s") #'whistle-save)
    map)
  "Keymap for `whistle-ts-mode'.")

;; Evil mode support
(with-eval-after-load 'evil
  (evil-define-key 'normal whistle-ts-mode-map
    (kbd ", ,") #'whistle-save
    (kbd ", s") #'whistle-sync-to-server
    (kbd ", l") #'whistle-load-from-server
    (kbd ", n") #'whistle-set-rule-name
    (kbd ", a") #'whistle-activate-rule
    (kbd ", v") #'whistle-insert-value-block
    (kbd ", t") #'whistle-insert-template
    (kbd ", r") #'whistle-refresh-server-values-cache)
  (evil-define-key 'insert whistle-ts-mode-map
    (kbd "`") #'whistle-ts-mode-electric-backtick
    (kbd "C-c C-c") #'whistle-save
    (kbd "C-c C-s") #'whistle-sync-to-server
    (kbd "C-c C-l") #'whistle-load-from-server
    (kbd "C-c C-n") #'whistle-set-rule-name
    (kbd "C-c C-a") #'whistle-activate-rule
    (kbd "C-c C-v") #'whistle-insert-value-block
    (kbd "C-c C-t") #'whistle-insert-template
    (kbd "C-c C-r") #'whistle-refresh-server-values-cache))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.whistle\\'" . whistle-ts-mode))

(provide 'whistle-ts-mode)
;;; whistle-ts-mode.el ends here
