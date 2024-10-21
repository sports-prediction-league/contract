t:
	snforge test

deploy:
#	sncast --account account_1 deploy --url https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/mLHskI2HsCQrodimPkMEefxe5r8XSLhy --fee-token eth --class-hash 0x01784449a2a2d6a5eb29b0ebe5f65929ee05960d940d667ace64a4419feffde7 --constructor-calldata 0x4b45615c40e7242a2378fbaf20f6f06476221ffa29f3c773c2fdccbf3aac49b
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