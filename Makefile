default: help

help:
	@echo "See Makefile for implemented functions"

compile:
	forge compile --via-ir

clean:
	forge clean

build:
	forge build --via-ir

fuzz:
	forge test --fork-url ${ETH_RPC} --via-ir

fuzzv:
	forge test --fork-url ${ETH_RPC} --via-ir -vvv

supply:
	forge test --mt test_supplyCollateralAndDelegateCredit --fork-url ${ETH_RPC} --via-ir -vvv

borrow:
	forge test --mt test_createLeveragedPosition --fork-url ${ETH_RPC} --via-ir -vvv
