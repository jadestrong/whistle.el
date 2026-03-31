;;; whistle.el --- Whistle rules and values editor for Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Your Name
;; Version: 2.0.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: tools, whistle, proxy, debugging
;; URL: https://github.com/yourusername/whistle.el

;;; Commentary:

;; This package provides a comprehensive Emacs interface for managing
;; Whistle proxy rules and values.  Features include:
;;
;; - Rules and Values management (create, edit, delete)
;; - Syntax highlighting for whistle rules
;; - Auto-completion for whistle protocols
;; - Search and filter functionality
;; - Import/export capabilities
;; - Multiple whistle instance support

;;; Code:

(require 'tabulated-list)
(require 'json)
(require 'url)
(require 'cl-lib)

;;; Customization

(defgroup whistle nil
  "Whistle proxy rules and values editor."
  :group 'tools
  :prefix "whistle-")

(defcustom whistle-base-url "http://127.0.0.1:8899"
  "Base URL for the Whistle proxy server."
  :type 'string
  :group 'whistle)

(defcustom whistle-instances nil
  "List of whistle instances.
Each instance is a plist with :name and :url properties.
Example: \\='((:name \"Local\" :url \"http://127.0.0.1:8899\")
            (:name \"Remote\" :url \"http://remote-host:8899\"))"
  :type '(repeat (plist :key-type (choice (const :name) (const :url))
                        :value-type string))
  :group 'whistle)

(defcustom whistle-auto-refresh t
  "Whether to automatically refresh the list after operations."
  :type 'boolean
  :group 'whistle)

(defcustom whistle-confirm-delete t
  "Whether to confirm before deleting rules or values."
  :type 'boolean
  :group 'whistle)

;;; Variables

(defvar whistle-rules--data nil
  "Cached rules data from whistle server.")

(defvar whistle-values--data nil
  "Cached values data from whistle server.")

(defvar whistle-rules--current nil
  "Name of the currently editing rule.")

(defvar whistle-values--current nil
  "Name of the currently editing value.")

(defvar whistle--current-instance nil
  "Currently selected whistle instance URL.")

;;; HTTP Utilities

(defun whistle--get-base-url ()
  "Get the current whistle base URL."
  (or whistle--current-instance whistle-base-url))

(defun whistle--http-get (path callback &optional error-callback)
  "Send GET request to PATH and call CALLBACK with response data.
If ERROR-CALLBACK is provided, call it on error with error message."
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
  "Send POST request to PATH with DATA and call CALLBACK with response.
If ERROR-CALLBACK is provided, call it on error with error message."
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

;;; Rules List Mode

(defvar whistle-rules--filter-string ""
  "Current filter string for rules list.")

(define-derived-mode whistle-rules-list-mode tabulated-list-mode "Whistle-Rules"
  "Major mode for managing Whistle proxy rules.

\\{whistle-rules-list-mode-map}"
  (setq tabulated-list-format [("Name" 40 t)
                               ("Active" 8 t)
                               ("Size" 10 t)])
  (setq tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook #'whistle-rules-refresh nil t)
  (tabulated-list-init-header))

(defun whistle-rules-refresh ()
  "Refresh the rules list from whistle server."
  (interactive)
  (let ((buffer (current-buffer)))
    (message "Fetching rules from %s..." (whistle--get-base-url))
    (whistle--http-get "/cgi-bin/rules/list"
                       (lambda (data)
                         (message "DEBUG: Received data: %S" data)
                         (setq whistle-rules--data (alist-get 'list data))
                         (message "DEBUG: whistle-rules--data: %S" whistle-rules--data)
                         (message "DEBUG: whistle-rules--data length: %d" (length whistle-rules--data))
                         (with-current-buffer buffer
                           (whistle-rules--update-list))
                         (message "Rules refreshed successfully"))
                       (lambda (err)
                         (message "Failed to refresh rules: %s" err)))))

(defun whistle-rules--update-list ()
  "Update the tabulated list entries based on current data and filter."
  (message "DEBUG: update-list called in buffer: %s" (buffer-name))
  (message "DEBUG: update-list called, data: %S" whistle-rules--data)
  (message "DEBUG: filter string: %S" whistle-rules--filter-string)
  (let ((entries
         (cl-remove-if-not
          (lambda (entry)
            (or (string-empty-p whistle-rules--filter-string)
                (string-match-p whistle-rules--filter-string (car entry))))
          (mapcar
           (lambda (item)
             (message "DEBUG: Processing item: %S" item)
             (let ((name (alist-get 'name item))
                   (selected (alist-get 'selected item))
                   (data (alist-get 'data item)))
               (message "DEBUG: name=%s, selected=%s, data-length=%d" name selected (length (or data "")))
               (list name
                     (vector
                      name
                      (if selected "✓" "")
                      (format "%d B" (length (or data "")))))))
           whistle-rules--data))))
    (message "DEBUG: Generated %d entries" (length entries))
    (message "DEBUG: Setting tabulated-list-entries to: %S" entries)
    (setq tabulated-list-entries entries)
    (message "DEBUG: About to call tabulated-list-print")
    (tabulated-list-print t)
    (message "DEBUG: tabulated-list-print completed")))

(defun whistle-rules-filter (pattern)
  "Filter rules list by PATTERN."
  (interactive "sFilter rules: ")
  (setq whistle-rules--filter-string pattern)
  (whistle-rules--update-list)
  (message (if (string-empty-p pattern)
               "Filter cleared"
             "Filtered by: %s") pattern))

(defun whistle-rules-clear-filter ()
  "Clear the current filter."
  (interactive)
  (whistle-rules-filter ""))

;;;###autoload
(defun whistle-rules ()
  "Open the whistle rules management buffer."
  (interactive)
  (let ((buf (get-buffer-create "*Whistle Rules*")))
    (with-current-buffer buf
      (whistle-rules-list-mode)
      (whistle-rules-refresh))
    (switch-to-buffer buf)))

;;; Rules Operations

(defun whistle-rules-open ()
  "Open the selected rule for editing."
  (interactive)
  (let* ((id (tabulated-list-get-id))
         (rule (cl-find id whistle-rules--data
                        :key (lambda (r) (alist-get 'name r))
                        :test #'string=)))
    (when rule
      (setq whistle-rules--current id)
      (let ((buf (get-buffer-create "*Whistle Rule Content*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (or (alist-get 'data rule) ""))
          (whistle-rule-edit-mode)
          (set-buffer-modified-p nil))
        (switch-to-buffer buf)))))

(defun whistle-rules-create (name)
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
     (when whistle-auto-refresh
       (whistle-rules-refresh)))
   (lambda (err)
     (message "Failed to create rule: %s" err))))

(defun whistle-rules-delete ()
  "Delete the selected rule."
  (interactive)
  (let ((name (tabulated-list-get-id)))
    (unless name
      (user-error "No rule selected"))
    (when (or (not whistle-confirm-delete)
              (yes-or-no-p (format "Delete rule '%s'? " name)))
      (message "Deleting rule: %s..." name)
      (whistle--http-post
       "/cgi-bin/rules/remove"
       `(("name" . ,name))
       (lambda (_response)
         (message "Rule deleted: %s" name)
         (when whistle-auto-refresh
           (whistle-rules-refresh)))
       (lambda (err)
         (message "Failed to delete rule: %s" err))))))

(defun whistle-rules-toggle ()
  "Toggle activation status of the selected rule."
  (interactive)
  (let* ((name (tabulated-list-get-id))
         (rule (cl-find name whistle-rules--data
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
         (when whistle-auto-refresh
           (whistle-rules-refresh)))
       (lambda (err)
         (message "Failed to toggle rule: %s" err))))))

(defun whistle-rules-rename (new-name)
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
       (when whistle-auto-refresh
         (whistle-rules-refresh)))
     (lambda (err)
       (message "Failed to rename rule: %s" err)))))

;;; Whistle Rule Edit Mode

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
  `(;; Comments
    ("^\\s-*#.*$" . font-lock-comment-face)
    ;; Protocol operators
    (,(regexp-opt whistle-protocols 'symbols) . font-lock-keyword-face)
    ;; URLs and domains
    ("\\(https?://\\|wss?://\\)[^ \t\n]+" . font-lock-string-face)
    ;; Pattern matching operators
    ("\\^\\|\\$\\|\\*\\|?" . font-lock-builtin-face)
    ;; File paths (local files)
    ("{[^}]+}" . font-lock-variable-name-face)
    ;; Variable references
    ("\\$\\w+" . font-lock-variable-name-face)
    ;; IP addresses
    ("\\b\\([0-9]\\{1,3\\}\\.\\)\\{3\\}[0-9]\\{1,3\\}\\b" . font-lock-constant-face)
    ;; Ports
    (":[0-9]+" . font-lock-constant-face))
  "Font lock keywords for whistle rules.")

(defvar whistle-rule-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'whistle-rules-save)
    (define-key map (kbd "C-c C-a") #'whistle-rules-select)
    (define-key map (kbd "C-c C-k") #'whistle-rules-edit-cancel)
    (define-key map (kbd "C-c C-t") #'whistle-rules-insert-template)
    map)
  "Keymap for `whistle-rule-edit-mode'.")

(define-derived-mode whistle-rule-edit-mode prog-mode "Whistle-Rule"
  "Major mode for editing whistle rules.

\\{whistle-rule-edit-mode-map}"
  (setq-local comment-start "#")
  (setq-local comment-start-skip "#+\\s-*")
  (setq-local font-lock-defaults '(whistle-font-lock-keywords))
  (font-lock-ensure))

(defun whistle-rules-save ()
  "Save the current rule to whistle server."
  (interactive)
  (unless whistle-rules--current
    (user-error "No rule selected"))
  (let ((content (buffer-string)))
    (message "Saving rule: %s..." whistle-rules--current)
    (whistle--http-post
     "/cgi-bin/rules/update"
     `(("name" . ,whistle-rules--current)
       ("rules" . ,content))
     (lambda (_)
       (set-buffer-modified-p nil)
       (message "Saved rule: %s" whistle-rules--current))
     (lambda (err)
       (message "Failed to save rule: %s" err)))))

(defun whistle-rules-select ()
  "Activate the current rule."
  (interactive)
  (let ((name whistle-rules--current))
    (unless name
      (user-error "No rule selected"))
    (message "Activating rule: %s..." name)
    (whistle--http-post
     "/cgi-bin/rules/select"
     `(("name" . ,name))
     (lambda (_)
       (message "Activated rule: %s" name))
     (lambda (err)
       (message "Failed to activate rule: %s" err)))))

(defun whistle-rules-edit-cancel ()
  "Cancel editing and close the buffer."
  (interactive)
  (when (or (not (buffer-modified-p))
            (yes-or-no-p "Buffer modified, close anyway? "))
    (kill-buffer)))

(defun whistle-rules-insert-template ()
  "Insert a rule template at point."
  (interactive)
  (let ((templates
         '(("Proxy" . "# Proxy request\npattern proxy://host:port")
           ("Host mapping" . "# Map domain to IP\npattern host://ip")
           ("Mock data" . "# Mock with local file\npattern file://{path/to/file}")
           ("CORS" . "# Enable CORS\npattern resCors://")
           ("Delay" . "# Add delay\npattern resDelay://1000")
           ("Header" . "# Add header\npattern resHeaders://{header-name: value}")
           ("Redirect" . "# Redirect\npattern redirect://new-url")
           ("Status code" . "# Change status\npattern statusCode://404"))))
    (let ((choice (completing-read "Template: " (mapcar #'car templates) nil t)))
      (when choice
        (insert (cdr (assoc choice templates)) "\n")))))

;;; Values Management

(defvar whistle-values--filter-string ""
  "Current filter string for values list.")

(define-derived-mode whistle-values-list-mode tabulated-list-mode "Whistle-Values"
  "Major mode for managing Whistle proxy values.

\\{whistle-values-list-mode-map}"
  (setq tabulated-list-format [("Name" 40 t)
                               ("Type" 10 t)
                               ("Size" 10 t)])
  (setq tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook #'whistle-values-refresh nil t)
  (tabulated-list-init-header))

(defun whistle-values-refresh ()
  "Refresh the values list from whistle server."
  (interactive)
  (message "Fetching values from %s..." (whistle--get-base-url))
  (whistle--http-get "/cgi-bin/values/list"
                     (lambda (data)
                       (setq whistle-values--data (alist-get 'list data))
                       (whistle-values--update-list)
                       (message "Values refreshed successfully"))
                     (lambda (err)
                       (message "Failed to refresh values: %s" err))))

(defun whistle-values--update-list ()
  "Update the tabulated list entries based on current data and filter."
  (setq tabulated-list-entries
        (cl-remove-if-not
         (lambda (entry)
           (or (string-empty-p whistle-values--filter-string)
               (string-match-p whistle-values--filter-string (car entry))))
         (mapcar
          (lambda (item)
            (let ((name (alist-get 'name item))
                  (data (alist-get 'data item))
                  (type (whistle-values--guess-type data)))
              (list name
                    (vector
                     name
                     type
                     (format "%d B" (length (or data "")))))))
          whistle-values--data)))
  (tabulated-list-print t))

(defun whistle-values--guess-type (content)
  "Guess the type of value CONTENT."
  (cond
   ((string-match-p "^\\s-*{" content) "JSON")
   ((string-match-p "^\\s-*<" content) "HTML/XML")
   ((string-match-p "^[a-zA-Z0-9-]+:\\s-*" content) "Headers")
   (t "Text")))

(defun whistle-values-filter (pattern)
  "Filter values list by PATTERN."
  (interactive "sFilter values: ")
  (setq whistle-values--filter-string pattern)
  (whistle-values--update-list)
  (message (if (string-empty-p pattern)
               "Filter cleared"
             "Filtered by: %s") pattern))

(defun whistle-values-clear-filter ()
  "Clear the current filter."
  (interactive)
  (whistle-values-filter ""))

;;;###autoload
(defun whistle-values ()
  "Open the whistle values management buffer."
  (interactive)
  (let ((buf (get-buffer-create "*Whistle Values*")))
    (with-current-buffer buf
      (whistle-values-list-mode)
      (whistle-values-refresh))
    (switch-to-buffer buf)))

;;; Values Operations

(defun whistle-values-open ()
  "Open the selected value for editing."
  (interactive)
  (let* ((id (tabulated-list-get-id))
         (value (cl-find id whistle-values--data
                         :key (lambda (v) (alist-get 'name v))
                         :test #'string=)))
    (when value
      (setq whistle-values--current id)
      (let ((buf (get-buffer-create "*Whistle Value Content*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (or (alist-get 'data value) ""))
          (whistle-value-edit-mode)
          (set-buffer-modified-p nil))
        (switch-to-buffer buf)))))

(defun whistle-values-create (name)
  "Create a new value with NAME."
  (interactive "sNew value name: ")
  (when (string-empty-p name)
    (user-error "Value name cannot be empty"))
  (message "Creating value: %s..." name)
  (whistle--http-post
   "/cgi-bin/values/add"
   `(("name" . ,name)
     ("value" . ""))
   (lambda (_response)
     (message "Value created: %s" name)
     (when whistle-auto-refresh
       (whistle-values-refresh)))
   (lambda (err)
     (message "Failed to create value: %s" err))))

(defun whistle-values-delete ()
  "Delete the selected value."
  (interactive)
  (let ((name (tabulated-list-get-id)))
    (unless name
      (user-error "No value selected"))
    (when (or (not whistle-confirm-delete)
              (yes-or-no-p (format "Delete value '%s'? " name)))
      (message "Deleting value: %s..." name)
      (whistle--http-post
       "/cgi-bin/values/remove"
       `(("name" . ,name))
       (lambda (_response)
         (message "Value deleted: %s" name)
         (when whistle-auto-refresh
           (whistle-values-refresh)))
       (lambda (err)
         (message "Failed to delete value: %s" err))))))

(defun whistle-values-rename (new-name)
  "Rename the selected value to NEW-NAME."
  (interactive "sNew name: ")
  (let ((old-name (tabulated-list-get-id)))
    (unless old-name
      (user-error "No value selected"))
    (when (string-empty-p new-name)
      (user-error "New name cannot be empty"))
    (message "Renaming value from %s to %s..." old-name new-name)
    (whistle--http-post
     "/cgi-bin/values/rename"
     `(("name" . ,old-name)
       ("newName" . ,new-name))
     (lambda (_response)
       (message "Value renamed: %s -> %s" old-name new-name)
       (when whistle-auto-refresh
         (whistle-values-refresh)))
     (lambda (err)
       (message "Failed to rename value: %s" err)))))

;;; Values Edit Mode

(defvar whistle-value-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'whistle-values-save)
    (define-key map (kbd "C-c C-k") #'whistle-values-edit-cancel)
    (define-key map (kbd "C-c C-j") #'whistle-values-format-json)
    map)
  "Keymap for `whistle-value-edit-mode'.")

(define-derived-mode whistle-value-edit-mode text-mode "Whistle-Value"
  "Major mode for editing whistle values.

\\{whistle-value-edit-mode-map}")

(defun whistle-values-save ()
  "Save the current value to whistle server."
  (interactive)
  (unless whistle-values--current
    (user-error "No value selected"))
  (let ((content (buffer-string)))
    (message "Saving value: %s..." whistle-values--current)
    (whistle--http-post
     "/cgi-bin/values/update"
     `(("name" . ,whistle-values--current)
       ("value" . ,content))
     (lambda (_)
       (set-buffer-modified-p nil)
       (message "Saved value: %s" whistle-values--current))
     (lambda (err)
       (message "Failed to save value: %s" err)))))

(defun whistle-values-edit-cancel ()
  "Cancel editing and close the buffer."
  (interactive)
  (when (or (not (buffer-modified-p))
            (yes-or-no-p "Buffer modified, close anyway? "))
    (kill-buffer)))

(defun whistle-values-format-json ()
  "Format the current buffer as JSON."
  (interactive)
  (when (executable-find "python")
    (let ((content (buffer-string)))
      (condition-case err
          (with-temp-buffer
            (insert content)
            (shell-command-on-region
             (point-min) (point-max)
             "python -m json.tool"
             (current-buffer) t "*JSON Format Error*")
            (let ((formatted (buffer-string)))
              (with-current-buffer (get-buffer "*Whistle Value Content*")
                (erase-buffer)
                (insert formatted)
                (message "JSON formatted successfully"))))
        (error
         (message "Failed to format JSON: %s" err))))))

;;; Auto-completion

(defun whistle-completion-at-point ()
  "Completion function for whistle protocols."
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when bounds
      (list (car bounds)
            (cdr bounds)
            whistle-protocols
            :annotation-function (lambda (_) " <protocol>")
            :company-docsig (lambda (candidate)
                              (pcase candidate
                                ("host" "Map domain to IP")
                                ("proxy" "Proxy through specified server")
                                ("file" "Mock with local file")
                                ("statusCode" "Change HTTP status code")
                                ("redirect" "Redirect to another URL")
                                ("resCors" "Enable CORS")
                                ("resHeaders" "Add response headers")
                                ("reqHeaders" "Add request headers")
                                (_ "")))))))

(defun whistle-setup-completion ()
  "Setup completion for whistle mode."
  (add-hook 'completion-at-point-functions
            #'whistle-completion-at-point nil t))

(add-hook 'whistle-rule-edit-mode-hook #'whistle-setup-completion)

;;; Export/Import

(defun whistle-rules-export (file)
  "Export all rules to FILE in JSON format."
  (interactive "FExport rules to file: ")
  (unless whistle-rules--data
    (user-error "No rules data available. Refresh first."))
  (with-temp-file file
    (insert (json-encode whistle-rules--data)))
  (message "Rules exported to %s" file))

(defun whistle-rules-import (file)
  "Import rules from FILE.
Note: This requires manual setup on the whistle server."
  (interactive "fImport rules from file: ")
  (with-temp-buffer
    (insert-file-contents file)
    (let ((data (json-read)))
      (message "Imported %d rules. Use whistle web UI to apply them."
               (length data)))))

(defun whistle-values-export (file)
  "Export all values to FILE in JSON format."
  (interactive "FExport values to file: ")
  (unless whistle-values--data
    (user-error "No values data available. Refresh first."))
  (with-temp-file file
    (insert (json-encode whistle-values--data)))
  (message "Values exported to %s" file))

(defun whistle-values-import (file)
  "Import values from FILE.
Note: This requires manual setup on the whistle server."
  (interactive "fImport values from file: ")
  (with-temp-buffer
    (insert-file-contents file)
    (let ((data (json-read)))
      (message "Imported %d values. Use whistle web UI to apply them."
               (length data)))))

;;; Utility Functions

(defun whistle-open-web-ui ()
  "Open whistle web UI in browser."
  (interactive)
  (browse-url (whistle--get-base-url)))

(defun whistle-switch-instance ()
  "Switch between configured whistle instances."
  (interactive)
  (if (null whistle-instances)
      (message "No instances configured. Set `whistle-instances'.")
    (let* ((choices (mapcar (lambda (inst)
                              (cons (plist-get inst :name)
                                    (plist-get inst :url)))
                            whistle-instances))
           (choice (completing-read "Select instance: " choices nil t)))
      (setq whistle--current-instance (cdr (assoc choice choices)))
      (message "Switched to: %s (%s)" choice whistle--current-instance))))

;;;###autoload
(defun whistle ()
  "Main entry point for whistle.el.
Prompts user to choose between Rules and Values management."
  (interactive)
  (let ((choice (completing-read "Whistle: "
                                 '("Rules" "Values" "Web UI")
                                 nil t)))
    (pcase choice
      ("Rules" (whistle-rules))
      ("Values" (whistle-values))
      ("Web UI" (whistle-open-web-ui)))))

;;; Keybindings

;; Rules list mode
(define-key whistle-rules-list-mode-map (kbd "g") #'whistle-rules-refresh)
(define-key whistle-rules-list-mode-map (kbd "RET") #'whistle-rules-open)
(define-key whistle-rules-list-mode-map (kbd "c") #'whistle-rules-create)
(define-key whistle-rules-list-mode-map (kbd "d") #'whistle-rules-delete)
(define-key whistle-rules-list-mode-map (kbd "r") #'whistle-rules-rename)
(define-key whistle-rules-list-mode-map (kbd "t") #'whistle-rules-toggle)
(define-key whistle-rules-list-mode-map (kbd "SPC") #'whistle-rules-toggle)
(define-key whistle-rules-list-mode-map (kbd "/") #'whistle-rules-filter)
(define-key whistle-rules-list-mode-map (kbd "C-c C-c") #'whistle-rules-clear-filter)
(define-key whistle-rules-list-mode-map (kbd "E") #'whistle-rules-export)
(define-key whistle-rules-list-mode-map (kbd "I") #'whistle-rules-import)
(define-key whistle-rules-list-mode-map (kbd "w") #'whistle-open-web-ui)
(define-key whistle-rules-list-mode-map (kbd "s") #'whistle-switch-instance)
(define-key whistle-rules-list-mode-map (kbd "q") #'quit-window)

;; Values list mode
(define-key whistle-values-list-mode-map (kbd "g") #'whistle-values-refresh)
(define-key whistle-values-list-mode-map (kbd "RET") #'whistle-values-open)
(define-key whistle-values-list-mode-map (kbd "c") #'whistle-values-create)
(define-key whistle-values-list-mode-map (kbd "d") #'whistle-values-delete)
(define-key whistle-values-list-mode-map (kbd "r") #'whistle-values-rename)
(define-key whistle-values-list-mode-map (kbd "/") #'whistle-values-filter)
(define-key whistle-values-list-mode-map (kbd "C-c C-c") #'whistle-values-clear-filter)
(define-key whistle-values-list-mode-map (kbd "E") #'whistle-values-export)
(define-key whistle-values-list-mode-map (kbd "I") #'whistle-values-import)
(define-key whistle-values-list-mode-map (kbd "w") #'whistle-open-web-ui)
(define-key whistle-values-list-mode-map (kbd "s") #'whistle-switch-instance)
(define-key whistle-values-list-mode-map (kbd "q") #'quit-window)

(provide 'whistle)

;;; whistle.el ends here
