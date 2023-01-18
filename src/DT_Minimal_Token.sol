// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./IDT_Token.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {DefaultOperatorFilterer} from "@operator-filter-registry/src/DefaultOperatorFilterer.sol";

contract DT_45_Token is IDT_Token, ERC721Enumerable, DefaultOperatorFilterer, IERC2981, AccessControl, Ownable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    struct share_data {
        uint16 share;
        address payee;
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant CONTRACT_ADMIN = keccak256("CONTRACT_ADMIN");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    uint16 internal constant collectionRoyaltyAmount = 100;
    string private collectionURI;
    uint16 public nextToken = 1;
    string public tokenBaseURI;
    bool public frozen;
    mapping(uint16 => bool) public withdrawnTokens;
    // limit batching of tokens due to gas limit restrictions
    uint16 public constant BATCH_LIMIT = 20;

    share_data[] public shares;

    event ContractURIChanged(string uri);
    event BaseURI(string baseURI);
    event WithdrawnBatch(address indexed user, uint256[] tokenIds);
    event PaymentReceived(uint256 value);
    event MetadataFrozen();

    error InvalidTokenOwner(uint256 tokenId);

    constructor(string memory _name, string memory _symbol, string memory _tokenBaseURI, share_data[] memory _shares)
        ERC721(_name, _symbol)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(CONTRACT_ADMIN, _msgSender());
        tokenBaseURI = _tokenBaseURI;
        uint256 count = 0;
        for (uint256 sh = 0; sh < _shares.length; sh++) {
            count += _shares[sh].share;
            shares.push(_shares[sh]);
        }
        require(count == 1000, "total shares must equal 1000");
    }

    receive() external payable {
        emit PaymentReceived(msg.value);
    }

    function contractURI() external view returns (string memory) {
        return collectionURI;
    }

    function mintSeveral(address _minter, uint16 numberOfTokens) external onlyRole(MINTER_ROLE) {
        uint256 pos = nextToken;
        console.log("POS IS", pos);
        nextToken += numberOfTokens;
        for (uint256 j = 0; j < numberOfTokens; j++) {
            _mint(_minter, pos++);
        }
    }

    function freeze() external onlyRole(CONTRACT_ADMIN) {
        frozen = true;
        emit MetadataFrozen();
    }

    function setBaseURI(string memory newBaseURI) external onlyRole(CONTRACT_ADMIN) {
        require(!frozen, "Collection is frozen");
        tokenBaseURI = newBaseURI;
        emit BaseURI(newBaseURI);
    }

    function setContractURI(string memory _uri) external onlyRole(CONTRACT_ADMIN) {
        collectionURI = _uri;
        emit ContractURIChanged(_uri);
    }

    function tokenExists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    /// IERC2981
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        // calculate the amount of royalties
        uint256 _royaltyAmount = (salePrice * collectionRoyaltyAmount) / 1000; // 10%
        // return the amount of royalties and the recipient collection address
        return (address(this), _royaltyAmount);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        // reformat to directory structure as below
        string memory folder = (tokenId / 1000).toString();
        string memory file = tokenId.toString();
        string memory slash = "/";
        return string(abi.encodePacked(tokenBaseURI, folder, slash, file, ".json"));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721Enumerable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC721Enumerable).interfaceId || interfaceId == type(AccessControl).interfaceId
            || interfaceId == type(IERC165).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required tokenId(s) for user
     * Should set `withdrawnTokens` mapping to `false` for the tokenId being deposited
     * Minting can also be done by other functions
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded tokenIds. Batch deposit also supported.
     */
    function deposit(address user, bytes calldata depositData) external onlyRole(DEPOSITOR_ROLE) {
        // deposit single
        if (depositData.length == 32) {
            uint256 tokenId = abi.decode(depositData, (uint256));
            withdrawnTokens[uint16(tokenId)] = false;
            _mint(user, tokenId);

            // deposit batch
        } else {
            uint256[] memory tokenIds = abi.decode(depositData, (uint256[]));
            uint256 length = tokenIds.length;
            for (uint256 i; i < length; i++) {
                withdrawnTokens[uint16(tokenIds[i])] = false;
                _mint(user, tokenIds[i]);
            }
        }
    }

    /**
     * @notice called when user wants to withdraw token back to root chain
     * @dev Should handle withraw by burning user's token.
     * Should set `withdrawnTokens` mapping to `true` for the tokenId being withdrawn
     * This transaction will be verified when exiting on root chain
     * @param tokenId tokenId to withdraw
     */
    function withdraw(uint256 tokenId) external {
        require(_msgSender() == ownerOf(tokenId), "INVALID_TOKEN_OWNER");
        withdrawnTokens[uint16(tokenId)] = true;
        _burn(tokenId);
    }

    /**
     * @notice called when user wants to withdraw multiple tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param tokenIds tokenId list to withdraw
     */
    function withdrawBatch(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        require(length <= BATCH_LIMIT, "EXCEEDS_BATCH_LIMIT");

        // Iteratively burn ERC721 tokens, for performing
        // batch withdraw
        for (uint256 i; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            if (_msgSender() != ownerOf(tokenId)) {
                revert InvalidTokenOwner(tokenId);
            }
            withdrawnTokens[uint16(tokenId)] = true;
            _burn(tokenId);
        }

        // At last emit this event, which will be used
        // in MintableERC721 predicate contract on L1
        // while verifying burn proof
        emit WithdrawnBatch(_msgSender(), tokenIds);
    }

    function split_erc20_payment(address erc20) external {
        IERC20 token = IERC20(erc20);
        uint256 amount_to_pay = token.balanceOf(address(this));
        for (uint256 payee = 0; payee < shares.length; payee++) {
            token.safeTransfer(shares[payee].payee, shares[payee].share * amount_to_pay / 1000);
        }
    }

    function split_payment() external {
        uint256 amount_to_pay = address(this).balance;
        for (uint256 payee = 0; payee < shares.length; payee++) {
            sendETH(shares[payee].payee, shares[payee].share * amount_to_pay / 1000);
        }
    }

    function sendETH(address dest, uint256 amount) internal {
        (bool sent,) = payable(dest).call{value: amount}(""); // don't use send or xfer (gas)
        require(sent, "Failed to send Ether");
    }

    // opensea stuff

    function transferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}
