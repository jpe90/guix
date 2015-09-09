;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013, 2014, 2015 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2015 Mark H Weaver <mhw@netris.org>
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

(define-module (gnu services networking)
  #:use-module (gnu services)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages tor)
  #:use-module (gnu packages messaging)
  #:use-module (gnu packages ntp)
  #:use-module (gnu packages wicd)
  #:use-module (guix gexp)
  #:use-module (guix store)
  #:use-module (srfi srfi-26)
  #:export (%facebook-host-aliases
            static-networking-service
            dhcp-client-service
            %ntp-servers
            ntp-service
            tor-service
            bitlbee-service
            wicd-service))

;;; Commentary:
;;;
;;; Networking services.
;;;
;;; Code:

(define %facebook-host-aliases
  ;; This is the list of known Facebook hosts to be added to /etc/hosts if you
  ;; are to block it.
  "\
# Block Facebook IPv4.
127.0.0.1   www.facebook.com
127.0.0.1   facebook.com
127.0.0.1   login.facebook.com
127.0.0.1   www.login.facebook.com
127.0.0.1   fbcdn.net
127.0.0.1   www.fbcdn.net
127.0.0.1   fbcdn.com
127.0.0.1   www.fbcdn.com
127.0.0.1   static.ak.fbcdn.net
127.0.0.1   static.ak.connect.facebook.com
127.0.0.1   connect.facebook.net
127.0.0.1   www.connect.facebook.net
127.0.0.1   apps.facebook.com

# Block Facebook IPv6.
fe80::1%lo0 facebook.com
fe80::1%lo0 login.facebook.com
fe80::1%lo0 www.login.facebook.com
fe80::1%lo0 fbcdn.net
fe80::1%lo0 www.fbcdn.net
fe80::1%lo0 fbcdn.com
fe80::1%lo0 www.fbcdn.com
fe80::1%lo0 static.ak.fbcdn.net
fe80::1%lo0 static.ak.connect.facebook.com
fe80::1%lo0 connect.facebook.net
fe80::1%lo0 www.connect.facebook.net
fe80::1%lo0 apps.facebook.com\n")


(define* (static-networking-service interface ip
                                    #:key
                                    gateway
                                    (provision '(networking))
                                    (name-servers '())
                                    (net-tools net-tools))
  "Return a service that starts @var{interface} with address @var{ip}.  If
@var{gateway} is true, it must be a string specifying the default network
gateway."
  (define loopback?
    (memq 'loopback provision))

  ;; TODO: Eventually replace 'route' with bindings for the appropriate
  ;; ioctls.
  (service

   ;; Unless we're providing the loopback interface, wait for udev to be up
   ;; and running so that INTERFACE is actually usable.
   (requirement (if loopback? '() '(udev)))

   (documentation
    "Bring up the networking interface using a static IP address.")
   (provision provision)
   (start #~(lambda _
              ;; Return #t if successfully started.
              (let* ((addr     (inet-pton AF_INET #$ip))
                     (sockaddr (make-socket-address AF_INET addr 0)))
                (configure-network-interface #$interface sockaddr
                                             (logior IFF_UP
                                                     #$(if loopback?
                                                           #~IFF_LOOPBACK
                                                           0))))
              #$(if gateway
                    #~(zero? (system* (string-append #$net-tools
                                                     "/sbin/route")
                                      "add" "-net" "default"
                                      "gw" #$gateway))
                    #t)
              #$(if (pair? name-servers)
                    #~(call-with-output-file "/etc/resolv.conf"
                        (lambda (port)
                          (display
                           "# Generated by 'static-networking-service'.\n"
                           port)
                          (for-each (lambda (server)
                                      (format port "nameserver ~a~%"
                                              server))
                                    '#$name-servers)))
                    #t)))
   (stop #~(lambda _
             ;; Return #f is successfully stopped.
             (let ((sock (socket AF_INET SOCK_STREAM 0)))
               (set-network-interface-flags sock #$interface 0)
               (close-port sock))
             (not #$(if gateway
                        #~(system* (string-append #$net-tools
                                                  "/sbin/route")
                                   "del" "-net" "default")
                        #t))))
   (respawn? #f)))

(define* (dhcp-client-service #:key (dhcp isc-dhcp))
  "Return a service that runs @var{dhcp}, a Dynamic Host Configuration
Protocol (DHCP) client, on all the non-loopback network interfaces."

  (define dhclient
    #~(string-append #$dhcp "/sbin/dhclient"))

  (define pid-file
    "/var/run/dhclient.pid")

  (service
   (documentation "Set up networking via DHCP.")
   (requirement '(user-processes udev))

   ;; XXX: Running with '-nw' ("no wait") avoids blocking for a minute when
   ;; networking is unavailable, but also means that the interface is not up
   ;; yet when 'start' completes.  To wait for the interface to be ready, one
   ;; should instead monitor udev events.
   (provision '(networking))

   (start #~(lambda _
              ;; When invoked without any arguments, 'dhclient' discovers all
              ;; non-loopback interfaces *that are up*.  However, the relevant
              ;; interfaces are typically down at this point.  Thus we perform
              ;; our own interface discovery here.
              (define valid?
                (negate loopback-network-interface?))
              (define ifaces
                (filter valid? (all-network-interface-names)))

              ;; XXX: Make sure the interfaces are up so that 'dhclient' can
              ;; actually send/receive over them.
              (for-each set-network-interface-up ifaces)

              (false-if-exception (delete-file #$pid-file))
              (let ((pid (fork+exec-command
                          (cons* #$dhclient "-nw"
                                 "-pf" #$pid-file ifaces))))
                (and (zero? (cdr (waitpid pid)))
                     (let loop ()
                       (catch 'system-error
                         (lambda ()
                           (call-with-input-file #$pid-file read))
                         (lambda args
                           ;; 'dhclient' returned before PID-FILE was created,
                           ;; so try again.
                           (let ((errno (system-error-errno args)))
                             (if (= ENOENT errno)
                                 (begin
                                   (sleep 1)
                                   (loop))
                                 (apply throw args))))))))))
   (stop #~(make-kill-destructor))))

(define %ntp-servers
  ;; Default set of NTP servers.
  '("0.pool.ntp.org"
    "1.pool.ntp.org"
    "2.pool.ntp.org"))

(define* (ntp-service #:key (ntp ntp)
                      (servers %ntp-servers))
  "Return a service that runs the daemon from @var{ntp}, the
@uref{http://www.ntp.org, Network Time Protocol package}.  The daemon will
keep the system clock synchronized with that of @var{servers}."
  ;; TODO: Add authentication support.

  (define config
    (string-append "driftfile /var/run/ntp.drift\n"
                   (string-join (map (cut string-append "server " <>)
                                     servers)
                                "\n")
                   "
# Disable status queries as a workaround for CVE-2013-5211:
# <http://support.ntp.org/bin/view/Main/SecurityNotice#DRDoS_Amplification_Attack_using>.
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery

# Yet, allow use of the local 'ntpq'.
restrict 127.0.0.1
restrict -6 ::1\n"))

  (let ((ntpd.conf (plain-file "ntpd.conf" config)))
    (service
     (provision '(ntpd))
     (documentation "Run the Network Time Protocol (NTP) daemon.")
     (requirement '(user-processes networking))
     (start #~(make-forkexec-constructor
               (list (string-append #$ntp "/bin/ntpd") "-n"
                     "-c" #$ntpd.conf
                     "-u" "ntpd")))
     (stop #~(make-kill-destructor))
     (user-accounts (list (user-account
                           (name "ntpd")
                           (group "nogroup")
                           (system? #t)
                           (comment "NTP daemon user")
                           (home-directory "/var/empty")
                           (shell
                            #~(string-append #$shadow "/sbin/nologin"))))))))

(define* (tor-service #:key (tor tor))
  "Return a service to run the @uref{https://torproject.org,Tor} daemon.

The daemon runs with the default settings (in particular the default exit
policy) as the @code{tor} unprivileged user."
  (let ((torrc (plain-file "torrc" "User tor\n")))
    (service
     (provision '(tor))

     ;; Tor needs at least one network interface to be up, hence the
     ;; dependency on 'loopback'.
     (requirement '(user-processes loopback))

     (start #~(make-forkexec-constructor
               (list (string-append #$tor "/bin/tor") "-f" #$torrc)))
     (stop #~(make-kill-destructor))

     (user-groups   (list (user-group
                           (name "tor")
                           (system? #t))))
     (user-accounts (list (user-account
                           (name "tor")
                           (group "tor")
                           (system? #t)
                           (comment "Tor daemon user")
                           (home-directory "/var/empty")
                           (shell
                            #~(string-append #$shadow "/sbin/nologin")))))

     (documentation "Run the Tor anonymous network overlay."))))

(define* (bitlbee-service #:key (bitlbee bitlbee)
                          (interface "127.0.0.1") (port 6667)
                          (extra-settings ""))
  "Return a service that runs @url{http://bitlbee.org,BitlBee}, a daemon that
acts as a gateway between IRC and chat networks.

The daemon will listen to the interface corresponding to the IP address
specified in @var{interface}, on @var{port}.  @code{127.0.0.1} means that only
local clients can connect, whereas @code{0.0.0.0} means that connections can
come from any networking interface.

In addition, @var{extra-settings} specifies a string to append to the
configuration file."
  (let ((conf (plain-file "bitlbee.conf"
                          (string-append "
  [settings]
  User = bitlbee
  ConfigDir = /var/lib/bitlbee
  DaemonInterface = " interface "
  DaemonPort = " (number->string port) "
" extra-settings))))
    (service
     (provision '(bitlbee))
     (requirement '(user-processes loopback))
     (activate #~(begin
                   (use-modules (guix build utils))

                   ;; This directory is used to store OTR data.
                   (mkdir-p "/var/lib/bitlbee")
                   (let ((user (getpwnam "bitlbee")))
                     (chown "/var/lib/bitlbee"
                            (passwd:uid user) (passwd:gid user)))))
     (start #~(make-forkexec-constructor
               (list (string-append #$bitlbee "/sbin/bitlbee")
                     "-n" "-F" "-u" "bitlbee" "-c" #$conf)))
     (stop  #~(make-kill-destructor))
     (user-groups   (list (user-group (name "bitlbee") (system? #t))))
     (user-accounts (list (user-account
                           (name "bitlbee")
                           (group "bitlbee")
                           (system? #t)
                           (comment "BitlBee daemon user")
                           (home-directory "/var/empty")
                           (shell #~(string-append #$shadow
                                                   "/sbin/nologin"))))))))

(define* (wicd-service #:key (wicd wicd))
  "Return a service that runs @url{https://launchpad.net/wicd,Wicd}, a network
manager that aims to simplify wired and wireless networking."
  (service
   (documentation "Run the Wicd network manager.")
   (provision '(networking))
   (requirement '(user-processes dbus-system loopback))
   (start #~(make-forkexec-constructor
             (list (string-append #$wicd "/sbin/wicd")
                   "--no-daemon")))
   (stop #~(make-kill-destructor))
   (activate
    #~(begin
        (use-modules (guix build utils))
        (mkdir-p "/etc/wicd")
        (let ((file-name "/etc/wicd/dhclient.conf.template.default"))
          (unless (file-exists? file-name)
            (copy-file (string-append #$wicd file-name)
                       file-name)))))))

;;; networking.scm ends here
