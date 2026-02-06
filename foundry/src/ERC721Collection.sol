// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC2981Upgradeable} from "openzeppelin-contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";

interface IVRFAdapter {
    function requestRandomness(uint256 tokenId) external returns (uint256 requestId);
}

/// @title ERC721Collection
/// @notice Upgradeable ERC721 collection with royalties and reveal mechanism
/// @dev Supports instant and delayed (VRF) reveal types
contract ERC721Collection is
    Initializable,
    ERC721Upgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct InitConfig {
        string name;
        string symbol;
        string revealType;
        string baseURI;
        string placeholderURI;
        address royaltyReceiver;
        uint96 royaltyFeeNumerator;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 batchMintSupply;
        address vrfAdapter;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    using SafeCast for uint256;

    uint256 public maxSupply;
    uint256 public mintPrice;
    uint256 public batchMintSupply;
    string public revealType;

    uint256 private _nextTokenId;
    string private _baseTokenURI;
    string private _placeholderURI;
    address private _vrfAdapter;
    address private _paymentReceiver;

    mapping(uint256 => bool) private _isRevealed;
    mapping(uint256 => bool) private _vrfPendingReveals;
    mapping(uint256 => uint256) private _revealedTraitsIndex;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BaseURIUpdated(string newBaseURI);
    event DefaultRoyaltyInfoSet(address indexed royaltyReceiver, uint96 indexed royaltyFeeNumerator);
    event Initialized(address indexed owner, string name, string symbol);
    event MintPriceUpdated(uint256 indexed newMintPrice);
    event NewMintedToken(uint256 indexed tokenId);
    event PaymentReceiverUpdated(address indexed newPaymentReceiver);
    event TokenRevealed(uint256 indexed tokenId, uint256 indexed traitIndex);
    event VRFRequested(uint256 indexed requestId, uint256 indexed tokenId);
    event VRFRevealCompleted(uint256 indexed tokenId, uint256 indexed traitIndex);
    event Withdrawn(uint256 indexed balance);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error IncorrectBatchMintSupply();
    error InsufficientBalance();
    error InvalidVRFRequest();
    error MaxSupplyReached();
    error NoUnrevealedIndexes();
    error NotAnOwner();
    error OnlyVRFAdapter();
    error TokenAlreadyPendingReveal();
    error TokenIsNotMinted();
    error TokenIsRevealedAlready();
    error TransferFailed();
    error VRFRequestFailed();
    error VrfAdapterNotSet();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the collection
    /// @param config Configuration parameters
    function initialize(InitConfig memory config) external initializer {
        __ERC721_init(config.name, config.symbol);
        __ERC2981_init();
        __Ownable_init(msg.sender);

        revealType = config.revealType;
        _baseTokenURI = config.baseURI;
        _placeholderURI = config.placeholderURI;
        maxSupply = config.maxSupply;
        mintPrice = config.mintPrice;
        batchMintSupply = config.batchMintSupply;

        if (config.vrfAdapter == address(0)) revert ZeroAddress();
        _vrfAdapter = config.vrfAdapter;

        if (config.batchMintSupply > config.maxSupply) {
            revert IncorrectBatchMintSupply();
        }

        _setDefaultRoyalty(config.royaltyReceiver, config.royaltyFeeNumerator);
        _paymentReceiver = config.royaltyReceiver;
        _nextTokenId = 1;

        uint256 endTokenId = _nextTokenId + batchMintSupply;
        unchecked {
            for (uint256 i = _nextTokenId; i < endTokenId; ++i) {
                // Using _mint instead of _safeMint for gas efficiency during batch mint
                // Safe because tokens are transferred to collection owner after creation
                _mint(msg.sender, i);
            }
            _nextTokenId = endTokenId;
        }

        emit Initialized(msg.sender, config.name, config.symbol);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints a new token
    function mint() external payable nonReentrant {
        if (_nextTokenId > maxSupply) revert MaxSupplyReached();
        if (msg.value < mintPrice) revert InsufficientBalance();

        (bool success,) = payable(_paymentReceiver).call{value: msg.value}("");
        if (!success) revert TransferFailed();

        _safeMint(msg.sender, _nextTokenId);
        emit NewMintedToken(_nextTokenId);

        if (keccak256(abi.encodePacked(revealType)) == keccak256(abi.encodePacked("instant"))) {
            _instantReveal(_nextTokenId);
        }

        unchecked {
            _nextTokenId++;
        }
    }

    /// @notice Requests delayed reveal via VRF
    /// @param tokenId The token ID to reveal
    function delayedReveal(uint256 tokenId) external nonReentrant {
        if (msg.sender != ownerOf(tokenId)) revert NotAnOwner();
        if (_isRevealed[tokenId]) revert TokenIsRevealedAlready();
        if (_vrfPendingReveals[tokenId]) revert TokenAlreadyPendingReveal();
        if (_vrfAdapter == address(0)) revert VrfAdapterNotSet();

        _vrfPendingReveals[tokenId] = true;

        try IVRFAdapter(_vrfAdapter).requestRandomness(tokenId) returns (uint256 requestId) {
            emit VRFRequested(requestId, tokenId);
        } catch {
            _vrfPendingReveals[tokenId] = false;
            revert VRFRequestFailed();
        }
    }

    /// @notice Callback from VRF adapter with random number
    /// @param tokenId The token ID to reveal
    /// @param randomNumber The random number from VRF
    function revealWithRandomNumber(uint256 tokenId, uint256 randomNumber) external {
        if (msg.sender != _vrfAdapter) revert OnlyVRFAdapter();
        if (_isRevealed[tokenId]) revert TokenIsRevealedAlready();
        if (!_vrfPendingReveals[tokenId]) revert InvalidVRFRequest();

        uint256 startIndex = (randomNumber % maxSupply) + 1;
        uint256 traitIndex = nextUnrevealedIndex(startIndex);

        _isRevealed[tokenId] = true;
        _revealedTraitsIndex[tokenId] = traitIndex;
        _vrfPendingReveals[tokenId] = false;

        emit TokenRevealed(tokenId, traitIndex);
        emit VRFRevealCompleted(tokenId, traitIndex);
    }

    /// @notice Sets the base URI
    /// @param newBaseURI The new base URI
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /// @notice Sets the default royalty info
    /// @param royaltyReceiver The royalty receiver address
    /// @param royaltyFeeNumerator The royalty fee in basis points
    function setDefaultRoyaltyInfo(address royaltyReceiver, uint96 royaltyFeeNumerator) external onlyOwner {
        if (royaltyReceiver == address(0)) revert ZeroAddress();
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeNumerator);
        emit DefaultRoyaltyInfoSet(royaltyReceiver, royaltyFeeNumerator);
    }

    /// @notice Sets the payment receiver address
    /// @param newPaymentReceiver The new payment receiver
    function setPaymentReceiver(address newPaymentReceiver) external onlyOwner {
        if (newPaymentReceiver == address(0)) revert ZeroAddress();
        _paymentReceiver = newPaymentReceiver;
        emit PaymentReceiverUpdated(newPaymentReceiver);
    }

    /// @notice Sets the mint price
    /// @param newMintPrice The new mint price
    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        mintPrice = newMintPrice;
        emit MintPriceUpdated(newMintPrice);
    }

    /// @notice Withdraws contract balance
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        (bool success,) = payable(_paymentReceiver).call{value: balance}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(balance);
    }

    /// @notice Returns the count of revealed tokens
    function getRevealedCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i <= _nextTokenId - 1; ++i) {
            if (_isRevealed[i]) {
                count++;
            }
        }
        return count;
    }

    /// @notice Returns the VRF adapter address
    function getVRFAdapter() external view returns (address) {
        return _vrfAdapter;
    }

    /// @notice Returns the default royalty receiver
    function getDefaultRoyaltyReceiver() external view returns (address) {
        (address receiver,) = royaltyInfo(type(uint256).max, 10000);
        return receiver;
    }

    /// @notice Returns the revealed trait index for a token
    /// @param tokenId The token ID
    function getRevealedTraitIndex(uint256 tokenId) external view returns (uint256) {
        if (!_isRevealed[tokenId]) return 0;
        return _revealedTraitsIndex[tokenId];
    }

    /// @notice Returns the total minted supply
    function getSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /// @notice Returns the remaining mintable supply
    function remainingSupply() external view returns (uint256) {
        return maxSupply - (_nextTokenId - 1);
    }

    /// @notice Checks if a token is revealed
    /// @param tokenId The token ID
    function isRevealed(uint256 tokenId) external view returns (bool) {
        if (tokenId >= _nextTokenId) revert TokenIsNotMinted();
        return _isRevealed[tokenId];
    }

    /// @notice Returns the next token ID to be minted
    function getNextTokenId() external view returns (uint256) {
        if (this.remainingSupply() == 0) revert MaxSupplyReached();
        return _nextTokenId;
    }

    /// @notice Returns the mint price
    function getMintPrice() external view returns (uint256) {
        return mintPrice;
    }

    /// @notice Checks if a token is approved for an operator
    /// @param tokenId The token ID
    /// @param operator The operator address
    function isTokenApproved(uint256 tokenId, address operator) external view returns (bool) {
        address owner = ownerOf(tokenId);
        return (getApproved(tokenId) == operator || isApprovedForAll(owner, operator));
    }

    /// @notice Returns the collection settings
    function getCollectionSettings() external view returns (InitConfig memory config) {
        config.name = name();
        config.symbol = symbol();
        config.revealType = revealType;
        config.baseURI = _baseTokenURI;
        config.placeholderURI = _placeholderURI;
        (config.royaltyReceiver, config.royaltyFeeNumerator) = _getDefaultRoyaltyInfo();
        config.maxSupply = maxSupply;
        config.mintPrice = mintPrice;
        config.batchMintSupply = batchMintSupply;
        config.vrfAdapter = _vrfAdapter;
    }

    /// @notice Checks if a token reveal is pending
    /// @param tokenId The token ID
    function isVrfPendingReveal(uint256 tokenId) external view returns (bool) {
        return _vrfPendingReveals[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the royalty info for a token
    /// @param tokenId The token ID
    /// @param salePrice The sale price
    /// @return royaltyAmount The royalty amount
    /// @return royaltyReceiver The royalty receiver
    function getRoyaltyByTokenId(uint256 tokenId, uint256 salePrice) public view returns (uint256 royaltyAmount, address royaltyReceiver) {
        (royaltyReceiver, royaltyAmount) = royaltyInfo(tokenId, salePrice);
    }

    /// @notice Finds the next unrevealed index
    /// @param startIndex The starting index
    function nextUnrevealedIndex(uint256 startIndex) public view returns (uint256) {
        for (uint256 i = startIndex; i >= 1;) {
            if (!_isRevealed[i]) {
                return i;
            }
            unchecked {
                --i;
            }
        }

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

    /// @notice See {IERC165-supportsInterface}
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Returns the token URI
    /// @param tokenId The token ID
    function tokenURI(uint256 tokenId) public view virtual override(ERC721Upgradeable) returns (string memory) {
        _requireOwned(tokenId);

        if (!_isRevealed[tokenId]) {
            return _placeholderURI;
        }

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0
            ? string(abi.encodePacked(baseURI, Strings.toString(_revealedTraitsIndex[tokenId])))
            : "";
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Performs instant reveal using pseudo-random number
    function _instantReveal(uint256 tokenId) internal {
        uint256 randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    blockhash(block.number - 1),
                    msg.sender,
                    tokenId,
                    _nextTokenId
                )
            )
        );

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

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override {}

    /// @dev Hook called before token transfers
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /// @dev Returns the base URI
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Returns the default royalty info
    function _getDefaultRoyaltyInfo() internal view returns (address receiver, uint96 feeNumerator) {
        uint256 salePrice = _feeDenominator();
        uint256 royaltyAmount;
        (receiver, royaltyAmount) = royaltyInfo(type(uint256).max, salePrice);
        feeNumerator = royaltyAmount.toUint96();
    }
}
