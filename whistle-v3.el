;;; whistle-v3.el --- Advanced Whistle editor with polymode -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Your Name
;; Version: 3.0.0
;; Package-Requires: ((emacs "26.1") (polymode "0.2.2") (json-mode "1.8.0"))
;; Keywords: tools, whistle, proxy, debugging

;;; Commentary:

;; Advanced Whistle editor with polymode support for JSON code blocks.
;; This file provides:
;;   - Polymode configuration for JSON code blocks
;;   - whistle-mode (polymode-based major mode)
;;
;; For the tree-sitter based version without polymode, use whistle-ts-mode.

;;; Code:

(require 'whistle-core)
(require 'polymode)
(require 'json-mode)

;;; Polymode Configuration for Code Blocks

;; Define the host mode
(define-hostmode poly-whistle-hostmode
  :mode 'whistle-mode)

;; Define the inner mode for JSON code blocks
(define-innermode poly-whistle-json-innermode
  :mode 'json-mode
  :head-matcher "^```[a-zA-Z0-9._-]*$"
  :tail-matcher "^```\\s-*$"
  :head-mode 'host
  :tail-mode 'host)

;; Define the polymode
(define-polymode poly-whistle-mode
  :hostmode 'poly-whistle-hostmode
  :innermodes '(poly-whistle-json-innermode))

;; Ensure whistle keybindings work in JSON innermode
(defun poly-whistle-json-mode-setup ()
  "Setup keybindings for JSON innermode to preserve whistle commands."
  (when (and (boundp 'polymode-mode) polymode-mode)
    ;; Add whistle keybindings to json-mode-map when in polymode
    (local-set-key (kbd "C-c C-s") #'whistle-sync-to-server)
    (local-set-key (kbd "C-c C-l") #'whistle-load-from-server)
    (local-set-key (kbd "C-x C-s") #'whistle-save)))

(add-hook 'json-mode-hook #'poly-whistle-json-mode-setup)

;;; Major Mode

(defvar whistle-mode-map
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
  "Keymap for `whistle-mode'.")

(define-derived-mode whistle-mode prog-mode "Whistle"
  "Major mode for editing whistle rules and values in unified format.
Uses polymode for multi-mode support in code blocks.

\\{whistle-mode-map}"
  (setq-local comment-start "#")
  (setq-local comment-start-skip "#+\\s-*")
  (setq-local font-lock-defaults '(whistle-font-lock-keywords t))

  (whistle-setup-completion)

  ;; Auto-detect rule name from file name if visiting a .whistle file
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

  ;; Enable polymode for code blocks
  (poly-whistle-mode))

;; Evil mode support for edit mode
(with-eval-after-load 'evil
  (evil-define-key 'normal whistle-mode-map
    (kbd ", ,") #'whistle-save
    (kbd ", s") #'whistle-sync-to-server
    (kbd ", l") #'whistle-load-from-server
    (kbd ", n") #'whistle-set-rule-name
    (kbd ", a") #'whistle-activate-rule
    (kbd ", v") #'whistle-insert-value-block
    (kbd ", t") #'whistle-insert-template)
  (evil-define-key 'insert whistle-mode-map
    (kbd "C-c C-c") #'whistle-save
    (kbd "C-c C-s") #'whistle-sync-to-server
    (kbd "C-c C-l") #'whistle-load-from-server
    (kbd "C-c C-n") #'whistle-set-rule-name
    (kbd "C-c C-a") #'whistle-activate-rule
    (kbd "C-c C-v") #'whistle-insert-value-block
    (kbd "C-c C-t") #'whistle-insert-template))

;;;###autoload
;; (add-to-list 'auto-mode-alist '("\\.whistle\\'" . whistle-mode))
;; 注释掉以避免与 whistle-ts-mode 冲突
;; 如果想使用 polymode 版本，取消注释上面这行

(provide 'whistle-v3)

;;; whistle-v3.el ends here
