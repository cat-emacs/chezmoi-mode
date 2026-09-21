;;; chezmoi-difftastic-test.el --- Tests for chezmoi-difftastic -*- lexical-binding: t; no-native-compile: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'chezmoi-difftastic)

(ert-deftest chezmoi-difftastic-config-survives-major-mode-change ()
  (let ((config-file (make-temp-file "chezmoi-difftastic-test-"))
        (buffer (generate-new-buffer " *chezmoi-difftastic-test*")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq-local chezmoi-difftastic--config-file config-file)
            (add-hook 'kill-buffer-hook
                      #'chezmoi-difftastic--delete-config nil t)
            (fundamental-mode)
            (should (equal chezmoi-difftastic--config-file config-file)))
          (kill-buffer buffer)
          (should-not (file-exists-p config-file)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (when (file-exists-p config-file)
        (delete-file config-file)))))

(ert-deftest chezmoi-difftastic-cleans-config-when-process-start-fails ()
  (let ((config-file (make-temp-file "chezmoi-difftastic-test-"))
        (buffer (generate-new-buffer " *chezmoi-difftastic-test*")))
    (unwind-protect
        (cl-letf (((symbol-function 'difftastic--run-command)
                   (lambda (&rest _) (error "process failed"))))
          (should-error
           (chezmoi-difftastic--run
            config-file buffer '("chezmoi" "diff") 80)
           :type 'error)
          (should-not (file-exists-p config-file)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (when (file-exists-p config-file)
        (delete-file config-file)))))

(ert-deftest chezmoi-difftastic-result-retains-config-and-local-rerun ()
  (let ((config-file (make-temp-file "chezmoi-difftastic-test-"))
        (buffer (generate-new-buffer " *chezmoi-difftastic-test*"))
        (difftastic-display-buffer-function #'ignore)
        action)
    (unwind-protect
        (cl-letf (((symbol-function 'difftastic--run-command)
                   (lambda (_buffer _command callback)
                     (setq action callback)
                     'process)))
          (should
           (eq (chezmoi-difftastic--run
                config-file buffer '("chezmoi" "diff") 80)
               'process))
          (with-current-buffer buffer
            ;; Difftastic switches major mode before invoking its callback.
            (fundamental-mode)
            (funcall action)
            (should (equal chezmoi-difftastic--config-file config-file))
            (should (eq (key-binding (kbd "g"))
                        #'chezmoi-difftastic-rerun)))
          (kill-buffer buffer)
          (should-not (file-exists-p config-file)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (when (file-exists-p config-file)
        (delete-file config-file)))))

(ert-deftest chezmoi-difftastic-rerun-uses-current-width ()
  (let ((config-file (make-temp-file "chezmoi-difftastic-test-"))
        (buffer (generate-new-buffer " *chezmoi-difftastic-test*"))
        (difftastic-rerun-requested-window-width-function (lambda () 123))
        (difftastic-requested-window-width-function (lambda () 80))
        captured-command
        captured-environment)
    (unwind-protect
        (with-current-buffer buffer
          (setq-local chezmoi-difftastic--config-file config-file)
          (cl-letf (((symbol-function 'difftastic--build-process-environment)
                     (lambda () '("BASE=value")))
                    ((symbol-function 'difftastic--run-command)
                     (lambda (_buffer command _action)
                       (setq captured-command command
                             captured-environment process-environment)
                       'process)))
            (chezmoi-difftastic-rerun)
            (should (equal captured-command
                           (chezmoi-difftastic--command config-file)))
            (should (member "DFT_WIDTH=123" captured-environment))
            (should (member "BASE=value" captured-environment))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (when (file-exists-p config-file)
        (delete-file config-file)))))

(provide 'chezmoi-difftastic-test)
;;; chezmoi-difftastic-test.el ends here
