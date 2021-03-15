.PHONY : all config build run clean test_live test_simulated_substrate test_simulated_cosmos test_faulty_simulated_substrate test_faulty_simulated_cosmos
.DEFAULT_GOAL := all

clean-gaia:
	rm -rf ./cosmos-sdk ./gaia 2>/dev/null
	rm -rf data 2>/dev/null

build-gaia: | clean-gaia
	git clone https://github.com/ParthDesai/cosmos-sdk
	cd cosmos-sdk && git checkout add-wasm-management

	git clone https://github.com/cosmos/gaia
	cd gaia/ && git checkout e9d6d7f8cbba0bb3bf1ed531260b913824e3a117
	
	cd gaia && echo "replace github.com/cosmos/cosmos-sdk => ../cosmos-sdk" >> go.mod
	cd gaia && sed -i "s/-mod=readonly//g" Makefile
	
	cd gaia && make build

start-gaia: | clean-config-gaia config-gaia
	cd gaia && make build
	gaia/build/gaiad start --home "data/.gaiad"  --rpc.laddr tcp://0.0.0.0:26657 --trace

clean-config-gaia:
	rm -rf data 2>/dev/null

config-gaia: | clean-config-gaia
	gaia/build/gaiad init --home "data/.gaiad" --chain-id=wormhole node || true
	yes | gaia/build/gaiad keys --home "data/.gaiad" add validator --keyring-backend test |& tail -1 > data/.gaiad/validator_mnemonic
	yes | gaia/build/gaiad keys --home "data/.gaiad" add relayer --keyring-backend test |& tail -1 > data/.gaiad/relayer_mnemonic

	gaia/build/gaiad add-genesis-account --home "data/.gaiad" $$(gaia/build/gaiad --home "data/.gaiad" keys show validator -a --keyring-backend test) 100000000000stake,100000000000validatortoken
	gaia/build/gaiad add-genesis-account --home "data/.gaiad" $$(gaia/build/gaiad --home "data/.gaiad" keys show relayer -a --keyring-backend test) 100000000000stake,100000000000validatortoken
	gaia/build/gaiad gentx --home "data/.gaiad" --chain-id "wormhole" validator 100000000000stake --keyring-backend test
	gaia/build/gaiad collect-gentxs --home "data/.gaiad"

	cp configs/live_config.json data/live_config.json
	cp configs/faulty* data/
	cp configs/simulated* data/

	cp configs/app.toml data/.gaiad/config/app.toml

clean-lcd:
	rm -rf celo-light-client 2>/dev/null

build-lcd: | clean-lcd
	git clone https://github.com/mkaczanowski/celo-light-client.git
	cd celo-light-client && git checkout wasm_contract

	cd celo-light-client && make wasm-optimized

start-lcd:
	cd celo-light-client && make wasm-optimized
	stat celo-light-client/target/wasm32-unknown-unknown/release/celo_light_client.wasm
	gaia/build/gaiad tx ibc wasm-manager push_wasm wormhole celo-light-client/target/wasm32-unknown-unknown/release/celo_light_client.wasm --gas=80000000 --home "data/.gaiad" --node http://localhost:26657 --chain-id wormhole --from=relayer --keyring-backend test --yes

clean-qt:
	rm -rf quantum-tunnel 2>/dev/null

build-qt: | clean-qt
	git clone https://github.com/mkaczanowski/quantum-tunnel
	cd quantum-tunnel && git checkout celo_handler

	cd quantum-tunnel && cargo build --features celo

start-qt:
	gaia/build/gaiad --home "data/.gaiad" query ibc wasm-manager wasm_code_entry wormhole | grep -oP "code_id: \K.*" | head -n1 | xargs -I{} sed -i 's/"wasm_id": ".*"/"wasm_id": "{}"/g' quantum-tunnel/test_data/simulated_celo_chain_config.json

	cd quantum-tunnel && COSMOS_SIGNER_SEED=$$(cat ../data/.gaiad/relayer_mnemonic) SUBSTRATE_SIGNER_SEED="flat reflect table identify forward west boat furnace similar million list wood"  CELO_SIGNER_SEED="flat reflect table identify forward west boat furnace similar million list wood" RUST_LOG=info cargo run --features celo -- -c test_data/simulated_celo_chain_config.json start

clean-geth:
	rm -rf celo-blockchain 2>/dev/null

build-geth: | clean-geth
	curl https://github.com/celo-org/celo-blockchain/archive/v1.2.4.tar.gz -L | tar xvz
	mv celo-blockchain-1.2.4 celo-blockchain

	cd celo-blockchain &&  go run build/ci.go install ./cmd/geth

start-geth:
	cd celo-blockchain && go run build/ci.go install ./cmd/geth && ./build/bin/geth  --maxpeers 50 --light.maxpeers 20 --syncmode lightest --rpc  --ws --wsport 3334 --wsapi eth,net,web3,istanbul --rpcapi eth,net,web3,istanbul console 

clean: | clean-geth clean-qt clean-lcd clean-gaia clean-config-gaia
