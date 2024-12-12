// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";

import {MyVault} from "../src/MyVault.sol";
import {DeployMyVault} from "../script/DeployMyVault.s.sol";

import {ILido, ILidoWithdrawalQueue} from "../src/interfaces/ILido.sol";

contract MyVaultTest is Test {
    IPool pool;
    MyVault vault;
    IERC20 asset;
    VariableDebtToken vdt;
    ILido lido;
    ILidoWithdrawalQueue lidoWithdraw;

    address LENDER;
    uint256 LENDER_KEY;

    address BORROWER;
    uint256 BORROWER_KEY;

    modifier delegateCredit(uint256 amount) {
        amount = bound(amount, 1, 1e6 * 1e6);

        bytes32 digest = vault.getDelegateCreditDigest(address(vault), amount, vdt.nonces(LENDER));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LENDER_KEY, digest);

        vm.startPrank(LENDER);
        asset.approve(address(vault), type(uint256).max);
        vault.supplyCollateralAndDelegateCredit(amount, 1e18, v, r, s);
        vm.stopPrank();

        _;
    }

    function setUp() external {
        (LENDER, LENDER_KEY) = makeAddrAndKey("lender");
        (BORROWER, BORROWER_KEY) = makeAddrAndKey("borrower");

        deal(LENDER, 100 ether);
        deal(BORROWER, 100 ether);
        (,, pool, vdt, vault, lido, lidoWithdraw) = (new DeployMyVault()).run();
        asset = vault.usdc();

        deal(address(vault), 1 ether);
        deal(address(asset), LENDER, 1e6 * 1e6);
        deal(address(asset), BORROWER, 1e6 * 1e6);
    }

    function test_supplyCollateralAndDelegateCredit(uint256 amount) external {
        // uint256 amount = 4e3 * 1e6;
        amount = bound(amount, 1, 1e6 * 1e6);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vdt.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        vdt.DELEGATION_WITH_SIG_TYPEHASH(),
                        address(vault),
                        amount,
                        vdt.nonces(LENDER),
                        type(uint256).max
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(LENDER_KEY, digest);

        vm.startPrank(LENDER);
        asset.approve(address(vault), type(uint256).max);
        vault.supplyCollateralAndDelegateCredit(amount, 1e18, v, r, s);
        vm.stopPrank();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(LENDER);

        console.log("total collateral base", totalCollateralBase);
        console.log("total debt base", totalDebtBase);
        console.log("available borrow base", availableBorrowsBase);
        console.log("current liquidation threshold", currentLiquidationThreshold);
        console.log("ltv", ltv);
        console.log("health factor", healthFactor);

        uint256 borrowAllowance = vdt.borrowAllowance(LENDER, address(vault));
        console.log("borrow allowance", borrowAllowance);
    }

    function test_createLeveragedPosition() external delegateCredit(1e3 * 1e6) {
        // uint256 leverage = leverageSeed % 5;
        uint256 amount = 1e2 * 1e6;
        uint256 leverage = 1;

        vm.startPrank(BORROWER);
        asset.approve(address(vault), type(uint256).max);
        vault.createLeveragedPosition(amount, leverage);
        vm.stopPrank();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(LENDER);

        console.log("total collateral base", totalCollateralBase);
        console.log("total debt base", totalDebtBase);
        console.log("available borrow base", availableBorrowsBase);
        console.log("current liquidation threshold", currentLiquidationThreshold);
        console.log("ltv", ltv);
        console.log("health factor", healthFactor);

        // uint256 borrowAllowance = vdt.borrowAllowance(LENDER, address(vault));
        // console.log("borrow allowance", borrowAllowance);

        // vm.startPrank(BORROWER);
        // asset.approve(address(vault), type(uint256).max);
        // vault.createLeveragedPosition(amount, leverage);
        // vm.stopPrank();

        // (
        //     totalCollateralBase,
        //     totalDebtBase,
        //     availableBorrowsBase,
        //     currentLiquidationThreshold,
        //     ltv,
        //     healthFactor
        // ) = pool.getUserAccountData(LENDER);

        // console.log("total collateral base", totalCollateralBase);
        // console.log("total debt base", totalDebtBase);
        // console.log("available borrow base", availableBorrowsBase);
        // console.log("current liquidation threshold", currentLiquidationThreshold);
        // console.log("ltv", ltv);
        // console.log("health factor", healthFactor);
    }
}
