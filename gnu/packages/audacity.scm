;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2015 Taylan Ulrich Bayırlı/Kammer <taylanbayirli@gmail.com>
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

(define-module (gnu packages audacity)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages)
  #:use-module (gnu packages audio)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages base)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages mp3)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages python)
  #:use-module (gnu packages xiph)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages video)
  #:use-module (gnu packages wxwidgets))

(define-public audacity
  (package
    (name "audacity")
    (version "2.1.3")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://github.com/audacity/audacity/archive"
                           "/Audacity-" version ".tar.gz"))
       (sha256
        (base32 "11mx7gb4dbqrgfp7hm0154x3m76ddnmhf2675q5zkxn7jc5qfc6b"))))
    (build-system gnu-build-system)
    (inputs
     ;; TODO: Add portSMF and libwidgetextra once they're packaged.  In-tree
     ;; versions shipping with Audacity are used for now.
     `(("wxwidgets" ,wxwidgets-gtk2)
       ("gtk" ,gtk+-2)
       ("alsa-lib" ,alsa-lib)
       ("jack" ,jack-1)
       ("expat" ,expat)
       ("ffmpeg" ,ffmpeg)
       ("lame" ,lame)
       ("flac" ,flac)
       ("libid3tag" ,libid3tag)
       ("libmad" ,libmad)
       ("libsbsms" ,libsbsms)
       ("libsndfile" ,libsndfile)
       ("soundtouch" ,soundtouch)
       ("soxr" ,soxr)                   ;replaces libsamplerate
       ("twolame" ,twolame)
       ("vamp" ,vamp)
       ("libvorbis" ,libvorbis)
       ("lv2" ,lv2)
       ("lilv" ,lilv)
       ("portaudio" ,portaudio)))
    (native-inputs
     `(("autoconf" ,autoconf)
       ("automake" ,automake)
       ("gettext" ,gettext-minimal)     ;for msgfmt
       ("libtool" ,libtool)
       ("pkg-config" ,pkg-config)
       ("python" ,python-2)
       ("which" ,which)))
    (arguments
     '(#:configure-flags
       (let ((libid3tag (assoc-ref %build-inputs "libid3tag"))
             (libmad (assoc-ref %build-inputs "libmad")))
         (list
          ;; Loading FFmpeg dynamically is problematic.
          "--disable-dynamic-loading"
          ;; libid3tag and libmad provide no .pc files, so pkg-config fails to
          ;; find them.  Force their inclusion.
          (string-append "ID3TAG_CFLAGS=-I" libid3tag "/include")
          (string-append "ID3TAG_LIBS=-L" libid3tag "/lib -lid3tag -lz")
          (string-append "LIBMAD_CFLAGS=-I" libmad "/include")
          (string-append "LIBMAD_LIBS=-L" libmad "/lib -lmad")))
       #:phases
       (modify-phases %standard-phases
         ;; FFmpeg is only detected if autoreconf runs.
         (add-before 'configure 'autoreconf
           (lambda _
             (zero? (system* "autoreconf" "-vfi")))))
       ;; The test suite is not "well exercised" according to the developers,
       ;; and fails with various errors.  See
       ;; <http://sourceforge.net/p/audacity/mailman/message/33524292/>.
       #:tests? #f))
    (home-page "http://audacity.sourceforge.net/")
    (synopsis "Software for recording and editing sounds")
    (description
     "Audacity is a multi-track audio editor designed for recording, playing
and editing digital audio.  It features digital effects and spectrum analysis
tools.")
    (license license:gpl2+)))
