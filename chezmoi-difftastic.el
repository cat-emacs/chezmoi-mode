;;; chezmoi-difftastic.el --- Difftastic integration for chezmoi -*- lexical-binding: t -*-

;; Author: Harrison Pielke-Lombardo
;; Maintainer: Harrison Pielke-Lombardo
;; Homepage: https://github.com/cat-emacs/chezmoi-mode
;; Keywords: tools, vc, diff


;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.


;;; Commentary:

;; Provides a `difftastic' view of `chezmoi diff'.  Chezmoi's external diff
;; hook is configured in a temporary copy of its effective configuration, so
;; the user's regular configuration is not changed.

;;; Code:

(require 'chezmoi-mode)
(require 'json)

(defgroup chezmoi-difftastic nil
  "Difftastic integration for `chezmoi-mode'."
  :group 'chezmoi-mode-settings
  :group 'difftastic)

(defcustom chezmoi-difftastic-display "side-by-side-show-both"
  "Difft display layout used for `chezmoi diff'."
  :type '(choice (const :tag "Inline" "inline")
                 (const :tag "Side by side" "side-by-side")
                 (const :tag "Side by side, always two columns"
                        "side-by-side-show-both"))
  :group 'chezmoi-difftastic)

(defcustom chezmoi-difftastic-extra-arguments nil
  "Additional arguments passed to `difft' by `chezmoi diff'."
  :type '(repeat string)
  :group 'chezmoi-difftastic)

(defvar-local chezmoi-difftastic--config-file nil)
(put 'chezmoi-difftastic--config-file 'permanent-local t)

(defvar difftastic-executable "difft")
(defvar difftastic-difft-environment nil)
(defvar difftastic-display-buffer-function #'display-buffer)
(defvar difftastic-requested-window-width-function #'window-width)
(defvar difftastic-rerun-requested-window-width-function nil)

(declare-function difftastic--build-process-environment "difftastic" ())
(declare-function difftastic--run-command "difftastic" (buffer command &optional action))
(declare-function difftastic--run-command-filter "difftastic" (process string))
(declare-function difftastic-mode "difftastic" (&optional arg))

(defun chezmoi-difftastic--delete-config ()
  "Delete the temporary Chezmoi configuration for the current buffer."
  (when (and chezmoi-difftastic--config-file
             (file-exists-p chezmoi-difftastic--config-file))
    (delete-file chezmoi-difftastic--config-file))
  (setq chezmoi-difftastic--config-file nil))

(defun chezmoi-difftastic--config-file ()
  "Create a temporary effective Chezmoi configuration for `difft'."
  (let ((config-file (make-temp-file "chezmoi-difftastic-" nil ".json"))
        config
        success)
    (unwind-protect
        (progn
          (with-temp-buffer
            (let ((status
                   (chezmoi--locally
                    (call-process chezmoi-command nil t nil
                                  "dump-config" "--format=json" "--no-pager"))))
              (unless (zerop status)
                (user-error "Unable to read Chezmoi configuration"))
              (setq config
                    (json-parse-string
                     (buffer-string)
                     :object-type 'hash-table
                     :array-type 'list))))
          (let ((diff-config (or (gethash "diff" config)
                                 (make-hash-table :test #'equal))))
            (puthash "command" (executable-find difftastic-executable)
                     diff-config)
            (puthash "args"
                     (append
                      (list "--color" "always"
                            "--background"
                            (symbol-name (or (frame-parameter nil 'background-mode)
                                             'dark))
                            "--display" chezmoi-difftastic-display)
                      chezmoi-difftastic-extra-arguments)
                     diff-config)
            (puthash "pager" "\0" diff-config)
            (puthash "diff" diff-config config))
          (with-temp-file config-file
            (insert (json-encode config)))
          (setq success t)
          config-file)
      (unless success
        (ignore-errors (delete-file config-file))))))

(defun chezmoi-difftastic--command (config-file)
  "Return the Chezmoi command using CONFIG-FILE."
  (list chezmoi-command
        "--config" config-file
        "--config-format" "json"
        "diff"
        "--no-pager"))

(defun chezmoi-difftastic--set-result-state (command)
  "Set Difftastic result buffer state for COMMAND."
  (setq-local difftastic--metadata
              `((default-directory . ,default-directory)
                (git-command . ,command)
                (difftastic-args . nil)
                (difft-environment . ,difftastic-difft-environment)))
  (keymap-local-set "g" #'chezmoi-difftastic-rerun))

(defun chezmoi-difftastic-rerun ()
  "Rerun the current Chezmoi diff using the current window width."
  (interactive)
  (unless (and chezmoi-difftastic--config-file
               (file-exists-p chezmoi-difftastic--config-file))
    (user-error "The temporary Chezmoi configuration is unavailable"))
  (let* ((requested-width
          (funcall (or difftastic-rerun-requested-window-width-function
                       difftastic-requested-window-width-function)))
         (process-environment
          (cons (format "DFT_WIDTH=%d" requested-width)
                (difftastic--build-process-environment)))
         (command
          (chezmoi-difftastic--command chezmoi-difftastic--config-file))
         (buffer (current-buffer)))
    (difftastic--run-command
     buffer command
     (lambda ()
       (chezmoi-difftastic--set-result-state command)))))

(defun chezmoi-difftastic--run (config-file buffer command requested-width)
  "Run COMMAND in BUFFER using CONFIG-FILE and REQUESTED-WIDTH.
Return the process.  BUFFER owns CONFIG-FILE only after process creation."
  (let (process)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (chezmoi-difftastic--delete-config)
            (setq-local difftastic--metadata nil)
            (setq-local chezmoi-difftastic--config-file config-file)
            (add-hook 'kill-buffer-hook
                      #'chezmoi-difftastic--delete-config nil t))
          (setq process
                (difftastic--run-command
                 buffer command
                 (lambda ()
                   (chezmoi-difftastic--set-result-state command)
                   (funcall difftastic-display-buffer-function
                            buffer requested-width))))
          process)
      (unless process
        (with-current-buffer buffer
          (chezmoi-difftastic--delete-config))))))

;;;###autoload
(defun chezmoi-difftastic-diff ()
  "View `chezmoi diff' rendered by Difftastic.

The command uses a temporary copy of Chezmoi's effective configuration and
does not modify the user's Chezmoi configuration.  Press `g' in the resulting
buffer to rerun the diff."
  (interactive)
  (unless (require 'difftastic nil t)
    (user-error "Install the difftastic Emacs package first"))
  (unless (executable-find difftastic-executable)
    (user-error "Cannot find Difftastic executable: %s" difftastic-executable))
  (let ((config-file (chezmoi-difftastic--config-file))
        process)
    (unwind-protect
        (let* ((buffer (get-buffer-create "*chezmoi-difftastic-diff*"))
               (command (chezmoi-difftastic--command config-file))
               (requested-width
                (funcall difftastic-requested-window-width-function))
               (process-environment
                (cons (format "DFT_WIDTH=%d" requested-width)
                      (difftastic--build-process-environment))))
          (setq process
                (chezmoi-difftastic--run
                 config-file buffer command requested-width)))
      (unless process
        (ignore-errors (delete-file config-file))))))

(provide 'chezmoi-difftastic)

;;; chezmoi-difftastic.el ends here
