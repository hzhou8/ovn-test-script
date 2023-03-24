#!/bin/sh

n_zone=3
[ "$N_ZONE" != "" ] && n_zone=$N_ZONE

n_chassis=100
[ "$N_CHASSIS" != "" ] && n_chassis=$N_CHASSIS

n_lsp_per_ls=5
[ "$N_LSP_PER_LS" != "" ] && n_lsp_per_ls=$N_LSP_PER_LS

# We will create 2 PGs for each zone, one big and one small.
#
# For N_LSP_IN_PG_BIG it must be divisible by N_CHASSIS and cannot exceed
# N_CHASSIS x N_LSP_PER_LS.
n_lsp_in_pg_big=500
[ "$N_LSP_IN_PG_BIG" != "" ] && n_lsp_in_pg_big=$N_LSP_IN_PG_BIG

n_lsp_in_pg_small=10
[ "$N_LSP_IN_PG_SMALL" != "" ] && n_lsp_in_pg_small=$N_LSP_IN_PG_SMALL

n_ls=$n_chassis

n_vip=10
[ "$N_VIP" != "" ] && n_vip=$N_VIP

# N_BE_PER_VIP <= N_LSP_PER_LS
n_be_per_vip=3
[ "$N_BE_PER_VIP" != "" ] && n_be_per_vip=$N_BE_PER_VIP

n_nodeport_vip=3
[ "$N_NODEPORT_VIP" != "" ] && n_nodeport_vip=$N_NODEPORT_VIP

n_nodeport_node=2
[ "$N_NODEPORT_NODE" != "" ] && n_nodeport_node=$N_NODEPORT_NODE

# ACLs for each direction (big -> small, small -> big)
n_acl=5
[ "$N_ACL" != "" ] && n_acl=$N_ACL

n_l4_per_acl=5
[ "$N_L4_PER_ACL" != "" ] && n_l4_per_acl=$N_L4_PER_ACL

# Naming and IP/MAC address pattern:
# Assume n_ls is 4-digit decimal number, and n_lsp_per_ls < 100.
#
# LS naming: ls_<zone>_<id>, e.g. ls_1_0003
#
# LSP naming: lsp_<zone>_<ls id>_<id>, e.g. lsp_1_0003_08
#
# IP:
#   - for lrp:
#       <zone>.<highest 2 digits of ls>.<lowest 2 digits of ls>.1
#       e.g. 1.0.3.1
#   - for lsp:
#       <zone>.<highest 2 digits of ls>.<lowest 2 digits of ls>.1<lsp id>
#       e.g. 1.0.3.108
#
# MAC:
#   - for lrp:
#       ff:f<zone>:aa:<highest 2 digits of ls>:<lowest 2 digits of ls>:01
#       e.g. ff:f1:aa:00:03:01
#   - for lsp:
#       ff:f<zone>:bb:<highest 2 digits of ls>:<lowest 2 digits of ls>:<lsp id>
#       e.g. ff:f1:bb:00:03:08

# get_lsp_ip ZONE CHASSIS LSP
get_lsp_ip () {
    local zone=$1
    local ch=$2
    local lsp=$3
    local ls_id=$(printf "%04d" $ch)                      # e.g. 0003
    local ls_high=${ls_id::2}                             # e.g. 00
    local ls_low=${ls_id:2}                               # e.g. 03
    local ls_high_ip=$((10#$ls_high))                     # e.g. 0
    local ls_low_ip=$((10#$ls_low))                       # e.g. 3
    local ls_ip_pre=${zone}.${ls_high_ip}.${ls_low_ip}    # e.g. 1.0.3
    local lsp_id=$(printf "%02d" $lsp)                    # e.g. 08
    echo $ls_ip_pre.1$lsp_id                              # e.g. 1.0.3.108
}

# get_lsp_name ZONE CHASSIS LSP
get_lsp_name () {
    local zone=$1
    local ch=$2
    local lsp=$3
    local ls_id=$(printf "%04d" $ch)    # e.g. 0003
    local lsp_id=$(printf "%02d" $lsp)  # e.g. 08
    echo lsp_${zone}_${ls_id}_${lsp_id} # e.g. lsp_1_0003_08
}

date
echo start
for zone in $(seq 1 $n_zone); do
    lr=lr_$zone                                         # e.g. lr_1
    ovn-nbctl lr-add $lr

    for i in $(seq 1 $n_ls); do
        ls_id=$(printf "%04d" $i)                       # e.g. 0003
        ls_high=${ls_id::2}                             # e.g. 00
        ls_low=${ls_id:2}                               # e.g. 03
        ls_high_ip=$((10#$ls_high))                     # e.g. 0
        ls_low_ip=$((10#$ls_low))                       # e.g. 3
        ls_ip_pre=${zone}.${ls_high_ip}.${ls_low_ip}    # e.g. 1.0.3
        ls=ls_${zone}_${ls_id}                          # e.g. ls_1_0003

        lsp_lr=lsp_${ls}_${lr}
        lrp=lrp_${lr}_${ls}

        # Connect the LS to LR
        cmd="ls-add $ls \
            -- lrp-add $lr $lrp \
               ff:f${zone}:aa:${ls_high}:${ls_low}:01 $ls_ip_pre.1/24 \
            -- lsp-add $ls $lsp_lr \
            -- lsp-set-type $lsp_lr router \
            -- lsp-set-options $lsp_lr router-port=$lrp \
            -- lrp-set-gateway-chassis $lrp chassis_$ls_id 1 \
            -- lsp-set-addresses $lsp_lr router"

        # Create VIF LSPs
        for j in $(seq 1 $n_lsp_per_ls); do
            lsp_id=$(printf "%02d" $j)          # e.g. 08
            lsp=lsp_${zone}_${ls_id}_${lsp_id}  # e.g. lsp_1_0003_08
            cmd="${cmd} -- lsp-add $ls $lsp \
                -- lsp-set-addresses $lsp \
                   'ff:f${zone}:bb:${ls_high}:${ls_low}:${lsp_id} $ls_ip_pre.1$lsp_id' \
                -- lsp-set-port-security $lsp \
                   'ff:f${zone}:bb:${ls_high}:${ls_low}:${lsp_id} $ls_ip_pre.1$lsp_id'"
        done
        eval ovn-nbctl $cmd
    done

    if (($n_acl == 0)); then
        break
    fi
    # Create a big PG of n_lsp_in_pg_big number of LSPs. For each LS, we need
    # to add (n_lsp_in_pg_big / n_ls) number of LSPs to the PG.
    n_lsp_per_ls_pg_big=$(( $n_lsp_in_pg_big / $n_ls ))
    lsp_in_pg_big=""
    for i in $(seq 1 $n_ls); do
        for j in $(seq 1 $n_lsp_per_ls_pg_big); do
            lsp=$(get_lsp_name $zone $i $j)
            lsp_in_pg_big="$lsp_in_pg_big $lsp"
        done
    done
    ovn-nbctl pg-add pg_big_$zone $lsp_in_pg_big

    # Create a small PG of n_lsp_in_pg_small number of LSP, one LSP from
    # each LS. Add 2 LSPs from each LS start from the 1st LS up to
    # n_lsp_in_pg_small / 2.
    n_lses_for_pg_small=$(( $n_lsp_in_pg_small / 2 ))
    lsp_in_pg_small=""
    for i in $(seq 1 $n_lses_for_pg_small); do
        lsp1=$(get_lsp_name $zone $i $n_lsp_per_ls)
        lsp2=$(get_lsp_name $zone $i $(( $n_lsp_per_ls - 1 )))
        lsp_in_pg_small="$lsp_in_pg_small $lsp1 $lsp2"
    done

    ovn-nbctl pg-add pg_small_$zone $lsp_in_pg_small

    for acl in $(seq 1 $n_acl); do
        dst_port_to_small="{1111" # e.g. {1111, 1112, 1113}
        dst_port_to_big="{2221"   # e.g. {2221, 2222, 2223}

        for i in $(seq 2 $n_l4_per_acl); do
            dst_port_to_small="$dst_port_to_small, 111$i"
            dst_port_to_big="$dst_port_to_big, 222$i"
        done

        dst_port_to_small="$dst_port_to_small }"
        dst_port_to_big="$dst_port_to_big }"

        # big to small
        l4_match="tcp && tcp.dst == $dst_port_to_small"
        # Ingress (small side)
        ovn-nbctl acl-add pg_small_$zone to-lport 10$acl \
            "outport == @pg_small_$zone && ip4 && ip4.src == \$pg_big_${zone}_ip4 && $l4_match" allow-related
        # Egress (big side)
        ovn-nbctl acl-add pg_big_$zone from-lport 10$acl \
            "inport == @pg_big_$zone && ip4 && ip4.dst == \$pg_small_${zone}_ip4 && $l4_match" allow-related

        # small to big
        l4_match="tcp && tcp.dst == $dst_port_to_big"
        # Ingress (big side)
        ovn-nbctl acl-add pg_big_$zone to-lport 10$acl \
            "outport == @pg_big_$zone && ip4 && ip4.src == \$pg_small_${zone}_ip4 && $l4_match" allow-related
        # Egress (small side)
        ovn-nbctl acl-add pg_small_$zone from-lport 10$acl \
            "inport == @pg_small_$zone && ip4 && ip4.dst == \$pg_big_${zone}_ip4 && $l4_match" allow-related
    done

    date
    echo "zone$zone logical routers, switches, ports and ACLs are created."
done


# For the zone_1, create cluster-wide east-west LBs
lb_port=8888
for v in $(seq 1 $n_vip); do
    vip=123.123.$(( $v / 100 )).$(( $v % 100 ))
    be_ip_ports=$(get_lsp_ip 1 $v 1):$lb_port
    for i in $(seq 2 $n_be_per_vip); do
        lsp_ip=$(get_lsp_ip 1 $v $i)
        be_ip_ports="$be_ip_ports,$lsp_ip:$lb_port"
    done

    ovn-nbctl lb-add lb_$v $vip:$lb_port $be_ip_ports tcp
done

# Create LB templates for north-south LBs
lb_template_var="^nodeport_vip"
for v in $(seq 1 $n_vip); do
    be_ip_ports=$(get_lsp_ip 1 $v 1):$lb_port
    for i in $(seq 2 $n_be_per_vip); do
        lsp_ip=$(get_lsp_ip 1 $v $i)
        be_ip_ports="$be_ip_ports,$lsp_ip:$lb_port"
    done

    ovn-nbctl --template lb-add lb_$v ${lb_template_var}:${v} $be_ip_ports tcp
done


# Create LB group
lb_group=$(ovn-nbctl create load_balancer_group name=cluster_lbs)
for i in $(ovn-nbctl --format=table --no-headings --column=_uuid list load_balancer); do
    ovn-nbctl add load_balancer_group cluster_lbs load_balancer $i
done

# For the zone_1, create the join switch and connect to lr_1
ovn-nbctl ls-add ls_join \
    -- lrp-add lr_1 lrp_lr_1_ls_join ff:f1:aa:aa:aa:aa 100.64.100.1/16 \
    -- lsp-add ls_join lsp_ls_join_lr_1 \
    -- lsp-set-type lsp_ls_join_lr_1 router \
    -- lsp-set-options lsp_ls_join_lr_1 router-port=lrp_lr_1_ls_join \
    -- lsp-set-addresses lsp_ls_join_lr_1 router

# Create chassises and bind ports.
# Create GRs per chassis and connect to the join switch.
# Create Ext switches and connect to GRs.
# Add LB references to GRs.
for i in $(seq 1 $n_chassis); do
    ch_id=$(printf "%04d" $i)                # e.g. 0003
    ch_high=${ch_id::2}                      # e.g. 00
    ch_low=${ch_id:2}                        # e.g. 03
    ch_high_ip=$((10#$ch_high))              # e.g. 0
    ch_low_ip=$((10#$ch_low))                # e.g. 3
    ch=chassis_$ch_id                        # e.g. chassis_0003
    ch_ip=192.168.${ch_high_ip}.${ch_low_ip} # e.g. 192.168.0.3

    ovn-sbctl chassis-add $ch geneve $ch_ip
    cmd=""
    for zone in $(seq 1 $n_zone); do
        for j in $(seq 1 $n_lsp_per_ls); do
            lsp_id=$(printf "%02d" $j)         # e.g. 08
            lsp=lsp_${zone}_${ch_id}_${lsp_id} # e.g. lsp_1_0003_08
            ch_uuid=$(ovn-sbctl --column=_uuid --bare list chassis $ch)
            cmd="${cmd} -- set port_binding $lsp chassis=$ch_uuid up=true"
        done
    done
    eval ovn-sbctl $cmd

    # Create GR and connect to ls_join
    gr=gr_${ch_id}
    lrp=lrp_${gr}_ls_join
    lsp=lsp_ls_join_${gr}
    ovn-nbctl lr-add $gr \
        -- set logical_router $gr options:chassis=$ch \
                                  options:dynamic_neigh_routers=true \
        -- lrp-add $gr $lrp ff:ff:aa:${ch_high}:${ch_low}:01 \
           100.64.${ch_high_ip}.${ch_low_ip}/16 \
        -- lsp-add ls_join $lsp \
        -- lsp-set-type $lsp router \
        -- lsp-set-options $lsp router-port=$lrp \
        -- lsp-set-addresses $lsp router

    # Create Ext switch and connect to the GR
    ls=ext_$ch_id
    lsp=lsp_${ls}_${gr}
    lrp=lrp_${gr}_${ls}
    ovn-nbctl ls-add $ls \
        -- lrp-add $gr $lrp ff:ff:aa:${ch_high}:${ch_low}:02 \
           10.8.${ch_high_ip}.${ch_low_ip}/16 \
        -- lsp-add $ls $lsp \
        -- lsp-set-type $lsp router \
        -- lsp-set-options $lsp router-port=$lrp \
        -- lsp-set-addresses $lsp router

    # Create the localnet port on the ext switch
    lsp=lsp_${ls}
    ovn-nbctl lsp-add $ls $lsp \
        -- lsp-set-type $lsp localnet \
        -- lsp-set-options $lsp network_name=providernet \
        -- lsp-set-addresses $lsp unknown

    # Add cluster LBs to the GR and the node LS (zone1 only)
    ls_zone1=ls_1_${ch_id}
    if [ "$lb_group" != "" ]; then
        ovn-nbctl set logical_router $gr load_balancer_group="$lb_group" \
            -- set logical_switch $ls_zone1 load_balancer_group="$lb_group"
    else
        for v in $(seq 1 $n_vip); do
            ovn-nbctl lr-lb-add $gr lb_$v -- ls-lb-add $ls_zone1 lb_$v
        done
    fi

    # Create north-south (node-port) LBs, and add to node GR and LS
    if (($i <= $n_nodeport_node)); then
        if [ "$lb_template_var" != "" ]; then
            # Template LB is already in lb group. Just create template vars here.
            ovn-nbctl create chassis_template_var \
                chassis=$ch variables:${lb_template_var}=$ch_ip
        else
            for v in $(seq 1 $n_nodeport_vip); do
                be_ip_ports=$(get_lsp_ip 1 $v 1):$lb_port
                for be_lsp in $(seq 2 $n_be_per_vip); do
                    be_lsp_ip=$(get_lsp_ip 1 $v $be_lsp)
                    be_ip_ports="$be_ip_ports,$be_lsp_ip:$lb_port"
                done
                vip_port=$ch_ip:$v
                lb_name=lb_${v}_nodeport_$i
                ovn-nbctl lb-add $lb_name $vip_port $be_ip_ports tcp \
                    -- lr-lb-add $gr $lb_name -- ls-lb-add $ls $lb_name
            done
        fi
    fi

    # TODO: create static routes

    if [ "$ch_low" == "00" ]; then
        date
        echo "Created $i chassis related objects."
    fi
done
# TODO:
# create snat/dnat rules
date
echo done
