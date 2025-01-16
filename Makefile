t:
	snforge test

deploy:
	sncast deploy --fee-token eth --class-hash ${class_hash} --constructor-calldata ${arg} ${another_arg}


declare:
	sncast \
    declare \
    --fee-token eth \
    --contract-name ${name}


upgrade:
	sncast \
	invoke \
	--fee-token eth \
	--contract-address ${address} \
	--function "upgrade" \
	--calldata ${calldata}