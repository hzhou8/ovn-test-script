================
OVN Test Scripts
================

Convinience scripts for testing OVN.

Usage
-----

1. Start OVN and OVS, e.g. using the OVN sandbox environment under OVN source
   tree:

   ::

        $ make sandbox

2. Start ovn-nbctl and ovn-sbctl daemon:

   ::

        $ export OVN_NB_DAEMON=$(ovn-nbctl --pidfile --detach)
        $ export OVN_SB_DAEMON=$(ovn-sbctl --pidfile --detach)

3. Set the environment variables for the scale test by sourcing the appropriate
   configuration file, e.g., ``args.200ch_50lsp_10000pg``:

   ::

        $ source args.200ch_50lsp_10000pg

4. Run the ``test_ovn_controller_scale_k8s.sh`` script to build the NB and SB
   databases with topology similar to what is used by ovn-kubernetes, at the
   specified scale, which may take a while, depending on the scale:

   ::

        $ ./test_ovn_controller_scale_k8s.sh

5. Optional: To test ovn-controller performance, you will also need to bind OVS
   interfaces. Run the ``ovs_interface.sh`` script with the appropriate
   argument:

   ::

        $ ./ovs_interface.sh bind

   and also pin a logical switch to the chassis (simulate what is done by
   ovn-kubernetes):

   ::

        $ ovn-nbctl set logical_router gr_0001 options:chassis=chassis-1

6. Other settings might be desirable for the test:

   ::

        $ ovs-appctl vlog/set file:info
        $ ovs-vsctl set open . external_ids:ovn-enable-lflow-cache=false
        $ ovn-nbctl set nb_global . options:ignore_lsp_down=true
        $ ovn-sbctl set conn . inactivity_probe=0
        $ ovs-vsctl set open . external_ids:ovn-remote-probe-interval=60000

7. Measure performance of any operations, for example:

   ::

        $ OVN_NB_DAEMON="" ovn-nbctl --wait=hv --print-wait-time remove port_group pg_big_1 ports 0010f3e3-ea81-4ed1-b351-cc7c29756c76
        $ OVN_NB_DAEMON="" ovn-nbctl --wait=hv --print-wait-time add port_group pg_big_1 ports 0010f3e3-ea81-4ed1-b351-cc7c29756c76
