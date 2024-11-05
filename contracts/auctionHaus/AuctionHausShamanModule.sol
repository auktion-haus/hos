// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import { INounsAuctionHouseV2 } from "../libs/INounsAuctionHouseV2.sol";
import { INounsDelegator } from "../libs/INounsDelegator.sol";

import { ManagerShaman } from "../shaman/ManagerShaman.sol";
import { IShaman } from "../shaman/interfaces/IShaman.sol";
import { ZodiacModuleShaman } from "../shaman/ZodiacModuleShaman.sol";
import { IAuctionHausShaman } from "./IAuctionHausShaman.sol";

// import "hardhat/console.sol";

// @notice Provided end time is invalid
error AuctionHausShamanModule__InvalidEndTime();

// @notice invalid captain
error AuctionHausShamanModule__InvalidCaptain();

// @notice Function should be called only by the Baal vault
error AuctionHausShamanModule__BaalVaultOnly();

// @notice MultiSend execution failed
error AuctionHausShamanModule__ExecutionFailed(bytes returnData);

// @notice Insufficient balance
error AuctionHausShamanModule__InsufficientBalance();

// @notice Auction has already been settled
error AuctionHausShamanModule__AuctionAlreadySettled();

// @notice Auction has completed
error AuctionHausShamanModule__AuctionCompleted();

// @notice Current bidder is the Baal target
error AuctionHausShamanModule__CurrentBidder();

// @notice Max bid amount is over the limit
error AuctionHausShamanModule__MaxOverBid();

/**
 * @title A Shaman Role to interact with Nouns DAO Auction House. Elected Captain can execute auctions
 * and receivce a reward for their service.
 * @author DAOHaus
 * @notice It uses Yeeter for token pre-sales and AuctionHaus for token auctions
 * @dev In order to operate the contract should have Baal Admin privileges as well as being added as
 * a Safe module to the Baal/Yeeter vault.
 */
contract AuctionHausShamanModule is IAuctionHausShaman, ZodiacModuleShaman, ManagerShaman {
    address public captain;
    uint256 public captainsReward;
    uint192 public captainMaxBid;

    uint256 public lastBidAmount;
    uint96 public lastBidTokenId;

    /// @notice endTime whn campaign expires
    uint256 public endTime;

    INounsAuctionHouseV2 public auctionHouseContract;

    /// @notice emitted when the contract is initialized
    /// @param baal baal address
    /// @param vault baal vault address
    /// @param endTime campaign end timestamp in seconds
    /// @param captain delegated bidder
    /// @param captainsReward captain reward
    /// @param captainMaxBid captain max bid
    /// @param auctionHouseAddress auction house address
    event Setup(
        address indexed baal,
        address indexed vault,
        uint256 endTime,
        address captain,
        uint256 captainsReward,
        uint192 captainMaxBid,
        address auctionHouseAddress
    );

    /// @notice emitted when a token is successfully launched
    /// @param tokenId token address
    /// @param ethSupply ETH liquidity amount
    event Executed(uint96 indexed tokenId, uint256 ethSupply);

    /// @notice A modifier for methods that require to be called by the Baal vault
    modifier baalVaultOnly() {
        if (_msgSender() != vault()) revert AuctionHausShamanModule__BaalVaultOnly();
        _;
    }

    /// @notice A modifier for methods that require to be called by the captain
    modifier captainOnly() {
        if (_msgSender() != captain) revert AuctionHausShamanModule__InvalidCaptain();
        _;
    }

    /**
     * @notice Initializer function
     * @param _baal baal address
     * @param _vault bal vault address
     * @param _endTime campaign end timestamp is seconds
     * @param _captain delegated bidder
     * @param _captainsReward captain reward
     * @param _captainMaxBid captain max bid
     * @param _auctionHouse auction house address
     */
    function __AuctionHausShamanModule__init(
        address _baal,
        address _vault,
        uint256 _endTime,
        address _captain,
        uint256 _captainsReward,
        uint192 _captainMaxBid,
        address _auctionHouse
    ) internal onlyInitializing {
        __ZodiacModuleShaman__init("AuctionHausShamanModule", _baal, _vault);
        __ManagerShaman_init_unchained();
        __AuctionHausShamanModule__init_unchained(_endTime, _captain, _captainsReward, _captainMaxBid, _auctionHouse);
    }

    /**
     * @notice Local initializer function
     * @param _endTime campaign end timestamp is seconds
     * @param _captain delegated bidder
     * @param _captainsReward captain reward
     * @param _captainMaxBid captain max bid
     * @param _auctionHouse auction house address
     */
    function __AuctionHausShamanModule__init_unchained(
        uint256 _endTime,
        address _captain,
        uint256 _captainsReward,
        uint192 _captainMaxBid,
        address _auctionHouse
    ) internal onlyInitializing {
        if (_endTime <= block.timestamp) revert AuctionHausShamanModule__InvalidEndTime();
        endTime = _endTime;
        captain = _captain;
        captainsReward = _captainsReward;
        captainMaxBid = _captainMaxBid;
        auctionHouseContract = INounsAuctionHouseV2(_auctionHouse);
    }

    /**
     * @notice Main initializer function to setup the shaman config
     * @inheritdoc IShaman
     */
    function setup(address _baal, address _vault, bytes memory _initializeParams) public override(IShaman) initializer {
        (
            uint256 _expiration,
            address _captain,
            uint256 _captainsReward,
            uint192 _captainMaxBid,
            address _auctionHouse
        ) = abi.decode(_initializeParams, (uint256, address, uint256, uint192, address));
        __AuctionHausShamanModule__init(
            _baal,
            _vault,
            _expiration,
            _captain,
            _captainsReward,
            _captainMaxBid,
            _auctionHouse
        );
        emit Setup(_baal, _vault, _expiration, _captain, _captainsReward, _captainMaxBid, _auctionHouse);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ZodiacModuleShaman, ManagerShaman) returns (bool) {
        return interfaceId == type(IAuctionHausShaman).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice proposal helper delegates votes to vault
     */
    function resetDelegation() public baalVaultOnly {
        delegateVotesToVault();
    }

    /**
     * @notice sets a new captain
     * @param _captain new captain address
     */
    function setCaptain(address _captain) public baalVaultOnly {
        captain = _captain;
    }

    /**
     * @notice sets a new captain
     * @param _captainMaxBid new captain address
     */
    function setCaptainMaxBid(uint192 _captainMaxBid) public baalVaultOnly {
        captainMaxBid = _captainMaxBid;
    }

    /**
     * @notice sets a new captains reward
     * @param _captainsReward new captains reward
     */
    function setCaptainsReward(uint256 _captainsReward) public baalVaultOnly isBaalManager {
        captainsReward = _captainsReward;
    }

    /**
     * @notice renounces captainship
     */
    function renounceCaptain() public captainOnly {
        captain = address(0);
        delegateVotesToVault();
    }

    /**
     * @notice delegates votes to a given address
     * @param delegatee address to delegate votes to
     */
    function delegateVotes(address delegatee) public isModuleEnabled captainOnly {
        address nounsAddress = auctionHouseContract.nouns();
        INounsDelegator delegator = INounsDelegator(nounsAddress);

        bytes memory delegateCalldata = abi.encodeCall(delegator.delegate, (delegatee));
        (bool success, bytes memory returnData) = execAndReturnData(
            nounsAddress,
            0,
            delegateCalldata,
            Enum.Operation.Call
        );

        if (!success) revert AuctionHausShamanModule__ExecutionFailed(returnData);
    }

    /**
     * @notice delegates votes to vault
     */
    function delegateVotesToVault() internal {
        address nounsAddress = auctionHouseContract.nouns();
        INounsDelegator delegator = INounsDelegator(nounsAddress);

        bytes memory delegateCalldata = abi.encodeCall(delegator.delegate, (vault()));
        (bool success, bytes memory returnData) = execAndReturnData(
            nounsAddress,
            0,
            delegateCalldata,
            Enum.Operation.Call
        );

        if (!success) revert AuctionHausShamanModule__ExecutionFailed(returnData);
    }

    /**
     * @notice Executes the auction bid
     * @inheritdoc IAuctionHausShaman
     * @dev The function can be called only by the captain
     * @dev TODO: rename to executeAuctionBid
     */
    function execute(uint192 maxBid) public nonReentrant isModuleEnabled isBaalManager captainOnly {
        uint256 yeethBalance = vault().balance;

        if (block.timestamp >= endTime) {
            revert AuctionHausShamanModule__InvalidEndTime();
        }

        INounsAuctionHouseV2.AuctionV2View memory currentAuction = auctionHouseContract.auction();

        uint96 tokenId = currentAuction.nounId;

        uint192 amount = maxBid <= captainMaxBid ? maxBid : nextBidAmount(currentAuction);

        if (amount > maxBid) {
            revert AuctionHausShamanModule__MaxOverBid();
        }
        if (yeethBalance < amount) {
            revert AuctionHausShamanModule__InsufficientBalance();
        }
        if (currentAuction.bidder == _baal.target()) {
            revert AuctionHausShamanModule__CurrentBidder();
        }
        if (currentAuction.settled) {
            revert AuctionHausShamanModule__AuctionAlreadySettled();
        }
        if (block.timestamp >= currentAuction.endTime) {
            revert AuctionHausShamanModule__AuctionCompleted();
        }

        // is client id (8441) an arbitrary referrer code? 8441/BAAL
        bytes memory bidCalldata = abi.encodeCall(auctionHouseContract.createBid, (tokenId, 8441));
        // bytes memory bidCalldata = abi.encodeCall(auctionHouseContract.createBid, (tokenId));

        (bool success, bytes memory returnData) = execAndReturnData(
            address(auctionHouseContract),
            amount,
            bidCalldata,
            Enum.Operation.Call
        );

        if (!success) revert AuctionHausShamanModule__ExecutionFailed(returnData);

        lastBidAmount = amount;
        lastBidTokenId = tokenId;

        if (captainsReward > 0) {
            address[] memory receivers = new address[](1);
            receivers[0] = captain;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = captainsReward;
            _baal.mintShares(receivers, amounts);
        }

        emit Executed(tokenId, lastBidAmount);
    }

    function nextBidAmount(INounsAuctionHouseV2.AuctionV2View memory currentAuction) public view returns (uint192) {
        // INounsAuctionHouseV2.AuctionV2View memory currentAuction = auctionHouseContract.auction();
        uint192 minBidIncrementPercentage = auctionHouseContract.minBidIncrementPercentage();
        uint192 reservePrice = auctionHouseContract.reservePrice();

        uint192 amount = currentAuction.amount < reservePrice
            ? reservePrice
            : currentAuction.amount + ((currentAuction.amount * minBidIncrementPercentage) / 100);

        return amount;
    }

    function auctionHouse() public view returns (address) {
        return address(auctionHouseContract);
    }
}
