// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EulerEmergencyResponse.sol";

contract DeployEulerEmergencyResponse is Script {
    function run() external returns (EulerEmergencyResponse response) {
        require(block.chainid == 1, "Ethereum mainnet only");

        address droseraCaller = vm.envAddress("DROSERA_AUTHORIZED_CALLER");
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 cooldownBlocks = 33;

        require(droseraCaller != address(0), "Invalid drosera caller");
        require(owner != address(0), "Invalid owner");

        vm.startBroadcast();
        response = new EulerEmergencyResponse(droseraCaller, owner, cooldownBlocks);
        vm.stopBroadcast();

        console.log("EulerEmergencyResponse deployed at:", address(response));
        console.log("Drosera caller:", droseraCaller);
        console.log("Owner:", owner);
    }
}
