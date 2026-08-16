#!/usr/bin/env bash

sudo sysctl kernel.split_lock_mitigate=1
sudo scxctl stop

sudo systemctl enable --now ananicy-cpp
