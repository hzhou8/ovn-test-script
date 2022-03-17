#!/bin/sh

if [ "$1" != "bind" ] && [ "$1" != "unbind" ]; then
    echo "Usage: $0 <bind | unbind>"
    exit 1
fi

n_lsp_per_ls=5
[ "$N_LSP_PER_LS" != "" ] && n_lsp_per_ls=$N_LSP_PER_LS
n_zone=3
[ "$N_ZONE" != "" ] && n_zone=$N_ZONE

for zone in $(seq 1 $n_zone); do
    for j in $(seq 1 $n_lsp_per_ls); do
        lsp_id=$(printf "%02d" $j)     # e.g. 08
        lsp=lsp_${zone}_0001_${lsp_id} # e.g. lsp_1_0001_08
        if [ "$1" = "bind" ]; then
            ovs-vsctl add-port br-int $lsp -- set interface $lsp external_ids:iface-id=$lsp
        else
            ovs-vsctl del-port $lsp
        fi
    done
done

# TODO: set ext bridge and mapping, so that patch ports can be created
