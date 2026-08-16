#!/usr/bin/env bash
sudo sysctl kernel.split_lock_mitigate=0
sudo scxctl start --sched lavd --mode gaming

sudo systemctl disable --now ananicy-cpp

#ADIOS Disk scheduler
# sync && echo mq-deadline | sudo tee /sys/block/nvme0n1/queue/scheduler
# sync && echo mq-deadline | sudo tee /sys/block/nvme1n1/queue/scheduler
# sync && echo mq-deadline | sudo tee /sys/block/sdb/queue/scheduler
# sync && echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
