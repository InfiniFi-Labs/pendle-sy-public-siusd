// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PendleERC20SYUpgV2} from "../contracts/core/StandardizedYield/implementations/PendleERC20SYUpgV2.sol";
import {PendleERC20WithOracleSY} from "../contracts/core/StandardizedYield/implementations/PendleERC20WithOracleSY.sol";
import {PendleChainlinkExchangeRateWrapper} from "../contracts/core/misc/PendleChainlinkExchangeRateWrapper.sol";

/*
https://pendle.notion.site/oft-sy-deployment
https://docs.chroniclelabs.org/Resources/FAQ/Oracles#what-happens-if-i-try-to-read-from-an-address-that-is-not-whitelisted
*/
contract DeployInfiniFiSYArbitrum is Script {
    address signer;

    address _PENDLE_PROXY_ADMIN = 0xA28c08f165116587D4F3E708743B4dEe155c5E64;
    address _OFT_IUSD = 0x5D81113b4e6A34256aa08bC44D17Bf101E811afa;
    address _OFT_SIUSD = 0x51B0f6AED4a421f09D28A5eDe1DCF460BCB54d30;
    address _ORACLE = 0xF67D834fE48f73491498173AE63ff808452Ea5a1;
    address _EXCHANGE_RATE_WRAPPER = 0x5e07001e944580316584c6ffD0116a766e074Bf4;

    function run() external {
        require(block.chainid == 42161, "Not on Arbitrum");
        uint256 _privateKey =
            vm.envOr("ETH_PRIVATE_KEY", 77814517325470205911140941194401928579557062014761831930645393041380819009408);
        signer = vm.addr(_privateKey);

        console.log("Using signer %s\n ", signer);

        /*vm.startBroadcast(_privateKey);
        PendleChainlinkExchangeRateWrapper exchangeRateWrapper = new PendleChainlinkExchangeRateWrapper(_ORACLE, 0);
        vm.stopBroadcast();*/
        PendleChainlinkExchangeRateWrapper exchangeRateWrapper = PendleChainlinkExchangeRateWrapper(_EXCHANGE_RATE_WRAPPER);

        // prank a whitelist for reading our oracle feed
        vm.prank(0xBd640b5C2190372877346474c8a9aA7b8C871DF1);
        (bool success, ) = _ORACLE.call(abi.encodeWithSignature("kiss(address)", address(exchangeRateWrapper)));
        require(success, "Failed to whitelist oracle feed");
        
        uint256 exchangeRate = exchangeRateWrapper.getExchangeRate();
        require(exchangeRate > 1.05e18, "Invalid exchange rate");
        require(exchangeRate < 1.06e18, "Invalid exchange rate");

        vm.startBroadcast(_privateKey);
        {
            PendleERC20WithOracleSY implementation = new PendleERC20WithOracleSY(_OFT_SIUSD, _OFT_IUSD, address(exchangeRateWrapper));
            IERC20Metadata yieldToken = IERC20Metadata(implementation.yieldToken());
            require(address(yieldToken) == _OFT_SIUSD, "Invalid yield token");
            IERC20Metadata underlyingAsset = IERC20Metadata(implementation.underlyingAsset());
            require(address(underlyingAsset) == _OFT_IUSD, "Invalid underlying asset");

            console.log("Contract size %s", address(implementation).code.length);

            bytes memory initData = abi.encodeWithSelector(
                PendleERC20SYUpgV2.initialize.selector,
                string.concat("SY ", yieldToken.name()),
                string.concat("SY-", yieldToken.symbol())
            );

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(implementation), address(_PENDLE_PROXY_ADMIN), initData);

            address[] memory tokensIn = PendleERC20WithOracleSY(payable(address(proxy))).getTokensIn();

            console.log("Got %s tokens allowed in", tokensIn.length);
            console.log("Deployed contract at %s", address(proxy));
            console.log("SY token name  : %s", PendleERC20WithOracleSY(payable(address(proxy))).name());
            console.log("SY token symbol: %s", PendleERC20WithOracleSY(payable(address(proxy))).symbol());
        }
        vm.stopBroadcast();
    }
}
