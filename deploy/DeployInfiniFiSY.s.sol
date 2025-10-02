// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PendleInfinifiSIUSD} from "../contracts/core/StandardizedYield/implementations/InfiniFi/PendleInfiniFisiUSD.sol";

contract DeployInfiniFi is Script {
    address signer;

    address PENDLE_ADMIN = 0xA28c08f165116587D4F3E708743B4dEe155c5E64;

    function run() external {
        uint256 _privateKey =
            vm.envOr("PRIVATE_KEY", 77814517325470205911140941194401928579557062014761831930645393041380819009408);
        signer = vm.addr(_privateKey);

        console.log("Using signer %s\n ", signer);

        vm.startBroadcast(_privateKey);
        {
            PendleInfinifiSIUSD implementation = new PendleInfinifiSIUSD();
            IERC20Metadata yieldToken = IERC20Metadata(implementation.yieldToken());
            assert(address(yieldToken) == implementation.SIUSD());

            console.log("Contract size %s", address(implementation).code.length);

            bytes memory initData = abi.encodeWithSelector(
                PendleInfinifiSIUSD.initialize.selector,
                string.concat("SY ", yieldToken.name()),
                string.concat("SY-", yieldToken.symbol())
            );

            TransparentUpgradeableProxy proxy =
                new TransparentUpgradeableProxy(address(implementation), address(PENDLE_ADMIN), initData);

            address[] memory tokensIn = PendleInfinifiSIUSD(payable(address(proxy))).getTokensIn();

            console.log("Got %s tokens allowed in", tokensIn.length);
            console.log("Deployed contract at %s", address(proxy));
            console.log("SY token name  : %s", PendleInfinifiSIUSD(payable(address(proxy))).name());
            console.log("SY token symbol: %s", PendleInfinifiSIUSD(payable(address(proxy))).symbol());
        }
        vm.stopBroadcast();
    }
}
