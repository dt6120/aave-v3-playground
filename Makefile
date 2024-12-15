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
