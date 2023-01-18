// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/DT_Minimal_Token.sol";

contract DTTest is Test {
    DT_45_Token public dtToken;
    DT_45_Token.share_data[] public arr_shares;
    address public shareOwner;

    function setUp() public {
        shareOwner = address(0x1);
        for (uint256 i = 0; i < 1000; i++) {
            DT_45_Token.share_data memory share = DT_45_Token.share_data(1, shareOwner);
            arr_shares.push(share);
        }
        dtToken = new DT_45_Token("Trump Digital Trading Card", "DT-45", "Donald T.", arr_shares);
        dtToken.grantRole(dtToken.MINTER_ROLE(), address(this));
    }

    function testPaymentSplitter() external {
        uint256 totalValue = 10.001 ether;
        vm.deal(address(dtToken), totalValue);
        dtToken.split_payment();
        assertEq(totalValue, address(shareOwner).balance); // assert if some owned all the shares, they'd get a full payment
    }

    function testAccessControl() external {
        address randomUser = address(0x3);
        vm.prank(randomUser); // set the msg.sender for the next call to randomUser
        vm.expectRevert(); // should fail because we don't have permission
        dtToken.setContractURI("randomUri");
    }


    function testTransfers() external {
        address sender = address(0x10);
        address receiver = address(0x3);

        uint16 amountToMint = 1;

        dtToken.mintSeveral(sender, amountToMint); // mint them 1 NFTs and try to transfer it
        vm.prank(sender);
        dtToken.transferFrom(sender, receiver, 1);
        assertEq(dtToken.balanceOf(receiver), 1);
        assertEq(dtToken.balanceOf(sender), 0);

    }

    uint256[] public tokenIds;
    function testMintingSeveralAndWithdraw() external {
        address receiver = address(0x10);
        uint16 amountToMint = 100;

        dtToken.mintSeveral(receiver, amountToMint); // mint them 100 NFTs
        assertEq(dtToken.balanceOf(receiver), amountToMint); // confirm user received 100 NFTs

        tokenIds.push(2); // cant have a dynamic array in memory so have to do this shit
        tokenIds.push(3);
        tokenIds.push(4);


        vm.prank(receiver);
        dtToken.withdrawBatch(tokenIds); // withdraw all tokenIds

        assertEq(dtToken.balanceOf(receiver), 97); // Assert 3 tokens were withdraw, 100 - 3 = 97
    }
}
