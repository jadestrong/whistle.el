;;; whistle-core.el --- Core functionality for Whistle editor -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Your Name
;; Version: 3.0.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: tools, whistle, proxy, debugging

;;; Commentary:

;; Core functionality for Whistle editor without polymode dependency.
;; This file provides:
;;   - Customization variables
;;   - Naming and hash utilities
;;   - Metadata system
;;   - File system utilities
;;   - HTTP utilities for server communication
;;   - Buffer parsing
;;   - Sync functions
;;   - Font-lock keywords
;;   - Auto-completion
;;   - Interactive commands
;;   - Rules list view

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

(defcustom whistle-rules-directory
  (expand-file-name "~/.whistle/rules/")
  "Directory to store whistle rule files.
Each rule is saved as RULE-NAME.whistle in this directory."
  :type 'directory
  :group 'whistle)

(defcustom whistle-auto-sync t
  "Whether to automatically sync with server on save."
  :type 'boolean
  :group 'whistle)

(defcustom whistle-auto-save t
  "Whether to automatically save to local file."
  :type 'boolean
  :group 'whistle)

(defcustom whistle-default-rule-name "Default"
  "Default rule name to use."
  :type 'string
  :group 'whistle)

(defcustom whistle-rule-prefix "emacs"
  "Prefix for Emacs-managed rules on the server.
Rules are stored as PREFIX:rule-name (e.g., emacs:my-rule)."
  :type 'string
  :group 'whistle)

(defcustom whistle-metadata-file
  (expand-file-name "~/.whistle/metadata.json")
  "File to store metadata for tracking rules and values."
  :type 'file
  :group 'whistle)

(defcustom whistle-auto-backup t
  "Whether to create backups before syncing."
  :type 'boolean
  :group 'whistle)

(defcustom whistle-backup-directory
  (expand-file-name "~/.whistle/backups/")
  "Directory to store backups."
  :type 'directory
  :group 'whistle)

(defcustom whistle-conflict-strategy 'prompt
  "Strategy for handling conflicts.
Possible values:
  'prompt      - Ask user what to do
  'server-wins - Always use server version
  'local-wins  - Always use local version"
  :type '(choice (const :tag "Prompt user" prompt)
                 (const :tag "Server wins" server-wins)
                 (const :tag "Local wins" local-wins))
  :group 'whistle)

;;; Variables

(defvar-local whistle--current-rule-name nil
  "Name of the currently editing rule.")

(defvar-local whistle--parsed-values nil
  "Alist of parsed values from the buffer.")

(defvar-local whistle--rules-end-pos nil
  "Position where rules section ends and values begin.")

(defvar-local whistle--file-path nil
  "Local file path for current rule.")

(defvar whistle--metadata-cache nil
  "Cached metadata loaded from file.")

;;; Naming Utilities

(defun whistle--group-name ()
  "Get the Whistle group name for Emacs-managed rules.
Returns the group name with the required \\r prefix."
  (concat "\r" whistle-rule-prefix))

(defun whistle--server-rule-name (display-name)
  "Convert display name to server name (just the rule name, no prefix).
Example: my-rule → my-rule (group is specified separately)"
  display-name)

(defun whistle--display-rule-name (server-name)
  "Convert server name to display name.
Since rules are now in a group, just return the name as-is."
  server-name)

(defun whistle--server-value-name (rule-name value-name)
  "Get server value name with rule namespace.
Example: (my-rule, user-data) → emacs-my-rule-user-data"
  (format "%s-%s-%s" whistle-rule-prefix rule-name value-name))

(defun whistle--display-value-name (server-value-name)
  "Extract display value name from server name.
Example: emacs-my-rule-user-data → user-data"
  (if (string-match (format "^%s-[^-]+-\\(.+\\)$" (regexp-quote whistle-rule-prefix))
                    server-value-name)
      (match-string 1 server-value-name)
    server-value-name))

(defun whistle--is-emacs-managed-p (name)
  "Check if NAME is managed by Emacs.
For rules, this is handled by group membership.
For values, check the prefix."
  (string-prefix-p (concat whistle-rule-prefix "-") name))

;;; Hash Utilities

(defun whistle--calculate-hash (content)
  "Calculate MD5 hash of CONTENT."
  (md5 content))

;;; Metadata System

(defun whistle--load-metadata ()
  "Load metadata from file."
  (if (file-exists-p whistle-metadata-file)
      (with-temp-buffer
        (insert-file-contents whistle-metadata-file)
        (let ((json-object-type 'alist)
              (json-array-type 'list))
          (setq whistle--metadata-cache (json-read))))
    ;; Initialize empty metadata
    (setq whistle--metadata-cache
          '((rules . ())
            (values . ())
            (version . "3.0.0")
            (lastSync . nil)))))

(defun whistle--save-metadata ()
  "Save metadata to file."
  (let ((dir (file-name-directory whistle-metadata-file)))
    (unless (file-exists-p dir)
      (make-directory dir t)))
  (with-temp-file whistle-metadata-file
    (insert (json-encode whistle--metadata-cache))))

(defun whistle--get-rule-metadata (rule-name)
  "Get metadata for RULE-NAME (display name)."
  (unless whistle--metadata-cache
    (whistle--load-metadata))
  (let ((server-name (whistle--server-rule-name rule-name)))
    (alist-get (intern server-name)
               (alist-get 'rules whistle--metadata-cache))))

(defun whistle--update-rule-metadata (rule-name data)
  "Update metadata for RULE-NAME with DATA."
  (unless whistle--metadata-cache
    (whistle--load-metadata))
  (let* ((server-name (whistle--server-rule-name rule-name))
         (rules (alist-get 'rules whistle--metadata-cache))
         (updated-rules (cons (cons (intern server-name) data)
                              (assq-delete-all (intern server-name) rules))))
    (setf (alist-get 'rules whistle--metadata-cache) updated-rules)
    (setf (alist-get 'lastSync whistle--metadata-cache)
          (format-time-string "%Y-%m-%dT%H:%M:%SZ" (current-time)))
    (whistle--save-metadata)))

(defun whistle--delete-rule-metadata (rule-name)
  "Delete metadata for RULE-NAME."
  (unless whistle--metadata-cache
    (whistle--load-metadata))
  (let* ((server-name (whistle--server-rule-name rule-name))
         (rules (alist-get 'rules whistle--metadata-cache)))
    (setf (alist-get 'rules whistle--metadata-cache)
          (assq-delete-all (intern server-name) rules))
    (whistle--save-metadata)))

;;; File System Utilities

(defun whistle--ensure-directory ()
  "Ensure the whistle rules directory exists."
  (unless (file-exists-p whistle-rules-directory)
    (make-directory whistle-rules-directory t)))

(defun whistle--rule-file-path (rule-name)
  "Get the file path for RULE-NAME."
  (expand-file-name (concat rule-name ".whistle") whistle-rules-directory))

(defun whistle--save-to-file ()
  "Save current buffer to local file."
  (interactive)
  (unless whistle--current-rule-name
    (user-error "No rule name set"))
  (whistle--ensure-directory)
  (let ((file-path (whistle--rule-file-path whistle--current-rule-name))
        (content (buffer-string)))
    (with-temp-file file-path
      (insert content))
    (setq whistle--file-path file-path)
    (set-buffer-modified-p nil)
    (set-visited-file-name file-path t)
    (message "✓ Saved to file: %s" file-path)))

(defun whistle--load-from-file (rule-name)
  "Load RULE-NAME from local file."
  (let ((file-path (whistle--rule-file-path rule-name)))
    (if (file-exists-p file-path)
        (progn
          (erase-buffer)
          (insert-file-contents file-path)
          (setq whistle--file-path file-path)
          (setq whistle--current-rule-name rule-name)
          (set-visited-file-name file-path t)
          (set-buffer-modified-p nil)
          (message "✓ Loaded from file: %s" file-path)
          t)
      nil)))

(defun whistle--list-local-rules ()
  "List all local rule files."
  (whistle--ensure-directory)
  (let ((files (directory-files whistle-rules-directory nil "\\.whistle$")))
    (mapcar (lambda (f) (file-name-sans-extension f)) files)))

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
            (url-request-extra-headers
             '(("Content-Type" . "application/x-www-form-urlencoded")))
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

;;; Sync with Whistle Server and File

(defun whistle-save ()
  "Save current buffer to both local file and server."
  (interactive)
  (unless whistle--current-rule-name
    (user-error "No rule name set"))

  ;; Always save to local file
  (whistle--save-to-file)

  ;; Optionally sync to server
  (when whistle-auto-sync
    (whistle-sync-to-server)))

(defun whistle-sync-to-server ()
  "Sync current buffer content to whistle server only."
  (interactive)
  (unless whistle--current-rule-name
    (user-error "No rule name set. Use whistle-set-rule-name first"))

  (let* ((current-rule-name whistle--current-rule-name)  ; Capture buffer-local value
         (parsed (whistle--parse-buffer))
         (rules-content (plist-get parsed :rules))
         (values-alist (plist-get parsed :values))
         (server-rule-name (whistle--server-rule-name current-rule-name))
         (sync-count 0)
         (total-count (1+ (length values-alist)))
         (value-names nil))

    (message "Syncing to whistle server (as %s)..." server-rule-name)

    ;; Transform value references in rules from {name} to {emacs-rule-name}
    (let ((transformed-rules rules-content))
      (dolist (value values-alist)
        (let ((display-name (car value))
              (server-name (whistle--server-value-name current-rule-name (car value))))
          (setq transformed-rules
                (replace-regexp-in-string
                 (regexp-quote (format "{%s}" display-name))
                 (format "{%s}" server-name)
                 transformed-rules))
          (push server-name value-names)))

      ;; Ensure group exists first, then sync rule
      (let ((group-name (whistle--group-name)))
        ;; Create/ensure group exists
        (whistle--http-post
         "/cgi-bin/rules/add"
         `(("name" . ,group-name))
         (lambda (_)
           ;; Group created/exists, now add rule to group
           (whistle--http-post
            "/cgi-bin/rules/add"
            `(("name" . ,server-rule-name)
              ("value" . ,transformed-rules)
              ("groupName" . ,group-name))
            (lambda (_)
              (setq sync-count (1+ sync-count))
              (message "Synced rules (%d/%d)" sync-count total-count)
              (when (= sync-count total-count)
                ;; Update metadata
                (whistle--update-rule-metadata
                 current-rule-name
                 `((displayName . ,current-rule-name)
                   (localFile . ,whistle--file-path)
                   (fileHash . ,(whistle--calculate-hash (buffer-string)))
                   (serverHash . ,(whistle--calculate-hash (buffer-string)))
                   (values . ,(vconcat value-names))
                   (modified . ,(format-time-string "%Y-%m-%dT%H:%M:%SZ" (current-time)))))
                (message "✓ Sync completed: rule %s in group %s + %d values"
                        server-rule-name whistle-rule-prefix (length values-alist))))
            (lambda (err)
              (message "Failed to sync rules: %s" err))))
         (lambda (err)
           ;; Group creation failed, but continue anyway
           (message "Group setup warning: %s" err))))


      ;; Sync values to the same group (always use /add, it updates if exists)
      (let ((group-name (whistle--group-name)))
        ;; First, get list of existing values to clean up orphaned ones
        (whistle--http-get
         "/cgi-bin/values/list"
         (lambda (values-data)
           (let* ((all-server-values (mapcar (lambda (v) (cdr (assoc 'name v)))
                                             (cdr (assoc 'list values-data))))
                  ;; Build expected value prefix for this rule
                  (value-prefix (format "%s-%s-" whistle-rule-prefix current-rule-name))
                  ;; Find all values belonging to this rule on server
                  (rule-server-values (cl-remove-if-not
                                      (lambda (name) (string-prefix-p value-prefix name))
                                      all-server-values))
                  ;; Build list of current local value names
                  (local-value-names (mapcar (lambda (v)
                                              (whistle--server-value-name current-rule-name (car v)))
                                            values-alist))
                  ;; Find orphaned values (on server but not in local file)
                  (orphaned-values (cl-remove-if (lambda (name) (member name local-value-names))
                                                 rule-server-values)))

             ;; Delete orphaned values
             (dolist (orphaned-name orphaned-values)
               (whistle--http-post
                "/cgi-bin/values/remove"
                `(("name" . ,orphaned-name))
                (lambda (_)
                  (message "Deleted orphaned value: %s" orphaned-name))
                (lambda (err)
                  (message "Failed to delete orphaned value '%s': %s" orphaned-name err))))

             ;; Create/ensure value group exists first
             (whistle--http-post
              "/cgi-bin/values/add"
              `(("name" . ,group-name))
              (lambda (_)
                ;; Group created/exists, now add values to group
                (dolist (value values-alist)
                  (let ((server-name (whistle--server-value-name current-rule-name (car value))))
                    (whistle--http-post
                     "/cgi-bin/values/add"
                     `(("name" . ,server-name)
                       ("value" . ,(cdr value))
                       ("groupName" . ,group-name))
                     (lambda (_)
                       (setq sync-count (1+ sync-count))
                       (message "Synced value '%s' (%d/%d)" server-name sync-count total-count)
                       (when (= sync-count total-count)
                         (message "✓ Sync completed: rule %s in group %s + %d values"
                                 server-rule-name whistle-rule-prefix (length values-alist))))
                     (lambda (err)
                       (message "Failed to sync value '%s': %s" server-name err))))))
              (lambda (err)
                ;; Value group creation failed, but continue anyway
                (message "Value group setup warning: %s" err)))))
         (lambda (err)
           (message "Failed to get values list for cleanup: %s" err)))))))

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
                                               (or (alist-get 'data v) "")))
                                       values-list)))
                    ;; Populate buffer
                    (erase-buffer)
                    (if (and (string-empty-p rules-content)
                             (null values-alist))
                        ;; Empty rule - insert template
                        (insert (format "# Whistle Rule: %s\n\n" name))
                      ;; Has content
                      (insert (whistle--format-buffer rules-content values-alist)))
                    (goto-char (point-min))
                    (set-buffer-modified-p nil)
                    (message "✓ Loaded rule '%s' with %d values"
                            name (length values-alist))))
                (lambda (err)
                  (message "Failed to load values: %s" err))))
           ;; Rule not found - this might be a newly created rule
           (message "Rule '%s' created. Edit and save with C-c C-c" name)
           (erase-buffer)
           (insert (format "# Whistle Rule: %s\n\n" name))
           (goto-char (point-max))
           (set-buffer-modified-p nil))))
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

;;; Font Lock Keywords

(defconst whistle-font-lock-keywords
  `(;; Comments
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
            ;; Complete protocols with :// suffix
            (list start end
                  ;; 使用 completion-table-case-fold 实现大小写不敏感
                  (completion-table-case-fold whistle-protocols)
                  :annotation-function (lambda (_) " <protocol>")
                  :exit-function
                  (lambda (candidate status)
                    (when (eq status 'finished)
                      ;; 检查后面是否已经有 ://
                      (unless (looking-at "://")
                        (insert "://")))))))))))

(defun whistle-setup-completion ()
  "Setup completion for whistle mode."
  (add-hook 'completion-at-point-functions
            #'whistle-completion-at-point nil t))

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
Tries to load from local file first, then from server if not found locally."
  (interactive
   (list (completing-read "Rule name: "
                          (append (whistle--list-local-rules)
                                  (list whistle-default-rule-name))
                          nil nil nil nil whistle-default-rule-name)))
  (let* ((name (or rule-name whistle-default-rule-name))
         (buffer (get-buffer-create (format "*Whistle: %s*" name))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'whistle-mode 'whistle-ts-mode)
        ;; Try to use whistle-ts-mode if available, fallback to fundamental
        (if (fboundp 'whistle-ts-mode)
            (whistle-ts-mode)
          (fundamental-mode)))
      (setq whistle--current-rule-name name)
      (when (zerop (buffer-size))
        ;; Try local file first
        (unless (whistle--load-from-file name)
          ;; Fallback to server
          (whistle-load-from-server name))))
    (switch-to-buffer buffer)))

;;; Rules List View

(defvar whistle-list--rules-data nil
  "Cached rules data for list view.")

;; Keybindings for list mode (must be defined before the mode)
(defvar whistle-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'whistle-list-open)
    (define-key map (kbd "g") #'whistle-list-refresh)
    (define-key map (kbd "c") #'whistle-list-create)
    (define-key map (kbd "d") #'whistle-list-delete)
    (define-key map (kbd "r") #'whistle-list-rename)
    (define-key map (kbd "t") #'whistle-list-toggle)
    (define-key map (kbd "SPC") #'whistle-list-toggle)
    (define-key map (kbd "m") #'whistle-list-managed-rules)
    (define-key map (kbd "C") #'whistle-cleanup-orphaned-values)
    (define-key map (kbd "D") #'whistle-delete-all-managed-rules)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `whistle-list-mode'.")

(define-derived-mode whistle-list-mode tabulated-list-mode "Whistle-List"
  "Major mode for listing and managing whistle rules.

\\{whistle-list-mode-map}"
  (setq tabulated-list-format [("Name" 30 t)
                               ("Active" 8 t)
                               ("Size" 10 t)])
  (setq tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook #'whistle-list-refresh nil t)
  (tabulated-list-init-header))

;; Evil mode support for list mode
(with-eval-after-load 'evil
  (evil-set-initial-state 'whistle-list-mode 'normal)
  (evil-define-key 'normal whistle-list-mode-map
    (kbd "RET") #'whistle-list-open
    "gr" #'whistle-list-refresh
    "c" #'whistle-list-create
    "d" #'whistle-list-delete
    "r" #'whistle-list-rename
    "t" #'whistle-list-toggle
    (kbd "SPC") #'whistle-list-toggle
    "m" #'whistle-list-managed-rules
    "C" #'whistle-cleanup-orphaned-values
    "D" #'whistle-delete-all-managed-rules
    "q" #'quit-window))

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
  "Create a new rule with NAME (will be prefixed with emacs:)."
  (interactive "sNew rule name: ")
  (when (string-empty-p name)
    (user-error "Rule name cannot be empty"))
  ;; Use whistle-edit-rule which handles V3 naming properly
  (whistle-edit-rule name))

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

;;; Utility Functions

(defun whistle-open-web-ui ()
  "Open whistle web UI in browser."
  (interactive)
  (browse-url (whistle--get-base-url)))

;;; Cleanup Utilities

(defun whistle-list-managed-rules ()
  "List all Emacs-managed rules with their sync status."
  (interactive)
  (whistle--http-get
   "/cgi-bin/rules/list"
   (lambda (data)
     (let* ((rules (cdr (assoc 'list data)))
            (managed-rules (seq-filter
                           (lambda (rule)
                             (whistle--is-emacs-managed-p (cdr (assoc 'name rule))))
                           rules))
            (buf (get-buffer-create "*Whistle Managed Rules*")))
       (with-current-buffer buf
         (let ((inhibit-read-only t))
           (erase-buffer)
           (insert "Emacs-Managed Whistle Rules\n")
           (insert "===========================\n\n")
           (if (null managed-rules)
               (insert "No Emacs-managed rules found.\n")
             (dolist (rule managed-rules)
               (let* ((server-name (cdr (assoc 'name rule)))
                      (display-name (whistle--display-rule-name server-name))
                      (metadata (whistle--get-rule-metadata display-name))
                      (status (if metadata
                                 (let ((file-hash (alist-get 'fileHash metadata))
                                       (local-file (alist-get 'localFile metadata)))
                                   (cond
                                    ((not (file-exists-p local-file)) "⚠️  no local file")
                                    ((not file-hash) "📝 not synced")
                                    (t "✓ synced")))
                               "❓ no metadata")))
                 (insert (format "  %-30s %s\n" display-name status)))))
           (insert (format "\nTotal: %d Emacs-managed rules\n"
                          (length managed-rules)))
           (goto-char (point-min))
           (view-mode 1)))
       (display-buffer buf)))
   (lambda (err)
     (message "Failed to list managed rules: %s" err))))

(defun whistle-cleanup-orphaned-values ()
  "Find and optionally delete values that belong to non-existent rules."
  (interactive)
  (whistle--http-get
   "/cgi-bin/values/list"
   (lambda (values-data)
     (whistle--http-get
      "/cgi-bin/rules/list"
      (lambda (rules-data)
        (let* ((all-values (cdr (assoc 'list values-data)))
               (all-rules (cdr (assoc 'list rules-data)))
               (rule-names (mapcar (lambda (r) (cdr (assoc 'name r))) all-rules))
               (orphaned-values
                (seq-filter
                 (lambda (value)
                   (let ((value-name (cdr (assoc 'name value))))
                     ;; Check if it's an emacs-managed value
                     (when (string-match (format "^%s:\\([^:]+\\):" whistle-rule-prefix)
                                       value-name)
                       (let ((rule-name (match-string 0 value-name)))
                         ;; Remove trailing colon
                         (setq rule-name (substring rule-name 0 -1))
                         ;; Check if the rule doesn't exist
                         (not (member rule-name rule-names))))))
                 all-values)))
          (if (null orphaned-values)
              (message "No orphaned values found.")
            (let ((buf (get-buffer-create "*Whistle Orphaned Values*")))
              (with-current-buffer buf
                (let ((inhibit-read-only t))
                  (erase-buffer)
                  (insert "Orphaned Emacs-Managed Values\n")
                  (insert "==============================\n\n")
                  (insert (format "Found %d orphaned values:\n\n" (length orphaned-values)))
                  (dolist (value orphaned-values)
                    (insert (format "  - %s\n" (cdr (assoc 'name value)))))
                  (insert "\nThese values belong to deleted rules.\n")
                  (insert "Press 'd' to delete all orphaned values, 'q' to quit.\n")
                  (goto-char (point-min))
                  (local-set-key (kbd "d")
                               (lambda ()
                                 (interactive)
                                 (when (yes-or-no-p
                                       (format "Delete %d orphaned values? "
                                              (length orphaned-values)))
                                   (whistle--delete-values-batch orphaned-values))))
                  (local-set-key (kbd "q") 'quit-window)
                  (view-mode 1)))
              (display-buffer buf)))))
      (lambda (err)
        (message "Failed to fetch rules: %s" err))))
   (lambda (err)
     (message "Failed to fetch values: %s" err))))

(defun whistle--delete-values-batch (values)
  "Delete a batch of VALUES."
  (let ((total (length values))
        (deleted 0)
        (failed 0))
    (dolist (value values)
      (let ((value-name (cdr (assoc 'name value))))
        (whistle--http-post
         "/cgi-bin/values/remove"
         `(("name" . ,value-name))
         (lambda (_)
           (setq deleted (1+ deleted))
           (message "Deleted %d/%d values..." deleted total)
           (when (= deleted (- total failed))
             (message "Cleanup complete: %d deleted, %d failed" deleted failed)))
         (lambda (err)
           (setq failed (1+ failed))
           (message "Failed to delete %s: %s" value-name err)))))))

(defun whistle-delete-all-managed-rules ()
  "Delete all Emacs-managed rules and their associated values.
This will remove all rules with the configured prefix from the server."
  (interactive)
  (when (yes-or-no-p
         (format "Delete ALL Emacs-managed rules (prefix: %s:)? This cannot be undone! "
                whistle-rule-prefix))
    (whistle--http-get
     "/cgi-bin/rules/list"
     (lambda (data)
       (let* ((rules (cdr (assoc 'list data)))
              (managed-rules (seq-filter
                            (lambda (rule)
                              (whistle--is-emacs-managed-p (cdr (assoc 'name rule))))
                            rules)))
         (if (null managed-rules)
             (message "No Emacs-managed rules found.")
           (when (yes-or-no-p
                  (format "Found %d Emacs-managed rules. Confirm deletion? "
                         (length managed-rules)))
             (whistle--delete-rules-batch managed-rules)))))
     (lambda (err)
       (message "Failed to list rules: %s" err)))))

(defun whistle--delete-rules-batch (rules)
  "Delete a batch of RULES and their associated values."
  (let ((total (length rules))
        (deleted 0)
        (failed 0))
    (dolist (rule rules)
      (let ((rule-name (cdr (assoc 'name rule))))
        (whistle--http-post
         "/cgi-bin/rules/remove"
         `(("name" . ,rule-name))
         (lambda (_)
           (setq deleted (1+ deleted))
           (message "Deleted %d/%d rules..." deleted total)
           ;; Delete associated values
           (let ((display-name (whistle--display-rule-name rule-name)))
             (whistle--delete-rule-values display-name))
           (when (= deleted (- total failed))
             (message "Cleanup complete: %d rules deleted, %d failed" deleted failed)
             (when (get-buffer "*Whistle Rules*")
               (with-current-buffer "*Whistle Rules*"
                 (whistle-list-refresh)))))
         (lambda (err)
           (setq failed (1+ failed))
           (message "Failed to delete %s: %s" rule-name err)))))))

(defun whistle--delete-rule-values (display-name)
  "Delete all values associated with rule DISPLAY-NAME."
  (let ((metadata (whistle--get-rule-metadata display-name)))
    (when metadata
      (let ((values (alist-get 'values metadata)))
        (when values
          (dolist (value-name values)
            (whistle--http-post
             "/cgi-bin/values/remove"
             `(("name" . ,value-name))
             (lambda (_)
               (message "Deleted value: %s" value-name))
             (lambda (err)
               (message "Failed to delete value %s: %s" value-name err)))))))))

;;;###autoload
(defun whistle ()
  "Open whistle rules list."
  (interactive)
  (let ((buf (get-buffer-create "*Whistle Rules*")))
    (with-current-buffer buf
      (whistle-list-mode)
      (whistle-list-refresh))
    (switch-to-buffer buf)))

(provide 'whistle-core)

;;; whistle-core.el ends here
