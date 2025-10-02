all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Update Dependencies
update:; forge update

build:; forge build

install:
	@forge install OpenZeppelin/openzeppelin-contracts@v5.4.0
	@forge install foundry-rs/forge-std@v1.10.0
	@forge install smartcontractkit/chainlink-brownie-contracts@1.3.0

# run tests on sepolia
#run_test :; forge test --fork-url $$SEPOLIA_RPC_URL -vvv

coverage_report :; FOUNDRY_PROFILE=coverage forge coverage --report summary --report lcov -vv

# generate state dump for defi staking pool
# run in terminal 1
open_anvil_to_dump_state :; anvil --port 8545 --dump-state anvil_states/defi_staking_state.json
# run in terminal 2
deploy_dspool :; forge script script/DeployDSPool.s.sol --broadcast --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --json > anvil_states/defi_staking_state_log.json

start_anvil_with_dspool :; anvil --load-state anvil_states/defi_staking_state.json
# verify
verify_dspool :
	@cast call 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 'symbol()(string)' --rpc-url http://127.0.0.1:8545
	@cast call 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853 'name()(string)' --rpc-url http://127.0.0.1:8545
	@cast call 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9 'latestRoundData()(uint80,int256,uint256,uint256,uint80)' --rpc-url http://127.0.0.1:8545
