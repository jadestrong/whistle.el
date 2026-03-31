;;; whistle-v2.el --- Unified Whistle rules and values editor -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Your Name
;; Version: 3.0.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: tools, whistle, proxy, debugging

;;; Commentary:

;; Unified buffer for editing both whistle rules and values.
;; Format:
;;   - Rules at the top (standard whistle syntax)
;;   - Values as markdown code blocks: ```value-name\n...\n```
;;   - Auto-completion for value names in rules

;;; Code:

(require 'json)
(require 'url)
(require 'cl-lib)

;;; Customization

(defgroup whistle nil
  "Whistle proxy unified editor."
  :group 'tools
  :prefix "whistle-")

(defcustom whistle-base-url "http://127.0.0.1:8899"
  "Base URL for the Whistle proxy server."
  :type 'string
  :group 'whistle)

(defcustom whistle-auto-sync t
  "Whether to automatically sync with server on save."
  :type 'boolean
  :group 'whistle)

(defcustom whistle-default-rule-name "Default"
  "Default rule name to use."
  :type 'string
  :group 'whistle)

;;; Variables

(defvar-local whistle--current-rule-name nil
  "Name of the currently editing rule.")

(defvar-local whistle--parsed-values nil
  "Alist of parsed values from the buffer.")

(defvar-local whistle--rules-end-pos nil
  "Position where rules section ends and values begin.")

;;; HTTP Utilities

(defun whistle--get-base-url ()
  "Get the current whistle base URL."
  whistle-base-url)

(defun whistle--http-get (path callback &optional error-callback)
  "Send GET request to PATH and call CALLBACK with response data."
  (condition-case err
      (url-retrieve
       (concat (whistle--get-base-url) path)
       (lambda (status)
         (let ((error-status (plist-get status :error)))
           (if error-status
               (progn
                 (kill-buffer)
                 (if error-callback
                     (funcall error-callback (format "HTTP error: %s" error-status))
                   (message "Whistle request failed: %s" error-status)))
             (condition-case parse-err
                 (progn
                   (goto-char url-http-end-of-headers)
                   (let* ((json-object-type 'alist)
                          (json-array-type 'list)
                          (data (json-read)))
                     (kill-buffer)
                     (funcall callback data)))
               (error
                (kill-buffer)
                (if error-callback
                    (funcall error-callback (format "JSON parse error: %s" parse-err))
                  (message "Failed to parse response: %s" parse-err))))))))
    (error
     (if error-callback
         (funcall error-callback (format "Network error: %s" err))
       (message "Network error: %s" err)))))

(defun whistle--http-post (path data callback &optional error-callback)
  "Send POST request to PATH with DATA and call CALLBACK with response."
  (condition-case err
      (let ((url-request-method "POST")
            (url-request-data
             (mapconcat
              (lambda (kv)
                (concat (url-hexify-string (car kv))
                        "="
                        (url-hexify-string (cdr kv))))
              data "&")))
        (url-retrieve
         (concat (whistle--get-base-url) path)
         (lambda (status)
           (let ((error-status (plist-get status :error)))
             (if error-status
                 (progn
                   (kill-buffer)
                   (if error-callback
                       (funcall error-callback (format "HTTP error: %s" error-status))
                     (message "Whistle request failed: %s" error-status)))
               (condition-case parse-err
                   (progn
                     (goto-char url-http-end-of-headers)
                     (let* ((json-object-type 'alist)
                            (json-array-type 'list)
                            (data (json-read)))
                       (kill-buffer)
                       (funcall callback data)))
                 (error
                  (kill-buffer)
                  (if error-callback
                      (funcall error-callback (format "JSON parse error: %s" parse-err))
                    (message "Failed to parse response: %s" parse-err)))))))))
    (error
     (if error-callback
         (funcall error-callback (format "Network error: %s" err))
       (message "Network error: %s" err)))))

;;; Buffer Parsing

(defun whistle--parse-buffer ()
  "Parse the current buffer into rules and values sections.
Returns a plist with :rules and :values."
  (save-excursion
    (goto-char (point-min))
    (let ((rules-content "")
          (values-alist nil)
          (in-value-block nil)
          (current-value-name nil)
          (current-value-content nil))

      ;; Parse buffer line by line
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position)
                     (line-end-position))))

          ;; Check for value block start: ```value-name
          (if (string-match "^```\\([a-zA-Z0-9._-]+\\)$" line)
              (progn
                (setq in-value-block t)
                (setq current-value-name (match-string 1 line))
                (setq current-value-content ""))

            ;; Check for value block end: ```
            (if (and in-value-block (string-match "^```$" line))
                (progn
                  (setq in-value-block nil)
                  (push (cons current-value-name current-value-content) values-alist)
                  (setq current-value-name nil)
                  (setq current-value-content nil))

              ;; Regular line
              (if in-value-block
                  ;; Accumulate value content
                  (setq current-value-content
                        (concat current-value-content
                                (if (string-empty-p current-value-content) "" "\n")
                                line))
                ;; Accumulate rules content
                (setq rules-content
                      (concat rules-content
                              (if (string-empty-p rules-content) "" "\n")
                              line))))))

        (forward-line 1))

      (list :rules rules-content
            :values (nreverse values-alist)))))

(defun whistle--format-buffer (rules-content values-alist)
  "Format RULES-CONTENT and VALUES-ALIST into unified buffer format."
  (let ((result rules-content))
    ;; Add values section
    (when values-alist
      (setq result (concat result "\n\n"))
      (dolist (value values-alist)
        (setq result
              (concat result
                      (format "```%s\n%s\n```\n\n"
                              (car value)
                              (cdr value))))))
    result))

;;; Sync with Whistle Server

(defun whistle-sync-to-server ()
  "Sync current buffer content to whistle server."
  (interactive)
  (unless whistle--current-rule-name
    (user-error "No rule name set. Use whistle-set-rule-name first"))

  (let* ((parsed (whistle--parse-buffer))
         (rules-content (plist-get parsed :rules))
         (values-alist (plist-get parsed :values))
         (sync-count 0)
         (total-count (1+ (length values-alist))))

    (message "Syncing to whistle server...")

    ;; Sync rules
    (whistle--http-post
     "/cgi-bin/rules/update"
     `(("name" . ,whistle--current-rule-name)
       ("rules" . ,rules-content))
     (lambda (_)
       (setq sync-count (1+ sync-count))
       (message "Synced rules (%d/%d)" sync-count total-count)
       (when (= sync-count total-count)
         (message "✓ Sync completed: 1 rule + %d values" (length values-alist))))
     (lambda (err)
       (message "Failed to sync rules: %s" err)))

    ;; Sync each value
    (dolist (value values-alist)
      (whistle--http-post
       "/cgi-bin/values/update"
       `(("name" . ,(car value))
         ("value" . ,(cdr value)))
       (lambda (_)
         (setq sync-count (1+ sync-count))
         (message "Synced value '%s' (%d/%d)" (car value) sync-count total-count)
         (when (= sync-count total-count)
           (message "✓ Sync completed: 1 rule + %d values" (length values-alist))))
       (lambda (err)
         (message "Failed to sync value '%s': %s" (car value) err))))))

(defun whistle-load-from-server (&optional rule-name)
  "Load rules and values from whistle server.
If RULE-NAME is nil, prompt for it."
  (interactive)
  (let ((name (or rule-name
                  whistle--current-rule-name
                  (read-string "Rule name: " whistle-default-rule-name))))
    (setq whistle--current-rule-name name)

    (message "Loading rule '%s' from server..." name)

    ;; Load rule
    (whistle--http-get
     "/cgi-bin/rules/list"
     (lambda (data)
       (let* ((rules-list (alist-get 'list data))
              (rule (cl-find name rules-list
                            :key (lambda (r) (alist-get 'name r))
                            :test #'string=)))
         (if rule
             (let ((rules-content (or (alist-get 'data rule) "")))
               ;; Load values
               (whistle--http-get
                "/cgi-bin/values/list"
                (lambda (values-data)
                  (let* ((values-list (alist-get 'list values-data))
                         (values-alist (mapcar
                                       (lambda (v)
                                         (cons (alist-get 'name v)
                                               (alist-get 'data v)))
                                       values-list)))
                    ;; Populate buffer
                    (erase-buffer)
                    (insert (whistle--format-buffer rules-content values-alist))
                    (goto-char (point-min))
                    (set-buffer-modified-p nil)
                    (message "✓ Loaded rule '%s' with %d values"
                            name (length values-alist))))
                (lambda (err)
                  (message "Failed to load values: %s" err))))
           (message "Rule '%s' not found on server" name))))
     (lambda (err)
       (message "Failed to load rules: %s" err)))))

(defun whistle-set-rule-name (name)
  "Set the current rule NAME for this buffer."
  (interactive "sRule name: ")
  (setq whistle--current-rule-name name)
  (message "Rule name set to: %s" name))

;;; Syntax Highlighting

(defconst whistle-protocols
  '("http" "https" "ws" "wss" "tunnel" "socks" "proxy" "pac"
    "host" "req" "res" "weinre" "log" "plugin" "reqScript" "resScript"
    "reqDelay" "resDelay" "reqSpeed" "resSpeed" "reqHeaders" "resHeaders"
    "reqType" "resType" "reqCharset" "resCharset" "reqCookies" "resCookies"
    "reqCors" "resCors" "reqPrepend" "resPrepend" "reqBody" "resBody"
    "reqAppend" "resAppend" "reqReplace" "resReplace" "reqWrite" "resWrite"
    "statusCode" "redirect" "headerReplace" "urlParams" "method" "referer"
    "auth" "ua" "cache" "attachment" "forwardProxy" "delete" "cipher"
    "enable" "disable" "filter" "ignore" "pipe" "mark" "exports")
  "List of whistle protocol operators.")

(defconst whistle-font-lock-keywords
  `(;; Value blocks
    ("^```\\([a-zA-Z0-9._-]+\\)$" 1 font-lock-function-name-face)
    ("^```$" . font-lock-comment-delimiter-face)
    ;; Comments
    ("^\\s-*#.*$" . font-lock-comment-face)
    ;; Protocol operators
    (,(regexp-opt whistle-protocols 'symbols) . font-lock-keyword-face)
    ;; URLs and domains
    ("\\(https?://\\|wss?://\\)[^ \t\n]+" . font-lock-string-face)
    ;; Value references in rules: {value-name}
    ("{\\([a-zA-Z0-9._-]+\\)}" 1 font-lock-variable-name-face)
    ;; Pattern matching operators
    ("\\^\\|\\$\\|\\*\\|?" . font-lock-builtin-face)
    ;; IP addresses
    ("\\b\\([0-9]\\{1,3\\}\\.\\)\\{3\\}[0-9]\\{1,3\\}\\b" . font-lock-constant-face)
    ;; Ports
    (":[0-9]+" . font-lock-constant-face))
  "Font lock keywords for whistle unified mode.")

;;; Auto-completion

(defun whistle--get-value-names ()
  "Get all value names defined in current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((names nil))
      (while (re-search-forward "^```\\([a-zA-Z0-9._-]+\\)$" nil t)
        (push (match-string-no-properties 1) names))
      (nreverse names))))

(defun whistle-completion-at-point ()
  "Completion function for whistle protocols and value names."
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when bounds
      ;; Check if we're inside {  }
      (save-excursion
        (let ((start (car bounds))
              (end (cdr bounds)))
          (if (and (> start (point-min))
                   (eq (char-before start) ?{))
              ;; Complete value names
              (list start end (whistle--get-value-names)
                    :annotation-function (lambda (_) " <value>"))
            ;; Complete protocols
            (list start end whistle-protocols
                  :annotation-function (lambda (_) " <protocol>"))))))))

(defun whistle-setup-completion ()
  "Setup completion for whistle mode."
  (add-hook 'completion-at-point-functions
            #'whistle-completion-at-point nil t))

;;; Major Mode

(defvar whistle-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'whistle-sync-to-server)
    (define-key map (kbd "C-c C-l") #'whistle-load-from-server)
    (define-key map (kbd "C-c C-n") #'whistle-set-rule-name)
    (define-key map (kbd "C-c C-a") #'whistle-activate-rule)
    (define-key map (kbd "C-c C-v") #'whistle-insert-value-block)
    (define-key map (kbd "C-c C-t") #'whistle-insert-template)
    map)
  "Keymap for `whistle-mode'.")

(define-derived-mode whistle-mode prog-mode "Whistle"
  "Major mode for editing whistle rules and values in unified format.

\\{whistle-mode-map}"
  (setq-local comment-start "#")
  (setq-local comment-start-skip "#+\\s-*")
  (setq-local font-lock-defaults '(whistle-font-lock-keywords))
  (whistle-setup-completion)
  (when (boundp 'whistle-default-rule-name)
    (setq whistle--current-rule-name whistle-default-rule-name))
  (font-lock-ensure))

;;; Interactive Commands

(defun whistle-activate-rule ()
  "Activate the current rule on whistle server."
  (interactive)
  (unless whistle--current-rule-name
    (user-error "No rule name set"))
  (whistle--http-post
   "/cgi-bin/rules/select"
   `(("name" . ,whistle--current-rule-name))
   (lambda (_)
     (message "✓ Activated rule: %s" whistle--current-rule-name))
   (lambda (err)
     (message "Failed to activate rule: %s" err))))

(defun whistle-insert-value-block (name)
  "Insert a value block template with NAME."
  (interactive "sValue name: ")
  (insert (format "```%s\n\n```\n" name))
  (forward-line -2))

(defun whistle-insert-template ()
  "Insert a rule template at point."
  (interactive)
  (let ((templates
         '(("Proxy" . "pattern proxy://host:port")
           ("Host mapping" . "pattern host://ip")
           ("Mock with value" . "pattern resBody://{value-name}")
           ("Mock with file" . "pattern file://{path/to/file}")
           ("CORS" . "pattern resCors://")
           ("Delay" . "pattern resDelay://1000")
           ("Header" . "pattern resHeaders://{header-value}")
           ("Redirect" . "pattern redirect://new-url"))))
    (let ((choice (completing-read "Template: " (mapcar #'car templates) nil t)))
      (when choice
        (insert (cdr (assoc choice templates)) "\n")))))

;;;###autoload
(defun whistle-edit-rule (&optional rule-name)
  "Open a buffer to edit whistle RULE-NAME.
If RULE-NAME is nil, prompt for it or use default."
  (interactive)
  (let* ((name (or rule-name
                   (read-string "Rule name: " whistle-default-rule-name)))
         (buffer (get-buffer-create (format "*Whistle: %s*" name))))
    (with-current-buffer buffer
      (whistle-mode)
      (setq whistle--current-rule-name name)
      (when (zerop (buffer-size))
        (whistle-load-from-server name)))
    (switch-to-buffer buffer)))

;;; Rules List View

(defvar whistle-list--rules-data nil
  "Cached rules data for list view.")

(define-derived-mode whistle-list-mode tabulated-list-mode "Whistle-List"
  "Major mode for listing and managing whistle rules.

\\{whistle-list-mode-map}"
  (setq tabulated-list-format [("Name" 30 t)
                               ("Active" 8 t)
                               ("Size" 10 t)])
  (setq tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook #'whistle-list-refresh nil t)
  (tabulated-list-init-header))

(defun whistle-list-refresh ()
  "Refresh the rules list from whistle server."
  (interactive)
  (message "Fetching rules from %s..." (whistle--get-base-url))
  (whistle--http-get "/cgi-bin/rules/list"
                     (lambda (data)
                       (setq whistle-list--rules-data (alist-get 'list data))
                       (whistle-list--update-display)
                       (message "Rules refreshed successfully"))
                     (lambda (err)
                       (message "Failed to refresh rules: %s" err))))

(defun whistle-list--update-display ()
  "Update the tabulated list display."
  (setq tabulated-list-entries
        (mapcar
         (lambda (item)
           (let ((name (alist-get 'name item))
                 (selected (alist-get 'selected item))
                 (data (alist-get 'data item)))
             (list name
                   (vector
                    name
                    (if selected "✓" "")
                    (format "%d B" (length (or data "")))))))
         whistle-list--rules-data))
  (tabulated-list-print t))

(defun whistle-list-open ()
  "Open the selected rule for editing in whistle-mode."
  (interactive)
  (let ((name (tabulated-list-get-id)))
    (unless name
      (user-error "No rule selected"))
    (whistle-edit-rule name)))

(defun whistle-list-create (name)
  "Create a new rule with NAME."
  (interactive "sNew rule name: ")
  (when (string-empty-p name)
    (user-error "Rule name cannot be empty"))
  (message "Creating rule: %s..." name)
  (whistle--http-post
   "/cgi-bin/rules/add"
   `(("name" . ,name)
     ("value" . ""))
   (lambda (_response)
     (message "Rule created: %s" name)
     (whistle-list-refresh)
     (whistle-edit-rule name))
   (lambda (err)
     (message "Failed to create rule: %s" err))))

(defun whistle-list-delete ()
  "Delete the selected rule."
  (interactive)
  (let ((name (tabulated-list-get-id)))
    (unless name
      (user-error "No rule selected"))
    (when (yes-or-no-p (format "Delete rule '%s'? " name))
      (message "Deleting rule: %s..." name)
      (whistle--http-post
       "/cgi-bin/rules/remove"
       `(("name" . ,name))
       (lambda (_response)
         (message "Rule deleted: %s" name)
         (whistle-list-refresh))
       (lambda (err)
         (message "Failed to delete rule: %s" err))))))

(defun whistle-list-toggle ()
  "Toggle activation status of the selected rule."
  (interactive)
  (let* ((name (tabulated-list-get-id))
         (rule (cl-find name whistle-list--rules-data
                        :key (lambda (r) (alist-get 'name r))
                        :test #'string=)))
    (unless rule
      (user-error "No rule selected"))
    (let ((is-selected (alist-get 'selected rule)))
      (message "%s rule: %s..." (if is-selected "Deactivating" "Activating") name)
      (whistle--http-post
       (if is-selected "/cgi-bin/rules/unselect" "/cgi-bin/rules/select")
       `(("name" . ,name))
       (lambda (_response)
         (message "Rule %s: %s" (if is-selected "deactivated" "activated") name)
         (whistle-list-refresh))
       (lambda (err)
         (message "Failed to toggle rule: %s" err))))))

(defun whistle-list-rename (new-name)
  "Rename the selected rule to NEW-NAME."
  (interactive "sNew name: ")
  (let ((old-name (tabulated-list-get-id)))
    (unless old-name
      (user-error "No rule selected"))
    (when (string-empty-p new-name)
      (user-error "New name cannot be empty"))
    (message "Renaming rule from %s to %s..." old-name new-name)
    (whistle--http-post
     "/cgi-bin/rules/rename"
     `(("name" . ,old-name)
       ("newName" . ,new-name))
     (lambda (_response)
       (message "Rule renamed: %s -> %s" old-name new-name)
       (whistle-list-refresh))
     (lambda (err)
       (message "Failed to rename rule: %s" err)))))

;; Keybindings for list mode
(defvar whistle-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'whistle-list-open)
    (define-key map (kbd "g") #'whistle-list-refresh)
    (define-key map (kbd "c") #'whistle-list-create)
    (define-key map (kbd "d") #'whistle-list-delete)
    (define-key map (kbd "r") #'whistle-list-rename)
    (define-key map (kbd "t") #'whistle-list-toggle)
    (define-key map (kbd "SPC") #'whistle-list-toggle)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `whistle-list-mode'.")

;;;###autoload
(defun whistle ()
  "Open whistle rules list."
  (interactive)
  (let ((buf (get-buffer-create "*Whistle Rules*")))
    (with-current-buffer buf
      (whistle-list-mode)
      (whistle-list-refresh))
    (switch-to-buffer buf)))

(provide 'whistle-v2)

;;; whistle-v2.el ends here
