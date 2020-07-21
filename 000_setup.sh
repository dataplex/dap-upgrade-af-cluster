#!/usr/bin/env bash

. config.sh

for i in $(set | grep ^MASTER\d* | grep _INT | cut -f2 -d=);do
	ssh -i $SSH_KEY $SSH_USER@$i "sudo yum update -y; sudo yum install -y docker jq"
	ssh -i $SSH_KEY $SSH_USER@$i "sudo systemctl enable docker; sudo systemctl start docker"
	ssh -i $SSH_KEY $SSH_USER@$i "sudo usermod -a -G docker ec2-user"

	scp -i $SSH_KEY $FROM_FILE_PATH $SSH_USER@$i:.
	local from_file="$(echo "$FROM_FILE_PATH" | awk -F '/' '{print $NF}')"
	ssh -i $SSH_KEY $SSH_USER@$i "docker load -i ./$from_file"

	scp -i $SSH_KEY $TO_FILE_PATH $SSH_USER@$i:.
	local to_file="$(echo "$TO_FILE_PATH" | awk -F '/' '{print $NF}')"
	ssh -i $SSH_KEY $SSH_USER@$i "docker load -i ./$to_file"
done
