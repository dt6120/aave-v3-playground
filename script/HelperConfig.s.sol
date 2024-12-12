// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import {ILido, ILidoWithdrawalQueue} from "../src/interfaces/ILido.sol";

contract HelperConfig is Script {
    uint256 public constant ETHEREUM_CHAIN_ID = 1;

    struct NetworkConfig {
        IERC20 asset;
        IPoolAddressesProvider poolAddressesProvider;
        IPool pool;
        VariableDebtToken variableDebtToken;
        ILido lido;
        ILidoWithdrawalQueue lidoWithdraw;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == ETHEREUM_CHAIN_ID) {
            activeNetworkConfig = getEthereumConfig();
        }
    }

    function getEthereumConfig() private view returns (NetworkConfig memory) {
        IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        IPoolAddressesProvider pap = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
        // pool: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
        IPool pool = IPool(pap.getPool());
        DataTypes.ReserveData memory reserveData = pool.getReserveData(address(usdc));
        // usdc vdt: 0x72E95b8931767C79bA4EeE721354d6E99a61D004
        VariableDebtToken vdt = VariableDebtToken(reserveData.variableDebtTokenAddress);
        ILido lido = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        ILidoWithdrawalQueue lidoWithdraw = ILidoWithdrawalQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

        return NetworkConfig({
            asset: usdc,
            poolAddressesProvider: pap,
            pool: pool,
            variableDebtToken: vdt,
            lido: lido,
            lidoWithdraw: lidoWithdraw
        });
    }
}
