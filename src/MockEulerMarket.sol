// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockEulerEToken {
    uint256 public totalSupplyUnderlying;

    function setTotalSupplyUnderlying(uint256 value) external {
        totalSupplyUnderlying = value;
    }

    function burnAssets(uint256 amount) external {
        require(totalSupplyUnderlying >= amount, "insufficient assets");
        totalSupplyUnderlying -= amount;
    }
}

contract MockEulerDToken {
    uint256 public totalSupply;

    function setTotalSupply(uint256 value) external {
        totalSupply = value;
    }

    function mintDebt(uint256 amount) external {
        totalSupply += amount;
    }
}

contract MockEulerPauseTarget {
    bool public paused;
    address public authorizedResponder;

    event EmergencyPaused(address indexed caller);

    error OnlyResponder();

    constructor(address responder_) {
        authorizedResponder = responder_;
    }

    function setAuthorizedResponder(address responder_) external {
        authorizedResponder = responder_;
    }

    function emergencyPause() external {
        if (msg.sender != authorizedResponder) revert OnlyResponder();
        paused = true;
        emit EmergencyPaused(msg.sender);
    }
}

contract MockEulerExploitSurface {
    MockEulerEToken public immutable eToken;
    MockEulerDToken public immutable dToken;

    constructor(address eToken_, address dToken_) {
        eToken = MockEulerEToken(eToken_);
        dToken = MockEulerDToken(dToken_);
    }

    function healthySetup(uint256 assets, uint256 liabilities) external {
        eToken.setTotalSupplyUnderlying(assets);
        dToken.setTotalSupply(liabilities);
    }

    // Euler-style bug: assets are reduced but liabilities remain
    function donateToReservesBug(uint256 amount) external {
        eToken.burnAssets(amount);
    }
}
