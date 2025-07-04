// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../contracts/core/StandardizedYield/implementations/InfiniFi/PendleInfiniFisiUSD.sol";

interface FiatTokenV1 {
    function masterMinter() external returns (address);

    function mint(address _to, uint256 _amount) external returns (bool);

    function configureMinter(address minter, uint256 minterAmount) external returns (bool);
}

// Main Fixture and configuration for preparing test environment
abstract contract InfiniFiTest is Test {
    // this function is required to ignore this file from coverage
    function test() public pure virtual {}

    // this function is to be used to deal tokens because the
    // USDC contract does not work with the standard deal function
    // as the storage is not the same as many other tokens
    // basically, USDC needs to be minted as the master minter
    // while for other tokens, we use deal from the stdCheats
    function dealToken(address token, address to, uint256 amount) public {
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        if (token == usdc) {
            // if usdc, needs to mint as the master minter
            address masterMint = FiatTokenV1(usdc).masterMinter();
            vm.prank(masterMint);
            FiatTokenV1(usdc).configureMinter(address(this), type(uint256).max);
            FiatTokenV1(usdc).mint(to, amount);
        } else {
            deal(token, to, amount);
        }
    }
}

contract InfiniFiPendleTest is InfiniFiTest {
    PendleInfinifiSIUSD adapter;
    address user = makeAddr("user");

    address usdc;
    address iusd;
    address siusd;

    function setUp() public {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/bYiYTFqsDKMe0iuVrL-1RKE1dfAMSzNp");

        // Deploy implementation
        PendleInfinifiSIUSD implementation = new PendleInfinifiSIUSD();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            PendleInfinifiSIUSD.initialize.selector, "Pendle InfiniFi siUSD", "PendleInfiniFi-siUSD"
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        adapter = PendleInfinifiSIUSD(payable(address(proxy)));

        usdc = adapter.USDC();
        iusd = adapter.IUSD();
        siusd = adapter.SIUSD();
    }

    function _deposit(address token, uint256 amount) internal {
        dealToken(token, user, amount);

        vm.startPrank(user);
        IERC20(token).approve(address(adapter), type(uint256).max);

        uint256 balanceOfUserBefore = IERC20(token).balanceOf(user);
        uint256 adapterBalanceBefore = adapter.balanceOf(user);
        uint256 siUSDBalanceBefore = IERC20(siusd).balanceOf(user);

        adapter.deposit(user, token, amount, 0);

        uint256 balanceOfUserAfter = IERC20(token).balanceOf(user);
        uint256 adapterBalanceAfter = adapter.balanceOf(user);
        uint256 siUSDBalanceAfter = IERC20(siusd).balanceOf(user);

        // Verify the deposit worked
        assertEq(balanceOfUserBefore - balanceOfUserAfter, amount, "Token should be transferred from user");
        assertGt(adapterBalanceAfter, adapterBalanceBefore, "User should receive adapter tokens");
        assertEq(siUSDBalanceAfter, siUSDBalanceBefore, "User should not receive siUSD tokens");
    }

    function _redeem(address token, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(siusd).approve(address(adapter), type(uint256).max);
        adapter.approve(address(adapter), type(uint256).max);

        uint256 balanceOfUserBefore = IERC20(token).balanceOf(user);
        uint256 adapterBalanceBefore = adapter.balanceOf(user);

        adapter.redeem(user, amount, token, 0, false);

        uint256 balanceOfUserAfter = IERC20(token).balanceOf(user);
        uint256 adapterBalanceAfter = adapter.balanceOf(user);

        // Verify the redeem worked
        assertGt(balanceOfUserAfter, balanceOfUserBefore, "User should receive token");
        assertLt(adapterBalanceAfter, adapterBalanceBefore, "Adapter tokens should be less");
    }

    function test_adapter() public {
        _deposit(usdc, 100e6);
        _deposit(iusd, 100e18);

        uint256 shareTokenAmount = adapter.balanceOf(user);

        _redeem(iusd, shareTokenAmount / 2);
        _redeem(usdc, shareTokenAmount / 2);
    }
}
