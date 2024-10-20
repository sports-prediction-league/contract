t:
	snforge test

deploy:
#	sncast --account account_1 deploy --url https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/mLHskI2HsCQrodimPkMEefxe5r8XSLhy --fee-token eth --class-hash 0x01784449a2a2d6a5eb29b0ebe5f65929ee05960d940d667ace64a4419feffde7 --constructor-calldata 0x4b45615c40e7242a2378fbaf20f6f06476221ffa29f3c773c2fdccbf3aac49b
	sncast deploy --fee-token eth --class-hash 0x0149754fbc153c4aa948cbbe946273ef36e06506f821bebfc693e76dc1182933 --constructor-calldata 0x4b45615c40e7242a2378fbaf20f6f06476221ffa29f3c773c2fdccbf3aac49b


declare:
	sncast \
    declare \
    --fee-token eth \
    --contract-name Prediction


upgrade:
	sncast \
	invoke \
	--fee-token eth \
	--contract-address 0x2265c71be9283b0131e391ff18f3858167ed457d71322dbaa5befab9cfc0030 \
	--function "upgrade" \
	--calldata 0x13d581142ddf7f4fcec0c40e717c122db75627cafd6f9ef107b54997468224b