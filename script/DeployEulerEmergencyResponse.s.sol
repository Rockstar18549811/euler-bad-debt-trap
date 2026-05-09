// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "../src/EulerEmergencyResponse.sol";

contract DeployEulerEmergencyResponse is Script {
    function run() external returns (EulerEmergencyResponse response) {
        // Chain ID guard — prevents accidental deployment to wrong network
        require(block.chainid == 1, "This script is for Ethereum mainnet only");

        // Load authorized caller from environment
        address authorizedCaller = vm.envAddress("DROSERA_AUTHORIZED_CALLER");
        require(authorizedCaller != address(0), "Invalid authorized caller");

        vm.startBroadcast();
        response = new EulerEmergencyResponse(authorizedCaller);
        vm.stopBroadcast();

        console.log("EulerEmergencyResponse deployed at:", address(response));
        console.log("Authorized caller:", authorizedCaller);
    }
}
