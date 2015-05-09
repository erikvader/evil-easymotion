;;; evil-easymotion.el --- A port of vim's easymotion to emacs

;; Copyright (C) 2014 PythonNut

;; Author: PythonNut <pythonnut@pythonnut.com>
;; Keywords: convenience, evil
;; Version: 20141205
;; URL: https://github.com/pythonnut/evil-easymotion.el
;; Package-Requires: ((emacs "24") (cl-lib "0.5") (avy "20150508.1418"))

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; This is a clone of the popular easymotion package for vim, which
;; describes itself in these terms:

;; > EasyMotion provides a much simpler way to use some motions in vim.
;; > It takes the <number> out of <number>w or <number>f{char} by
;; > highlighting all possible choices and allowing you to press one key
;; > to jump directly to the target.

;; If you're having trouble picturing this, please visit the github repo
;; for a screencast.

;; Usage/status
;; ============

;; evil-easymotion, rather unsurprisingly can use evil. However, you don't
;; _need_ evil to use it. evil-easymotion can happily define motions for
;; regular emacs commands. With that said, evil is recommended, not
;; least because it's awesome.

;; Currently most motions are supported, and it's easy to define your own easymotions.

;;   (evilem-define (kbd "SPC w") 'evil-forward-word-begin)

;; To define easymotions for all motions that evil defines by default, add

;;   (evilem-default-keybindings "SPC")

;; This binds all motions under the prefix `SPC` in `evil-motion-state-map`. This is not done by default for motions defined manually. You will need to supply the prefix.

;; More advanced use-cases are detailed in the github README.

;;; Code:
(require 'cl-lib)
(require 'noflet)

(defgroup evilem nil
  "Emulate vim-easymotion"
  :group 'convenience
  :prefix "evilem-")

(defcustom evilem-keys (string-to-list "zxbqpwomceirukdlsvnahgyt5647382910fj")
  "Value of `avy-keys' to set during motions. Set to nil to leave unchanged."
  :type '(repeat :tag "Keys" character))

(defcustom evilem-style 'at-full
  "Value of `avy-style' to set during motions. Set to nil to leave unchanged."
  :type '(choice
           (const :tag "Pre" pre)
           (const :tag "At" at)
           (const :tag "At Full" at-full)
           (const :tag "Post" post)
           (const :tag "Default" nil)))

;; macro helper, from evil source
(defun evilem-unquote (exp)
  "Return EXP unquoted."
  (while (eq (car-safe exp) 'quote)
    (setq exp (cadr exp)))
  exp)

(defun evilem-generic (collector)
  "avy-jump to the set of points generated by collector"
  (require 'avy-jump)
  (let* ((avy-all-windows nil)
          (candidate
            (avy--process
              (mapcar
                (lambda (pt)
                  (cons (cons pt pt)
                    (get-buffer-window)))
                collector)
              (avy--style-fn (or evilem-style avy-style)))))
    (avy--goto candidate)))

(defun evilem-collect (func)
  "Repeatedly execute func, and collect the cursor positions into a list"
  (let ((points)
         (duplicate-count 0)

         ;; make sure the motion doesn't move the window
         (scroll-conservatively 101)
         (smooth-scroll-margin 0)
         (scroll-margin 0))
    (save-excursion
      (while
        (progn
          (with-demoted-errors
            (setq
              this-command func
              last-command func)
            (call-interactively func))
          (if (memq (point) points)
            (setq duplicate-count (1+ duplicate-count))
            (when (not (eobp))
              (push (point) points)
              (setq duplicate-count 0)))
          (and
            (>= (point) (window-start))
            (<= (point) (window-end))
            (not (eobp))
            (not (bobp))
            (< duplicate-count 10))))
      (nreverse points))))

(defmacro evilem-make-motion (name func &optional pre-hook post-hook vars)
  "Automatically define an evil easymotion for `func', naming it `name'"
  `(evil-define-motion ,name (count)
     (evil-without-repeat
       ,(when pre-hook `(funcall ,pre-hook))
       (let ,(append '((old-point (point))
                        (avy-keys (or evilem-keys avy-keys)))
               vars)
         (evilem-generic (evilem-collect ,func))
         ;; handle the off-by-one case
         (when (< (point) old-point)
           (setq evil-this-type 'exclusive)))
       ,(when post-hook `(funcall ,post-hook)))))

(defmacro evilem-make-motion-plain (name func &optional pre-hook post-hook vars)
  "Automatically define a plain easymotion for `func', naming it `name'"
  `(defun ,name ()
     (interactive)
     ,(when pre-hook `(funcall ,pre-hook))
     (let ,(append '((avy-keys (or evilem-keys avy-keys))) vars)
       (evilem-generic (evilem-collect ,func)))
     ,(when post-hook `(funcall ,post-hook))))

(defmacro evilem-create (motion &optional pre-hook post-hook vars)
  `(evilem-make-motion
     ,(make-symbol
        (concat "evilem-motion-" (symbol-name (evilem-unquote motion))))
     ,motion ,pre-hook ,post-hook ,vars))

(defmacro evilem-create-plain (motion &optional pre-hook post-hook vars)
  `(evilem-make-motion-plain
     ,(make-symbol
        (concat "evilem-motion-" (symbol-name (evilem-unquote motion))))
     ,motion ,pre-hook ,post-hook ,vars))

;;;###autoload
(defmacro evilem-define (key motion &optional pre-hook post-hook vars)
  "Automatically create and bind an evil motion"
  `(define-key evil-motion-state-map ,key
     (evilem-create ,motion ,pre-hook ,post-hook ,vars)))

;;;###autoload
(defmacro evilem-define-plain (key motion &optional pre-hook post-hook vars)
  "Automatically create and bind a plain emacs motion"
  `(global-set-key ,key
     (evilem-create-plain ,motion ,pre-hook ,post-hook ,vars)))

;;;###autoload
(defun evilem-default-keybindings (prefix)
  "Define easymotions for all motions evil defines by default"
  (define-key evil-motion-state-map (kbd prefix) 'nil)
  (with-no-warnings
    (evilem-define (kbd (concat prefix " w")) 'evil-forward-word-begin)
    (evilem-define (kbd (concat prefix " W")) 'evil-forward-WORD-begin)
    (evilem-define (kbd (concat prefix " e")) 'evil-forward-word-end)
    (evilem-define (kbd (concat prefix " E")) 'evil-forward-WORD-end)
    (evilem-define (kbd (concat prefix " b")) 'evil-backward-word-begin)
    (evilem-define (kbd (concat prefix " B")) 'evil-backward-WORD-begin)
    (evilem-define (kbd (concat prefix " ge")) 'evil-backward-word-end)
    (evilem-define (kbd (concat prefix " gE")) 'evil-backward-WORD-end)

    (evilem-define (kbd (concat prefix " j")) 'next-line
      nil nil ((temporary-goal-column (current-column))
                (line-move-visual nil)))

    (evilem-define (kbd (concat prefix " k")) 'previous-line
      nil nil ((temporary-goal-column (current-column))
                (line-move-visual nil)))

    (evilem-define (kbd (concat prefix " g j")) 'next-line
      nil nil ((temporary-goal-column (current-column))
                (line-move-visual t)))

    (evilem-define (kbd (concat prefix " g k")) 'previous-line
      nil nil ((temporary-goal-column (current-column))
                (line-move-visual t)))

    (evilem-define (kbd (concat prefix " t")) 'evil-repeat-find-char
      (lambda ()
        (save-excursion
          (let ((evil-cross-lines t))
            (call-interactively 'evil-find-char-to))))
      nil
      ((evil-cross-lines t)))

    (evilem-define (kbd (concat prefix " T")) 'evil-repeat-find-char
      (lambda ()
        (save-excursion
          (let ((evil-cross-lines t))
            (call-interactively 'evil-find-char-to-backward))))
      nil
      ((evil-cross-lines t)))

    (evilem-define (kbd (concat prefix " f")) 'evil-repeat-find-char
      (lambda ()
        (save-excursion
          (let ((evil-cross-lines t))
            (call-interactively 'evil-find-char))))
      nil
      ((evil-cross-lines t)))

    (evilem-define (kbd (concat prefix " F")) 'evil-repeat-find-char
      (lambda ()
        (save-excursion
          (let ((evil-cross-lines t))
            (call-interactively 'evil-find-char-backward))))
      nil
      ((evil-cross-lines t)))

    (evilem-define (kbd (concat prefix " [[")) 'evil-backward-section-begin)
    (evilem-define (kbd (concat prefix " []")) 'evil-backward-section-end)
    (evilem-define (kbd (concat prefix " ]]")) 'evil-forward-section-begin)
    (evilem-define (kbd (concat prefix " ][")) 'evil-forward-section-end)

    (evilem-define (kbd (concat prefix " (")) 'evil-forward-sentence)
    (evilem-define (kbd (concat prefix " )")) 'evil-backward-sentence)

    (evilem-define (kbd (concat prefix " n")) 'evil-search-next)
    (evilem-define (kbd (concat prefix " N")) 'evil-search-previous)
    (evilem-define (kbd (concat prefix " *")) 'evil-search-word-forward)
    (evilem-define (kbd (concat prefix " #")) 'evil-search-word-backward)

    (evilem-define (kbd (concat prefix " -")) 'evil-previous-line-first-non-blank)
    (evilem-define (kbd (concat prefix " +")) 'evil-next-line-first-non-blank)))

(provide 'evil-easymotion)
;;; evil-easymotion.el ends here
