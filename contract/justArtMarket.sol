// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract JustArtMarket is Ownable, ReentrancyGuard {
    // EVENTS
    event ItemCreated(
        string collection,
        address indexed owner,
        uint itemId,
        uint256 price
    );

    event ItemRemoved(address indexed owner, string itemName, uint itemId);

    event ItemRelisted(
        address indexed owner,
        string itemName,
        uint itemId,
        uint256 price
    );

    event ItemSold(
        address indexed buyer,
        string itemName,
        uint itemId,
        uint256 price
    );

    event NewMarketFee(address owner, uint256 newPercentage);

    // STRUCTS
    enum Type {
        UNAVAILABLE,
        ADD,
        REMOVE,
        BUY
    }

    struct Transaction {
        Type tranType;
        address from;
        uint256 price;
        uint256 createdAt;
    }

    struct Item {
        string name;
        string description;
        string image;
        string location;
        uint256 price;
        address owner;
        bool isItemListed;
        Transaction[] history;
    }

    // VARIABLES
    uint256 private marketFeePercentage;
    uint256 private itemCount;
    mapping(uint => Item) public Items;
    // keeps track of ids that exist
    mapping(uint => bool) public exists;
    // keeps track of the number of items a user owns
    mapping(address => uint) public balance;
    mapping(address => uint[]) public userItems;

    address internal cUsdTokenAddress =
        0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    // METHODS
    constructor() {
        // so the marketFee percentage will be deducted from the selling price of the item
        // currently set to 2%
        marketFeePercentage = 2;
    }

    /// @dev check if item with id _itemId exist
    modifier exist(uint _itemId) {
        require(exists[_itemId], "Query of nonexistent token");
        _;
    }

    modifier checkIfItemOwner(uint _itemId) {
        require(Items[_itemId].owner == msg.sender, "Only item owner");
        _;
    }

    modifier checkPrice(uint _price) {
        require(_price >= 1 ether, "Minimum price must be at least one CUSD");
        _;
    }

    modifier checkIfListed(uint _itemId) {
        require(Items[_itemId].isItemListed, "Item isn't listed");
        _;
    }

    /// @dev allow users to add an item to the marketplace
    function listNewItem(
        string calldata _name,
        string calldata _description,
        string calldata _image,
        string calldata _location,
        uint256 _price
    ) external checkPrice(_price) {
        Item storage _Item = Items[itemCount];
        uint index = itemCount;
        itemCount++;
        _Item.name = _name;
        _Item.description = _description;
        _Item.image = _image;
        _Item.location = _location;
        _Item.price = _price;
        _Item.isItemListed = true;
        _Item.owner = msg.sender;

        //add new transaction history
        newHistory(index, Type.ADD);

        balance[msg.sender]++;
        exists[index] = true;
        userItems[msg.sender].push(index);
        emit ItemCreated(_name, msg.sender, index, _price);
    }

    /// @dev allow users to buy a listed item
    function buyItem(uint _itemId)
        external
        payable
        checkIfListed(_itemId)
        nonReentrant
    {
        Item storage _Item = Items[_itemId];

        // checks if the spending amount has been approved for the smart contract
        require(
            IERC20(cUsdTokenAddress).allowance(msg.sender, address(this)) >=
                _Item.price,
            "Failed to send remaining to item owner"
        );

        // calculate due market fee for item
        uint256 fee = getItemFee(_itemId);
        uint remaining = _Item.price - fee;

        // add item to buyer
        userItems[msg.sender].push(_itemId);
        balance[msg.sender]++;
        balance[_Item.owner]--;
        //unlist Item from market
        _Item.isItemListed = false;

        //set buyer as item owner
        _Item.owner = msg.sender;

        //add new transaction history
        newHistory(_itemId, Type.BUY);
        require(
            IERC20(cUsdTokenAddress).transferFrom(
                msg.sender,
                _Item.owner,
                remaining
            ),
            "Failed to send remaining to item owner"
        );

        require(
            IERC20(cUsdTokenAddress).transferFrom(msg.sender, owner(), fee),
            "Failed to pay market fee to contract owner"
        );

        emit ItemSold(msg.sender, _Item.name, _itemId, _Item.price);
    }

    /// @dev allow users to unlist an item
    function unlistItem(uint _itemId)
        external
        checkIfItemOwner(_itemId)
        checkIfListed(_itemId)
    {
        // get item from storage
        Item storage _Item = Items[_itemId];

        //update location, price and listed parameter
        _Item.isItemListed = false;
        _Item.price = 0;
        //add new transaction history
        newHistory(_itemId, Type.REMOVE);
        emit ItemRemoved(msg.sender, _Item.name, _itemId);
    }

    /// @dev allow users to relist an item
    function relistItem(
        uint _itemId,
        string calldata _newLocation,
        uint256 _price
    ) external exist(_itemId) checkIfItemOwner(_itemId) checkPrice(_price) {
        // get item from storage
        Item storage _Item = Items[_itemId];

        //run checks
        require(!Items[_itemId].isItemListed, "Item already listed");

        //update location, price and listed parameter
        _Item.location = _newLocation;
        _Item.price = _price;
        _Item.isItemListed = true;

        //add new transaction history
        newHistory(_itemId, Type.ADD);

        emit ItemRelisted(msg.sender, _Item.name, _itemId, _Item.price);
    }


    /// @dev allows the contract's owner to change the market fee
    /// @notice fee percentage can't be higher than 10%
    function updateMarketFeePercentage(uint256 newPercentage)
        external
        onlyOwner
    {
        require(newPercentage <= 10, "Fee can't be higher than 10%");
        marketFeePercentage = newPercentage;
        emit NewMarketFee(msg.sender, newPercentage);
    }

    /// @dev push a transaction log onto the history array of an item
    function newHistory(uint _itemId, Type _tranType) internal {
        Item storage _Item = Items[_itemId];
        _Item.history.push(
            Transaction({
                tranType: _tranType,
                from: msg.sender,
                price: _Item.price,
                createdAt: block.timestamp
            })
        );
    }

    // View Methods

    /// @dev returns item from itemID
    function getItemFromID(uint _itemId)
        external
        view
        exist(_itemId)
        returns (Item memory)
    {
        return Items[_itemId];
    }

    /// @dev return item count
    function getItemCounts() external view returns (uint256) {
        return itemCount;
    }

    /// @dev return useritems array
    function getUserItems(address _user) external view returns (Item[] memory) {
        require(_user != address(0), "Invalid address");
        Item[] memory itemsArray = new Item[](balance[_user]);
        uint index = 0;
        for (uint i = 0; i < userItems[_user].length; i++) {
            uint currentId = userItems[_user][i];
            if (Items[currentId].owner == msg.sender) {
                itemsArray[index] = Items[currentId];
                index++;
            }
        }
        return itemsArray;
    }

    /// @dev returns the due market fee for item
    function getItemFee(uint _itemId)
        public
        view
        checkiflisted(_itemId)
        returns (uint)
    {
        // to avoid overflow/underflow issues, price is divided by 100 to get the feeAmount per each percent
        uint256 feePerPecent = Items[_itemId].price / 100;
        return feePerPecent * marketFeePercentage;
    }

    /// @dev returns marketfee percentage
    function getMarketFee() external view returns (uint256) {
        return marketFeePercentage;
    }
}
