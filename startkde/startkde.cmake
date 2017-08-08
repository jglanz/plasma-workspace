#!/bin/sh
#
#  DEFAULT Plasma STARTUP SCRIPT ( @PROJECT_VERSION@ )
#

# When the X server dies we get a HUP signal from xinit. We must ignore it
# because we still need to do some cleanup.
trap 'echo GOT SIGHUP' HUP

# Check if a Plasma session already is running and whether it's possible to connect to X
kcheckrunning
kcheckrunning_result=$?
if test $kcheckrunning_result -eq 0 ; then
	echo "Plasma seems to be already running on this display."
	xmessage -geometry 500x100 "Plasma seems to be already running on this display." > /dev/null 2>/dev/null
	exit 1
elif test $kcheckrunning_result -eq 2 ; then
	echo "\$DISPLAY is not set or cannot connect to the X server."
        exit 1
fi

# Boot sequence:
#
# kdeinit is used to fork off processes which improves memory usage
# and startup time.
#
# * kdeinit starts klauncher first.
# * Then kded is started. kded is responsible for keeping the sycoca
#   database up to date. When an up to date database is present it goes
#   into the background and the startup continues.
# * Then kdeinit starts kcminit. kcminit performs initialisation of
#   certain devices according to the user's settings
#
# * Then ksmserver is started which takes control of the rest of the startup sequence

# We need to create config folder so we can write startupconfigkeys
if [  ${XDG_CONFIG_HOME} ]; then
  configDir=$XDG_CONFIG_HOME;
else
  configDir=${HOME}/.config; #this is the default, http://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html
fi

mkdir -p $configDir

#This is basically setting defaults so we can use them with kstartupconfig5
cat >$configDir/startupconfigkeys <<EOF
kcminputrc Mouse cursorTheme 'breeze_cursors'
kcminputrc Mouse cursorSize ''
ksplashrc KSplash Theme Breeze
ksplashrc KSplash Engine KSplashQML
kdeglobals KScreen ScreenScaleFactors ''
kcmfonts General forceFontDPI 0
EOF

# preload the user's locale on first start
plasmalocalerc=$configDir/plasma-localerc
test -f $plasmalocalerc || {
cat >$plasmalocalerc <<EOF
[Formats]
LANG=$LANG
EOF
}

# export LC_* variables set by kcmshell5 formats into environment
# so it can be picked up by QLocale and friends.
exportformatssettings=$configDir/plasma-locale-settings.sh
test -f $exportformatssettings && {
    . $exportformatssettings
}

# Write a default kdeglobals file to set up the font
kdeglobalsfile=$configDir/kdeglobals
test -f $kdeglobalsfile || {
cat >$kdeglobalsfile <<EOF
[General]
XftAntialias=true
XftHintStyle=hintmedium
XftSubPixel=none
EOF
}

kstartupconfig5
returncode=$?
if test $returncode -ne 0; then
    xmessage -geometry 500x100 "kstartupconfig5 does not exist or fails. The error code is $returncode. Check your installation."
    exit 1
fi
[ -r $configDir/startupconfig ] && . $configDir/startupconfig

if [ "$kdeglobals_kscreen_screenscalefactors" ]; then
    export QT_SCREEN_SCALE_FACTORS="$kdeglobals_kscreen_screenscalefactors"
fi
#Manually disable auto scaling because we are scaling above
#otherwise apps that manually opt in for high DPI get auto scaled by the developer AND manually scaled by us
export QT_AUTO_SCREEN_SCALE_FACTOR=0

#Set the QtQuickControls style to our own: for QtQuickControls1
#it will fall back to Desktop, while it will use our own org.kde.desktop
#for QtQuickControlsStyle and Kirigami
export QT_QUICK_CONTROLS_STYLE=org.kde.desktop

# XCursor mouse theme needs to be applied here to work even for kded or ksmserver
if test -n "$kcminputrc_mouse_cursortheme" -o -n "$kcminputrc_mouse_cursorsize" ; then
    @EXPORT_XCURSOR_PATH@

    kapplymousetheme "$kcminputrc_mouse_cursortheme" "$kcminputrc_mouse_cursorsize"
    if test $? -eq 10; then
        XCURSOR_THEME=breeze_cursors
        export XCURSOR_THEME
    elif test -n "$kcminputrc_mouse_cursortheme"; then
        XCURSOR_THEME="$kcminputrc_mouse_cursortheme"
        export XCURSOR_THEME
    fi
    if test -n "$kcminputrc_mouse_cursorsize"; then
        XCURSOR_SIZE="$kcminputrc_mouse_cursorsize"
        export XCURSOR_SIZE
    fi
fi

if test "$kcmfonts_general_forcefontdpi" -ne 0; then
    xrdb -quiet -merge -nocpp <<EOF
Xft.dpi: $kcmfonts_general_forcefontdpi
EOF
fi

dl=$DESKTOP_LOCKED
unset DESKTOP_LOCKED # Don't want it in the environment

ksplash_pid=
if test -z "$dl"; then
  # the splashscreen and progress indicator
  case "$ksplashrc_ksplash_engine" in
    KSplashQML)
      ksplash_pid=`ksplashqml "${ksplashrc_ksplash_theme}" --pid`
      ;;
    None)
      ;;
    *)
      ;;
  esac
fi

# Source scripts found in <config locations>/plasma-workspace/env/*.sh
# (where <config locations> correspond to the system and user's configuration
# directories, as identified by Qt's qtpaths,  e.g.  $HOME/.config
# and /etc/xdg/ on Linux)
#
# This is where you can define environment variables that will be available to
# all KDE programs, so this is where you can run agents using e.g. eval `ssh-agent`
# or eval `gpg-agent --daemon`.
# Note: if you do that, you should also put "ssh-agent -k" as a shutdown script
#
# (see end of this file).
# For anything else (that doesn't set env vars, or that needs a window manager),
# better use the Autostart folder.

scriptpath=`qtpaths --locate-dirs GenericConfigLocation plasma-workspace | tr ':' '\n'`

# Add /env/ to the directory to locate the scripts to be sourced
for prefix in `echo $scriptpath`; do
  for file in "$prefix"/env/*.sh; do
    test -r "$file" && . "$file" || true
  done
done

# Activate the kde font directories.
#
# There are 4 directories that may be used for supplying fonts for KDE.
#
# There are two system directories. These belong to the administrator.
# There are two user directories, where the user may add her own fonts.
#
# The 'override' versions are for fonts that should come first in the list,
# i.e. if you have a font in your 'override' directory, it will be used in
# preference to any other.
#
# The preference order looks like this:
# user override, system override, X, user, system
#
# Where X is the original font database that was set up before this script
# runs.

usr_odir=$HOME/.fonts/kde-override
usr_fdir=$HOME/.fonts

if test -n "$KDEDIRS"; then
  kdedirs_first=`echo "$KDEDIRS"|sed -e 's/:.*//'`
  sys_odir=$kdedirs_first/share/fonts/override
  sys_fdir=$kdedirs_first/share/fonts
else
  sys_odir=$KDEDIR/share/fonts/override
  sys_fdir=$KDEDIR/share/fonts
fi

# We run mkfontdir on the user's font dirs (if we have permission) to pick
# up any new fonts they may have installed. If mkfontdir fails, we still
# add the user's dirs to the font path, as they might simply have been made
# read-only by the administrator, for whatever reason.

test -d "$sys_odir" && xset +fp "$sys_odir"
test -d "$usr_odir" && (mkfontdir "$usr_odir" ; xset +fp "$usr_odir")
test -d "$usr_fdir" && (mkfontdir "$usr_fdir" ; xset fp+ "$usr_fdir")
test -d "$sys_fdir" && xset fp+ "$sys_fdir"

# Ask X11 to rebuild its font list.
xset fp rehash

# Set a left cursor instead of the standard X11 "X" cursor, since I've heard
# from some users that they're confused and don't know what to do. This is
# especially necessary on slow machines, where starting KDE takes one or two
# minutes until anything appears on the screen.
#
# If the user has overwritten fonts, the cursor font may be different now
# so don't move this up.
#
xsetroot -cursor_name left_ptr

# Get Ghostscript to look into user's KDE fonts dir for additional Fontmap
if test -n "$GS_LIB" ; then
    GS_LIB=$usr_fdir:$GS_LIB
    export GS_LIB
else
    GS_LIB=$usr_fdir
    export GS_LIB
fi

echo 'startkde: Starting up...'  1>&2

# Make sure that the KDE prefix is first in XDG_DATA_DIRS and that it's set at all.
# The spec allows XDG_DATA_DIRS to be not set, but X session startup scripts tend
# to set it to a list of paths *not* including the KDE prefix if it's not /usr or
# /usr/local.
if test -z "$XDG_DATA_DIRS"; then
    XDG_DATA_DIRS="@CMAKE_INSTALL_PREFIX@/@SHARE_INSTALL_PREFIX@:/usr/share:/usr/local/share"
fi
export XDG_DATA_DIRS

# Mark that full KDE session is running (e.g. Konqueror preloading works only
# with full KDE running). The KDE_FULL_SESSION property can be detected by
# any X client connected to the same X session, even if not launched
# directly from the KDE session but e.g. using "ssh -X", kdesu. $KDE_FULL_SESSION
# however guarantees that the application is launched in the same environment
# like the KDE session and that e.g. KDE utilities/libraries are available.
# KDE_FULL_SESSION property is also only available since KDE 3.5.5.
# The matching tests are:
#   For $KDE_FULL_SESSION:
#     if test -n "$KDE_FULL_SESSION"; then ... whatever
#   For KDE_FULL_SESSION property:
#     xprop -root | grep "^KDE_FULL_SESSION" >/dev/null 2>/dev/null
#     if test $? -eq 0; then ... whatever
#
# Additionally there is (since KDE 3.5.7) $KDE_SESSION_UID with the uid
# of the user running the KDE session. It should be rarely needed (e.g.
# after sudo to prevent desktop-wide functionality in the new user's kded).
#
# Since KDE4 there is also KDE_SESSION_VERSION, containing the major version number.
# Note that this didn't exist in KDE3, which can be detected by its absense and
# the presence of KDE_FULL_SESSION.
#
KDE_FULL_SESSION=true
export KDE_FULL_SESSION
xprop -root -f KDE_FULL_SESSION 8t -set KDE_FULL_SESSION true

KDE_SESSION_VERSION=5
export KDE_SESSION_VERSION
xprop -root -f KDE_SESSION_VERSION 32c -set KDE_SESSION_VERSION 5

KDE_SESSION_UID=`id -ru`
export KDE_SESSION_UID

XDG_CURRENT_DESKTOP=KDE
export XDG_CURRENT_DESKTOP

# At this point all environment variables are set, let's send it to the DBus session server to update the activation environment
if which dbus-update-activation-environment >/dev/null 2>/dev/null ; then
    dbus-update-activation-environment --systemd --all
else
    @CMAKE_INSTALL_FULL_LIBEXECDIR@/ksyncdbusenv
fi
if test $? -ne 0; then
  # Startup error
  echo 'startkde: Could not sync environment to dbus.'  1>&2
  test -n "$ksplash_pid" && kill "$ksplash_pid" 2>/dev/null
  xmessage -geometry 500x100 "Could not sync environment to dbus."
  exit 1
fi

# We set LD_BIND_NOW to increase the efficiency of kdeinit.
# kdeinit unsets this variable before loading applications.
LD_BIND_NOW=true @CMAKE_INSTALL_FULL_LIBEXECDIR_KF5@/start_kdeinit_wrapper --kded +kcminit_startup
if test $? -ne 0; then
  # Startup error
  echo 'startkde: Could not start kdeinit5. Check your installation.'  1>&2
  test -n "$ksplash_pid" && kill "$ksplash_pid" 2>/dev/null
  xmessage -geometry 500x100 "Could not start kdeinit5. Check your installation."
  exit 1
fi

qdbus org.kde.KSplash /KSplash org.kde.KSplash.setStage kinit &

# finally, give the session control to the session manager
# see kdebase/ksmserver for the description of the rest of the startup sequence
# if the KDEWM environment variable has been set, then it will be used as KDE's
# window manager instead of kwin.
# if KDEWM is not set, ksmserver will ensure kwin is started.
# kwrapper5 is used to reduce startup time and memory usage
# kwrapper5 does not return useful error codes such as the exit code of ksmserver.
# We only check for 255 which means that the ksmserver process could not be
# started, any problems thereafter, e.g. ksmserver failing to initialize,
# will remain undetected.
test -n "$KDEWM" && KDEWM="--windowmanager $KDEWM"
# If the session should be locked from the start (locked autologin),
# lock now and do the rest of the KDE startup underneath the locker.
KSMSERVEROPTIONS=""
test -n "$dl" && KSMSERVEROPTIONS=" --lockscreen"
kwrapper5 @CMAKE_INSTALL_FULL_BINDIR@/ksmserver $KDEWM $KSMSERVEROPTIONS
if test $? -eq 255; then
  # Startup error
  echo 'startkde: Could not start ksmserver. Check your installation.'  1>&2
  test -n "$ksplash_pid" && kill "$ksplash_pid" 2>/dev/null
  xmessage -geometry 500x100 "Could not start ksmserver. Check your installation."
fi

#Anything after here is logout/shutdown

wait_drkonqi=`kreadconfig5 --file startkderc --group WaitForDrKonqi --key Enabled --default true`

if test x"$wait_drkonqi"x = x"true"x ; then
    # wait for remaining drkonqi instances with timeout (in seconds)
    wait_drkonqi_timeout=`kreadconfig5 --file startkderc --group WaitForDrKonqi --key Timeout --default 900`
    wait_drkonqi_counter=0
    while qdbus | grep "^[^w]*org.kde.drkonqi" > /dev/null ; do
        sleep 5
        wait_drkonqi_counter=$((wait_drkonqi_counter+5))
        if test "$wait_drkonqi_counter" -ge "$wait_drkonqi_timeout" ; then
            # ask remaining drkonqis to die in a graceful way
            qdbus | grep 'org.kde.drkonqi-' | while read address ; do
                qdbus "$address" "/MainApplication" "quit"
            done
            break
        fi
    done
fi

echo 'startkde: Shutting down...'  1>&2
# just in case
test -n "$ksplash_pid" && kill "$ksplash_pid" 2>/dev/null

# Clean up
kdeinit5_shutdown

unset KDE_FULL_SESSION
xprop -root -remove KDE_FULL_SESSION
unset KDE_SESSION_VERSION
xprop -root -remove KDE_SESSION_VERSION
unset KDE_SESSION_UID

echo 'startkde: Done.'  1>&2
