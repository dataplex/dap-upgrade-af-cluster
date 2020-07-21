# dap-upgrade-af-cluster
A set of scripts to help upgrade the master/standby nodes in an auto-failover cluster

1. Copy config.sh.template to config.sh and set values appropriately.
2. Run the scripts in order....
```shell
$ cp config.sh.template config.sh
$ vi config.sh
$ ./000_setup.sh
$ ./001_clean.sh # only required on repeat runs
$ ./002_install_old.sh # sets up the 'original' version in an AF cluster
$ ./003_upgrade.sh
```

It's that simple.... let me know how I can improve it!
