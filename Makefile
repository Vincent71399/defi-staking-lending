-include .env

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Update Dependencies
update:; forge update

build:; forge build

install:
	@forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-git
	@forge install foundry-rs/forge-std@v1.10.0 --no-git
	@forge install smartcontractkit/chainlink-brownie-contracts@1.3.0 --no-git

# run tests on sepolia
run_test :; forge test --fork-url $$SEPOLIA_RPC_URL -vvv
