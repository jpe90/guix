;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2022 Jon Eskin <eskinjp@gmail.com>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages qbe)
  #:use-module (guix packages)
  #:use-module (guix build-system gnu)
  #:use-module (guix git-download)
  #:use-module (guix licenses))

(define-public qbe
  (package
    (name "qbe")
    (version "2022.04.11")
    (source (origin
              (method git-fetch)
              (uri
               (git-reference
                (url "git://c9x.me/qbe.git")
                (commit "2caa26e388b1c904d2f12fb09f84df7e761d8331")))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "1gv03ym0gqrl4wkbhysa82025xwrkr1fg44z814b6vnggwlqgljc"))))
    (build-system gnu-build-system)
    (arguments
     '(#:make-flags (list (string-append "PREFIX=" (assoc-ref %outputs "out"))
                          "CC=gcc")
       #:phases (modify-phases %standard-phases
                  (delete 'configure)
                  (add-before 'check 'fix-cc
                    (lambda* (#:key inputs outputs #:allow-other-keys)
                      ;; fix test script overriding environment variable
                      (substitute* "tools/test.sh"
                        (("cc=\"cc -no-pie\"") "cc=\"gcc -no-pie\""))
                      #t)))))
    (synopsis "Lightweight compiler backend")
    (description
     "QBE aims to be a pure C embeddable backend that provides 70% of the
performance of advanced compilers in 10% of the code.")
    (home-page "https://c9x.me/compile/")
    (license expat)))
