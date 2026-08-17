;;; chezmoi-autoload-test.el --- Autoload tests for chezmoi-mode -*- lexical-binding: t; no-native-compile: t; -*-

;;; Code:

(require 'ert)
(require 'loaddefs-gen)

(defvar chezmoi-auto-enable-mode)
(defvar chezmoi-mode)
(defvar chezmoi-root)

(defconst chezmoi-autoload-test--source-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory
     (expand-file-name (or load-file-name buffer-file-name)))))
  "Directory containing the chezmoi-mode sources under test.")

(ert-deftest chezmoi-autoload-configures-path-based-mode-activation ()
  "Generated autoloads should enable Chezmoi only for target-state sources."
  (should-not (featurep 'chezmoi-core))
  (let* ((root (make-temp-file "chezmoi-autoload-root" t))
         (source-file (expand-file-name "dot_zshrc" root))
         (data-file (expand-file-name
                     ".chezmoidata/packages/emacs.toml" root))
         (nested-ignore (expand-file-name
                         "dot_config/.chezmoiignore" root))
         (nested-data (expand-file-name
                       "dot_config/.chezmoidata.toml" root))
         (autoload-file
          (make-temp-file
           (expand-file-name ".chezmoi-mode-autoloads-"
                             chezmoi-autoload-test--source-directory)
           nil ".el"))
         (find-file-hook (remove #'chezmoi--mode-from-path find-file-hook))
         (chezmoi-root (file-name-as-directory root))
         (chezmoi-auto-enable-mode t)
         buffers)
    (unwind-protect
        (progn
          (loaddefs-generate chezmoi-autoload-test--source-directory
                             autoload-file nil nil nil t)
          (load autoload-file nil t)
          (dolist (command '(chezmoi-dired-add-marked-files
                             chezmoi-ediff
                             chezmoi-ediff-merge
                             chezmoi-magit-status
                             chezmoi-transient))
            (should (autoloadp (symbol-function command))))
          (dolist (command '(chezmoi-age-get-identity
                             chezmoi-age-get-recipients))
            (should-not (fboundp command)))
          (should-not (featurep 'chezmoi-age))
          (should (memq #'chezmoi--mode-from-path find-file-hook))
          (with-temp-file source-file)
          (make-directory (file-name-directory data-file) t)
          (with-temp-file data-file)
          (make-directory (file-name-directory nested-ignore) t)
          (with-temp-file nested-ignore)
          (with-temp-file nested-data)
          (dolist (case `((,source-file . t)
                          (,data-file . nil)
                          (,nested-ignore . nil)
                          (,nested-data . nil)))
            (let ((buffer (find-file-noselect (car case))))
              (push buffer buffers)
              (with-current-buffer buffer
                (should (eq (and chezmoi-mode t) (cdr case)))))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-file autoload-file)
      (delete-directory root t))))

(provide 'chezmoi-autoload-test)
;;; chezmoi-autoload-test.el ends here
