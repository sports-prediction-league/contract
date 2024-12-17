t:
	snforge test

deploy:
	sncast deploy --fee-token eth --class-hash ${class_hash} --constructor-calldata ${arg}


declare:
	sncast \
    declare \
    --fee-token eth \
    --contract-name Prediction


upgrade:
	sncast \
	invoke \
	--fee-token eth \
	--contract-address ${address} \
	--function "upgrade" \
	--calldata ${calldata}