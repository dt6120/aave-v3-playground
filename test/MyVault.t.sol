// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPriceOracle} from "aave-v3-core/contracts/interfaces/IPriceOracle.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

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
    IPoolAddressesProvider pap;

    uint256 constant STARTING_ETH_BALANCE = 100 ether;
    uint256 constant STARTING_USDC_BALANCE = 1e6 * 1e6;
    uint256 constant CREDIT_DELEGATION_AMOUNT = 10 ether;

    uint256 constant LENDER_COUNT = 10;
    uint256 constant BORROWER_COUNT = 3;

    uint256 constant MAX_LEVERAGE = 5;
    uint256 constant MIN_USDC_AMOUNT = 10;

    address[] lenders;
    uint256[] lenderKeys;
    address[] borrowers;

    modifier delegateCredit(uint256 amount, uint256 lenderCount) {
        amount = bound(amount, MIN_USDC_AMOUNT, STARTING_USDC_BALANCE);

        for (uint256 i = 0; i < lenderCount; i++) {
            address lender = lenders[i];
            uint256 lenderKey = lenderKeys[i];

            bytes32 digest = vault.getDelegateCreditDigest(address(vault), amount, vdt.nonces(lender));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(lenderKey, digest);

            vm.startPrank(lender);
            asset.approve(address(vault), type(uint256).max);
            vault.supplyCollateralAndDelegateCredit(amount, 1e18, v, r, s);
            vm.stopPrank();
        }

        _;
    }

    modifier dealLenders() {
        _;

        for (uint256 i = 0; i < LENDER_COUNT; i++) {
            (address lender, uint256 lenderKey) = makeAddrAndKey(string.concat("lender_", Strings.toString(i + 1)));

            deal(lender, STARTING_ETH_BALANCE);
            deal(address(asset), lender, STARTING_USDC_BALANCE);

            lenders.push(lender);
            lenderKeys.push(lenderKey);
        }
    }

    modifier dealBorrowers() {
        _;

        for (uint256 i = 0; i < BORROWER_COUNT; i++) {
            address borrower = makeAddr(string.concat("borrower_", Strings.toString(i + 1)));

            deal(borrower, STARTING_ETH_BALANCE);
            deal(address(asset), borrower, STARTING_USDC_BALANCE);

            borrowers.push(borrower);
        }
    }

    function setUp() external dealLenders dealBorrowers {
        (, pap, pool, vdt, vault, lido, lidoWithdraw) = (new DeployMyVault()).run();
        asset = vault.usdc();
    }

    function test_supplyCollateralAndDelegateCredit(uint256 amount) external delegateCredit(amount, 6) {
        assertGt(vault.getTotalAvailableLenderDeposits(), 0);

        // (
        //     uint256 totalCollateralBase,
        //     uint256 totalDebtBase,
        //     uint256 availableBorrowsBase,
        //     uint256 currentLiquidationThreshold,
        //     uint256 ltv,
        //     uint256 healthFactor
        // ) = pool.getUserAccountData(LENDER);

        // console.log("total collateral base", totalCollateralBase);
        // console.log("total debt base", totalDebtBase);
        // console.log("available borrow base", availableBorrowsBase);
        // console.log("current liquidation threshold", currentLiquidationThreshold);
        // console.log("ltv", ltv);
        // console.log("health factor", healthFactor);

        // uint256 borrowAllowance = vdt.borrowAllowance(LENDER, address(vault));
        // console.log("borrow allowance", borrowAllowance);
    }

    function test_createLeveragedPosition(
        uint256 amount,
        uint256 lenderSeed,
        uint256 borrowerSeed,
        uint256 leverageSeed
    ) external delegateCredit(STARTING_USDC_BALANCE, 6) {
        amount = bound(amount, MIN_USDC_AMOUNT, STARTING_USDC_BALANCE);

        uint256 leverage = leverageSeed % MAX_LEVERAGE;
        vm.assume(leverage != 0);

        address borrower = borrowers[borrowerSeed % BORROWER_COUNT];

        vm.startPrank(borrower);
        deal(address(vault), 1 ether);
        asset.approve(address(vault), type(uint256).max);
        vault.createLeveragedPosition(amount, leverage);
        vm.stopPrank();

        // (
        // uint256 totalCollateralBase,
        // uint256 totalDebtBase,
        // uint256 availableBorrowsBase,
        // uint256 currentLiquidationThreshold,
        // uint256 ltv,
        // uint256 healthFactor
        // ) = pool.getUserAccountData(LENDER);

        // console.log("total collateral base", totalCollateralBase);
        // console.log("total debt base", totalDebtBase);
        // console.log("available borrow base", availableBorrowsBase);
        // console.log("current liquidation threshold", currentLiquidationThreshold);
        // console.log("ltv", ltv);
        // console.log("health factor", healthFactor);

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

    function test_estimateHealthFactor(uint256 amount, uint256 lenderSeed, uint256 borrowerSeed, uint256 leverageSeed)
        external
        delegateCredit(STARTING_USDC_BALANCE, 6)
    {
        address lender = lenders[0];

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(lender);

        // console.log("total collateral base", vault._convertBaseAmountToAsset(totalCollateralBase));
        // console.log("total debt base", vault._convertBaseAmountToAsset(totalDebtBase));
        // console.log("available borrow base", vault._convertBaseAmountToAsset(availableBorrowsBase));
        // console.log("current liquidation threshold", currentLiquidationThreshold);
        // console.log("ltv", ltv);
        // console.log("health factor", healthFactor);

        amount = amount % STARTING_USDC_BALANCE;
        vm.assume(amount != 0);

        uint256 leverage = leverageSeed % MAX_LEVERAGE;
        vm.assume(leverage != 0);

        uint256 borrowAmount = vault._getBorrowableAmount(lender, amount);

        uint256 healthFactorEstimate = vault._estimateHealthFactorAfterBorrow(lender, borrowAmount);
        // console.log("health factor estimate", healthFactorEstimate);

        address borrower = borrowers[borrowerSeed % BORROWER_COUNT];

        vm.startPrank(borrower);
        deal(address(vault), 1 ether);
        asset.approve(address(vault), type(uint256).max);
        vault.createLeveragedPosition(amount, leverage);
        vm.stopPrank();

        (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor) =
            pool.getUserAccountData(lenders[0]);

        // console.log("total collateral base", vault._convertBaseAmountToAsset(totalCollateralBase));
        // console.log("total debt base", vault._convertBaseAmountToAsset(totalDebtBase));
        // console.log("available borrow base", vault._convertBaseAmountToAsset(availableBorrowsBase));
        // console.log("current liquidation threshold", currentLiquidationThreshold);
        // console.log("ltv", ltv);
        // console.log("health factor", healthFactor);

        assertEq(healthFactorEstimate, healthFactor);
    }
}
