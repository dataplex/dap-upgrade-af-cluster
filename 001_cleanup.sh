#!/usr/bin/env bash

. config.sh

rm -f cluster.yaml
rm -f policy-load.out
rm -f *.seed

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "rm -f *.seed"
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "rm -f *.seed"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "rm -f *.seed"
