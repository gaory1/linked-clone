#!/bin/bash

set -e

if test $# -lt 1; then
    echo "usage: $0 <src_vm_name> [new_vm_name]"
    exit 1
fi

src_name=$1
new_name=$2
if test -z "$new_name"; then
    new_name=${src_name}-clone
fi

xml=$(mktemp -u /tmp/linked-clone-XXXX)
virsh dumpxml $src_name > $xml
sed -i "s|<name>.*</name>|<name>$new_name</name>|" $xml
sed -i "s|<uuid>.*</uuid>|<uuid>$(uuidgen)</uuid>|" $xml

virsh define $xml
/bin/rm $xml

i=0
virsh domblklist --details $src_name | tail -n +3 | while read type device target source
do
    test -z "$source" && break
    test "$source" = "-" && continue
    test "$device" = "disk" || continue
    new_disk=$(dirname $source)/${new_name}-$i.img
    qemu-img create -f qcow2 -b $source $new_disk
    chown libvirt-qemu $source
    virsh detach-disk $new_name $target --config
    virsh attach-disk $new_name $new_disk $target --driver qemu --subdriver=qcow2 --config
    i=$[$i+1]
done

virsh domiflist $new_name | tail -n +3 | while read name type source model mac
do
    test -z "$type" && break
    virsh detach-interface $new_name $type --config
    virsh attach-interface $new_name --type $type --source $source --model $model --config
done

