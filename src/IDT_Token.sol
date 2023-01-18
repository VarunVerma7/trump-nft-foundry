// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IDT_Token {
    function mintSeveral(address _minter, uint16 numberOfTokens) external;
    function tokenExists(uint256 tokenId) external view returns (bool);
}
