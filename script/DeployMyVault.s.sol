// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {MyVault} from "../src/MyVault.sol";
import {ILido, ILidoWithdrawalQueue} from "../src/interfaces/ILido.sol";

contract DeployMyVault is Script {
    function run()
        external
        returns (
            IERC20 asset,
            IPoolAddressesProvider pap,
            IPool pool,
            VariableDebtToken vdt,
            MyVault vault,
            ILido lidoStaking,
            ILidoWithdrawalQueue lidoWithdraw
        )
    {
        HelperConfig config = new HelperConfig();
        (asset, pap, pool, vdt, lidoStaking, lidoWithdraw) = config.activeNetworkConfig();

        vm.broadcast();
        vault = new MyVault("vUSDC", "vUSDC", asset, pap, vdt, lidoStaking, lidoWithdraw);
    }
}
