;;; whistle-ts-mode.el --- Tree-sitter based Whistle mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Your Name
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, whistle, proxy, debugging

;;; Commentary:

;; Tree-sitter based major mode for editing Whistle rules with embedded JSON.
;; Uses text mode as host and JSON tree-sitter for code blocks.

;;; Code:

(require 'treesit)
(require 'whistle-core)  ; 复用核心功能（不依赖 polymode）

(defcustom whistle-ts-mode-indent-offset 2
  "Number of spaces for each indentation step in `whistle-ts-mode'."
  :type 'integer
  :group 'whistle)

;; JSON 缩进规则（参考 json-ts-mode）
(defvar whistle-ts-mode--indent-rules
  `((json
     ;; 闭合括号回到父级缩进
     ((node-is "}") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ;; object/array 内部元素缩进
     ((parent-is "object") parent-bol ,whistle-ts-mode-indent-offset)
     ((parent-is "array") parent-bol ,whistle-ts-mode-indent-offset)))
  "Tree-sitter indentation rules for `whistle-ts-mode'.")

;; Font-lock 设置（使用 json-ts-mode 的高亮）
(defvar whistle-ts-mode--font-lock-settings
  (when (treesit-ready-p 'json)
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
     :override t ;; Needed for overriding string face on keys.
     '((pair key: (string) @font-lock-property-name-face))

     :language 'json
     :feature 'error
     :override t
     '((ERROR) @font-lock-warning-face)))
  "Tree-sitter font-lock settings for JSON in whistle-ts-mode.")

;; Range 规则：定义 JSON 代码块区域
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

(defun whistle-ts-mode--language-at-point (point)
  "Return the language at POINT."
  (let ((ranges (whistle-ts-mode--json-ranges)))
    (if (cl-some (lambda (range)
                   (and (>= point (car range))
                        (<= point (cdr range))))
                 ranges)
        'json
      nil)))

;;;###autoload
(define-derived-mode whistle-ts-mode prog-mode "Whistle[TS]"
  "Major mode for editing Whistle rules with tree-sitter support.
Uses JSON tree-sitter grammar for code blocks.

\\{whistle-ts-mode-map}"
  :group 'whistle

  ;; 检查 JSON grammar 是否可用
  (unless (treesit-ready-p 'json)
    (error "Tree-sitter grammar for JSON isn't available. Please install it with: M-x treesit-install-language-grammar RET json RET"))

  ;; 基本设置
  (setq-local comment-start "#")
  (setq-local comment-start-skip "#+\\s-*")

  ;; 创建 JSON parser
  (when (treesit-ready-p 'json)
    (let ((parser (treesit-parser-create 'json)))
      ;; 设置 JSON parser 只在代码块范围内工作
      (treesit-parser-set-included-ranges
       parser
       (whistle-ts-mode--json-ranges)))

    ;; 设置缩进
    (setq-local treesit-simple-indent-rules whistle-ts-mode--indent-rules)

    ;; 设置 font-lock
    (setq-local treesit-font-lock-settings whistle-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((string number constant)
                  (bracket delimiter pair)))

    ;; 设置语言检测函数
    (setq-local treesit-language-at-point-function
                #'whistle-ts-mode--language-at-point)

    ;; 启用 tree-sitter
    (treesit-major-mode-setup))

  ;; 复用 whistle-v3 的功能
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

  ;; 添加 buffer 变化的 hook 来更新 JSON ranges
  (add-hook 'after-change-functions #'whistle-ts-mode--update-ranges nil t))

(defun whistle-ts-mode--update-ranges (&rest _)
  "Update JSON parser ranges after buffer changes."
  (when (and (treesit-ready-p 'json)
             (treesit-parser-list))
    (let ((parser (car (treesit-parser-list))))
      (when parser
        (treesit-parser-set-included-ranges
         parser
         (whistle-ts-mode--json-ranges))))))

;; Keymap (与 whistle-mode 保持一致)
(defvar whistle-ts-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'whistle-save)
    (define-key map (kbd "C-c C-s") #'whistle-sync-to-server)
    (define-key map (kbd "C-c C-l") #'whistle-load-from-server)
    (define-key map (kbd "C-c C-n") #'whistle-set-rule-name)
    (define-key map (kbd "C-c C-a") #'whistle-activate-rule)
    (define-key map (kbd "C-c C-v") #'whistle-insert-value-block)
    (define-key map (kbd "C-c C-t") #'whistle-insert-template)
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
    (kbd ", t") #'whistle-insert-template)
  (evil-define-key 'insert whistle-ts-mode-map
    (kbd "C-c C-c") #'whistle-save
    (kbd "C-c C-s") #'whistle-sync-to-server
    (kbd "C-c C-l") #'whistle-load-from-server
    (kbd "C-c C-n") #'whistle-set-rule-name
    (kbd "C-c C-a") #'whistle-activate-rule
    (kbd "C-c C-v") #'whistle-insert-value-block
    (kbd "C-c C-t") #'whistle-insert-template))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.whistle\\'" . whistle-ts-mode))

(provide 'whistle-ts-mode)
;;; whistle-ts-mode.el ends here
