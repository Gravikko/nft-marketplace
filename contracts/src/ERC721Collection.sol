
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC2981Upgradeable} from "openzeppelin-contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @title VRF Adapter Interface
/// @notice Interface for VRF Adapter contract
interface IVRFAdapter {
    function requestRandomness(uint256 tokenId) external returns (uint256 requestId);
}

/// @title An NFT Creation contract with multiple choices of reveal types
/// @notice This is an upgradeable ERC721 collection with royalties support

/// @TODO: VRF chainlink 
/// multisignature + timelock to avoid compromentation (not only in this contract, but in each, factory , marketplace and etc)
/// beacon proxy

contract ERC721Collection is 
    Initializable,
    ERC721Upgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    uint256 public maxSupply;
    uint256 public mintPrice;
    uint256 public batchMintSupply; 
    uint256 private _nextTokenId;
    string public revealType;
    string private _baseTokenURI;
    string private placeholderURI;
    mapping(uint256 => bool) private _isRevealed;
    mapping(uint256 => bool) private _vrfPendingReveals;
    mapping(uint256 => uint256) private _revealedTraitsIndex;
    address private _vrfAdapter;

    /* Events */
    event BaseURIUpdated(string newBaseURI);
    event Initialized(address indexed owner, string name, string symbol);
    event MintPriceUpdated(uint256 indexed newMintPrice);
    event NewDefaultRoyaltyInfoSet(address indexed royaltyReceiver, uint96 indexed royaltyFeeNumerator);
    event NewMintedToken(uint256 indexed tokenId);
    event TokenRevealed(uint256 indexed tokenId, uint256 indexed traitIndex);
    event VRFRequested(uint256 indexed requestId, uint256 indexed tokenId);
    event VRFRevealCompleted(uint256 indexed tokenId, uint256 indexed traitIndex);
    event Withdrawn(uint256 indexed balance);

    /* Errors */ 
    error IncorrectBatchMintSupply();
    error InsufficientBalance();
    error InvalidVRFRequest();
    error MaxSupplyReached();
    error NoUnrevealedIndexes();
    error NotAnOwner();
    error OnlyVRFAdapter();
    error TokenAlreadyPendingReveal(uint256 tokenId);
    error TokenIsNotMinted();
    error TokenIsRevealedAlready(uint256 tokenId);
    error TransferFailed();
    error VRFRequestFailed();
    error VrfAdapterNotSet();
    error ZeroAddress();
 
    constructor() {
        _disableInitializers();
    }
 
    /**
     * @dev Initializes the contract. Called by the proxy
     * @param name Token collection name
     * @param symbol Token collection symbol   
     * @param _revealType Type of reveal (e.g., "instant", "manual")
     * @param baseURI Base URI for unrevealed tokens
     * @param _placeholderURI Placeholder URI for unrevealed tokens
     * @param royaltyReceiver Address to receive royalties
     * @param royaltyFeeNumerator Fee numerator for royalties (basis points / 10000)
     * @param _maxSupply Maximum number of tokens
     * @param _mintPrice Price per mint
     * @param _batchMintSupply Number of tokens allow for batch mint
     */
    function initialize(
        string memory name,
        string memory symbol, 
        string memory _revealType,
        string memory baseURI,
        string memory _placeholderURI,
        address royaltyReceiver, 
        uint96 royaltyFeeNumerator,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _batchMintSupply,
        address vrfAdapter
    ) external initializer {
        __ERC721_init(name, symbol);
        __ERC2981_init();
        __Ownable_init(msg.sender);
 
        revealType = _revealType;
        _baseTokenURI = baseURI;
        placeholderURI = _placeholderURI; 
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        batchMintSupply = _batchMintSupply;

        if (vrfAdapter == address(0)) revert ZeroAddress();

        _vrfAdapter = vrfAdapter;

        if (batchMintSupply > maxSupply) {
            revert IncorrectBatchMintSupply();
        }
        
        // Set royalty info
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeNumerator);
        
        _nextTokenId = 1;

        uint256 endTokenId = _nextTokenId + batchMintSupply;
        unchecked {
            for (uint256 i = _nextTokenId; i < endTokenId; ++i) {
                _mint(msg.sender, i);
            }
            _nextTokenId = endTokenId;
        }

        emit Initialized(msg.sender, name, symbol);
    }


    /**
     * @dev Mint 
     */
    function mint() external payable {
        if (_nextTokenId > maxSupply) revert MaxSupplyReached();
        if (msg.value < mintPrice) revert InsufficientBalance();
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        if (!success) revert TransferFailed();
        _safeMint(msg.sender, _nextTokenId);
        emit NewMintedToken(_nextTokenId);

        if (revealType == "instant") {
            instantReveal(_nextTokenId);
        }

        unchecked {
            _nextTokenId++;
        }
    }

    /**
     * @dev Sets the base URI for tokens
     * @param newBaseURI New base URI
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev Sets new 
     */
    function setNewDefaultRoyaltyInfo(address royaltyReceiver, uint96 royaltyFeeNumerator) external {
        if (royaltyReceiver == address(0)) revert ZeroAddress();
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeNumerator);
        emit NewDefaultRoyaltyInfoSet(royaltyReceiver, royaltyFeeNumerator);
    }

    /**
     * @dev Reveal is processing using VRF Chainlink
     * @param tokenId The token ID to reveal
     */
    function delayedReveal(uint256 tokenId) external {
        if (msg.sender != ownerOf(tokenId)) {
            revert NotAnOwner();
        }

        if (_isRevealed[tokenId]) {
            revert TokenIsRevealedAlready(tokenId);
        }

        if (_vrfPendingReveals[tokenId]) {
            revert TokenAlreadyPendingReveal(tokenId);
        }

        if (_vrfAdapter == address(0)) {
            revert VrfAdapterNotSet();
        }

        // Mark token as pending reveal
        _vrfPendingReveals[tokenId] = true;

        // Request randomness from VRF Adapter
        try IVRFAdapter(_vrfAdapter).requestRandomness(tokenId) returns (uint256 requestId) {
            emit VRFRequested(requestId, tokenId);
        } catch {
            _vrfPendingReveals[tokenId] = false;
            revert VRFRequestFailed();
        }
    }

    /**
     * @dev Callback function called by VRF Adapter with random number
     * @param tokenId The token ID to reveal
     * @param randomNumber The random number from VRF
     */
    function revealWithRandomNumber(uint256 tokenId, uint256 randomNumber) external {
        if (msg.sender != _vrfAdapter) {
            revert OnlyVRFAdapter();
        }

        if (!_vrfPendingReveals[tokenId]) {
            revert InvalidVRFRequest();
        }

        if (_isRevealed[tokenId]) {
            revert TokenIsRevealedAlready(tokenId);
        }

        // Use random number to find unrevealed trait index
        uint256 startIndex = (randomNumber % maxSupply) + 1;
        uint256 traitIndex = nextUnrevealedIndex(startIndex);

        // Mark as revealed and set trait index
        _isRevealed[tokenId] = true;
        _revealedTraitsIndex[tokenId] = traitIndex;
        _vrfPendingReveals[tokenId] = false;

        emit TokenRevealed(tokenId, traitIndex);
        emit VRFRevealCompleted(tokenId, traitIndex);
    }

    /**
     * @dev Sets new mint price 
     */
    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        mintPrice = newMintPrice;
        emit MintPriceUpdated(newMintPrice);
    }

    /**
     * @dev Withdraw money from contract balance
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(balance);
    }

    /**
     * @dev Get count of revealed tokens
     */
    function getRevealedCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i <= _nextTokenId - 1; ++i) {
            if (_isRevealed[i]) {
                count++;
            }
        }
        return count;
    } 

    /**
     * @dev Gets the VRF Adapter address
     * @return The VRF Adapter address
     */
    function getVRFAdapter() external view returns (address) {
        return _vrfAdapter;
    } 

    /**
     * @dev Get Default royalty receiver
     */
    function getDefaultRoyaltyReceiver() external view returns(address) {
        ERC2981Storage storage $ = _getERC2981Storage();
        return $._defaultRoyaltyInfo.receiver;
    }


    /**
     * @dev Get the revealed trait index for a tokenId
     * @return The trait index if token is revealed, 0 if not
     */
    function getRevealedTraitIndex(uint256 tokenId) external view returns (uint256) {
        if (!_isRevealed[tokenId]) return 0;
        return _revealedTraitsIndex[tokenId];
    }

    /**
     * @dev Get total number of minted tokens
     */
    function getSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @dev Get remaining supply of available to mint
    */
    function remainingSupply() external view returns (uint256) {
        return maxSupply - (_nextTokenId - 1);
    }

    /**
     * @dev Check if token is revealed
     */
    function isRevealed(uint256 tokenId) external view returns (bool) {
        if (tokenId >= _nextTokenId) revert TokenIsNotMinted();
        return _isRevealed[tokenId];
    }

    /**
     * @dev Check if token is approved for marketplace
     */
    function isTokenApproved(uint256 tokenId, address _marketplace) external view returns(bool) {
        address owner = _ownerOf(tokenId);
        return (
            _tokenApprovals[tokenId] == _marketplace ||
            _operatorApprovals[owner][_marketplace]
        );
    }

    /**
     * @dev See {IERC165-supportsInterface}
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns token URI depend on revealed status
     */
    function tokenURI(uint256 tokenId) 
        public
        view
        virtual
        override(ERC721Upgradeable)
        returns(string memory)
    {
        _requireOwned(tokenId);

        if (!_isRevealed[tokenId]) {
            return placeholderURI;
        }

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 
            ? string(abi.encodePacked(baseURI, Strings.toString(_revealedTraitsIndex[tokenId])))
            : "";
    }

    /**
     * @dev Returns royalty info for tokenId
     */
    function getRoyaltyByTokenId(uint256 tokenId) public view returns(uint256 royaltyAmount, address royaltyReceiver) {
        ERC2981Storage storage $ = _getERC2981Storage();
        RoyaltyInfo storage _royaltyInfo = $._tokenRoyaltyInfo[tokenId];
        royaltyReceiver = _royaltyInfo.receiver;
        royaltyAmount = _royaltyInfo.royaltyFraction;

        if (royaltyReceiver == address(0)) {
            royaltyReceiver = $._defaultRoyaltyInfo.receiver;
            royaltyAmount = $._defaultRoyaltyInfo.royaltyFraction;
        } 
    }

    /**
     * @dev Find the nearest unrevealed index, starting from startIndex
     * @param startIndex The index to start searching from
     * @return The nearest unrevealed trait index
     */
    function nextUnrevealedIndex(uint256 startIndex) public view returns(uint256) {
        // Search backwards from startIndex
        for (uint256 i = startIndex; i >= 1;) {
            if (!_isRevealed[i]) {
                return i;
            }
            unchecked {
                --i;
            }
        }

        // If nothing found backwards, search forwards
        for (uint256 i = startIndex + 1; i <= maxSupply;) {
            if (!_isRevealed[i]) {
                return i;
            }
            unchecked {
                ++i;
            }
        }

        revert NoUnrevealedIndexes();
    }

    /**
     * @dev Generates pseudo-random number for instant reveal
     * @notice This is not cryptographically secure and can be manipulated by miners/validators
     * @param tokenId The token ID being revealed
     * @return A pseudo-random trait index (1 to maxSupply)
     */
    function instantReveal(uint256 tokenId) internal {
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            block.prevrandao,
            blockhash(block.number - 1),
            msg.sender,
            tokenId,
            _nextTokenId
        )));

        uint256 unrevealedCount;
        for (uint256 i = 1; i <= maxSupply; ++i) {
            if (!_isRevealed[i]) {
                unrevealedCount++;
            }
        }

        if (unrevealedCount == 0) {
            revert NoUnrevealedIndexes();
        }

        uint256 startIndex = (randomSeed % maxSupply) + 1;
        uint256 traitIndex = nextUnrevealedIndex(startIndex);
        _isRevealed[tokenId] = true;
        _revealedTraitsIndex[tokenId] = traitIndex;

        emit TokenRevealed(tokenId, traitIndex); 
    }

    /**
     * @dev Authorizes upgrade. Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address) internal override {}

    /**
     * @dev Hook called before any transfer
     */
    function _update(address to, uint256 tokenId, address auth)
        internal 
        override(ERC721Upgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Returns the base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
