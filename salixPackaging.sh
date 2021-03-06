#!/bin/sh
# vim: et sw=2 sts=2 ts=2 tw=0:

__copyright__="Cyrille Pontvieux <jrd@enialis.net>"
__license__="GPLv2+"
__version__="1.0"

cd $(dirname "$0")
# encusre /sbin and /usr/sbin are in the PATH (in case of a sudo)
PATH=/sbin:/usr/sbin:$PATH
export PATH
  
CFG_FILE=/etc/salixPackaging
LOCALREPO_URL=https://github.com/jrd/localrepo/raw/master/localrepo
networkBase=192.168.100

CNONE="[0m"
CBOLD="[;1m"
CRED="[31m"; CLRED="[31;1m"
CGREEN="[32m"; CLGREEN="[32;1m"
CMAROON="[33m"; CYELLOW="[33;1m"
CBLUE="[34m"; CLBLUE="[34;1m"
CMAGENTA="[35m"; CLMAGENTA="[35;1m"
CCYAN="[36m"; CLCYAN="[36;1m"
CGREY="[37m"; CLGREY="[37;1m"
CWHITE="[38m"; CLWHITE="[38;1m"

usage() {
  needroot="$CLRED*$CNONE"
  notimplemented="$CMAGENTA:'($CNONE"
  cat <<EOF
Usage: salixPackaging [OPTIONS]
Help a packager to manage his/her packages for Salix.

Where OPTIONS are:
  -h, --help
    This usage
  -V, --version
    Show the version
  --check
    Sanity check of Host environment.
  --prepare $needroot
    Prepare the host to install LXC versions of Salix.
  --register
    Register your information as packager.
  --install=VERSION,ARCH $needroot
    Install a LXC version of Salix for the specified VERSION and ARCH. ARCH could be 'i486' or 'x86_64'.
  --list-installed
    List all LXC Salix version installed.
  --remove=VERSION,ARCH $needroot
    Remove a LXC Salix version.
  -c, --create
    Create a new package.
  -l, --pkg-list
    Show all packages and their state.
  -p, --pkg-info=PACKAGE_NAME
    Show some information about the PACKAGE_NAME.
  -e, --edit=PACKAGE_NAME,PACKAGE_VER,VERSION
    Edit a PACKAGE_NAME SLKBUILD file, version PACKAGE_VER, for Salix VERSION.
  -v, --verify=PACKAGE_NAME,VERSION
    Verify the latest stable version of the PACKAGE_NAME for the Salix VERSION.
  -a, --verify-all [=PACKAGE_NAME]
    Verify the latest stable version on all packages. Will take some time.
  -u, --update=PACKAGE_NAME,VERSION
    Update an already existing package for the Salix VERSION.
  -b, --build=PACKAGE_NAME,PACKAGE_VER,VERSION,ARCH[,NUMJOBS]
    Schedule to build PACKAGE_NAME, version PACKAGE_VER, for Salix version VERSION and ARCH.
    NUMJOBS indicate the number of processors/cores to use when building. Default 1.
    The build is appened to the queue.
  -q, --queue=ACTION
    Manage the build queue. ACTION could be:
    - list list the queue
    - clear clear the queue
    - remove:POSITION1,POSITION2,… remove a build from the queue, POSITION could be a position or a range in the form 2-5.
    - run execute the builds in order from the queue. Each successful build is removed from the queue.
  -r, --rsync
    Rsync the local repo to your remote one.
  -t, --ticket=PACKAGE_NAME,VERSION TICKET_NUMBER
    Create a ticket on Salix Tracker about PACKAGE_NAME and Salix VERSION for all built ARCH.
    If TICKET_NUMBER is specified, add it as a comment on that ticket rather than creating a new one.
  -i, --interactive $notimplemented
    Will enter an interactive mode if used with -l, -p, -v, -q. Creating a package (-c), editing a package (-e), and creating a ticket (-t) are always interactive.

  $needroot: root privileges required
  $notimplemented: not implemented yet
EOF
}

show_version() {
  cat <<EOF
salixPackaging v.$__version__
Copyright $__copyright__
License $__license__
EOF
}

usage_ver_arch() {
  cat <<EOF
LXC should be filled in the form:
  version,arch
Where 'version' could be '14.0', '14.1' for example
And 'arch' could be 'i486' or 'x86_64' for example.
EOF
}
check_ver_arch() {
  echo "$1"|grep -vq '^[^,]\+,[^,]\+$' && usage_ver_arch && exit 1
}

usage_pkg_ver() {
  cat <<EOF
Package should be filled in the form:
  package_name,salix_version
Where 'salix_version' could be '14.0', '14.1' for example.
EOF
}
check_pkg_ver() {
  echo "$1"|grep -vq '^[^,]\+,[^,]\+$' && usage_pkg_ver && exit 1
}

usage_pkg_ver_ver() {
  cat <<EOF
Package should be filled in the form:
  package_name,package_ver,salix_version
Where 'salix_version' could be '14.0', '14.1' for example.
EOF
}
check_pkg_ver_ver() {
  echo "$1"|grep -vq '^[^,]\+,[^,]\+,[^,]\+$' && usage_pkg_ver_ver && exit 1
}

usage_pkg_ver_ver_arch() {
  cat <<EOF
Package should be filled in the form:
  package_name,package_ver,salix_version,arch
Where 'salix_version' could be '14.0', '14.1' for example
And 'arch' could be 'i486', 'x86_64' or 'noarch'.
EOF
}
check_pkg_ver_ver_arch() {
  echo "$1"|grep -vq '^[^,]\+,[^,]\+,[^,]\+,[^,]\+\(,[1-9]\+\)\?$' && usage_pkg_ver_ver_arch && exit 1
}

check_root() {
  if [ $(id -u) -ne 0 ]; then
    echo "You should run this action with root privileges." >&2
    exit 1
  fi
}

check_net_device() {
  [ -d /sys/class/net/"$1" ] && [ $(cat /sys/class/net/"$1"/type) -lt 256 ]
}

notnull() {
  [ -n "$1" ]
}
READ_VALUE=
# Prompt for a value, using an optional default value
# $1 = prompt
# $2 = default value
# $3 = command to check for validity, takes a value as argument. 'notnull' is accepted as special value
# The value is put in the global READ_VALUE variable
# exit with error on ctrl+c
read_info() {
  _prompt="$1"
  _def="$2"
  _check="$3"
  [ -z "$_check" ] && _check=true
  _value=
  [ -n "$_def" ] && _prompt="$_prompt [$_def]: " || _prompt="$_prompt: "
  _valid=false
  trap 'printf "\nInterrupted\n";exit 2' 2 # will break on ctrl+c
  while ! $_valid; do
    printf "$_prompt"
    read -r _value # hopes the -r is portable enough
    [ -n "$_def" ] && [ -z "$_value" ] && _value="$_def"
    $_check "$_value" && _valid=true
  done
  trap 2 # restore normal behavior
  if $_valid; then
    READ_VALUE=$_value
    return 0
  else
    READ_VALUE=
    return 1
  fi
}
# Will ask for a choice between possibilities.
# case insensitive (A-Z only)
# $1 = prompt
# $2 = choices, separated by spaces in lowercase
# $3 = default value
# $4 = case insensitive (true, default) or not (false)
# The chosen value is put in the global READ_VALUE variable
# exit with error on ctrl+c
read_choice() {
  _prompt="$1"
  _choices="$2"
  _def="$3"
  _case_insensitive="$4"
  [ -z "$_case_insensitive" ] && _case_insensitive=true
  if $_case_insensitive; then
    _filterval='tr A-Z a-z'
  else
    _filterval='cat'
  fi
  _value=
  _prompt="$_prompt ["
  _first=true
  for _c in $_choices; do
    $_first || _prompt="${_prompt},"
    _first=false
    [ "$_c" = "$_def" ] && _c=${CBOLD}$(echo "$_c"|sed 's/\$/*/')${CNONE}
    _prompt="${_prompt}${_c}"
  done
  _prompt="$_prompt]? "
  _valid=false
  trap 'printf "\nInterrupted\n";exit 2' 2 # will break on ctrl+c
  while ! $_valid; do
    printf "$_prompt"
    read -r _value # hopes the -r is portable enough
    _value=$(echo "$_value"|$_filterval)
    [ -n "$_def" ] && [ -z "$_value" ] && _value="$_def"
    for _c in $_choices; do
      _c=$(echo "$_c"|$_filterval)
      if [ "$_value" = "$_c" ]; then
        _valid=true
        break
      fi
    done
  done
  trap 2 # restore normal behavior
  if $_valid; then
    READ_VALUE=$_value
    return 0
  else
    READ_VALUE=
    return 1
  fi
}

action_check() {
  ok="${CLGREEN}OK$CNONE"
  fail="${CLRED}Fail$CNONE"
  if lxc-checkconfig; then
    echo "LXC: $ok"
  else
    echo "LXC: $fail"
    return 1
  fi
  printf "Arch: "
  if [ $(uname -m) = x86_64 ]; then
    echo "$ok"
  else
    echo "$fail"
    echo "You're not running a 64bits OS, you will not be able to build x86_64 package." >&2
    echo "Please, run a Salix 64bits to make packages." >&2
    return 1
  fi
  printf "bridge utils: "
  if /usr/sbin/brctl --help >/dev/null 2>&1; then
    echo "$ok"
  else
    echo "$fail"
    echo "brctl could not be found, please install bridge-utils." >&2
    return 1
  fi
  printf "rc.local: "
  if grep -q lxcbr0 /etc/rc.d/rc.local; then
    echo "$ok"
  else
    echo "$fail"
    echo "rc.local seems not to contain the needed preparation for LXC Bridge." >&2
    echo "Please, launch the prepare action." >&2
    return 1
  fi
  printf "Bridge: "
  if ifconfig|grep -q 'lxcbr0:'; then
    echo "$ok"
  else
    echo "$fail"
    echo "lxcbr0 bridge interface seems not to be configured." >&2
    echo "Please, run /etc/rc.d/rc.local to install it." >&2
    return 1
  fi
  return 0
}

action_prepare() {
  check_root
  read_info "What is your Internet device (wlan0 or eth0 for example)" '' check_net_device
  extIface=$READ_VALUE
  cat <<EOF >> /etc/rc.d/rc.local
# salixPackaging
networkBase=$networkBase
extIface=$extIface
brctl addbr lxcbr0
brctl setfd lxcbr0 0
ifconfig lxcbr0 \$networkBase.1 netmask 255.255.255.0 promisc up
iptables -t nat -A POSTROUTING -s \$networkBase.0/24 -o \$extIface -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF
  cat <<EOF >> /etc/rc.d/rc.local_shutdown
# salixPackaging
ifconfig lxcbr0 down
brctl delbr lxcbr0
EOF
  brctl addbr lxcbr0
  brctl setfd lxcbr0 0
  ifconfig lxcbr0 $networkBase.1 netmask 255.255.255.0 promisc up
  iptables -t nat -A POSTROUTING -s $networkBase.0/24 -o $extIface -j MASQUERADE
  echo 1 > /proc/sys/net/ipv4/ip_forward
  touch $CFG_FILE
  chmod a+rw $CFG_FILE
  echo "Bridge interface ${CLGREEN}lxcbr0$CNONE configured. Using IP ${CLGREEN}$networkBase.1$CNONE."
}

action_register() {
  cat <<EOF
Packager Information
====================

Please give some information about yourself and about your remote repository.
If you don't have a remote repository to hold your packages, please send an
email to the ML http://lists.sourceforge.net/lists/listinfo/salix-main in
order to have a space at people.salixos.org.
If you never already made some packages for Salix, take a look here:
http://docs.salixos.org/wiki/Packaging_rules

Hit Ctrl+C to abort.

EOF
  read_info 'Name' '' notnull || return 1
  name="$READ_VALUE"
  read_info 'Email' '' notnull || return 1
  email="$READ_VALUE"
  tag=$(for n in $(echo "$name"|tr '-' ' '); do echo -n "$n"|sed -r 's/^(.).*/\1/'|tr A-Z a-z; done)
  read_info 'Package tag' "$tag" || return 1
  tag="$READ_VALUE"
  read_info 'Remote URL' "http://people.salixos.org/$USER/salix" check_url || return 1
  url="$READ_VALUE"
  read_info 'SCP URI for Rsync' "simplynux.net:www/salix" check_scp_uri || return 1
  scpuri="$READ_VALUE"
  read_info 'Schema location' '$pkgname/$pkgver-$arch-$pkgrel' notnull || return 1
  schema="$READ_VALUE"
  read_info "Your Sourceforge bearer token authentication is needed.\nYou can make one on https://sourceforge.net/auth/oauth/\nBearer Token" '' notnull
  token="$READ_VALUE"
  cat <<EOF > $CFG_FILE
pkgr_name="$name"
pkgr_email="$email"
pkgr_tag=$tag
pkgr_url='$url'
pkgr_scpuri='$scpuri'
pkgr_schema='$schema'
pkgr_user='$USER'
pkgr_uid=$(id -u)
pkgr_token=$token
EOF
  return 0
}

check_url() {
  url="$1"
  if [ "$url" = 'SKIP' ]; then
    echo 'Skipping'
  elif ! wget --no-check-certificate -O /dev/null -q "$url"; then
    echo "$url is not valid" >&2
    false
  fi
}

check_scp_uri() {
  scpuri="$1"
  tmp=$(mktemp -d)
  if sshfs -o uid=$(id -u) -o gid=$(id -g) "$scpuri" $tmp; then
    echo "Connection ok, disconnecting..."
    sleep 3
    fusermount -u $tmp
    sleep 1
    rmdir $tmp
    true
  else
    rmdir $tmp
    echo "$scpuri is not valid" >&2
    false
  fi
}

check_registered() {
  if [ ! -r "$CFG_FILE" ] || ! grep -q pkgr_name $CFG_FILE; then
    echo "You should first register as a packager." >&2
    exit 1
  fi
}

action_install() {
  ver=$1
  arch=$2
  check_root
  check_registered
  echo "Creating LXC Salix $ver - $arch"
  # find next number for IP and Mac address
  n=$(find_installed_salix|wc -l)
  # host start at 1, so next add +2
  NUMIP=$(($n + 2))
  NUMMAC=$(/bin/echo -e "obase=16\n$n + 2"|bc) # hexa
  [ "$NUMIP" -lt 16 ] && NUMMAC="0$NUMMAC" # before 16=0x10, prepend a 0
  conf=$(mktemp)
  sed -r "s/@NUMIP@/$NUMIP/; s/@NUMMAC@/$NUMMAC/;" lxc-default.conf > $conf
  name=salixpkg-$ver-$arch
  if lxc-create -n $name -f $conf -t $PWD/lxc-salix -- --arch=$arch --release=$ver; then
    rm $conf
    . $CFG_FILE
    chroot /var/lib/lxc/$name/rootfs sh -c "echo 'pkg:pkg:$pkgr_uid:users::/home/pkg:/bin/bash'|/usr/sbin/newusers"
    chroot /var/lib/lxc/$name/rootfs /usr/sbin/usermod -a -G lp,wheel,floppy,audio,video,cdrom,plugdev,power,netdev,scanner pkg
    chmod +x /var/lib/lxc/$name/rootfs/etc/rc.d/rc.sshd
    mkdir -p /var/lib/lxc/$name/rootfs/root/.ssh /var/lib/lxc/$name/rootfs/home/pkg/.ssh
    touch /var/lib/lxc/$name/rootfs/root/.ssh/authorized_keys /var/lib/lxc/$name/rootfs/home/pkg/.ssh/authorized_keys
    chroot /var/lib/lxc/$name/rootfs chown -R pkg: /home/pkg/.ssh
    chmod go= /var/lib/lxc/$name/rootfs/root/.ssh /var/lib/lxc/$name/rootfs/home/pkg/.ssh
    for sec in rsa dsa; do
      if [ -e /home/$pkgr_user/.ssh/id_$sec.pub ]; then
        cat /home/$pkgr_user/.ssh/id_$sec.pub > /var/lib/lxc/$name/rootfs/root/.ssh/authorized_keys
        cat /home/$pkgr_user/.ssh/id_$sec.pub > /var/lib/lxc/$name/rootfs/home/pkg/.ssh/authorized_keys
        break
      fi
    done
    # local repository
    wget -q -O /var/lib/lxc/$name/rootfs/usr/local/sbin/localrepo "$LOCALREPO_URL"
    chmod +x /var/lib/lxc/$name/rootfs/usr/local/sbin/localrepo
    # script to install deps
    cat <<'EOF' > /var/lib/lxc/$name/rootfs/usr/local/sbin/installdeps
#!/bin/sh
set -e
if [ -n "$1" ]; then
  /usr/sbin/slapt-get -u
  pkgs=''
  for p in $(echo "$1"|tr ',' ' '); do
    if echo "$p" | grep -q '|'; then
      for p2 in $(echo "$p"|tr '|' ' '); do
        /usr/sbin/slapt-get --filelist $p2 > /dev/null && break
        pkgs="$pkgs $p2"
        break
      done
    else
      pkgs="$pkgs $p"
    fi
  done
  /usr/sbin/slapt-get -i $pkgs
fi
EOF
    chmod +x /var/lib/lxc/$name/rootfs/usr/local/sbin/installdeps
    if lxc-start -d -n $name; then
      echo "LXC started."
      sleep 3 # ensure all is started in the container
      chroot /var/lib/lxc/$name/rootfs /usr/local/sbin/localrepo -c
      return 0
    else
      echo "Cannot start the LXC." >&2
      return 1
    fi
  else
    rm $conf
    echo "Cannot create the LXC." >&2
    return 1
  fi
}

find_installed_salix() {
  lxc-ls -1|sed -rn '/^salixpkg-/{s/^salixpkg-//;p}'|sort
}

action_listinstalled() {
  find_installed_salix|sed -r 's/^([^-]+)-(.*)/ - \1, \2/'
  return $?
}

action_remove() {
  ver=$1
  arch=$2
  check_root
  echo "Removing LXC Salix $ver - $arch"
  lxc-stop -n salixpkg-$ver-$arch
  lxc-destroy -n salixpkg-$ver-$arch
  return $?
}

check_numlxc() {
  if [ $(find_installed_salix|wc -l) -eq 0 ]; then
    echo "You should first install a Salix LXC version." >&2
    exit 1
  fi
}

action_create() {
  check_registered
  check_numlxc
  cat <<EOF
Package creation
================

EOF
  read_info 'Package name' '' notnull || return 1
  pkg_name="$READ_VALUE"
  if [ -e src/$pkg_name ]; then
    # Package already exists so we must just ask to create it for missing LXC Salix version
    already=''
    new=''
    for salix_ver in $(find_installed_salix|cut -d- -f1|sort -u); do
      if [ -e src/$pkg_name/$salix_ver ]; then
        already="$already $salix_ver"
      else
        new="$new $salix_ver"
      fi
    done
    already=$(echo "$already"|sed 's/^ *//; s/ *$//;') # trim
    new=$(echo "$new"|sed 's/^ *//; s/ *$//;') # trim
    if [ -z "$new" ]; then
      echo "Package already exists and no new Salix version found" >&2
      return 1
    else
      salix_ver_ref=$(echo "$already"|tr ' ' '\n'|sort -r|head -n1)
      echo "Package found in Salix version $salix_ver_ref."
      echo "Install it into $new."
      pkg_ver=$(cat src/$pkg_name/$salix_ver_ref/version)
      for salix_ver in $new; do
        copy_package_build "$pkg_name" "$pkg_ver" "$salix_ver_ref" "$salix_ver" true
      done
      echo "Done."
    fi
  else
    read_choice 'Package architectures' 'all noarch arm i486 x86_64' 'all'
    pkg_arch="$READ_VALUE"
    read_info 'Home page (SKIP to skip)' '' check_url || return 1
    [ "$READ_VALUE" != 'SKIP' ] && pkg_url="$READ_VALUE"
    read_info 'Download URL page (SKIP to skip)' '' check_url || return 1
    [ "$READ_VALUE" != 'SKIP' ] && pkg_dl_url="$READ_VALUE"
    if [ -n "$pkg_dl_url" ]; then
      pkg_check_schema=''
      choices=''
      for c in $(find templates/version -type f|sort); do
        c=$(basename "$c")
        choices="$choices $c"
      done
      while true; do
        while [ -z "$pkg_check_schema" ]; do
          read_choice "Latest version check schema.\nChoose from" "$choices custom help" 'help' || return 1
          pkg_check_schema="$READ_VALUE"
          case $pkg_check_schema in
            custom)
              echo "A custom pattern is a filter on the HTML download page"
              echo "in order to find the latest stable version."
              echo "Example:"
              echo "  sed -rn 'FIXME'|grep -v 'alpha\|beta\|rc'|sort -rV"
              read_info 'Custom pattern' '' notnull || return 1
              pkg_check_pattern="$READ_VALUE"
              ;;
            help)
              for c in $choices; do
                [ $c = custom ] && continue
                . ./templates/version/$c
                echo "$c: $version_pattern"
                echo "    $help_text"
                unset version_pattern
                unset help_text
                unset download_pattern
              done
              pkg_check_schema=''
              ;;
            *)
              . ./templates/version/$pkg_check_schema
              pkg_check_pattern=$version_pattern
              unset version_pattern
              unset help_text
              unset download_pattern
              ;;
          esac
        done
        echo "Pattern: $pkg_check_pattern"
        printf "Versions found: "
        pkg_versions=$(find_all_versions "$pkg_dl_url" "$pkg_check_pattern")
        echo "$pkg_versions"
        read_choice "Pattern ok" "y n" "y" || return 1
        [ $READ_VALUE = y ] && break;
      done
      read_choice "Allow betas versions" "y n" "n" || return 1
      if [ $READ_VALUE = n ]; then
        pkg_stable=true
      else
        pkg_stable=false
      fi
      printf "Latest version found: "
      pkg_ver=$(find_latest_version "$pkg_versions" "$pkg_stable")
      echo $pkg_ver
      read_choice "Use this version" "y n" "y" || return 1
      if [ $READ_VALUE = n ]; then
        read_info "Then, which specific version" "$pkg_ver" notnull || return 1
        pkg_ver="$READ_VALUE"
        pkg_fixver=true
      else
        pkg_fixver=false
      fi
      pkg_md5=$(wget --no-check-certificate -q -O - "$pkg_dl_url"|grep '<a href'|grep -v 'http://'|md5sum|sed 's/  -//')
    else
      read_info "Version" '' notnull || return 1
      pkg_ver="$READ_VALUE"
      pkg_check_schema='custom'
      pkg_check_pattern=''
      pkg_md5=''
      pkg_stable=false
      pkg_fixver=true
    fi
    read_choice "Build schema" "$(for f in templates/build/*; do basename $f; done)" 'configure' || return 1
    pkg_build_schema="$READ_VALUE"
    salix_ver_ref=''
    for salix_ver in $(find_installed_salix|cut -d- -f1|sort -u); do
      if [ -z "$salix_ver_ref" ]; then
        store_package_info "$salix_ver" "$pkg_name" "$pkg_arch" "$pkg_url" "$pkg_dl_url" "$pkg_check_schema" "$pkg_check_pattern" "$pkg_md5" "$pkg_ver" "$pkg_stable" "$pkg_fixver" "$pkg_build_schema"
        salix_ver_ref="$salix_ver"
      else
        copy_package_build "$pkg_name" "$pkg_ver" "$salix_ver_ref" "$salix_ver" false
      fi
    done
  fi
  return 0
}

# Find all versions
# Returns versions separated by space. "up to date" or "changed" for md5 checks
# $1 = URL to check
# $2 = pattern for the URL
# $3 = referenced md5sum
find_all_versions() {
  _url="$1"
  _pat="$2"
  _md5ref="$3"
  _filter=$(mktemp) # better than using eval I think.
  echo '#!/bin/sh' > $_filter
  printf "$_pat" >> $_filter
  chmod +x $_filter
  _versions=$(wget --no-check-certificate -q -O - "$_url"|$_filter)
  rm $_filter
  if echo "$_versions"|grep -q '^MD5:'; then
    _md5=$(echo "$_versions"|sed 's/MD5://')
    if [ "$_md5" = "$_md5ref" ]; then
      echo "up to date"
    else
      echo "changed"
    fi
  else
    echo "$_versions"
  fi
}

# Find the latest version
# Returns the version or "up to date" or "changed"
# $1 = versions sorted in reveres order
# $2 = from stable versions only (true, by default) or from all versions (false)
find_latest_version() {
  _versions="$1"
  _stable="$2"
  [ -z "$_stable" ] && _stable=true
  if echo "$_versions"|grep -q "up to date\|changed"; then
    echo "$_versions"
  else
    if $_stable; then
      _versions=$(echo "$_versions"|grep -vi 'alpha\|beta\|m[0-9]\|rc')
    fi
    _ver=$(echo "$_versions"|head -n1)
    echo "$_ver"
  fi
}

store_package_info() {
  salix_ver="$1"; shift
  pkg_name="$1"; shift
  pkg_arch="$1"; shift
  pkg_url="$1"; shift
  pkg_dl_url="$1"; shift
  pkg_check_schema="$1"; shift
  pkg_check_pattern="$1"; shift
  pkg_md5="$1"; shift
  pkg_ver="$1"; shift
  pkg_stable="$1"; shift
  pkg_fixver="$1"; shift
  pkg_build_schema="$1"; shift
  mkdir -p src/$pkg_name/$salix_ver
  (
    cd src/$pkg_name
    echo "$pkg_arch" > arch
    echo "$pkg_url" > url
    echo "$pkg_dl_url" > dlurl
    echo "$pkg_md5" > md5sum
    echo "$pkg_check_schema" > schema
    echo "$pkg_check_pattern" > pattern
    echo "$pkg_build_schema" > buildschema
    echo "$pkg_ver" > $salix_ver/version
    echo "$pkg_stable" > $salix_ver/stable
    echo "$pkg_fixver" > $salix_ver/fixversion
  )
  store_package_build "$pkg_name" "$pkg_ver" "$salix_ver"
  echo "Information for package ${CGREEN}${pkg_name}$CNONE has been stored for $salix_ver."
}

store_package_build() {
  pkg_name="$1"
  pkg_ver="$2"
  salix_ver="$3"
  . $CFG_FILE
  pkg_arch=$(cat src/$pkg_name/arch)
  pkg_url=$(cat src/$pkg_name/url)
  dl_url=$(cat src/$pkg_name/dlurl)
  schema=$(cat src/$pkg_name/schema)
  pkg_dl_url=${dl_url}'/${pkgname}-${pkgver}.tar.gz'
  if [ $schema != custom ]; then
    . ./templates/version/$schema
    pkg_dl_url="$download_pattern"
  fi
  unset version_pattern
  unset help_text
  unset download_pattern
  pkg_build_schema=$(cat src/$pkg_name/buildschema)
  pkgr_email_dot=$(echo "$pkgr_email"|sed -r 's/\./~dot~/g; s/@/~at~/g;')
  arch_var=''
  if [ $pkg_arch != all ]; then
    arch_var="arch=$pkg_arch"
  fi
  pkgr_schema_archprotected=$(echo "$pkgr_schema"|sed -r 's/\$arch/\\$arch/g;')
  pkgr_schema_protected=$(echo "$pkgr_schema_archprotected"|sed -r 's/\\/\\\\/g;')
  mkdir -p src/$pkg_name/$salix_ver/$pkg_ver
  pkg_ver_slackware=$(echo $pkg_ver|sed -r 's/[-_]/./g') # Slackware does not allow hyphens or underscores in package version
  cat <<EOF|sed -f - templates/SLKBUILD > src/$pkg_name/$salix_ver/$pkg_ver/SLKBUILD
  s/@PNAME@/$pkgr_name/;
  s/@PEMAIL@/$pkgr_email_dot/;
  s/@NAME@/$pkg_name/;
  s/@VER@/$pkg_ver_slackware/;
  s/@RLZ@/1/;
  s/@PTAG@/$pkgr_tag/;
  s/@ARCHVAR@/$arch_var/;
  s,@DLURL@,$pkg_dl_url,;
  s,@PURL@,$pkgr_url,;
  s,@PSCHEMA@,$pkgr_schema_protected,;
  s,@URL@,$pkg_url,;
  /^build()/ rtemplates/build/$pkg_build_schema
EOF
  for dep in dep makedep sug con; do
    cat /dev/null > src/$pkg_name/$salix_ver/$pkg_ver/$dep
  done
  action_edit "$pkg_name" "$pkg_ver" "$salix_ver"
}

copy_package_build() {
  pkg_name="$1"
  pkg_ver="$2"
  salix_ver="$3"
  salix_newver="$4"
  ask="$5"
  mkdir -p src/$pkg_name/$salix_newver/$pkg_ver
  cp src/$pkg_name/$salix_ver/version src/$pkg_name/$salix_newver/
  cp src/$pkg_name/$salix_ver/$pkg_ver/* src/$pkg_name/$salix_newver/$pkg_ver/
  echo "$pkg_ver" > src/$pkg_name/$salix_newver/version
  if $ask; then
    read_choice "Use this specific fixed ($pkg_ver) version" "y n" "n" || return 1
    if [ $READ_VALUE = y ]; then
      echo "true" > src/$pkg_name/$salix_newver/fixversion
    else
      echo "false" > src/$pkg_name/$salix_newver/fixversion
    fi
  else
    cp src/$pkg_name/$salix_ver/fixversion src/$pkg_name/$salix_newver/
  fi
  echo "Information for package ${CGREEN}${pkg_name}$CNONE has been stored for ${CGREEN}${salix_ver}${CNONE}."
}

copy_package_ver_build() {
  pkg_name="$1"
  salix_ver="$2"
  pkg_ver="$3"
  pkg_newver="$4"
  mkdir -p src/$pkg_name/$salix_ver/$pkg_newver
  cp src/$pkg_name/$salix_ver/$pkg_ver/* src/$pkg_name/$salix_ver/$pkg_newver/
  if grep -q '^_pkgver' src/$pkg_name/$salix_ver/$pkg_newver/SLKBUILD; then
    sed -ri "s/^_pkgver=.*/_pkgver=$pkg_newver/" src/$pkg_name/$salix_ver/$pkg_newver/SLKBUILD
  else
    sed -ri "s/^pkgver=.*/pkgver=$pkg_newver/" src/$pkg_name/$salix_ver/$pkg_newver/SLKBUILD
  fi
  echo "Information for package ${CGREEN}${pkg_name}$CNONE has been stored in version ${CGREEN}${pkg_newver}${CNONE}, for Salix $salix_ver."
}

# $1 = text
# $2 = start pos (could be empty for 0)
# $3 = end pos (could be empty for EOL)
center_text() {
  _text="$1"
  _x0="$2"
  [ -n "$_x0" ] || _x0=0
  _x1="$3"
  [ -n "$_x1" ] || _x1=$(tput cols)
  _text2=$(printf "$_text"|sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g") # remove color codes to compute length
  _s=$(expr length "$_text2")
  if [ $(( $_x1 - $_x0 )) -gt $_s ]; then
    _pos=$(( ($_x1 + $_x0 - $_s) / 2 ))
    tput hpa $_pos
  else
    tput hpa $_x0
  fi
  printf "$_text"
}

# $1 = character to repeat
# $2 = number of repetition
rep_char() {
  printf "%${2}s"|sed "s/ /$1/g"
}

# $1 = lines, separated by newlines, each column separated be a coma (CSV)
# $2 = headers, CSV format
# $3 = columns colors, CSV format. Each color is specified as ANSI
# $4 = columns minimum size, CSV format. Each size is specified as a positive number, following by a * to indicate it can grow or not.
# $5 = title
# $6 = prompt
# $7 = actions possible character/action.
# return the choosen action in CHOOSEN_ACTION variable
CHOOSEN_ACTION=''
show_interactive_list() {
  lines="$1"
  headers="$2"
  colcolors="$3"
  colsizes="$4"
  title="$5"
  prompt="$6"
  actions="$7"
  CHOOSEN_ACTION=''
  tput reset
  TCOLS=$(tput cols)
  TLINES=$(tput lines)
  center_text "$title\n"
  n=$((1+$(printf -- "$headers"|sed 's/[^,]//g'|wc -m)))
  varsizes=''
  sum=1
  realsizes=$(printf "$colsizes"|sed 's/\*//g'|tr ',' "\n") # one on each line
  for i in $(seq $n); do
    colsize=$(printf -- "$colsizes"|cut -d, -f$i)
    if echo "$colsize"|grep -q '*'; then
      varsizes="$varsizes $i"
      colsize=$(printf "$colsize"|sed 's/\*$//')
    fi
    sum=$(($sum + $colsize + 1)) # 1 = sep
  done
  while [ $TCOLS -gt $sum ]; do
    for i in $varsizes; do
      size=$(printf "$realsizes"|sed -n "${i}p")
      size=$(($size + 1))
      realsizes=$(printf "$realsizes"|sed "${i}s/.*/$size/")
      sum=$(($sum + 1))
      [ $TCOLS -gt $sum ] || break
    done
  done
  pos=0
  printf "┌"
  for i in $(seq $n); do
    colsize=$(printf -- "$realsizes"|sed -n "${i}p")
    if [ $i -ne 1 ]; then
      tput hpa $pos
      printf "┬"
    fi
    pos=$(($pos + 1))
    printf "$(rep_char '─' $colsize)"
    pos=$(($pos + $colsize))
  done
  printf "┐\n"
  pos=0
  for i in $(seq $n); do
    h=$(printf -- "$headers"|cut -d, -f$i)
    colcolor=$(printf -- "$colcolors"|cut -d, -f$i)
    colsize=$(printf -- "$realsizes"|sed -n "${i}p")
    tput hpa $pos
    printf "│"
    center_text "$colcolor$h$(tput sgr0)" $(($pos + 1)) $(($pos + 1 + $colsize))
    pos=$(($pos + 1 + $colsize))
  done
  printf "│\n"
  pos=0
  printf "├"
  for i in $(seq $n); do
    colsize=$(printf -- "$realsizes"|sed -n "${i}p")
    if [ $i -ne 1 ]; then
      tput hpa $pos
      printf "┼"
    fi
    pos=$(($pos + 1))
    printf "$(rep_char '─' $colsize)"
    pos=$(($pos + $colsize))
  done
  printf "┤\n"
  from=1
  to=$(($TLINES - 6))
  nb=$(printf "$lines"|wc -l)
  [ $to -gt $nb ] && to=$nb
  l=$from
  printf "$lines"|sed -n "$from,$to{p}"|while read line; do
    l=$(($l + 1))
    pos=0
    for i in $(seq $n); do
      cell=$(printf -- "$line"|cut -d, -f$i)
      colcolor=$(printf -- "$colcolors"|cut -d, -f$i)
      colsize=$(printf -- "$realsizes"|sed -n "${i}p")
      tput hpa $pos
      printf "│"
      printf "$colcolor$cell"
      tput sgr0
      pos=$(($pos + 1 + $colsize))
    done
    tput hpa $TCOLS
    printf "│\n"
  done
  pos=0
  printf "└"
  for i in $(seq $n); do
    colsize=$(printf -- "$realsizes"|sed -n "${i}p")
    if [ $i -ne 1 ]; then
      tput hpa $pos
      printf "┴"
    fi
    pos=$(($pos + 1))
    printf "$(rep_char '─' $colsize)"
    pos=$(($pos + $colsize))
  done
  printf "┘\n"
  printf -- "$prompt\n"
}

action_pkglist() {
  packages=''
  for p in $(find src -mindepth 1 -maxdepth 1 -type d -not -name '.*'|sort); do
    p=$(basename "$p")
    for s in $(find src/$p -mindepth 1 -maxdepth 1 -type d -not -name '.*'|sort); do
      v=$(cat $s/version)
      packages=$(printf "$packages\n$p,$v,$(basename $s)")
    done
  done
  packages=$(printf "$packages"|sed 1d)
  if [ $INTERACTIVE -gt 0 ]; then
    show_interactive_list "$packages" "Package,Version,Salix" "$(tput setaf 4),$(tput setaf 2),$(tput setaf 3)" "20*,20,5" "Packages" "H for Help" 'hq'
    echo choosen=$CHOOSEN_ACTION
  else
    for pkg in $packages; do
      echo "$pkg"|sed -r 's/^([^,]+),([^,]+),(.*)/\1 - \2 (\3)/;'
    done
  fi
  return 0
}

action_pkginfo() {
  pkg_name="$1"
  [ -d src/$pkg_name ] || return 1
  pkg_arch=$(cat src/$pkg_name/arch)
  pkg_url=$(cat src/$pkg_name/url)
  pkg_dl_url=$(cat src/$pkg_name/dlurl)
  pkg_check_schema=$(cat src/$pkg_name/schema)
  pkg_check_pattern=$(cat src/$pkg_name/pattern)
  pkg_md5=$(cat src/$pkg_name/md5sum)
  pkg_build_schema=$(cat src/$pkg_name/buildschema)
  cat <<EOF
${CBOLD}${pkg_name}${CNONE}
$(for i in $(seq 1 $(expr length "$pkg_name")); do printf '='; done)
arch=${CLGREEN}${pkg_arch}${CNONE}
url=$pkg_url
download url=$pkg_dl_url
MD5 sum of the download page=$pkg_md5
Schema check for latest version=$pkg_check_schema
Schema pattern=$pkg_check_pattern
Build schema=$pkg_build_schema
EOF
  for salix_ver in $(find src/$pkg_name -mindepth 1 -maxdepth 1 -type d -not -name '.*'|sort); do
    salix_ver=$(basename "$salix_ver")
    pkg_ver=$(cat src/$pkg_name/$salix_ver/version)
    pkg_stable=$(cat src/$pkg_name/$salix_ver/stable)
    pkg_fixver=$(cat src/$pkg_name/$salix_ver/fixversion)
    echo ''
    echo "Versions for ${CLGREEN}${salix_ver}${CNONE}"
    salix_ver_underline=$(for i in $(seq 1 $(expr length "$salix_ver")); do printf '='; done)
    echo "=============$salix_ver_underline"
    echo "Current version=${CBOLD}${pkg_ver}${CNONE}"
    echo "Stable only=${CBOLD}${pkg_stable}${CNONE}"
    echo "Fixed version=${CBOLD}${pkg_fixver}${CNONE}"
    for v in $(find src/$pkg_name/$salix_ver -mindepth 1 -maxdepth 1 -type d -not -name '.*'|sort); do
      v=$(basename "$v")
      rlz=$(sed -rn '/^pkgrel/{s/.*=([0-9]+).*/\1/;p}' src/$pkg_name/$salix_ver/$v/SLKBUILD)
      echo "- version ${CLGREEN}${v}${CNONE}, release ${CLGREEN}${rlz}${CNONE}"
    done
  done
  return 0
}

action_edit() {
  pkg_name="$1"
  pkg_ver="$2"
  salix_ver="$3"
  [ -r src/$pkg_name/$salix_ver/$pkg_ver/SLKBUILD ] || return 1
  doedit=true
  while $doedit; do
    vim src/$pkg_name/$salix_ver/$pkg_ver/SLKBUILD
    grep -q FIXME src/$pkg_name/$salix_ver/$pkg_ver/SLKBUILD || doedit=false
    if $doedit; then
      echo "There are still some FIXME in the SLKBUILD, please correct them before continue."
      read junk
    fi
  done
  read_choice "Do you want to edit the local files and dependencies (shell)" "y n" "n" || return 1
  if [ $READ_VALUE = y ]; then
    (cd src/$pkg_name/$salix_ver/$pkg_ver && sh)
  fi
  return 0
}

action_verify() {
  pkg_name="$1"
  salix_ver="$2"
  [ -d src/$pkg_name/$salix_ver ] || return 1
  pkg_dl_url=$(cat src/$pkg_name/dlurl)
  pkg_check_pattern=$(cat src/$pkg_name/pattern)
  pkg_md5=$(cat src/$pkg_name/md5sum)
  pkg_stable=$(cat src/$pkg_name/$salix_ver/stable)
  pkg_versions=$(find_all_versions "$pkg_dl_url" "$pkg_check_pattern" "$pkg_md5")
  pkg_new_ver=$(find_latest_version "$pkg_versions" "$pkg_stable")
  pkg_ver=$(cat src/$pkg_name/$salix_ver/version)
  pkg_fixver=$(cat src/$pkg_name/$salix_ver/fixversion)
  if [ "$pkg_ver" = "$pkg_new_ver" ]; then
    echo "${CLGREEN}Up to date${CNONE} (${CLCYAN}${pkg_new_ver}${CNONE})"
  elif [ "$pkg_new_ver" = "up to date" ]; then
    echo "${CYELLOW}Seems up to date${CNONE} (${CLCYAN}MD5${CNONE})"
  elif [ "$pkg_new_ver" = "changed" ]; then
    echo "${CLMAGENTA}Seems changed${CNONE} (${CLCYAN}MD5${CNONE})"
  elif "$pkg_fixver"; then
    echo "${CGREEN}Fixed version to ${pkg_ver}${CNONE} (${CLCYAN}${pkg_new_ver}${CNONE})"
  else
    echo "${CLRED}Need to upgrade from version ${CBLUE}${pkg_ver}${CLRED} to ${CLCYAN}${pkg_new_ver}${CNONE}"
  fi
  return 0
}

action_verifyall() {
  if [ -z "$1" ]; then
    pkg_list=$(find src -mindepth 1 -maxdepth 1 -type d -not -name '.*'|sort)
  else
    [ -d src/$1 ] || return 1
    pkg_list="$1"
  fi
  for p in $pkg_list; do
    pkg_name=$(basename "$p")
    for s in $(find src/$pkg_name -mindepth 1 -maxdepth 1 -type d -not -name '.*'|sort); do
      salix_ver=$(basename "$s")
      printf "$pkg_name - $salix_ver: "
      action_verify "$pkg_name" "$salix_ver"
    done
  done
  return 0
}

action_update() {
  pkg_name="$1"
  salix_ver="$2"
  stable="$3"
  [ -z "$stable" ] && stable=true
  [ -d src/$pkg_name/$salix_ver ] || return 1
  pkg_fixver=$(cat src/$pkg_name/$salix_ver/fixversion)
  if $pkg_fixver; then
    echo "${CLRED}Cannot update, fix version requested${CNONE}" >&2
    return 1
  else
    url=$(cat src/$pkg_name/dlurl)
    pat=$(cat src/$pkg_name/pattern)
    oldver=$(cat src/$pkg_name/$salix_ver/version)
    filter=$(mktemp) # better than using eval I think.
    echo '#!/bin/sh' > $filter
    printf "$pat" >> $filter
    $stable && printf "|grep -vi 'alpha\\|beta\\|m[0-9]\\|rc'" >> $filter
    chmod +x $filter
    ver=$(wget --no-check-certificate -q -O - "$url"|$filter|head -n1)
    rm $filter
    if echo "$ver"|grep -q '^MD5:'; then
      md5=$(echo "$ver"|sed 's/MD5://')
    else
      md5=$(wget --no-check-certificate -q -O - "$pkg_dl_url"|grep '<a href'|grep -v 'http://'|md5sum|sed 's/  -//')
    fi
    echo "$md5" > src/$pkg_name/md5sum
    echo "$ver" > src/$pkg_name/$salix_ver/version
    if echo "$ver"|grep -qv '^MD5'; then
      copy_package_ver_build "$pkg_name" "$salix_ver" "$oldver" "$ver"
    fi
    echo "${CLGREEN}Updated to version ${CLCYAN}${ver}${CNONE}"
    return 0
  fi
}

action_build() {
  pkg_name="$1"
  pkg_ver="$2"
  salix_ver="$3"
  salix_arch="$4"
  numjobs="$5"
  [ -z "$numjobs" ] && numjobs=1
  check_registered
  [ -r src/$pkg_name/$salix_ver/$pkg_ver/SLKBUILD ] || return 1
  found=false
  for salix in $(find_installed_salix); do
    sver=$(echo $salix|cut -d- -f1)
    sarch=$(echo $salix|cut -d- -f2)
    if [ $sver = $salix_ver ] && [ $sarch = $salix_arch ]; then
      found=true
      break
    fi
  done
  if ! $found; then
    echo "LXC Salix version $salix_ver and arch $salix_arch has not been installed." >&2
    return 1
  fi
  deps=''
  if [ -r src/$pkg_name/$salix_ver/$pkg_ver/makedep ]; then
    deps=$(cat src/$pkg_name/$salix_ver/$pkg_ver/makedep) 
  fi
  if [ -r src/$pkg_name/$salix_ver/$pkg_ver/dep ]; then
    [ -n "$deps" ] && deps="$deps,"
    deps="${deps}$(cat src/$pkg_name/$salix_ver/$pkg_ver/dep)"
  fi
  echo "$pkg_name,$pkg_ver,$salix_ver,$salix_arch:$numjobs:$deps" >> queue
  echo "$pkg_name-$pkg_ver for $salix_ver-$salix_arch added to the queue."
  return 0
}

action_queue() {
  action="$1"
  check_registered
  check_numlxc
  [ -e queue ] || touch queue
  case "$action" in
    list)
      if [ $INTERACTIVE -gt 0 ]; then
        echo Interactive mode # TODO
      else
        sed 's/:.*//;s/,/-/;s/,/ on /;s/,/-/;=' queue|sed -n 'h;n;H;g;s/\n/: /p'
        return 0
      fi
      ;;
    clear)
      cat /dev/null > queue
      return 0
      ;;
    remove:*)
      param=$(echo "$action"|cut -d: -f2)
      lines=''
      for line in $(echo $param|tr , ' '); do
        if echo $line|grep -q '-'; then
          for subline in $(seq $(echo $line|cut -d- -f1) $(echo $line|cut -d- -f2)); do
            lines="$lines${subline}d;"
          done
        else
          lines="$lines${line}d;"
        fi
      done
      sed -i "$lines" queue
      return $?
      ;;
    run)
      . $CFG_FILE
      line=$(head -n1 queue)
      while [ -n "$line" ]; do
        pkg=$(echo $line|cut -d: -f1)
        numjobs=$(echo $line|cut -d: -f2)
        deps=$(echo $line|cut -d: -f3)
        pkg_name=$(echo $pkg|cut -d, -f1)
        pkg_ver=$(echo $pkg|cut -d, -f2)
        salix_ver=$(echo $pkg|cut -d, -f3)
        salix_arch=$(echo $pkg|cut -d, -f4)
        pkg_arch=$(cat src/$pkg_name/arch)
        [ $pkg_arch = all ] && pkg_arch=$salix_arch
        lxc_name=salixpkg-$salix_ver-$salix_arch
        lxc_root=/var/lib/lxc/$lxc_name/rootfs
        lxc_build=/home/pkg/build/$pkg_name-$pkg_ver
        lxc_ip=
        src_dir=src/$pkg_name/$salix_ver/$pkg_ver
        echo ''
        echo ${CLCYAN}"Building $pkg_name-$pkg_ver for $salix_ver-$salix_arch...${CNONE}"
        # remove old build if any
        rm -rf ${lxc_root}${lxc_build}
        mkdir -p ${lxc_root}${lxc_build}
        cp -rv $src_dir/. ${lxc_root}${lxc_build}/
        lxc_ip=$(sed -rn '/lxc.network.ipv4[ =]/{s,.*= *(.+)/.*,\1,;p}' /var/lib/lxc/$lxc_name/config)
        if [ -n "$deps" ]; then
          ssh -t root@$lxc_ip "installdeps '$deps'"
          if [ $? -ne 0 ]; then
            echo "${CLRED}Unable to install the dependencies for $pkg_name-$pkg_ver for $salix_ver-$salix_arch${CNONE}" >&2
            echo "Deps list: ${CRED}$deps${CNONE}" >&2
            return 1
          fi
        fi
        # building the package
        ssh -t pkg@$lxc_ip "cd $lxc_build; LANG=en_US.utf8 numjobs=$numjobs fakeroot slkbuild -X"
        if [ $? -eq 0 ]; then
          pkg_rel=$(sed -rn '/^pkgrel/{s/.*=([0-9]+.*)/\1/;p}' ${lxc_root}${lxc_build}/SLKBUILD)
          pkg_ver_slackware=$(echo $pkg_ver|sed -r 's/[-_]/./g')
          pkg_base_name=$pkg_name-$pkg_ver_slackware-$pkg_arch-$pkg_rel
          # create .dep, .sug and .con files if non empty
          for ext in dep sug con; do
            f=${lxc_root}${lxc_build}/$ext
            if [ -e $f ] && [ -n "$(cat $f)" ]; then
              mv $f ${lxc_root}${lxc_build}/$pkg_base_name.$ext
            else
              rm -f $f
            fi
          done
          rm -f ${lxc_root}${lxc_build}/makedep
          # add the package to the localrepo
          grep -q '/localrepo/' ${lxc_root}/etc/slapt-get/slapt-getrc || ssh -t root@$lxc_ip "localrepo -s"
          pkg_ext=
          for ext in txz tgz; do
            if [ -e ${lxc_root}${lxc_build}/$pkg_base_name.$ext ]; then
              pkg_ext=$ext
              break
            fi
          done
          [ -n "$pkg_ext" ] || return 1
          ssh -t root@$lxc_ip "localrepo -a ${lxc_build}/$pkg_base_name.$pkg_ext"
          bin_dir=$(echo "bin/$pkgr_schema"|sed "s/\$pkgname/$pkg_name/; s/\$pkgver/$pkg_ver_slackware/; s/\$arch/$pkg_arch/; s/\$pkgrel/$pkg_rel/")
          mkdir -p $bin_dir
          cp -rv ${lxc_root}${lxc_build}/. $bin_dir/
          echo "${CLGREEN}Package $pkg_name-$pkg_ver building DONE for $salix_ver-$salix_arch${CNONE}"
          sed -i '1d' queue # remove first line
          line=$(head -n1 queue) # read the next one
        else
          echo "${CLRED}Package $pkg_name-$pkg_ver building FAILED for $salix_ver-$salix_arch${CNONE}" >&2
          read_choice "Would you like to edit the package" "y n" "y"
          if [ $READ_VALUE = y ]; then
            action_edit "$pkg_name" "$pkg_ver" "$salix_ver"
          fi
          break
        fi
      done
      if [ -z "$(cat queue)" ]; then
        return 0
      else
        return 1
      fi
      ;;
    *)
      echo "Unknown action $action for queue." >&2
      return 1
      ;;
  esac
}

action_rsync() {
  . $CFG_FILE
  mkdir remote
  trap 'fusermount -u remote;rmdir remote;exit 2' 2 # Ctrl+C
  if sshfs -o uid=$(id -u) -o gid=$(id -g) "$pkgr_scpuri" remote; then
    echo "Connection ok, Synchronizing..."
    rsync -rvh --inplace --del --times --progress --stats bin/ remote
    sync
    sleep 1
    fusermount -u remote
    sleep 1
    rmdir remote
    echo "${CLGREEN}Synchronization done${CNONE}"
    return 0
  else
    rmdir remote
    echo "${CLRED}Cannot connect, please check your configuration for $pkgr_scpuri${CNONE}" >&2
    return 1
  fi
}

action_ticket() {
  pkg_name="$1"
  salix_ver="$2"
  ticket_id="$3"
  [ -d src/$pkg_name/$salix_ver ] || return 1
  pkg_ver=$(cat src/$pkg_name/$salix_ver/version)
  pkg_ver_slackware=$(echo $pkg_ver|sed -r 's/[-_]/./g')
  pkg_rel=$(sed -rn '/^pkgrel/{s/.*=([0-9]+.*)/\1/;p}' src/$pkg_name/$salix_ver/$pkg_ver/SLKBUILD)
  pkg_url=$(cat src/$pkg_name/url)
  pkg_arch=$(cat src/$pkg_name/arch)
  if [ "$pkg_arch" = "all" ]; then
    arches="i486 x86_64 arm"
  else
    arches="$pkg_arch"
  fi
  . $CFG_FILE
  if [ -z "$ticket_id" ]; then
    read_choice "Ticket Type" 'New Upgrade Rebuild Transfer' 'New' false || return 1
    tickettype="$READ_VALUE"
    read_choice "Importance" 'Trivial  Minor  Normal  Major  Critical' 'Normal' false || return 1
    importance="$READ_VALUE"
  fi
  read_info "Short message" '' true || return 1
  message="$READ_VALUE"
  desc=''
  if [ -n "$message" ]; then
    desc='*'$(printf "$message"|sed 's/\*/\\\\*/g')"*\n"
  fi
  desc="$desc**Homepage:**\n<$pkg_url>\n"
  for arch in $arches; do
    bin_dir=$(echo "$pkgr_schema"|sed "s/\$pkgname/$pkg_name/; s/\$pkgver/$pkg_ver_slackware/; s/\$arch/$arch/; s/\$pkgrel/$pkg_rel/")
    if [ -d bin/$bin_dir ]; then
      pkg_base=$pkg_name-$pkg_ver_slackware-$arch-$pkg_rel
      desc="${desc}---\n\n**Package $arch:**\n>"
      for ext in txz tgz md5 src dep sug con; do
        [ -f "bin/$bin_dir/$pkg_base.$ext" ] && desc="$desc- <$pkgr_url/$bin_dir/$pkg_base.$ext>\n";
      done
      desc="$desc\n**Log $arch:**\n><$pkgr_url/$bin_dir/build-$pkg_base.log>\n\n**Buildscript and source $arch:**\n>- <$pkgr_url/$bin_dir/SLKBUILD>\n"
      for f in $(find bin/$bin_dir -type f|sort); do
        f=$(basename "$f")
        echo "$f"|grep -q "^$pkg_base\.\|^build-$pkg_base\.log\|^SLKBUILD$" && continue
        desc="${desc}- <$pkgr_url/$bin_dir/$f>\n"
      done
    fi
  done
  printf "\n----------\n${CGREEN}${desc}${CNONE}----------\n"
  if [ -z "$ticket_id" ]; then
    read_choice "\nPosting this" 'y n' 'y'
  else
    read_choice "\nAdding this to $ticket_id" 'y n' 'y'
  fi
  [ $READ_VALUE = y ] || return 0 # no error
  base_url=https://sourceforge.net
  ticket_uri=/p/salix/packages/
  if [ -z "$ticket_id" ]; then
    newticket_uri=/rest/p/salix/packages/new
    ticket_id=$(cat <<EOF|python
#!/bin/env python
# coding: utf8
import urllib
import urllib2
import json
url='$base_url$newticket_uri'
params = {
  'access_token' : '$pkgr_token',
  'ticket_form.summary' : '$pkg_name-$pkg_ver',
  'ticket_form.status' : 'open',
  'ticket_form.assigned_to' : '',
  'ticket_form.labels' : '',
  'ticket_form.custom_fields._type' : '$tickettype',
  'ticket_form.custom_fields._importance' : '$importance',
  'ticket_form.custom_fields._salix_version' : '$salix_ver',
  'ticket_form.description' : """$desc""",
}
data = urllib.urlencode(params)
resp = urllib2.urlopen(urllib2.Request(url, data))
jsondata = json.loads(''.join(resp.readlines()))
print(jsondata['ticket']['ticket_num'])
EOF
) || return 1
  else
    infoticket_uri=/rest/p/salix/packages/$ticket_id
    thread_id=$(cat <<EOF|python
#!/bin/env python
# coding: utf8
import urllib
import urllib2
import json
url='$base_url$infoticket_uri'
resp = urllib2.urlopen(urllib2.Request(url))
jsondata = json.loads(''.join(resp.readlines()))
print(jsondata['ticket']['discussion_thread']['_id'])
EOF
) || return 1
    postticket_uri=/rest/p/salix/packages/_discuss/thread/$thread_id/new
    cat <<EOF|python || return 1
#!/bin/env python
# coding: utf8
import urllib
import urllib2
url='$base_url$postticket_uri'
params = {
  'access_token' : '$pkgr_token',
  'text' : """$desc""",
}
data = urllib.urlencode(params)
resp = urllib2.urlopen(urllib2.Request(url, data))
EOF
  fi
  if [ -n "$ticket_id" ]; then
    echo "Ticket posted: $base_url$ticket_uri$ticket_id/"
    return 0
  else
    return 1
  fi
}

opts=$(getopt -o 'hVclp:e:v:a::u:b:q:rt:i' -l 'help,version,check,prepare,install:,list-installed,remove:,register,create,pkg-list,pkg-info:,edit:,verify:,verify-all::,update:,build:,queue:,rsync,ticket:,interactive' -- "$@")
ret=$?
if [ $ret -eq 1 ]; then
  usage
  exit $ret
else
  eval set -- $opts
  INTERACTIVE=0
  ACTION=''
  PARAM1=''
  PARAM2=''
  PARAM3=''
  PARAM4=''
  PARAM5=''
  while [ -n "$1" -a "$1" != "--" ]; do
    case "$1" in
      -h|--help)
        shift
        usage
        exit 0
        ;;
      -V|--version)
        shift
        show_version
        exit 0
        ;;
      --check)
        shift
        ACTION=check
        ;;
      --prepare)
        shift
        ACTION=prepare
        ;;
      --register)
        shift
        ACTION=register
        ;;
      --install)
        shift
        ACTION=install
        verarch=$1
        shift
        check_ver_arch "$verarch"
        PARAM1=$(echo $verarch|cut -d, -f1)
        PARAM2=$(echo $verarch|cut -d, -f2)
        ;;
      --list-installed)
        shift
        ACTION=listinstalled
        ;;
      --remove)
        shift
        ACTION=remove
        verarch=$1
        shift
        check_ver_arch "$verarch"
        PARAM1=$(echo $verarch|cut -d, -f1)
        PARAM2=$(echo $verarch|cut -d, -f2)
        ;;
      -c|--create)
        shift
        ACTION=create
        INTERACTIVE=1
        ;;
      -l|--pkg-list)
        shift
        ACTION=pkglist
        ;;
      -p|--pkg-info)
        shift
        ACTION=pkginfo
        PARAM1=$1
        shift
        ;;
      -e|--edit)
        shift
        ACTION=edit
        INTERACTIVE=1
        fullpkg=$1
        shift
        check_pkg_ver_ver "$fullpkg" && exit 1
        PARAM1=$(echo $fullpkg|cut -d, -f1)
        PARAM2=$(echo $fullpkg|cut -d, -f2)
        PARAM3=$(echo $fullpkg|cut -d, -f3)
        ;;
      -v|--verify)
        shift
        ACTION=verify
        fullpkg=$1
        shift
        check_pkg_ver "$fullpkg" && exit 1
        PARAM1=$(echo $fullpkg|cut -d, -f1)
        PARAM2=$(echo $fullpkg|cut -d, -f2)
        ;;
      -a|--verify-all)
        shift
        ACTION=verifyall
        if echo "$1"|grep -vq '^-'; then
          PARAM1="$1"
          shift
        fi
        ;;
      -u|--update)
        shift
        ACTION=update
        INTERACTIVE=1
        fullpkg=$1
        shift
        check_pkg_ver "$fullpkg" && exit 1
        PARAM1=$(echo $fullpkg|cut -d, -f1)
        PARAM2=$(echo $fullpkg|cut -d, -f2)
        ;;
      -b|--build)
        shift
        ACTION=build
        fullpkg=$1
        shift
        check_pkg_ver_ver_arch "$fullpkg" && exit 1
        PARAM1=$(echo $fullpkg|cut -d, -f1)
        PARAM2=$(echo $fullpkg|cut -d, -f2)
        PARAM3=$(echo $fullpkg|cut -d, -f3)
        PARAM4=$(echo $fullpkg|cut -d, -f4)
        PARAM5=$(echo $fullpkg|cut -d, -f5)
        ;;
      -q|--queue)
        shift
        ACTION=queue
        PARAM1="$1"
        shift
        ;;
      -r|--rsync)
        shift
        ACTION=rsync
        ;;
      -t|--ticket)
        shift
        ACTION=ticket
        INTERACTIVE=1
        fullpkg=$1
        shift
        check_pkg_ver "$fullpkg" && exit 1
        PARAM1=$(echo $fullpkg|cut -d, -f1)
        PARAM2=$(echo $fullpkg|cut -d, -f2)
        ;;
      -i|--interactive)
        shift
        INTERACTIVE=1
        ;;
      *)
        echo "Unknown option $1" >&2
        exit 1
    esac
  done
  if [ -z "$ACTION" ]; then
    usage
    exit 1
  else
    # fix for optional args with getopt
    shift # remove "--"
    [ $ACTION = verifyall ] && [ -n "$1" ] && PARAM1="$1"
    [ $ACTION = ticket ] && [ -n "$1" ] && PARAM3="$1"
    if ! action_$ACTION $PARAM1 $PARAM2 $PARAM3 $PARAM4 $PARAM5; then
      echo "An error occured while processing action ${CLRED}$ACTION" $PARAM1 $PARAM2 $PARAM3 $PARAM4 $PARAM5 $CNONE >&2
      exit 1
    fi
  fi
fi
