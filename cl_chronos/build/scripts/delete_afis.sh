#!/bin/bash

# extract command
~/.local/bin/aws ec2 describe-fpga-images --owners self --filters \
"Name=update-time,Values=2019-11-25*" | grep "afi-" | sed 's/\"FpgaImageId\": \"//' | sed 's/\",//g' | sed -e 's/^\s*//' | sed 's/[ \t]*$//' > 2018_afis

input="2018_afis"
while IFS= read -r var
do
    echo "$var"
    ~/.local/bin/aws ec2 delete-fpga-image --fpga-image-id "$var"

done < "$input"
