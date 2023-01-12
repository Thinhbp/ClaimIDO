// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

contract Marketplace is
    Initializable,
    IERC721Receiver,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC1155ReceiverUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IERC20;
    using SafeMath for uint256;

    function initialize() public initializer {
        __Context_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        listingId = 0;
        serviceSellerFee = 4000;
        serviceBuyerFee = 2000;
    }

    modifier validNFTContractAddress(address _address) {
        require(_address != address(0) && _address != address(this));
        _;
    }

    modifier onlySeller(address nftAddress, uint256 tokenId) {
        require(listings[nftAddress][tokenId].owner == msg.sender);
        _;
    }

    modifier onlyItemSeller(address nftAddress, uint256 _listingId) {
        require(
            itemListings[nftAddress][_listingId].owner == msg.sender,
            "Marketplace: caller is not owner"
        );
        _;
    }

    modifier onlyWhitelistNFT(address nftAddress) {
        require(
            whitelistNFTContracts[nftAddress],
            "Marketplace: INVALID_NFT_CONTRACT"
        );
        _;
    }
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // Map from token ID to their corresponding offer.
    uint256 public listingId;
    uint256 public serviceSellerFee; // 100.000 = 100%
    uint256 public serviceBuyerFee; // 100.000 = 100%
    address public treasury;
    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => mapping(uint256 => ItemListing)) public itemListings;
    mapping(address => bool) public whitelistCurrencies;
    mapping(address => bool) public whitelistNFTContracts;

    struct Listing {
        // Price (in wei)
        uint256 price;
        // Current owner of NFT
        address owner;
        // current token address. only accept whitelist token
        address currency;
    }
    struct ItemListing {
        // Price (in wei)
        uint256 price;
        // Current owner of NFT
        address owner;
        // items
        uint256 tokenId;
        // amount of items
        uint256 amount;
    }

    function getListing(address nftAddress, uint256 tokenId)
        external
        view
        returns (uint256 price, address owner)
    {
        Listing memory listing = listings[nftAddress][tokenId];
        require(listingExists(listing));
        return (listing.price, listing.owner);
    }

    function createListing(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address currencyAddress
    )
        external
        validNFTContractAddress(nftAddress)
        onlyWhitelistNFT(nftAddress)
    {
        address seller = msg.sender;
        IERC721 nft = getNftContract(nftAddress);
        require(
            whitelistCurrencies[currencyAddress],
            "Marketplace: INVALID_CURRENCY"
        );
        require(
            whitelistNFTContracts[nftAddress],
            "Marketplace: INVALID_NFT_CONTRACT"
        );

        require(nft.ownerOf(tokenId) == seller, "Marketplace: NOT_NFT_OWNER");
        require(
            msg.sender != address(0) && msg.sender != address(this),
            "Marketplace: INVALID_SENDER"
        );

        nft.safeTransferFrom(seller, address(this), tokenId);

        Listing memory listing = Listing(price, seller, currencyAddress);
        listings[nftAddress][tokenId] = listing;

        emit ListingCreated(seller, nftAddress, tokenId, price);
    }

    function cancelListing(address nftAddress, uint256 tokenId)
        external
        onlySeller(nftAddress, tokenId)
    {
        IERC721 nft = getNftContract(nftAddress);
        Listing storage listing = listings[nftAddress][tokenId];
        nft.safeTransferFrom(address(this), listing.owner, tokenId);
        delete listings[nftAddress][tokenId];
        emit Unlisted(nftAddress, tokenId);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 _price
    ) external onlySeller(nftAddress, tokenId) {
        // update new listing
        listings[nftAddress][tokenId].price = _price;
        emit ListingUpdated(tokenId, _price);
    }

    /**
     * @notice
     */
    function buyNft(address nftAddress, uint256 tokenId)
        external
        payable
        nonReentrant
    {
        Listing storage listing = listings[nftAddress][tokenId];
        require(listingExists(listing), "Marketplace: NOT_EXISTED");
        require(msg.value == listing.price, "Marketplace: INVALID_PRICE");

        // it is require that we setup the treasury address beforehand

        if (listing.currency != address(0)) {} else {
            if (serviceSellerFee > 0) {
                payable(treasury).transfer(
                    msg.value -
                        (msg.value * (100000 - serviceSellerFee)).div(100000)
                );
            }

            uint256 price = (msg.value * (100000 - serviceSellerFee)).div(
                100000
            );
            payable(listing.owner).transfer(price);
        }

        IERC721 nft = getNftContract(nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Trade(
            msg.sender,
            listing.owner,
            nftAddress,
            tokenId,
            listing.price
        );
        delete listings[nftAddress][tokenId];
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0) && _treasury != address(this));
        treasury = _treasury;
    }

    /// @dev Returns true if the offer is on marketplace.
    /// @param listing - Listing to check.
    function listingExists(Listing memory listing)
        internal
        view
        returns (bool)
    {
        return (listing.owner != address(0));
    }

    /// @dev Gets the NFT object from an address, validating that implementsERC721 is true.
    /// @param nftAddress - Address of the NFT.
    function getNftContract(address nftAddress)
        internal
        pure
        returns (IERC721)
    {
        IERC721 candidateContract = IERC721(nftAddress);
        return candidateContract;
    }

    function getNftItemContract(address nftAddress)
        internal
        pure
        returns (IERC1155Upgradeable)
    {
        IERC1155Upgradeable candidateContract = IERC1155Upgradeable(nftAddress);
        return candidateContract;
    }

    function setserviceSellerFee(uint256 _serviceSellerFee) external onlyOwner {
        require(
            _serviceSellerFee >= 0 && _serviceSellerFee <= 100000,
            "service fee invalid"
        );

        serviceSellerFee = _serviceSellerFee;
        emit serviceSellerFeeUpdated(serviceSellerFee);
    }

    // function getTreasury() external view returns (address) {
    //     return treasury;
    // }

    /**
     * @dev create listing item in game
     * @param tokenId: list of token id
     * @param amount: list amount of token
     * @param price: list price of token
     */
    function createItemsListing(
        address nftAddress,
        uint256[] memory tokenId,
        uint256[] memory amount,
        uint256[] memory price,
        address currencyAddress
    ) external validNFTContractAddress(nftAddress) {
        address seller = msg.sender;
        require(
            seller != address(0) && seller != address(this),
            "Marketplace: Seller invalid address"
        );
        require(
            tokenId.length == amount.length && price.length == amount.length,
            "Marketplace: token, amount or price not match"
        );
        require(
            whitelistCurrencies[currencyAddress],
            "Marketplace: INVALID_CURRENCY"
        );
        require(
            whitelistNFTContracts[nftAddress],
            "Marketplace: INVALID_NFT_CONTRACT"
        );

        IERC1155Upgradeable nftContract = getNftItemContract(nftAddress);

        for (uint256 i = 0; i < tokenId.length; i++) {
            require(amount[i] > 0, "Marketplace: item amount invalid");
            uint256 balances = nftContract.balanceOf(seller, tokenId[i]);
            require(
                balances >= amount[i],
                "Marketplace: item balance insufficient"
            );
        }

        nftContract.safeBatchTransferFrom(
            seller,
            address(this),
            tokenId,
            amount,
            "0x"
        );

        for (uint256 i = 0; i < tokenId.length; i++) {
            ItemListing memory listing = ItemListing(
                price[i],
                seller,
                tokenId[i],
                amount[i]
            );
            listingId = listingId.add(1);
            itemListings[nftAddress][listingId] = listing;
            emit ItemListingCreated(
                seller,
                nftAddress,
                tokenId[i],
                amount[i],
                price[i],
                listingId
            );
        }
    }

    /**
     * @dev remove listing item in game
     * @param nftAddress: address of NFT contract
     * @param _listingId: id of listing
     */
    function cancelItemsListing(address nftAddress, uint256 _listingId)
        external
        onlyItemSeller(nftAddress, _listingId)
    {
        address seller = msg.sender;
        require(
            seller != address(0) && seller != address(this),
            "Marketplace: Seller invalid"
        );

        IERC1155Upgradeable nft = getNftItemContract(nftAddress);
        ItemListing storage listing = itemListings[nftAddress][_listingId];
        require(listing.owner == seller, "Marketplace: caller is not owner");
        nft.safeTransferFrom(
            address(this),
            listing.owner,
            listing.tokenId,
            listing.amount,
            "0x"
        );
        delete itemListings[nftAddress][_listingId];
        emit ItemUnlisted(_listingId);
    }

    /**
     * @dev update listing price
     * @param nftAddress: address of NFT contract
     * @param _listingId: id of listing
     * @param _price: new price
     */
    function updateItemsListing(
        address nftAddress,
        uint256 _listingId,
        uint256 _price
    ) external onlyItemSeller(nftAddress, _listingId) {
        itemListings[nftAddress][_listingId].price = _price;
        emit ItemListingUpdated(_listingId, _price);
    }

    /**
     * @dev make buy item transaction
     * @param nftAddress: address of NFT contract
     * @param _listingId: id of listing
     */
    function buyItems(address nftAddress, uint256 _listingId)
        external
        payable
        nonReentrant
    {
        ItemListing storage listing = itemListings[nftAddress][_listingId];
        require(listing.tokenId > 0, "Marketplace: listing not existed");
        require(listing.owner != msg.sender, "Marketplace: caller is owner");
        require(msg.value == listing.price, "P");

        if (serviceSellerFee > 0) {
            payable(treasury).transfer(
                msg.value -
                    (msg.value * (100000 - serviceSellerFee)).div(100000)
            );
        }

        uint256 price = (msg.value * (100000 - serviceSellerFee)).div(100000);
        payable(listing.owner).transfer(price);

        IERC1155Upgradeable nft = getNftItemContract(nftAddress);
        nft.safeTransferFrom(
            address(this),
            msg.sender,
            listing.tokenId,
            listing.amount,
            "0x"
        );

        emit ItemTrade(
            msg.sender,
            listing.owner,
            nftAddress,
            listing.tokenId,
            listing.amount,
            listing.price,
            _listingId
        );
        delete itemListings[nftAddress][_listingId];
    }

    function whitelistNFTContract(address[] calldata _nfts, bool _isAccept)
        external
        onlyOwner
    {
        require(_nfts.length > 0, "HERORES_INVALID");
        for (uint256 i = 0; i < _nfts.length; i++) {
            whitelistNFTContracts[_nfts[i]] = _isAccept;
        }
    }

    function whitelistCurrency(address[] calldata _currencies, bool _isAccept)
        external
        onlyOwner
    {
        require(_currencies.length > 0, "HERORES_INVALID");
        for (uint256 i = 0; i < _currencies.length; i++) {
            whitelistCurrencies[_currencies[i]] = _isAccept;
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes memory
    ) external virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return this.supportsInterface(interfaceId);
    }

    event ListingCreated(
        address indexed owner,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    event Unlisted(address indexed nftAddress, uint256 indexed tokenId);
    event ListingUpdated(uint256 indexed tokenId, uint256 price);
    event Trade(
        address indexed buyer,
        address indexed seller,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 price
    );
    event serviceSellerFeeUpdated(uint256 serviceSellerFee);
    event ItemListingCreated(
        address indexed owner,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 _listingId
    );
    event ItemUnlisted(uint256 indexed _listingId);
    event ItemListingUpdated(uint256 indexed _listingId, uint256 price);
    event ItemTrade(
        address indexed buyer,
        address indexed seller,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 _listingId
    );
}
