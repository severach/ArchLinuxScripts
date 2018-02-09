#!/usr/bin/bash

# 2015-07-18 git-aurcheck by severach (GPLv3+)

# -TODO: Version checker
# -TODO: ability to specify and exclude packages on the command line
# -TODO: Ability to elevate the version check return code
# -TODO: Switch origin on git packages from aur4 to aur (if necessary)
# -TODO: (TBD) pkgver=[a-z] not allowed in more pedantic mode
# -TODO: single watch variable
# TODO: Better link scanner for version checker, perl or xidel maybe?
# TODO: An explain switch that outputs implementation details about less obvious warnings.
# TODO: Github?
# TODO: Average release cycle (daily, weekly, monthly, yearly)
# TODO: (TBD) Convert pedantic level to warn/err values
# TODO: Rearrange code to allow many checks without .git folder
# TODO: man page

# BUG: -v can take a long time. ^C leaves a temporary folder.

# NOWAY: Version check in alternate file or against read-only remote links.
#   Won't be implemented. To minimize server abuse, version check is only
#   available to the PKGBUILD maintainer. Users must use 'cower -u' or another
#   AUR helper. If the maintainer won't check versions or implement _verwatch
#   then they need to be pressed into orphaning the package to someone who
#   will.
#   You can always cheat and clone with ssh.

# a helper like namcap that checks and offers solutions for common problems in git submissions to the AUR

# git is hard to learn, has a command sequence a bit over the top for AUR
# submissions, has dangerous command line defaults, and the AUR git server
# checks for little more than a missing .SRCINFO while reporting a horde of
# nonsensical errors. This checks a planned git submission and suggests
# appropriate next steps along with complete command lines with the safest
# available options.

# Commands that are safe and desirable are offered complete and ready to paste
# with the safe command line options.
# Commands that may not be safe or desirable are suggested but no pastable
# form is offered.

# Rather than guess the next steps and be wrong more often than not, run this
# over and over. All possible next steps are shown but only a few may be
# appropriate. Perform the first related steps and run again for updated next
# steps.

# Option -h for help.

# Return:
# 0 = all good
# 1 = some packages had warnings
# 2 = some packages had errors
# 3 = some packages had severe errors
# nn = some packages have version updates (choose nn with -V)
# 99 = some packages haven't been upgraded to AUR git
# >=126 = something went wrong (probably your fault)

# See below for how to change the origin if you are seeing packages
# you don't have write access to.

# List of AUR helpers that also check versions:
# pkglivecheck (defunct), pkgbuild-watch, pkgcheck, pkgoutofdate
# So far as I can tell, none of these used a sed expression to extract perfect
# version numbers or used vercmp to properly compare them.

# Checked with ShellCheck

set -u
set -e # This is tricky to code around.

if [ ! -s ~/.git-aurcheck ]; then
  cat > ~/.git-aurcheck << EOF
# Name configuration file for git-aurcheck, Arch Linux AUR4
# Enter a grep compatible search to allow git-aurcheck to detect your maintainer line
_opt_Maintainer='none'
#_opt_Maintainer='^# Maintainer:\s\+Your Name Here'
EOF
fi
source ~/.git-aurcheck
if [ "${_opt_Maintainer:=none}" = 'none' ]; then
  echo "Warning: Add your name to ~/.git-aurcheck for proper maintainer detection"
  echo ""
  sleep 1
fi

_opt_VERSION='0.62'
_opt_AUR4='aur'

# After August 8, these 3 time bomb lines can be removed and _opt_AUR4 can be gotten rid of altogether
#if [ "$(date +'%s')" -lt 1439006400 ]; then # date +%s -d'2015-08-08'
#  _opt_AUR4='aur4'
#fi

for _var_cmd in 'mksrcinfo' 'md5sum' 'pcre2grep'; do
  if ! command -v "${_var_cmd}" >/dev/null 2>&1; then
    echo -e "Error: Required program could not be found: ${_var_cmd}"
    echo -e 'Please install pkgbuild-introspection or other supporting package'
    exit 126
  fi
done
unset _var_cmd

if [ "${EUID}" -eq 0 ]; then
  echo "root doesn't make packages. Please run as a user."
  exit 127
fi

# This dummy function supresses errors in package aur ksh
srcinfo_write_attr() {
  :
}
export -f srcinfo_write_attr

# A special starts-with version of find that hunts for foo*, usually used with 'foo='
_var_findst_in='
_fn_findst_in_@@@() {
  if [ "${#_var_@@@[@]}" -ne 0 ]; then
    local _var_find
    for _var_find in "${_var_@@@[@]}"; do
      case "${_var_find}" in
      "$1"*) return 0;;
      esac
    done
  fi
  return 1
}
'
# A special starts-with version of find that hunts for foo or foo=version
_var_findver_in='
_fn_findver_in_@@@() {
  if [ "${#_var_@@@[@]}" -ne 0 ]; then
    local _var_find
    for _var_find in "${_var_@@@[@]}"; do
      case "${_var_find}" in
      "$1"|"$1="*) return 0;;
      esac
    done
  fi
  return 1
}
'
_var_find_in='
_fn_find_in_@@@() {
  if [ "${#_var_@@@[@]}" -ne 0 ]; then
    local _var_find
    for _var_find in "${_var_@@@[@]}"; do
      if [ "${_var_find}" = "$1" ]; then
        return 0
      fi
    done
  fi
  return 1
}
'
_opt_find_in="${_var_find_in//_var_@@@/_opt_@@@}"
eval "${_opt_find_in//@@@/EXCLUDES}"
eval "${_var_findst_in//@@@/provides}"
eval "${_var_findver_in//@@@/provides}"
eval "${_var_find_in//@@@/conflicts}"
eval "${_var_find_in//@@@/depends}"
eval "${_var_find_in//@@@/makedepends}"
eval "${_var_find_in//@@@/wantmakedepends}"
eval "${_var_find_in//@@@/gitadds}"
eval "${_var_find_in//@@@/allfiles}"
eval "${_var_find_in//@@@/srcfileswantgit}"
eval "${_var_find_in//@@@/srcfilesdontwantgit}"
eval "${_var_find_in//@@@/srcfiles}"
eval "${_var_find_in//@@@/gitfiles}"
unset _opt_find_in _var_find_in _var_findver_in _var_findst_in

# This accepts no parameters. The caller must cd to the directory to be checked.
_fn_aurcheck() {
  local _var_pwd
  _var_pwd="$(pwd)"
  local _var_pwdbn
  _var_pwdbn="$(basename "${_var_pwd}")"
  if [ -d '.git' ]; then
    # This is \n safe only because git escapes non printing characters
    # https://stackoverflow.com/questions/28417414/can-i-put-strings-divided-by-newlines-into-an-array-using-the-read-builtin
    local _var_gitfiles=() # because git-status --porcelain doesn't show all files
    # Despite claims, this still produces a non zero return code
    IFS=$'\n' read -r -d '' -a _var_gitfiles < <(git ls-files; echo -n $'\0') || :
    if [ "${#_var_gitfiles[@]}" -ne 0 ]; then
      local _var_idx
      local _var_file
      for _var_idx in "${!_var_gitfiles[@]}"; do
        _var_file="${_var_gitfiles[${_var_idx}]}"
        if [ "${_var_file: 0:1}" = '"' ] && [ "${_var_file: -1:1}" = '"' ]; then
          _var_gitfiles[${_var_idx}]="$(printf '%b' "${_var_file: 1:-1}")" # unescape file name
        fi
      done
      unset _var_idx
      unset _var_file
    fi

    local _var_allfiles=()
    if [ "${#_var_gitfiles[@]}" -ne 0 ]; then
      _var_allfiles=("${_var_gitfiles[@]}")
    fi

if ! :; then
    # This code was part of revision 2 which may be needed again if we decide to decode git-status
    local _var_gitlines=()
    IFS=$'\n' read -r -d '' -a _var_gitlines < <(git status --porcelain; echo -n $'\0') || :
        local _var_gitline
        local _var_statIDX='' # Index
        local _var_statWT=''  # Worktree
        local _var_statQM=''  # ? if either are ?
        for _var_gitline in "${_var_gitlines[@]}"; do
          local _var_gitlinef="${_var_gitline:3}"   # git status FILE -> FILE is not handled. Paths are not handled.
          if [ "${_var_gitlinef: 0:1}" = '"' ] && [ "${_var_gitlinef: -1:1}" = '"' ]; then
            _var_gitlinef="$(printf '%b' "${_var_gitlinef: 1:-1}")" # unescape file name
          fi
          if [ "${_var_gitlinef}" = "${_var_gitfile}" ]; then
            _var_statIDX="${_var_gitline: 0:1}"
            _var_statWT="${_var_gitline: 1:1}"
            [ "${_var_statIDX}" = '?' ] || [ "${_var_statWT}" = '?' ] && _var_statQM='?'
            break
          fi
        done
fi

    local _var_gitadds=()

    declare -A _var_644 # this is also the required files array.
    _var_644['PKGBUILD']=' ' # neither ${:-default} nor ${:+exists} can tell the difference between '' blank and unset so we must make these non blank. I don't see any other way short of trap.
    _var_644['.SRCINFO']=' Try: mksrcinfo'

    # pcregrep and pcre2grep don't have an autoexpanding buffer so they are not suitable for binary files
    # Error: line 3400 of file ... is too long for the internal buffer; check the --buffer-size option
    # We have no way to predict how large that buffer will need to be so we must disable binary searches: pcregrep -I
    local _var_forbidgreps=('/sbin|! grep -l% "/sbin"' '/usr/tmp|! grep -l% "/usr/tmp"' '/usr/local|! grep -l% "/usr/local"' '/bin|! pcre2grep -Il% "(?<!usr)/bin"')
    local _var_srcfiles=()
    local _var_install=''
    local _var_changelog=''
    local _var_pkgbase=''
    local _var_pkgnames=()
    local _var_makedepends=()
    local _var_depends=()
    local _var_conflicts=()
    local _var_provides=()
    local _var_pkgvernew=() # We take advantage of forgetting to update .SRCINFO.
    local _var_pkgverold=()
    local _var_pkgrelnew=()

    # Obtain the entire PKGBUILD in pieces, well formatted, comments removed, all without needing a subshell or running any of its code
    declare -A _var_PBfuncAll=()   # Array of all functions, ready for eval() to create them and unset -f to destroy them
    declare -A _var_PBftextAll=()  # Array of all functions, cleaned up for text searching
    declare -A _var_PBftextArch=() # Array of functions specific to PKGBUILD, cleaned for text searching
    local _var_PBtop=''            # Text of the PKGBUILD with all the functions subtracted out, mainly the top part
    local _var_PBall=''            # Text of the entire PKGBUILD
    if [ -s 'PKGBUILD' ]; then
      local _PKGBUILDtmp
      _PKGBUILDtmp="$(mktemp -p '/tmp' 'PKGBUILD.XXX')"
      echo '_fn_git-aurcheck() {' > "${_PKGBUILDtmp}"
      cat 'PKGBUILD' >> "${_PKGBUILDtmp}"
      echo '}' >> "${_PKGBUILDtmp}"
      source "${_PKGBUILDtmp}"
      rm -f "${_PKGBUILDtmp}"
      unset _PKGBUILDtmp
      local _var_line
      local _var_infunc=''
      local _var_thisftext=''
      local _var_thisfunc=''
      while IFS='' read -r _var_line; do
        #printf '%b\n' "${_var_line}"
        if [ "${#_var_line}" -ge 4 ] && [ "${_var_line: 0:4}" = '    ' ]; then
          local _var_cleanline="${_var_line% }"
          _var_cleanline="${_var_cleanline%;}"
          _var_PBall="${_var_PBall}${_var_cleanline#    }"$'\n'
          unset _var_cleanline
        fi
        case "${_var_line}" in
        '    function '*' () ')
          _var_infunc="${_var_line#    function }"
          _var_infunc="${_var_infunc% () }"
          _var_thisftext=''
          _var_thisfunc="${_var_line#    }"$'\n'
          ;;
        '    };'|'    }')
          _var_thisfunc="${_var_thisfunc}${_var_line#    }"$'\n'
          # Some end braces are not functions
          if [ ! -z "${_var_infunc}" ] && [ ! -z "${_var_PBfuncAll[${_var_infunc}]:-}" ]; then
            echo "Warning: function ${_var_infunc}() defined multiple times"
            [ "${returnv}" -ge 1 ] || returnv=1
          fi
          if [ ! -z "${_var_infunc}" ]; then
            _var_PBfuncAll[${_var_infunc}]="${_var_thisfunc}"
            _var_PBftextAll[${_var_infunc}]="${_var_thisftext}"
            case "${_var_infunc}" in
            'pkgver'|'prepare'|'build'|'package'*) _var_PBftextArch[${_var_infunc}]="${_var_thisftext}";;
            esac
          fi
          _var_infunc=''
          _var_thisftext=''
          _var_thisfunc=''
          ;;
        '    { ');;
        '    '*)
          if [ -z "${_var_infunc}" ]; then
            _var_line="${_var_line% }"
            _var_line="${_var_line%;}"
            _var_PBtop="${_var_PBtop}${_var_line#    }"$'\n'
          else
            _var_thisfunc="${_var_thisfunc}${_var_line#    }"$'\n'
            _var_thisftext="${_var_thisftext}${_var_line#        }"$'\n'
          fi
          ;;
        esac
      done < <(declare -f _fn_git-aurcheck)
      unset _var_line
      unset _var_infunc
      unset _var_thisfunc
      unset _var_thisftext
#set > x
#      # the function list is needed in so many places. Lets get a complete list.
#      _fn_runpkgbuild() {
#        set -u
#        source 'PKGBUILD'
#        set -u
#        declare -A _var_funclist
#        local _var_func
#        for _var_func in $(declare -fF | cut -d' ' -f3 | grep '^pkgver$\|^prepare$\|^build$\|^package'); do # notice package lacks the $
#          builtin printf "_var_funclist[${_var_func}]=%q\n" "$(declare -f ${_var_func})"
#        done
#      }
#      export -f _fn_runpkgbuild
#      eval "$(bash -c _fn_runpkgbuild)"
#      unset -f _fn_runpkgbuild
#      local _var_func
#      for _var_func in "${!_var_funclist[@]}"; do
#        case "${_var_func}" in
#        pkgver|prepare|build|package*) _var_funclistPB[${_var_func}]="${_var_funclist[${_var_func}]}";;
#        esac
#      done
#      unset _var_func

      # We can expand all these strings and arrays any way we want and look at everything in great detail. Let's make bash sing!

      if [ "${_opt_PEDANTIC}" -ge 1 ]; then
        local _var_orders=('pkgbase' 'pkgname' 'pkgver' 'pkgrel' 'epoch' 'pkgdesc' 'arch' 'url' 'license' 'groups' 'depends*' 'optdepends*' 'makedepends*' 'checkdepends*' 'provides*' 'conflicts*' 'replaces*' 'backup' 'options' 'install' 'changelog' 'source*' 'noextract' 'validpgpkeys' 'md5sums*' 'sha1sums*' 'sha224sums*' 'sha256sums*' 'sha384sums*' 'sha512sums*')
        # We make no attempt to order indented PKGBUILD variables or var+=
        readarray -t _var_topvars < <(sed -n -e 's:^\([a-z][a-z0-9A-Z_]\+\)=.*$:\1:p' <<<"${_var_PBtop}")

# A special find tool that searches $1 in a list like (foo foo*)
# $1 = variable to look for like xyzzy, pkgver, or source_i686
#   the orders list would contain ('pkgver' 'source*') respectively
#   xyzzy is invalid and returns -1
#   orders pkgver isn't followed by a * so must match $1 exactly
#   orders source is followed by a * so can match $1=source or $1=source_foobar. The arch list is ever expanding making it impractical to restrict the search to known arches.
# returns the array number in orders 0..n-1 or '-1' if not found
_fn_findst_in_orders() {
  if [ "${#_var_orders[@]}" -ne 0 ]; then
    local _var_findno
    local _var_find
    for _var_findno in "${!_var_orders[@]}"; do
      _var_find="${_var_orders[${_var_findno}]}"
      case "${_var_find}" in
      *'*')
        case "$1" in
        "${_var_find%\*}"|"${_var_find%\*}_"*) echo "${_var_findno}"; return 0;;
        esac
        ;;
      *)
        if [ "$1" = "${_var_find}" ]; then
          echo "${_var_findno}"
          return 0
        fi
        ;;
      esac
    done
  fi
  echo '-1'
  return 0
}

# A special find tool that searches $1 for it's position <= in a supposed-to-be ascending list. Any number in the list not ascending is ignored and skipped.
# $1 = number to look for like xyzzy, pkgver, or source_i686
# $2 = 'b' for before, 'a' after
# returns the index value 0..n-1. Generally this index is used on a cooresponding array.
#   before: If we hunt for 5 in the list (1 -1 3 92 6 8 27), -1 and 92 are skipped so the <= test lands on 6. The return value is the array index 4 because 5 should be placed before 6
_fn_findst_in_topords() {
  local _var_findnop=0
  if [ "${#_var_topords[@]}" -ne 0 ]; then
    local _var_findno
    local _var_find
    local _var_ord=0
    for _var_findno in "${!_var_topords[@]}"; do
      _var_find="${_var_topords[${_var_findno}]}"
      #echo "${_var_findno} ord: ${_var_find} -ge ${_var_ord}, findnop=${_var_findnop}" 1>&2
      if [ "${_var_find}" -ge "${_var_ord}" ]; then
        _var_ord="${_var_find}"
        [ "$2" = 'b' ] && _var_findnop="${_var_findno}"
        #echo "${_var_findno} cmp: ${_var_ord} -ge $1, findnop=${_var_findnop}" 1>&2
        if [ "${_var_ord}" -ge "$1" ]; then
          break
        fi
        [ "$2" = 'a' ] && _var_findnop="${_var_findno}"
      fi
    done
  fi
  echo "${_var_findnop}"
  return 0
}

        # Note that we do not attempt to order the arch arrays so (foo_x86_64 foo foo_i686) generates no warning. People can apply their own preferences.
        # With this outrageous check I think we've moved from pedantic to creepy!
        local _var_topords=()
        local _var_topvar
        local _var_ord=-1
        local _var_nextord
        for _var_topvar in "${_var_topvars[@]}"; do
          _var_nextord="$(_fn_findst_in_orders "${_var_topvar}")"
          _var_topords+=("${_var_nextord}")
          #echo "${_var_topvar}: ${_var_nextord} -lt ${_var_ord}"
          if [ "${_var_nextord}" -eq -1 ]; then
            echo "Warning: Custom top variable ${_var_topvar} should be prefixed with a _ to avoid conflict with makepkg variables"
            [ "${returnv}" -ge 1 ] || returnv=1
          elif [ "${_var_nextord}" -lt "${_var_ord}" ]; then
            echo "Warning: Top variable ${_var_topvar} goes before ${_var_topvars[$(_fn_findst_in_topords "${_var_nextord}" 'b')]}" # "
            [ "${returnv}" -ge 1 ] || returnv=1
          else
            _var_ord="${_var_nextord}"
          fi
        done
        unset _var_topvar
        unset _var_orders
        unset _var_ord
        unset _var_nextord
        unset -f _fn_findst_in_orders
        unset -f _fn_findst_in_topords
        unset _var_topvars
        unset _var_topords
      fi
#set > x

      #local _var_funcname
      # Interesting that ${!foo[@]} can work on empty arrays but "${foo[@]}" cannot
      #for _var_funcname in "${!_var_PBftextAll[@]}"; do
        # This isn't possible without extensive code analysis. package has globals. Other functions can local foo; foo=x
        #if grep -ql '^\s*[a-zA-Z0-9_]\+=' <<<"${_var_PBftextAll[${_var_funcname}]}"; then
        #  echo "Warning: function ${_var_funcname} contains non local variables"
        #  [ "${returnv}" -ge 1 ] || returnv=1
        #fi
      #done
      #unset _var_funcname
      # I could detect the lack of a package function but why bother? makepkg already does this split or not split.
      if grep -ql '||\s*return\s\+1\s*$' <<<"${_var_PBall}"; then
        echo "Warning: '|| return 1' deprecated. Please remove. makepkg does this with 'set -e'"
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
      if grep -ql '\${*startdir' <<<"${_var_PBall}"; then
        echo 'Warning: ${startdir} deprecated and should be removed. It can often be changed to ${srcdir}.'
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
      local _var_funcname
      for _var_funcname in "${!_var_PBftextArch[@]}"; do
        if [ "${_opt_PEDANTIC}" -ge 1 ]; then
          if ! grep -qlF 'set -u' <<<"${_var_PBftextArch[${_var_funcname}]}" || ! grep -qlF 'set +u' <<<"${_var_PBftextAll[${_var_funcname}]}"; then
            echo "Warning: function ${_var_funcname} should be surrounded by set -u and set +u"
            [ "${returnv}" -ge 1 ] || returnv=1
          fi
        fi
        if [ "${_var_funcname}" = 'prepare' ] && grep -ql '^\s*make' <<<"${_var_PBftextArch[${_var_funcname}]}"; then
          echo "Warning: make should be moved from ${_var_funcname}() into build() or possibly package()."
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        if [ "${_var_funcname}" != 'prepare' ] && grep -ql '^\s*tar\|^\s*bsdtar\|^\s*unzip' <<<"${_var_PBftextArch[${_var_funcname}]}"; then
          echo "Warning: tar,bsdtar,unzip should be moved from ${_var_funcname}() into prepare()."
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        if [ "${_var_funcname}" != 'prepare' ] && grep -ql '^\s*cmake' <<<"${_var_PBftextArch[${_var_funcname}]}"; then
          echo "Warning: cmake should be moved from ${_var_funcname}() into prepare()."
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        if [ "${_var_funcname}" != 'prepare' ] && grep -qlF './configure' <<<"${_var_PBftextArch[${_var_funcname}]}"; then
          echo "Warning: configure should be moved from ${_var_funcname}() into prepare()."
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        # We could catch nawk too but that's pretty rare.
        if [ "${_var_funcname}" = 'build' ] && grep -ql '^\s*sed\|^\s*awk\|^\s*patch\|^\s*gawk' <<<"${_var_PBftextArch[${_var_funcname}]}"; then
          echo "Warning: sed,awk,patches should be moved from ${_var_funcname}() into prepare() or possibly package()."
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
      done
      unset _var_funcname

      # Seems that set -x doesn't do this. There's some command like exit, return, set -e, or set -x that causes updpkgsums to zero length the PKGBUILD. I'll need to have it happen again to see which command causes it.
      #if grep -ql '^\s*set [+-]x' <<<"${_var_PBtop}"; then
      #  echo '******************************************************'
      #  echo 'Your PKGBUILD top level contains a set -x or set +x which will cause updpkgsums to destroy the PKGBUILD'
      #  echo 'THESE COMMANDS MUST BE REMOVED IMMEDIATELY!'
      #  echo '******************************************************'
      #  [ "${returnv}" -ge 2 ] || returnv=2
      #fi

      if grep -ql '^\s*sudo' <<<"${_var_PBall}"; then
        echo 'sudo is not an allowed command in a PKGBUILD!'
        [ "${returnv}" -ge 3 ] || returnv=3
      fi
#      rm -f "${_PKGBUILDtmp}"
#      unset _PKGBUILDtmp
      if [ "${_opt_PEDANTIC}" -ge 1 ]; then
        if ! grep -ql '^set -u' <<<"${_var_PBtop}" || ! grep -ql '^set +u' <<<"${_var_PBtop}"; then
          echo 'Warning: surrounding the PKGBUILD with set -u, set +u will help catch script errors.'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        if [ "${_opt_PEDANTIC}" -ge 3 ]; then
          # These test commands are specially crafted to fail correctly with set -e
          local _var_forbiddens=('/bin|! test -d "${pkgdir}/bin"' '/sbin|! test -d "${pkgdir}/sbin"' '/lib|! test -d "${pkgdir}/lib"' '/share|! test -d "${pkgdir}/share"' '/usr/sbin|! test -d "${pkgdir}/usr/sbin"' '/usr/local|! test -d "${pkgdir}/usr/local"')
          local _var_forbidden
          for _var_forbidden in "${_var_forbidgreps[@]}"; do
            _var_forbiddens+=("${_var_forbidden//%/r}"' "${pkgdir}"') # [@] probably won't work
          done
          local _var_forbiddenspr=()
          for _var_forbidden in "${_var_forbiddens[@]}"; do
            _var_forbiddenspr+=("${_var_forbidden#*|}" "${_var_forbidden%%|*}")
          done
          for _var_forbidden in "${_var_forbiddens[@]}"; do
            # These can be commented out so we must search the PKGBUILD directly
            if ! grep -qlF "${_var_forbidden#*|}" 'PKGBUILD'; then
              echo '  # Ensure there are no forbidden paths. Place at the end of package() and comment out as you find or need exceptions. (git-aurcheck)'
              printf '  %s || { echo "Line ${LINENO} Forbidden: %s"; false; }\n' "${_var_forbiddenspr[@]}" # Not sure why the extra ; is required
              [ "${returnv}" -ge 1 ] || returnv=1
              break
            fi
          done
          unset _var_forbiddenspr
          unset _var_forbiddens
          unset _var_forbidden
        fi
        if ! grep -ql '^\s*sha256sums=' <<<"${_var_PBtop}" && ! grep -ql '^\s*sha384sums=' <<<"${_var_PBtop}" && ! grep -ql '^\s*sha512sums=' <<<"${_var_PBtop}"; then
          echo 'Warning: sha256sums or better are recommended. Check existing sums before upgrading.'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        if grep -ql '^\s*md5sums=' <<<"${_var_PBtop}" || grep -ql '^\s*sha1sums=' <<<"${_var_PBtop}" || grep -ql '^\s*sha224sums=' <<<"${_var_PBtop}"; then
          echo 'Warning: lesser md5sums,sha1sums,sha224sums should be removed.'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        # Let's get them in the comments so search the entire PKGBUILD
        if grep -qlE '\$(pkgbase|pkgname|pkgver|srcdir|pkgdir|startdir|CARCH)' 'PKGBUILD'; then
          echo 'Warning: $vars should be converted to ${vars}.'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
        # Perfectly legit and we can't detect it: if ! :; then false; fi
        # All I can do is color them red in mc PKGBUILD.syntax
        # Here the best I can do is detect them intentionally non indented which is where I put them to be noticable.
        if grep -ql '^false' 'PKGBUILD'; then
          echo 'Warning: Your PKGBUILD contains a lone false and is unlikely to work'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
      fi

      # I'd like to recommend more $var to ${var} changes but I don't see a way to do it in grep.
      if [ "${_opt_Maintainer}" != 'none' ] && ! grep -ql "${_opt_Maintainer}" 'PKGBUILD'; then
        echo 'Warning: You are not listed as a maintainer in PKGBUILD.'
        [ "${returnv}" -ge 1 ] || returnv=1
      fi

      local _var_tempdir
      _var_tempdir="$(basename "$0")" # mksrcinfo doesn't let us specify a target file
      _var_tempdir="$(mktemp -p '/tmp' -d "${_var_tempdir}.XXXXX")" # ^C always breaks at curl version check which leaves this folder. Making the folder in /tmp allows to get out of cleaning it up. It also eliminates changes to the build folders timestamps during update checks.
      if pushd "${_var_tempdir}" >/dev/null; then
        ln -s "${_var_pwd}/PKGBUILD"
        if mksrcinfo; then
          # Use the updated .SRCINFO if we can get it
          # Every reader here must be copied below
          _var_install="$(sed -ne 's:^\tinstall = \(.\+\)$:\1:p' '.SRCINFO')"
          _var_changelog="$(sed -ne 's:^\tchangelog = \(.\+\)$:\1:p' '.SRCINFO')"
          _var_pkgbase="$(sed -ne 's:^pkgbase = \(.\+\)$:\1:p' '.SRCINFO')"
          IFS=$'\n' read -r -d '' -a _var_srcfiles    < <(sed -ne 's:^\tsource = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_pkgnames    < <(sed -ne 's:^pkgname = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_makedepends < <(sed -ne 's:^\tmakedepends = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_depends     < <(sed -ne 's:^\tdepends = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_conflicts   < <(sed -ne 's:^\tconflicts = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_provides    < <(sed -ne 's:^\tprovides = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_pkgvernew   < <(sed -ne 's:^\tpkgver = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          IFS=$'\n' read -r -d '' -a _var_pkgrelnew   < <(sed -ne 's:^\tpkgrel = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
          if [ ! -s "${_var_pwd}/.SRCINFO" ] || [ "$(grep -v '^#' '.SRCINFO' | md5sum)" != "$(grep -v '^#' "${_var_pwd}/.SRCINFO" | md5sum)" ]; then
            echo ".SRCINFO is missing or out of date. Try 'mksrcinfo'"
            [ "${returnv}" -ge 2 ] || returnv=2
            _var_gitadds+=('.SRCINFO') # this is the first add so no dups possible
          fi

          # https://bbs.archlinux.org/viewtopic.php?id=202062 Don't use $pkgname in paths in split packages: example of libsystemd

          if [ "${#_var_pkgnames[@]}" -ge 2 ] && grep -qlF $'${pkgname}\n$pkgname' <<<"${_var_PBftextAll[@]:-}"; then
#            # Extract listing of PKGBUILD defined functions compiled and comments removed by bash. This doesn't get functions defined by eval.
#            # We want only the functions. $pkgname is approprate in the top non function area
#            _fn_runpkgbuild() {
#              set -u
#              source "${_var_pwd}/PKGBUILD"
#              set -u
#              _foo=$(declare -fF | cut -d' ' -f3 | grep '^pkgver$\|^prepare$\|^build$\|^package') # notice package lacks the $
#              declare -f ${_foo}
#            }
#            export -f _fn_runpkgbuild
#            local _var_findinfunc
#            _var_findinfunc="$(_var_pwd="${_var_pwd}" bash -c _fn_runpkgbuild)"
#            unset -f _fn_runpkgbuild
            #if grep -qlF $'${pkgname}\n$pkgname' <<<"${_var_PBftextall[@]}"; then
              # We can recommend $pkgbase for non split packges but that's too pedantic, even for me!
              echo 'Warning: Using ${pkgname} in any function of a split package is unsafe. Use ${pkgbase}.'
              [ "${returnv}" -ge 1 ] || returnv=1
            #fi
            #unset _var_findinfunc
          fi

          # We could easily convert this entirely into the new arrays.
          if [ "${_opt_VERSION}" -ne 0 ] && { grep -qlF $'_verwatch=' <<<"${_var_PBtop}" || test ! -z "${_var_PBftextAll[_vercheck]:-}"; }; then
            _fn_runpkgbuild() {
              set -u
              source "${_var_pwd}/PKGBUILD"
              set +u
              if declare -fF _vercheck >/dev/null; then
                :
              elif [ "${#_verwatch[@]}" -eq 3 ]; then
                :
              elif [ "${#_verwatch[@]}" -eq 0 ]; then
                #echo 'To use version checking either _verwatch or _vercheck() must exist'
                #echo 'For help, add to PKGBUILD: _verwatch=x'
                #return 1
                return 0 # some packages contain _verwatch but don't ever execute it to make the variable come into existence. This is not an error.
              else
                echo 'To use version checking place a 3 element array _verwatch in PKGBUILD' >&2
                echo '#1: a link for curl to download that contains the text of the updates' >&2
                echo "#2: a string for sed -n -e 's:^...$:\1:p' that filters out the exact version text" >&2
                echo '  the search string must include exactly one \(\) pair to satisfy \1' >&2
                echo '#3: what to extract from the page: l=links, t=link text, f=all text' >&2
                echo 'Example from mdadm-git:' >&2
                echo "_verwatch=('ftp://ftp.kernel.org/pub/linux/utils/raid/mdadm/' 'mdadm-\(.*\)\.tar\.xz' 'f')" >&2
                echo 'Example from adminer-editor:' >&2
                echo "url='http://www.adminer.org/en/editor/'" >&2
                echo '_verwatch=("${url}"'" 'http://downloads.sourceforge.net/adminer/editor-\([0-9\.]\+\).php' 'l')" >&2
                return 1
              fi
              set -u
              # http://stackoverflow.com/questions/1881237/easiest-way-to-extract-the-urls-from-an-html-page-using-sed-or-awk-only
              # A real getlinks would use an html decoder and not Cthulhu's sed+grep.
              # $1: l get link href (default), t get link text, f FTP listing or other no html
              declare -f -F _getlinks >/dev/null || _getlinks() {
                # We don't handle links split across line. We can easily improve on the Cthulhu madness: sed -e 's:\s\+$::g' -e 's:^\s\+::g' | tr '\n' ' ' | sed -e 's:<[^/]:\n&:g' | sed -e 's:\s\+$::g' |
                case "${1}" in
                l) grep -aF 'href=' | grep -ao '<[aA] .*href=.*>' | sed -e 's/<[aA] /\n<a /g' | sed -ne 's/^<a .*href=["'"'"']\{0,1\}\([^ \t"'"'"'>]*\).*$/\1/p' -e '/^$/d';;
                t) grep -aF 'href=' | grep -ao '<[aA] .*href=.*>' | sed -e 's/<[aA] /\n<a /g' | sed -ne 's/^<a [^>]*>\([^<]*\)<.*$/\1/p' -e '/^$/d';;
                f) cat;;
                esac
              }
              # The PKGBUILD can replace any of these functions deemed necessary. The most likely to replace is _vercheck
              # Return sorted list of all version numbers available
              local _var_has_vercheck=0
              if declare -f -F _vercheck >/dev/null; then
                _var_has_vercheck=1
              else
                _vercheck() {
                  local _versed2="${_verwatch[1]//:/\\:}" # Escape the two things that the PKGBUILD is not permitted to do
                  _versed2="${_versed2//$/\\$}" # End of line (though sed doesn't seem to require this), and end of search
                  curl -s -l "${_verwatch[0]}" | _getlinks "${_verwatch[2]}" | sed -ne "s:^${_versed2}"'$:\1:p' | sort -V
                }
              fi
              # Polling is better than version announcements. Everyone's poll cron time will be different. An announcement would generate an immediate traffic rush.
              # _vercheck and _verscan depend only on pacman, coreutils, sed, and grep
              # $1, return code 0=found update 1=no update found; $1=1 always return 0=true
              # $2, echo nothing, $2=1 echo latest file found, $2=2 echo all newer files found, $2=3 echo comparison and all files, $2=4 combo 1,3
              declare -f -F _verscan >/dev/null || _verscan() {
                #local _pkgfile="${pkgname}-${pkgver}.tar.xz"
                local _rv=1
                [ "$1" -ne 0 ] && _rv=0
                local _verfound=0
                local _rvfile=''
                local _remfile
                local IFS=$'\n'
                while read -r _remfile; do
                  _verfound=1
                  local _vercmp
                  _vercmp="$(vercmp "${_remfile}" "${pkgver}")"
                  [ "$2" -ge 3 ] && printf '%-s %s\n' "${_vercmp}" "${_remfile}" 1>&2
                  if [ "${_vercmp}" -ge 1 ]; then
                    [ "$2" -eq 2 ] && echo "${_remfile}"
                    _rvfile="${_remfile}"
                    _rv=0
                  fi
                done < <(_vercheck)
                #_vercheck 1>&2
                if [ "${_verfound}" -eq 0 ]; then
                  echo 'No version results' 1>&2
                fi
                [ "$2" -eq 1 -o "$2" -eq 4 ] && echo "${_rvfile}"
                return ${_rv}
              }
              # If _vercheck is provided then the PKGBUILD is expected to do it's own thing. If _getlinks is used then the watch must still be provided.
              if [ "${_var_has_vercheck}" -ne 0 ] || [ ! -z "${_verwatch:-}" ]; then
                set -u
                if [ "${_opt_DEBUGVER}" -ne 0 ]; then
                  _verscan 0 4
                else
                  _verscan 0 1
                fi
                set -u
              fi
            }
            #set -u; _vercheck 0 3 && echo 'Update detected'; exit 1
            #export _opt_DEBUGVER
            export -f _fn_runpkgbuild
            local _var_newver
            set +e
            _var_newver="$(_opt_DEBUGVER=${_opt_DEBUGVER} _var_pwd="${_var_pwd}" bash -c _fn_runpkgbuild)"
            set -e
            #unset _opt_DEBUGVER
            unset -f _fn_runpkgbuild
            if [ ! -z "${_var_newver}" ]; then
              echo "Warning: a new version ${_var_newver} may be available."
              [ "${returnv}" -ge "${_opt_VEREXITCODE}" ] || returnv="${_opt_VEREXITCODE}"
            fi
            unset _var_newver
          fi
        else
          echo 'Your PKGBUILD crashes with mksrcinfo.'
          [ "${returnv}" -ge 3 ] || returnv=3
        fi
        cd "${_var_pwd}"
        rm -rf "${_var_tempdir}"
        popd >/dev/null # why don't pushd and popd have a --quiet option?
      else
        rmdir -f "${_var_tempdir}"
      fi
      unset _var_tempdir
    fi # -s 'PKGBUILD'

    # Nail the screwups no matter where they are!
    if [ -s '.SRCINFO' ]; then
      if [ -z "${_var_install}" ]; then
        _var_install="$(sed -ne 's:^\tinstall = \(.\+\)$:\1:p' '.SRCINFO')"
      fi
      if [ -z "${_var_changelog}" ]; then
        _var_changelog="$(sed -ne 's:^\tchangelog = \(.\+\)$:\1:p' '.SRCINFO')"
      fi
      if [ -z "${_var_pkgbase}" ]; then
        _var_pkgbase="$(sed -ne 's:^pkgbase = \(.\+\)$:\1:p' '.SRCINFO')"
      fi
      if [ "${#_var_pkgnames[@]}" -eq 0 ]; then
        IFS=$'\n' read -r -d '' -a _var_pkgnames < <(sed -ne 's:^pkgname = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      fi
      if [ "${#_var_makedepends[@]}" -eq 0 ]; then
        IFS=$'\n' read -r -d '' -a _var_makedepends < <(sed -ne 's:^\tmakedepends = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      fi
      if [ "${#_var_depends[@]}" -eq 0 ]; then
        IFS=$'\n' read -r -d '' -a _var_depends < <(sed -ne 's:^\tdepends = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      fi
      if [ "${#_var_conflicts[@]}" -eq 0 ]; then
        IFS=$'\n' read -r -d '' -a _var_conflicts < <(sed -ne 's:^\tconflicts = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      fi
      if [ "${#_var_provides[@]}" -eq 0 ]; then
        IFS=$'\n' read -r -d '' -a _var_provides < <(sed -ne 's:^\tprovides = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      fi
      IFS=$'\n' read -r -d '' -a _var_pkgverold < <(sed -ne 's:^\tpkgver = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      local _var_srcfiles1=()
      local _var_srcfile1
      IFS=$'\n' read -r -d '' -a _var_srcfiles1 < <(sed -ne 's:^\s\+source[^ =]* = \(.\+\)$:\1:p' '.SRCINFO'; echo -n $'\0') || :
      if [ "${#_var_srcfiles1[@]}" -ne 0 ]; then
        for _var_srcfile1 in "${_var_srcfiles1[@]}"; do
          if ! _fn_find_in_srcfiles "${_var_srcfile1}"; then
            _var_srcfiles+=("${_var_srcfile1}")
          fi
        done
      fi
      unset _var_srcfiles1
      unset _var_srcfile1
    fi
    if [ ! -z "${_var_install}" ]; then
      _var_644["${_var_install}"]=' ' # Why is this a space and not blank? See _var_644 above.
      if _fn_find_in_srcfiles "${_var_install}"; then
        echo "The install file ${_var_install} should be removed from the source array."
        [ "${returnv}" -ge 2 ] || returnv=2
      fi
      if [ -s "${_var_install}" ]; then
        local _var_forbidgrep
        for _var_forbidgrep in "${_var_forbidgreps[@]}"; do
          _var_forbidgrep="${_var_forbidgrep//%/q}"
          if ! eval "${_var_forbidgrep#*|} <(sed -e '/^[ \t]*#/d' '${_var_install}')"; then
            echo "Warning: The install file ${_var_install} has some forbidden text: ${_var_forbidgrep%%|*}"
            [ "${returnv}" -ge 1 ] || returnv=1
          fi
        done
        unset _var_forbidgrep
      fi
    fi
    unset _var_forbidgreps
    if [ ! -z "${_var_changelog}" ]; then
      _var_644["${_var_changelog}"]=' ' # Why is this a space? See above.
      if _fn_find_in_srcfiles "${_var_changelog}"; then
        echo "The changelog file ${_var_changelog} should be removed from the source array."
        [ "${returnv}" -ge 2 ] || returnv=2
      fi
    fi
    # The base is repeated in all the names. The code is here in case we find a case where it's not
    # The pkgbase is needed elsewhere
    #if [ "${_var_pkgbase}" != "${_var_pkgbase,,}" ]; then
    #  echo "AUR permits only lowercase package base names: ${_var_pkgbase}"
    #  [ "${returnv}" -ge 2 ] || returnv=2
    #fi
    if [ ! -z "${_var_pkgbase}" ] && [ "${_var_pkgbase}" != "${_var_pwdbn}" ]; then
      echo '******************************************************'
      echo "The folder name does not match the pkgbase/pkgname."
      echo "pkgbase: ${_var_pkgbase}"
      echo "Folder:  ${_var_pwdbn}"
      echo '******************************************************'
      [ "${returnv}" -ge 3 ] || returnv=3
    fi
    if [ "${#_var_pkgnames[@]}" -ne 0 ]; then
      local _var_pkgname
      for _var_pkgname in "${_var_pkgnames[@]}"; do
        if [ "${_var_pkgname}" != "${_var_pkgname,,}" ]; then
          echo "AUR permits only lowercase package names: ${_var_pkgname}"
          [ "${returnv}" -ge 2 ] || returnv=2
        fi
      done
      unset _var_pkgname
    fi
    unset _var_install
    unset _var_changelog

    if [ "${#_var_pkgrelnew[@]}" -gt 1 ]; then
      echo 'Warning: a package with multiple pkgrel is unexpected. If this is valid please report to the author so this program can be improved.'
      [ "${returnv}" -ge 1 ] || returnv=1
    fi
    # These are arrays but we'll only check the first one.
    if [ ! -z "${_var_pkgrelnew:-}" ] && [[ "${_var_pkgrelnew}" != [1-9] ]]; then
      echo 'pkgrel must be a digit from 1 to 9'
      [ "${returnv}" -ge 2 ] || returnv=2
    fi
    if [ ! -z "${_var_pkgvernew:-}" ]; then
      if [ ! -z "${_var_pkgverold:-}" ] && [ ! -z "${_var_pkgrelnew:-}" ] && [ "${_var_pkgvernew}" != "${_var_pkgverold}" ] && [ "${_var_pkgrelnew}" != '1' ]; then
        echo 'When the version changes the pkgrel must be set back to 1'
        [ "${returnv}" -ge 2 ] || returnv=2
      fi
      if [ "${_opt_PEDANTIC}" -ge 3 ]; then
        if [[ "${_var_pkgvernew:-}" != [0-9]* ]]; then
          echo 'Warning: version numbers typically should not start with a letter'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
      else
        if [[ "${_var_pkgvernew:-}" == [vV][0-9]* ]]; then
          echo 'Warning: version numbers typically should not start with a v'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
      fi
    fi
    unset _var_pkgvernew
    unset _var_pkgverold

    # Generate specific arrays from _var_srcfiles. Note that since we're mean and read both .SRCINFO, there may be false dups.
    local _var_srclinks=() # Sometimes this contains false dups. I don't care since it's not used for anything yet.
    local _var_srcfileswantgit=()
    local _var_srcfilesdontwantgit=()
    local _var_srcvcs=0
    local _var_wantmakedepends=()
    if [ "${#_var_srcfiles[@]}" -ne 0 ]; then
      local _var_srcfile
      local _var_idx
      local _var_srclink
      for _var_idx in "${!_var_srcfiles[@]}"; do
        _var_srcfile="${_var_srcfiles[${_var_idx}]}"
        _var_srclink=''
        if [ "${_var_srcfile/::/}" != "${_var_srcfile}" ]; then
          #_var_srclink="${_var_srcfile#*::}" # foo::git://
          #case "${_var_srclink}" in
          #bzr*|git*|hg*|svn*)_var_srcvcs=1;; # from makepkg
          #esac
          #_var_srcfile="${_var_srcfile%%::*}" # makepkg does it this way
          case "${_var_srcfile#*::}" in
          bzr*|git*|hg*|svn*);; # from makepkg, name is only useful if not before ::vcs
          *)
            _var_srcfilesdontwantgit+=("${_var_srcfile%%::*}");;
          esac
          _var_srcfiles[${_var_idx}]="${_var_srcfile}"
          _var_srcfile="${_var_srcfile#*::}"
        fi
        if [ "${_var_srcfile/:\/\//}" != "${_var_srcfile}" ]; then # it's a link ://
          _var_srclink="${_var_srcfile}" # We don't about what's on the end here
          case "${_var_srclink}" in
          bzr*)_var_srcvcs=1; ! _fn_find_in_wantmakedepends 'bzr|bzr'        && _var_wantmakedepends+=('bzr|bzr');;
          git*)_var_srcvcs=1; ! _fn_find_in_wantmakedepends 'git|git'        && _var_wantmakedepends+=('git|git');;
          hg*) _var_srcvcs=1; ! _fn_find_in_wantmakedepends 'hg|mercurial'   && _var_wantmakedepends+=('hg|mercurial');;
          svn*)_var_srcvcs=1; ! _fn_find_in_wantmakedepends 'svn|subversion' && _var_wantmakedepends+=('svn|subversion');;
          *)
            _var_srcfile="${_var_srcfile##*/}" # bash string version of basename
            _var_srcfilesdontwantgit+=("${_var_srcfile}")
            _var_srcfiles[${_var_idx}]="${_var_srcfile}"
          esac
        else
          _var_srcfileswantgit+=("${_var_srcfile}")
        fi
        if [ ! -z "${_var_srclink}" ]; then
          _var_srclinks+=("${_var_srclink}")
        fi
        ! _fn_find_in_allfiles "${_var_srcfile}" && _var_allfiles+=("${_var_srcfile}")
        #echo "${_var_srcfile}"
      done
      unset _var_srcfile
      unset _var_idx
      unset _var_srclink
      if [ -f 'PKGBUILD' ] && [ "${_var_srcvcs}" -ne 0 ]; then
        if ! grep -ql '^pkgver\s*(' 'PKGBUILD'; then
          echo 'Warning: A pkgver() function is usually useful for packages with vcs sources.'
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
      fi
    else
      echo 'Warning: .SRCINFO has no source files'
      [ "${returnv}" -ge 1 ] || returnv=1
    fi
    unset _var_srcvcs
    unset _var_srclinks

    # This went through 3 revisions.
    # 1) Run through git ls-files with FSA. Unmaintainable mess.
    # 2) Run through git status --porcelain with FSA. Only shows diffs and still unmaintainable.
    # 3) Now it's a series of simple set operations. The sets can be verified with set > tmpfile.
    if _fn_find_in_depends 'gcc'; then
      echo 'Warning: gcc should probably be moved from depends to makedepends.'
      [ "${returnv}" -ge 1 ] || returnv=1
    fi

    if [ "${#_var_wantmakedepends[@]}" -ne 0 ]; then
      local _var_wantmakedepend
      for _var_wantmakedepend in "${_var_wantmakedepends[@]}"; do
        _var_wantmakedepend="${_var_wantmakedepend#*|}"
        if ! _fn_find_in_makedepends "${_var_wantmakedepend}" && ! _fn_find_in_depends "${_var_wantmakedepend}"; then
          echo "For this vcs package '${_var_wantmakedepend}' must be added to makedepends or possibly depends."
          [ "${returnv}" -ge 2 ] || returnv=2
        fi
      done
      if [ "${#_var_wantmakedepends[@]}" -eq 1 ]; then # We don't have an opinion if there are 2 or more different vcs sources
        _var_wantmakedepend="${_var_wantmakedepends[0]}"
        _var_wantmakedepend="${_var_wantmakedepend%%|*}"
        local _var_wrongext=''
        case "${_var_pkgbase}" in
        *-bzr) [ "${_var_wantmakedepend}" != 'bzr' ] && _var_wrongext='-bzr';;
        *-git) [ "${_var_wantmakedepend}" != 'git' ] && _var_wrongext='-git';;
        *-hg)  [ "${_var_wantmakedepend}" != 'hg'  ] && _var_wrongext='-hg';;
        *-svn) [ "${_var_wantmakedepend}" != 'svn' ] && _var_wrongext='-svn';;
        esac
        if [ ! -z "${_var_wrongext}" ]; then
          echo "${_var_wrongext} is the wrong suffix for your vcs package. Try -${_var_wantmakedepend}"
          [ "${returnv}" -ge 2 ] || returnv=2
        fi
        unset _var_wrongext
      fi
      unset _var_wantmakedepend
    fi

    case "${_var_pkgbase}" in
    *-bzr|*-git|*-hg|*-svn)
      if ! _fn_find_in_conflicts "${_var_pkgbase%-*}" || ! _fn_findver_in_provides "${_var_pkgbase%-*}"; then
        echo 'Warning: most vcs packages should have a conflicts and provides'
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
      if ! _fn_findst_in_provides "${_var_pkgbase%-*}="; then
        echo 'Warning: vcs packages cannot satisfy versioned dependencies without a provides=version'
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
      if [ "${_var_pkgrelnew:-}" != '1' ]; then
        echo 'Warning: vcs packages usually have pkgrel=1'
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
      ;;
    esac
    unset _var_pkgbase
    unset _var_pkgrelnew

    local _var_reqfile
    for _var_reqfile in "${!_var_644[@]}"; do
      ! _fn_find_in_allfiles "${_var_reqfile}" && _var_allfiles+=("${_var_reqfile}") # This probably isn't necessary
      ! _fn_find_in_srcfiles "${_var_reqfile}" && _var_srcfiles+=("${_var_reqfile}") # This probably isn't necessary
      ! _fn_find_in_srcfileswantgit "${_var_reqfile}" && _var_srcfileswantgit+=("${_var_reqfile}")
      if [ ! -s "${_var_reqfile}" ]; then
        echo "Required file ${_var_reqfile} doesn't exist or blank.${_var_644[${_var_reqfile}]}"
        [ "${returnv}" -ge 2 ] || returnv=2
      elif [ "$(stat -c '%a' "${_var_reqfile}")" != '644' ]; then
        echo "File ${_var_reqfile} must have perms 644. Try: chmod 644 \"${_var_reqfile}\""
        [ "${returnv}" -ge 2 ] || returnv=2
      fi
      if ! _fn_find_in_gitfiles "${_var_reqfile}" && ! _fn_find_in_gitadds "${_var_reqfile}"; then
        echo "Required file ${_var_reqfile} not in git. Try: git add \"${_var_reqfile}\""
        [ "${returnv}" -ge 2 ] || returnv=2
        _var_gitadds+=("${_var_reqfile}")
      fi
    done
    unset _var_reqfile

    if [ "${#_var_srcfileswantgit[@]}" -ne 0 ]; then
      local _var_srcfile
      for _var_srcfile in "${_var_srcfileswantgit[@]}"; do
        if [ "${_var_644[${_var_srcfile}]:-xyzzy}" = 'xyzzy' ]; then
          if ! _fn_find_in_gitfiles "${_var_srcfile}" && ! _fn_find_in_gitadds "${_var_srcfile}"; then
            echo "Source file ${_var_srcfile} not in git. Try: git add \"${_var_srcfile}\""
            [ "${returnv}" -ge 2 ] || returnv=2
            _var_gitadds+=("${_var_srcfile}")
          fi
          if [ ! -f "${_var_srcfile}" ]; then
            echo "Source file ${_var_srcfile} doesn't exist or blank."
            [ "${returnv}" -ge 2 ] || returnv=2
          fi
        fi
      done
      unset _var_srcfile
    fi

    if [ "${#_var_gitfiles[@]}" -ne 0 ]; then
      local _var_gitfile
      for _var_gitfile in "${_var_gitfiles[@]}"; do
        if _fn_find_in_srcfilesdontwantgit "${_var_gitfile}"; then
          echo "Downloaded file ${_var_gitfile} should be removed from git. Try: git rm --cached \"${_var_gitfile}\""
          [ "${returnv}" -ge 2 ] || returnv=2
        elif ! _fn_find_in_srcfileswantgit "${_var_gitfile}"; then
          echo "Warning: File ${_var_gitfile} in git not in PKGBUILD. Maybe try: git rm --cached \"${_var_gitfile}\""
          [ "${returnv}" -ge 1 ] || returnv=1
        fi
      done
      unset _var_gitfile
    fi

    local _var_allfile
    local _var_perms
    for _var_allfile in "${_var_allfiles[@]}"; do
      if [ -f "${_var_allfile}" ]; then
        if [ -z "${_var_644[${_var_allfile}]:-}" ]; then
          _var_perms="$(stat -c '%a' "${_var_allfile}")"
          if [ "${_var_perms}" != '755' ] && [ "${_var_perms}" != '644' ]; then
            if _fn_find_in_srcfileswantgit "${_var_allfile}"; then
              echo "File ${_var_allfile} must have perms 644 or 755"
            else
              echo "File ${_var_allfile} should have perms 644 or 755"
            fi
            [ "${returnv}" -ge 2 ] || returnv=2
          fi
        fi
        if [ "$(stat -c '%U' "${_var_allfile}")" = 'root' ]; then
          echo "File ${_var_allfile} owned by root"
          [ "${returnv}" -ge 2 ] || returnv=2
        fi
      fi
    done
    unset _var_perms
    unset _var_allfile

    #if ... We can do this if we decide to decode git-status
    #  echo "${_var_gitfile} has been modified. Try: 'git add ${_var_gitfile}' or 'git add -u'"
    #  [ "${returnv}" -ge 2 ] || returnv=2
    #el
    # alas, git ls-files does not show us files that have been "git rm" but not pushed
    if [ "${#_var_gitadds[@]}" -gt 0 ]; then
      #_var_gitadds+=($'foo\t\n\r\lbar foobar' $'foo bar') # Test out %q
      echo -n 'Found: git add'
      builtin printf ' %q' "${_var_gitadds[@]}"
      echo ''
    fi
    local _var_gitmodified
    _var_gitmodified="$(git ls-files -m)"
    if [ "${_opt_PEDANTIC}" -ge 2 -o "${_opt_ALL}" -eq 0 ] && [ ! -z "${_var_gitmodified}" ]; then
      echo "Warning: There are modified files. Try 'git status' and maybe 'git add -u'"
      [ "${returnv}" -ge 1 ] || returnv=1
    fi
    local _var_gitadded
    _var_gitadded="$(git status --porcelain | grep '^M ')" || :

    local _var_returnvbeforestaged="${returnv}"
    if [ "${_opt_PEDANTIC}" -ge 2 -o "${_opt_ALL}" -eq 0 ] && git status --porcelain | grep -qv '^?\|^ M'; then
      echo "Warning: There are staged files. Try 'git status' and maybe commit and push"
      [ "${returnv}" -ge 1 ] || returnv=1
    fi
    set +e
    local _var_push
    _var_push="$(git cherry -v 2>/dev/null)" # local cannot be on this line or we lose the return value
    if [ $? -ne 0 ]; then
      # We want to only generate this warning near the commit instead of after every step.
      if [ "${_var_returnvbeforestaged}" -le 1 ]; then
        if [ "${returnv}" -eq 0 ]; then
          echo "Warning: You have not made your first push to create the ${_opt_AUR4^^} package. Maybe try 'git push origin master'"
        else
          echo "Warning: You have not made your first push to create the ${_opt_AUR4^^} package. Maybe try 'git commit -m \"Initial Import\"' and 'git push origin master'"
        fi
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
      set +e
      local _var_revlist
      _var_revlist="$(git rev-list HEAD --count 2>/dev/null)"
      if [ $? -eq 0 ] && [ ! -z "${_var_revlist}" ] && [ "${_var_revlist}" -ge 2 ]; then
        # git revert is worthless as it reverts in the forward direction. We need to go two steps in reverse to before HEAD.
        echo "There are multiple commits on an empty repository. This may not do what you want. It seems that git cannot reset before your first commit HEAD back to an empty repository. You may need to rm -rf '.git' and clone again as instructed by $(basename "$0")."
        [ "${returnv}" -ge 2 ] || returnv=2
      fi
      set -e
    elif [ ! -z "${_var_push}" ]; then
      # Unfortunately this does not detect multiple commits before the first commit is made
      if [ "${#_var_gitadds[@]}" -gt 0 ] || [ ! -z "${_var_gitmodified}" ] || [ ! -z "${_var_gitadded}" ] || [ "$(git log @{push}.. | grep -c '^commit')" -ge 2 ]; then
        # http://stackoverflow.com/questions/927358/how-do-you-undo-the-last-commit\
        echo "There are modifications after a commit. A push or another commit may not do what you want. Maybe try multiple times: git reset --soft 'HEAD~1'; git status"
        [ "${returnv}" -ge 2 ] || returnv=2
      else
        echo "Warning: There are commits not pushed. Try 'git cherry -v' and maybe push"
        [ "${returnv}" -ge 1 ] || returnv=1
      fi
    fi
    set -e
    unset _var_push
    unset _var_returnvbeforestaged
    unset _var_gitmodified
    unset _var_gitadded

    local _var_remoteurl
    _var_remoteurl="$(git ls-remote --get-url)"
    local _var_remoteurlbn
    _var_remoteurlbn="$(basename "${_var_remoteurl}" ".git")"
    if ! grep -qlF $'ssh://\nssh+git://' <<< "${_var_remoteurl}"; then
      echo "Warning: You don't have write access to this package so you can't fix these problems."
      # I see no reason to report this as a warning.
    fi
    if [ "${_var_remoteurl//aur4.archlinux.org/}" != "${_var_remoteurl}" ]; then
      if [ "${_opt_ALL}" -ne 0 ]; then
        echo "Warning: You should change your origin away from AUR4. Try: pushd '${_var_pwdbn}' >/dev/null && { git remote set-url origin '${_var_remoteurl//aur4.archlinux.org/aur.archlinux.org}'; popd >/dev/null; }"
      else
        echo "Warning: You should change your origin away from AUR4. Try: git remote set-url origin '${_var_remoteurl//aur4.archlinux.org/aur.archlinux.org}'"
      fi
      [ "${returnv}" -ge 1 ] || returnv=1
    fi
    # git-clone from AUR should block the cloning of new repository packages in core/extra, but it doesn't.
    if [ "${_var_remoteurlbn}" != "${_var_pwdbn}" ]; then
      echo '******************************************************'
      echo "The git package name doesn't match the folder name. Did you clone the wrong package?"
      git ls-remote --get-url
      echo "Folder: ${_var_pwdbn}"
      echo '******************************************************'
      [ "${returnv}" -ge 3 ] || returnv=3
    fi
    unset _var_remoteurl
    unset _var_remoteurlbn
#set > x # look for variables we forgot to unset
  else
    echo "${_var_pwdbn} is not an ${_opt_AUR4} package."
    if [ "${_var_pwd}" = ~/build ]; then
      echo 'This looks like a build folder.'
      echo "To check all with write access try: $0 -a | less"
      echo "To check just one try: cd foo; $(basename "$0")"
    elif [ -d ~/build ]; then
      echo 'Run this in your build folder to check many packages.'
    fi
    if [ -f 'PKGBUILD' ]; then
      # rm -rf a folder that likely exists is quite dangerous so we do 3 safety steps: stop if files and folderse aren't right, set -e to crash on any error, and clone to a temp folder.
      # To keep things safe does make the command a bit complex. I'm hoping this is histexpand safe.
      echo 'You can easily upgrade to read or write access without losing your files with:'
      echo "Write: test -s PKGBUILD -a '!' -d .git -a '!' -d '${_var_pwdbn}.aurtmp' && { git clone 'ssh://aur@${_opt_AUR4}.archlinux.org/${_var_pwdbn}.git' '${_var_pwdbn}.aurtmp' && mv '${_var_pwdbn}.aurtmp/.git' . && rm -rf '${_var_pwdbn}.aurtmp'} || echo 'How about NO!'"
      echo "Read: test -s PKGBUILD -a '!' -d .git -a '!' -d '${_var_pwdbn}.aurtmp' && { git clone 'https://${_opt_AUR4}.archlinux.org/${_var_pwdbn}.git/' '${_var_pwdbn}.aurtmp' && mv '${_var_pwdbn}.aurtmp/.git' . && rm -rf '${_var_pwdbn}.aurtmp'} || echo 'How about NO!'"
    fi
    [ "${returnv}" -ge 3 ] || returnv=3
  fi

  local _var_file
  for _var_file in '.MTREE' '.AURINFO' '.PKGINFO' '.INSTALL'; do
    if [ -f "${_var_file}" ]; then
      echo "Warning: ${_var_file} should be deleted"
      [ "${returnv}" -ge 1 ] || returnv=1
    fi
  done
}

_fn_usage() {
  local _var_BN
  _var_BN="$(basename "$0")"
cat << EOF
git-aurcheck ${_opt_VERSION} (C)2015 by severach for Arch Linux (GPL3+)
  -h crude help
  -a from ~/build folder, check all packages with write access
  -x= exclude package folders from -a scan. Ignored without -a.
  package[s] scan only specific packages. Exclusions dominate.
  -p pedantic, adds extra checks. Up to thrice for maximum pedantry.
  -v check for new version with PKGBUILD _verwatch.
  -t= change to target folder before starting. Useful for cron.
  -V= elevate new version warning to desired exit code. Numbers only.

To check for common problems in a package folder:
  cd ~/build/foo
  ${_var_BN}
To check for all problems and new versions in a package folder:
  ${_var_BN} -pppv
To check for problems in all packages with git ssh write access except foo,bar
  cd ~/build
  ${_var_BN} -a -x foo -x bar
To scan for updates in packages foo and bar
  ${_var_BN} -t $HOME/user/build -Vva foo bar
EOF
}

_opt_ALL=0
#_opt_FORCE=0 # If ever implemented, would automatically perform as many safe changes as possible.
_opt_PEDANTIC=0
_opt_VERSION=0
_opt_EXCLUDES=()
_opt_VEREXITCODE=1
_opt_DEBUG=''
_opt_DEBUGVER=0

while getopts ':hafpvx:t:V:D:' _var_opt; do
  case "${_var_opt}" in
    h) _fn_usage; exit 0;;
    a) _opt_ALL=1;;
#    f) _opt_FORCE=1;; # cannot be specified with -a
    p) _opt_PEDANTIC=$((_opt_PEDANTIC + 1));;
    v) _opt_VERSION=1;;
    x) _opt_EXCLUDES+=("${OPTARG}");;
    t) cd "${OPTARG}";; # from install -t
    V) _opt_VEREXITCODE="${OPTARG}";;
    D) _opt_DEBUG="${OPTARG}";;
    :) echo "$(basename "$0"): Option '-${OPTARG}' requires an argument" >&2
       exit 126;;
    *) echo "$(basename "$0"): Invalid option '-${OPTARG}'" >&2
       _fn_usage; exit 126;;
  esac
done
unset _var_opt
_opt_POSARGS=("${@: ${OPTIND}}")

test "${_opt_DEBUG/v/}" != "${_opt_DEBUG}" && _opt_DEBUGVER=1 || _opt_DEBUGVER=0 # -Dv

returnv=0
if [ "${_opt_ALL}" -ne 0 ]; then
  if [ -e 'PKGBUILD' ] ;then
    echo 'This looks like a package folder. Maybe you want to leave -a off.'
    exit 126
  elif [ "${#_opt_POSARGS[@]}" -ne 0 ]; then
#    _opt_FORCE=0
    for builddir in "${_opt_POSARGS[@]}"; do
      if [ -s "${builddir}/.git/config" ] && ! _fn_find_in_EXCLUDES "${builddir}" && pushd "${builddir}" >/dev/null; then
        echo "Checking ${builddir}"
        _fn_aurcheck
        popd >/dev/null
      fi
    done
  else
#    _opt_FORCE=0
    for builddir in *; do
      # It doesn't do any good to check packages that you can't fix because they aren't yours.
      # We consider writable ssh:// to be yours and read only http:// to not be yours.
      # Use https:// to clone packages you don't have write access to.
      # You can fix errant clones with the https url on the package page.
      # Example:
      # cd ~/build/foo
      # git ls-remote --get-url
      # git remote set-url origin "https://aur.archlinux.org/$(basename "$(pwd)").git/"
      # git remote show origin -n
      if [ -s "${builddir}/.git/config" ] && ! _fn_find_in_EXCLUDES "${builddir}" && grep -qlF $'url = ssh://\nurl = ssh+git://' "${builddir}/.git/config" && pushd "${builddir}" >/dev/null; then
        echo "Checking ${builddir}"
        _fn_aurcheck
        popd >/dev/null
      fi
    done
  fi
else
  _fn_aurcheck
fi

exit "${returnv}"
