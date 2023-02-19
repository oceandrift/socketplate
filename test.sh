#!/bin/dash

cd $(dirname "$0")
echo 'Testing library'
dub test || exit $?

cd ./examples/manual-setup
echo 'Building example: manual-setup'
dub build || exit $?

cd ../tcp-echo
echo 'Building example: tcp-echo'
dub build || exit $?
