#!/bin/sh
arches='i486 x86_64'
salix='14.1'
packages=$@
[ -z "$packages" ] && exit 1
cpus=$(($(sed -rn '/^processor/p' /proc/cpuinfo|sed -rn '$=') - 1))
cd $(dirname "$0")
for a in $arches; do
  for s in $salix; do
    for p in $packages; do
      v=$(./salixPackaging -p $p|grep -A 2 "^Versions for \[[^m]\+m$s"|grep '^Current version='|cut -d= -f2|sed -r 's/\[[^m]+m//g')
      ./salixPackaging -b $p $v $s $a $cpus
    done
  done
done
