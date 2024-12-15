// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPriceOracle} from "aave-v3-core/contracts/interfaces/IPriceOracle.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IWETH} from "aave-v3-core/contracts/misc/interfaces/IWETH.sol";
import {VariableDebtToken} from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import {ISwapRouter} from "uniswap-v3-periphery/interfaces/ISwapRouter.sol";

import {PercentageMath} from "aave-v3-core/contracts/protocol/libraries/math/PercentageMath.sol";
import {WadRayMath} from "aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol";

import {ILido, ILidoWithdrawalQueue} from "./interfaces/ILido.sol";

contract MyVault is ERC4626 {
    error MyVault__NonZeroAmountRequired();
    error MyVault__LenderPositionExists();
    error MyVault__HealthFactorTooLow();
    error MyVault__AssetTransferFailed();
    error MyVault__InsufficientLenderDeposits();
    error MyVault__UnstakeRequestNotFinalized();

    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 public constant HEALTH_FACTOR_PRECISION = 1e18;
    uint256 public constant MINIMUM_HEALTH_FACTOR = 1 * HEALTH_FACTOR_PRECISION;
    uint256 public constant MAX_DEADLINE = type(uint256).max;
    uint256 public constant LIDO_MAX_UNSTAKE_AMOUNT = 1000 ether;

    address public immutable uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public immutable weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IPoolAddressesProvider immutable pap;
    IPool immutable pool;
    VariableDebtToken immutable vdt;
    IERC20 public immutable usdc;
    ILido immutable lido;
    ILidoWithdrawalQueue immutable lidoWithdraw;

    struct LenderData {
        uint256 delegatedAmount;
        uint256 usedAmount;
        uint256 minHealthFactor;
    }

    struct LenderDelegation {
        address lender;
        uint256 amount;
    }

    struct BorrowerPosition {
        uint256 amount;
        LenderDelegation[] delegations;
    }

    mapping(address lender => LenderData data) private lenderData;
    mapping(address borrower => BorrowerPosition position) private borrowPositions;

    address[] private lenders;
    uint256 private totalLenderDeposits;

    event LenderPositionCreated(address lender, uint256 amount, uint256 minHealthFactor);
    event LenderDepositUtilized(address lender, uint256 amount);
    event LeveragePositionCreated(address borrower, uint256 amount, uint256 leverage);
    event LidoStakeCreated(uint256 stakedAmount, uint256 stEthMinted);
    event LidoUnstakeInitiated(uint256 amount, uint256[] requestIds);
    event LidoUnstakeClaimed(uint256[] requestIds);
    event AssetConvertedToETH(uint256 assetAmount, uint256 ethAmount);
    event GeneratingYieldWithStETH(uint256 amount);

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert MyVault__NonZeroAmountRequired();
        }
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        IERC20 _asset,
        IPoolAddressesProvider _pap,
        VariableDebtToken _vdt,
        ILido _lido,
        ILidoWithdrawalQueue _lidoWithdraw
    ) ERC4626(_asset) ERC20(name, symbol) {
        usdc = _asset;
        pap = _pap;
        pool = IPool(pap.getPool());
        vdt = _vdt;
        lido = _lido;
        lidoWithdraw = _lidoWithdraw;
    }

    function supplyCollateralAndDelegateCredit(uint256 amount, uint256 minHealthFactor, uint8 v, bytes32 r, bytes32 s)
        external
        nonZeroAmount(amount)
    {
        if (minHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert MyVault__HealthFactorTooLow();
        }

        // initialize new lending position for caller
        _createLenderPosition(msg.sender, amount, minHealthFactor);

        // ensure caller has approved this contract to transfer asset
        _supplyCollateral(msg.sender, amount);

        // ensure v, r, s recover to msg.sender
        _delegateCredit(msg.sender, amount, v, r, s);
    }

    // borrower deposits asset and borrows leveraged amount
    function createLeveragedPosition(uint256 amount, uint256 leverage)
        external
        nonZeroAmount(amount)
        nonZeroAmount(leverage)
    {
        // transfer asset amount from caller to this contract
        bool success = usdc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert MyVault__AssetTransferFailed();
        }
        // deposit(amount, msg.sender);

        uint256 amountToBorrow = amount * leverage;
        uint256 amountLeftToBorrow = amountToBorrow;

        if (amountLeftToBorrow > totalLenderDeposits) {
            revert MyVault__InsufficientLenderDeposits();
        }

        (bool lendersFound, LenderDelegation[] memory delegations) = _borrowUsingLenderDeposits(amountToBorrow);

        if (!lendersFound) {
            revert MyVault__InsufficientLenderDeposits();
        }

        BorrowerPosition memory position = BorrowerPosition(amountToBorrow, delegations);
        borrowPositions[msg.sender] = position;

        emit LeveragePositionCreated(msg.sender, amount, leverage);

        uint256 ethAmount = _convertAssetToETH(amountToBorrow);
        uint256 stEthMintAmount = _stakeWithLido(ethAmount);

        // any additional yield strategy using liquid staking tokens ?
        _generateYield(stEthMintAmount);
    }

    function getHealthFactor(address lender) external view returns (uint256 healthFactor) {
        // hf = ($collateral + $lockedAsset) * liquidationthreshold / debtborrowed
        healthFactor = _getLenderHealthFactor(lender);
    }

    function liquidate() external pure {}

    function _createLenderPosition(address lender, uint256 amount, uint256 minHealthFactor) internal {
        if (lenderData[lender].delegatedAmount > 0) {
            revert MyVault__LenderPositionExists();
        }

        lenders.push(lender);
        lenderData[lender] = LenderData(amount, 0, minHealthFactor);

        totalLenderDeposits = totalLenderDeposits + amount;

        // transfers asset amount from caller to this contract
        // mint corresponding shares to caller
        deposit(amount, lender);

        emit LenderPositionCreated(lender, amount, minHealthFactor);
    }

    function _supplyCollateral(address onBehalfOf, uint256 amount) internal {
        // asset is already deposited to this contrat during createLenderPosition
        // this contract approves pool contract to transfer asset
        usdc.approve(address(pool), amount);
        // transfer asset from this contract to pool contract
        // send aToken back to onBehalfOf
        pool.supply(address(usdc), amount, onBehalfOf, 0);
    }

    function _delegateCredit(address onBehalfOf, uint256 amount, uint8 v, bytes32 r, bytes32 s) internal {
        // v, r, s should recover and match to delegator
        // set delegation allowance for this contract
        // this allows this contract to borrow funds against caller supplied collateral
        vdt.delegationWithSig(onBehalfOf, address(this), amount, MAX_DEADLINE, v, r, s);
    }

    function _borrowUsingLenderDeposits(uint256 amount)
        internal
        returns (bool lendersFound, LenderDelegation[] memory delegations)
    {
        delegations = new LenderDelegation[](lenders.length);

        for (uint256 i = 0; i < lenders.length && amount > 0; i++) {
            uint256 borrowedAmount = _borrowUsingLenderDeposit(lenders[i], amount);
            if (borrowedAmount > 0) {
                amount = amount - borrowedAmount;
                delegations[i] = LenderDelegation(lenders[i], borrowedAmount);
            }
        }

        lendersFound = amount == 0;
    }

    function _borrowUsingLenderDeposit(address lender, uint256 amount) internal returns (uint256 borrowAmount) {
        // need to check if borrow amount breaks health factor
        // what is the denomination of borrow amount ?
        borrowAmount = _getBorrowableAmount(lender, amount);

        uint256 healthFactorEstimate = _estimateHealthFactorAfterBorrow(lender, borrowAmount);
        if (healthFactorEstimate < lenderData[lender].minHealthFactor) {
            return 0;
        }

        totalLenderDeposits = totalLenderDeposits - borrowAmount;
        lenderData[lender].usedAmount = lenderData[lender].usedAmount + borrowAmount;

        pool.borrow(address(usdc), borrowAmount, 2, 0, lender);

        // if health factor goes below lender terms, need to revert
        _revertIfHealthFactorBreaks(lender);

        emit LenderDepositUtilized(lender, amount);
    }

    function _convertAssetToETH(uint256 amount) internal returns (uint256 ethAmount) {
        // swap asset for ETH
        // uniswapRouterV3.swapExactTokenForETH();
        //     struct ExactInputParams {
        //     bytes path;
        //     address recipient;
        //     uint256 deadline;
        //     uint256 amountIn;
        //     uint256 amountOutMinimum;
        // }
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams("0x", address(this), block.timestamp, amount, 0);
        uint256 amountOut = ISwapRouter(uniswapV3Router).exactInput(params);

        IWETH(weth).withdraw(amountOut);

        emit AssetConvertedToETH(amount, amountOut);
    }

    function _stakeWithLido(uint256 amount) internal returns (uint256 stEthMinted) {
        // stake leveraged amount to lido contract
        stEthMinted = lido.submit{value: amount}(address(0));

        emit LidoStakeCreated(amount, stEthMinted);
    }

    function _generateYield(uint256 amount) internal {
        // convert stETH to wstETH using DEX
        // uniswapRouterV3.swapExactTokenForTokens()

        // supply wstETH on AAVE V3
        // lido.approve(address(pool), amount);
        // pool.supply(address(lido), amount, address(this), 0);

        emit GeneratingYieldWithStETH(amount);
    }

    function _initiateUnstakeWithLido(uint256 amount) internal {
        uint256 modRes = amount % LIDO_MAX_UNSTAKE_AMOUNT;
        uint256 divRes = amount / LIDO_MAX_UNSTAKE_AMOUNT;

        uint256 size = modRes > 0 ? divRes + 1 : divRes;
        uint256[] memory amounts = new uint256[](size);

        amounts[0] = modRes;

        for (uint256 i = 1; i < size; i++) {
            amounts[i] = LIDO_MAX_UNSTAKE_AMOUNT;
        }

        uint256[] memory requestIds = lidoWithdraw.requestWithdrawals(amounts, address(this));

        emit LidoUnstakeInitiated(amount, requestIds);
    }

    function _checkUnstakeRequestStatus(uint256[] memory requestIds) internal view returns (bool) {
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = lidoWithdraw.getWithdrawalStatus(requestIds);

        for (uint256 i = 0; i < statuses.length; i++) {
            ILidoWithdrawalQueue.WithdrawalRequestStatus memory status = statuses[i];
            if (!status.isFinalized || status.isClaimed) {
                return false;
            }
        }

        return true;
    }

    function _claimUnstakeWithLido(uint256[] memory requestIds) internal {
        if (!_checkUnstakeRequestStatus(requestIds)) {
            revert MyVault__UnstakeRequestNotFinalized();
        }

        uint256 firstIndex = 0;
        uint256 lastIndex = lidoWithdraw.getLastCheckpointIndex();

        uint256[] memory hints = lidoWithdraw.findCheckpointHints(requestIds, firstIndex, lastIndex);

        lidoWithdraw.claimWithdrawals(requestIds, hints);

        emit LidoUnstakeClaimed(requestIds);
    }

    function _getLenderHealthFactor(address lender) internal view returns (uint256 customHealthFactor) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(lender);

        uint256 whatBorrowerDepositedBase = 0;
        customHealthFactor = totalDebtBase == 0
            ? type(uint256).max
            : (totalCollateralBase + whatBorrowerDepositedBase).percentMul(currentLiquidationThreshold).wadDiv(
                totalDebtBase
            );
    }

    function _isHealthFactorOkay(address lender) internal view returns (bool isHealthy) {
        uint256 currentHealthFactor = _getLenderHealthFactor(lender);
        uint256 minHealthFactor = lenderData[lender].minHealthFactor;
        isHealthy = currentHealthFactor >= minHealthFactor;
    }

    function _revertIfHealthFactorBreaks(address lender) internal view {
        if (!_isHealthFactorOkay(lender)) {
            revert MyVault__HealthFactorTooLow();
        }
    }

    function _getSuppliedCollateralAmount(address lender) internal view returns (uint256 collateralAmount) {
        (uint256 totalCollateralBase,,,,,) = pool.getUserAccountData(lender);
    }

    function _getBorrowableAmount(address lender, uint256 amount) public view returns (uint256 borrowableAmount) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 borrowableAmountBase,
            uint256 liquidationThreshold,
            uint256 ltv,
        ) = pool.getUserAccountData(lender);

        uint256 whatBorrowerDepositedBase = 0;
        uint256 totalDebtBaseEstimate =
            (totalCollateralBase + whatBorrowerDepositedBase).percentMul(ltv).wadDiv(lenderData[lender].minHealthFactor);
        borrowableAmount =
            totalDebtBaseEstimate > totalDebtBase ? _convertBaseAmountToAsset(totalDebtBaseEstimate - totalDebtBase) : 0;

        borrowableAmount = amount > borrowableAmount ? borrowableAmount : amount;
    }

    function _estimateHealthFactorAfterBorrow(address lender, uint256 amount)
        public
        view
        returns (uint256 healthFactor)
    {
        (uint256 totalCollateralBase, uint256 totalDebtBase,, uint256 liquidationThreshold,,) =
            pool.getUserAccountData(lender);

        uint256 amountBase = _convertAssetToBaseAmount(amount);

        uint256 whatBorrowerDepositedBase = 0;
        healthFactor = (totalCollateralBase + whatBorrowerDepositedBase).percentMul(liquidationThreshold).wadDiv(
            totalDebtBase + amountBase
        );
    }

    function _convertBaseAmountToAsset(uint256 amount) public view returns (uint256 assetAmount) {
        IPriceOracle oracle = IPriceOracle(pap.getPriceOracle());
        uint256 assetPrice = oracle.getAssetPrice(asset());
        assetAmount = amount * (10 ** decimals()) / assetPrice;
    }

    function _convertAssetToBaseAmount(uint256 amount) public view returns (uint256 baseAmount) {
        IPriceOracle oracle = IPriceOracle(pap.getPriceOracle());
        uint256 assetPrice = oracle.getAssetPrice(asset());
        baseAmount = amount * assetPrice / (10 ** decimals());
    }

    function getTotalAvailableLenderDeposits() external view returns (uint256 totalDeposits) {
        totalDeposits = totalLenderDeposits;
    }

    function getDelegateCreditDigest(address delegatee, uint256 amount, uint256 nonce)
        external
        view
        returns (bytes32 digest)
    {
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                vdt.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(vdt.DELEGATION_WITH_SIG_TYPEHASH(), delegatee, amount, nonce, type(uint256).max))
            )
        );
    }
}
