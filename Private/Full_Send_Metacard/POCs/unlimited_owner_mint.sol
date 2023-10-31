// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "../src/FullSend.sol";

contract Hack is Test {
    FullSend public nftContract;
    address public admin = vm.addr(1);
    address public user = vm.addr(2);

    function setUp() external {
        //give everyone the sweet moneys
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        vm.startPrank(admin);
        nftContract = new FullSend("ipfs://QmTfh19epr5BTeq5Qv4CF3M1ughVHgd7DYS37nfdRHbMF5/", "");
        nftContract.flipMainSaleState();

        vm.stopPrank();
    }

    function testHack() public {

        //The admin mints all the tokens for himself(for free)
        vm.startPrank(admin);
        nftContract.mintToAddress(address(admin), 10000);
        vm.stopPrank();

        //The user tries to mint a token for himself but fails
        vm.startPrank(user);
        vm.expectRevert(bytes("Purchase would exceed max number of whitelist tokens"));
        (bool status, ) = address(nftContract).call{value: 0.75 ether}(abi.encodeWithSelector(FullSend.mint.selector, 1));
        assertTrue(status, "expectRevert: call did not revert");
        vm.stopPrank();
    }
}