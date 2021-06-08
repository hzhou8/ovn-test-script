#!/bin/sh

n_ls=1000
n_lsp_per_ls=10
n_lsp_in_pg=5000

# Naming and IP/MAC address pattern:
# Assume n_ls is 4-digit decimal number, and n_lsp_per_ls < 100.
#
# LS naming: ls_<id>, e.g. ls_0003
#
# LSP naming: lsp_<ls id>_<id>, e.g. lsp_0003_08
#
# IP:
#   - for lrp:
#       10.<highest 2 digits of ls>.<lowest 2 digits of ls>.1
#       e.g. 10.0.3.1
#   - for lsp:
#       10.<highest 2 digits of ls>.<lowest 2 digits of ls>.1<lsp id>
#       e.g. 10.0.3.108
#       
# MAC:
#   - for lrp:
#       ff:ff:aa:<highest 2 digits of ls>:<lowest 2 digits of ls>:01
#       e.g. ff:ff:aa:00:03:01
#   - for lsp:
#       ff:ff:bb:<highest 2 digits of ls>:<lowest 2 digits of ls>:<lsp id>
#       e.g. ff:ff:bb:00:03:08

ovn-nbctl lr-add jr

for i in $(seq 1 $n_ls); do
    ls_id=$(printf "%04d" $i)   # e.g. 0003
    ls=ls_${ls_id}              # e.g. ls_0003
    ls_high=${ls:3:2}           # e.g. 00
    ls_low=${ls:5}              # e.g. 03
    ls_high_ip=$((10#$ls_high)) # e.g. 0 
    ls_low_ip=$((10#$ls_low))   # e.g. 3
    ls_ip_pre=10.${ls_high_ip}.${ls_low_ip} # e.g. 10.0.3

    ovn-nbctl ls-add $ls \
        -- lrp-add jr lrp_jr_${ls} \
           ff:ff:aa:${ls_high}:${ls_low}:01 $ls_ip_pre.1/24 \
        -- lsp-add $ls lsp_${ls}_jr \
        -- lsp-set-type lsp_${ls}_jr router \
        -- lsp-set-options lsp_${ls}_jr router-port=lrp_jr_${ls} \
        -- lsp-set-addresses lsp_${ls}_jr

    for j in $(seq 1 $n_lsp_per_ls); do
        lsp_id=$(printf "%02d" $j)  # e.g. 08
        lsp=lsp_${ls_id}_${lsp_id}  # e.g. lsp_0003_08
        ovn-nbctl lsp-add $ls $lsp \
            -- lsp-set-addresses $lsp \
               "ff:ff:bb:${ls_high}:${ls_low}:${lsp_id} $ls_ip_pre.1$lsp_id" \
            -- lsp-set-port-security $lsp \
               "ff:ff:bb:${ls_high}:${ls_low}:${lsp_id} $ls_ip_pre.1$lsp_id"
    done
done

# Create a PG of n_lsp_in_pg number of LSPs. For each LS, we need to add
# (n_lsp_in_pg / n_ls) number of LSPs to the PG.
n_lsp_per_ls_pg=$(( $n_lsp_in_pg / $n_ls ))
for i in $(seq 1 $n_ls); do
    ls_id=$(printf "%04d" $i)   # e.g. 0003
    for j in $(seq 1 $n_lsp_per_ls_pg); do
        lsp_id=$(printf "%02d" $j)  # e.g. 08
        #lsp=lsp_${ls_id}_${lsp_id}  # e.g. lsp_0003_08
        lsp=lsp_${ls_id}_${lsp_id}  # e.g. lsp_0003_08
        lsp_in_pg="$lsp_in_pg $lsp"
    done
done

ovn-nbctl pg-add pg1 $lsp_in_pg

ovn-nbctl acl-add pg1 to-lport 100 'outport == @pg1 && ip4 && ip4.src == $pg1_ip4 && tcp.dst == 80' allow-related

