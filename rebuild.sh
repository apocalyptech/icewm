#!/bin/bash

unset ACONF DBGCM RELCM TESTC jobs prefix xterm
prefix=/usr
xterm=urxvt

# parse argv
for x
do
    case $x in
        (-a) ACONF=1 ;;  # enable autoconf+cscope
        (-c) DBGCM=1 ;;  # enable CMake debug build
        (-r) RELCM=1 ;;  # enable CMake release build
        (-t) TESTC=1 ;;  # test all combinations of configure options
        (-j*) jobs=$x ;; # number of gmake procs
        (--prefix=*) prefix=${x#*=} ;; # install prefix
        (--with-xterm=*) xterm=${x#*=} ;; # set terminal
        (*) echo "$0: Unknown option '$x'." >&2 ; exit 1 ;;
    esac
done

# set default
[[ -v ACONF || -v DBGCM || -v RELCM || -v TESTC ]] || ACONF=1

# gmake jobs
[[ -v jobs ]] || jobs=-j$(($(nproc 2>/dev/null||echo 4)<<1))

# check all POTFILES exist
if [[ -f po/POTFILES.in ]]; then
    fail=
    for file in $(< po/POTFILES.in ); do
        if [[ ! -f $file ]]; then
            echo "Missing $file is still in po/POTFILES.in!" >&2
            fail+="$file "
        fi
    done
    if [[ -n $fail ]]; then
        echo "Please update po/POTFILES.in for $fail!" >&2
        set -x
        exit 99
    fi
fi

if [[ -v ACONF ]]; then

    rm -f cscope.*
    ./autogen.sh
    ./configure.sh
    make clean
    make cscope
    cscope -b
    make "$jobs" clean all README

fi

if [[ -v DBGCM ]]; then

    # cmake cheat sheet... with Debian-style configuration
    mkdir -p builddir-debug || rm -rf builddir-debug/CMake*
    cd builddir-debug &&
    cmake .. \
        -DCONFIG_GDK_PIXBUF_XLIB=ON \
        -DCONFIG_LIBRSVG=ON \
        -DCONFIG_XRANDR=ON \
        -DCONFIG_XPM=ON \
        -DCMAKE_CXX_COMPILER_ID=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_INSTALL_PREFIX=$prefix \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DICEHELPIDX=$prefix/share/doc/icewm-common/html/icewm.html \
        -DCFGDIR=/etc/X11/icewm \
        -DVERSION=10.9.8-debug \
        -DDOCDIR=$prefix/share/doc/icewm-common \
        -DCMAKE_VERBOSE_MAKEFILE=ON \
        -DXTERMCMD=$xterm &&
    make "$jobs"
fi

if [[ -v RELCM ]]; then

    # cmake release configuration
    [[ -d build ]] && rm -rf build
    mkdir -m 0700 build &&
    cd build &&
    cmake .. \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_INSTALL_PREFIX=$prefix \
        -DCONFIG_GDK_PIXBUF_XLIB=ON \
        -DCONFIG_LIBRSVG=ON \
        -DCONFIG_XPM=ON \
        -DCMAKE_VERBOSE_MAKEFILE=ON \
        -DCONFIG_XRANDR=ON \
        -DENABLE_LTO=ON \
        -DXTERMCMD=$xterm &&
    make "$jobs"
fi

# test combinations of configure options
if [[ -v TESTC ]]; then
    rm -f -- rebuild.log rebuild.err
    for i in {001..050} :; do
        rm -f -- rebuild.tmp
        make "$jobs" clean &>>rebuild.log
        # pick five configure options randomly:
        able=$(./configure --help=short |
              sed -e 's|\[.*||' |
              awk '{print $1}' |
              grep -e --enable- -e --disable- |
              grep -v -e -FEATURE -e -checking -e -tracking -e -maintainer |
              grep -v -e -rules -e -install -e -libtool -e -static -e -shared |
              shuf -n 5)
        echo "# $i: $(date +%T): ./configure $able" | tee rebuild.tmp
        ./configure $able &>>rebuild.tmp &&
        make "$jobs" &>>rebuild.tmp ||
        { echo "FAILED for $able !" |
            tee -a rebuild.err;
            mv -fv rebuild.tmp rebuild-$i.err
        }
    done |& tee -a rebuild.log
fi

