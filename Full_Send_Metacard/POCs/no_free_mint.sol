// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "../src/FullSend.sol";

contract Hack is Test {
    FullSend public nftContract;
    address public admin = vm.addr(1);
    address public whitelistUser = vm.addr(2);

    function setUp() external {

        //give everyone the sweet moneys
        vm.deal(admin, 100 ether);
        vm.deal(whitelistUser, 100 ether);

        vm.startPrank(admin);
        nftContract = new FullSend("ipfs://QmTfh19epr5BTeq5Qv4CF3M1ughVHgd7DYS37nfdRHbMF5/", "");

        //output from helpers/merkle_tree_generator.js
        nftContract.setWhitelistMerkleRoot(0x3dd73fb4bffdc562cf570f864739747e2ab5d46ab397c4466da14e0e06b57d56);
        nftContract.flipPresaleState();
        vm.stopPrank();
    }

    function testHack() public {
        vm.startPrank(whitelistUser);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x3322f33946a3c503c916c8fc29768a547f01fa665e1eb22f9f66cf7e5a262012;

        //we expect the user to revert as it is calling mintWhiteList without any value
        vm.expectRevert(bytes("Incorrect ETH value sent"));
        (bool status, ) = address(nftContract).call{value: 0 ether}(abi.encodeWithSelector(FullSend.mintWhitelist.selector, proof, 1));
        assertTrue(status, "expectRevert: call did not revert");
        
        vm.stopPrank();
    }
}