// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFAdapter} from "../../src/VRFAdapter.sol";

contract MockVRFCoordinatorV2Plus is IVRFCoordinatorV2Plus {
    mapping(uint256 => address) public consumers;
    uint256 public nextRequestId = 1;

    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata /* req */
    ) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        consumers[requestId] = msg.sender;
        return requestId;
    }

    function fulfillRequest(
        VRFAdapter adapter,
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        require(consumers[requestId] == address(adapter), "unknown adapter");
        adapter.rawFulfillRandomWords(requestId, randomWords);
    }

    function addConsumer(uint256 subId, address consumer) external {}

    function removeConsumer(uint256 subId, address consumer) external {}

    function cancelSubscription(uint256 subId, address to) external {}

    function acceptSubscriptionOwnerTransfer(uint256 subId) external {}

    function requestSubscriptionOwnerTransfer(uint256 subId, address newOwner) external {}

    function createSubscription() external returns (uint256 subId) {}

    function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers) {}

    function pendingRequestExists(uint256 subId) external view returns (bool) {}

    function getActiveSubscriptionIds(uint256 startIndex, uint256 maxCount) external view returns (uint256[] memory) {}

    function fundSubscriptionWithNative(uint256 subId) external payable {}
}

contract MockERC721Collection {
    VRFAdapter public vrfAdapter;
    mapping(uint256 => uint256) public revealedTokens;

    bool public shouldRevertReveal = false;

    function setVRFAdapter(address adapter) external {
        vrfAdapter = VRFAdapter(adapter);
    }

    function revealWithRandomNumber(uint256 tokenId, uint256 randomNumber) external {
        require(msg.sender == address(vrfAdapter), "only vrf adapter");
        if (shouldRevertReveal) revert("reveal failed");
        revealedTokens[tokenId] = randomNumber;
    }

    function requestReveal(uint256 tokenId) external returns (uint256) {
        return vrfAdapter.requestRandomness(tokenId);
    }
}

contract MockMultisigTimelock {
    function verifyCurrentTransaction() public pure {}
}

contract MockVRFAdapter {
    uint256 public requestId = 1;
    function requestRandomness(uint256 tokenId) external returns (uint256) {
        uint256 randomNumber = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    requestId,
                    tokenId
                )
            )
        );
        requestId++;
        return randomNumber;
    }
}

contract MockERC721CollectionBeacon {
    address public _implementation;

    function upgradeTo(address newImplementation) external {
        _implementation = newImplementation;
    }

    function implementation() external view returns (address) {
        return _implementation;
    }
}