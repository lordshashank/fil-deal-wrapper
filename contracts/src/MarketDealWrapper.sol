// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Import Statements
import {MarketAPI} from "lib/filecoin-solidity/contracts/v0.8/MarketAPI.sol";
import {CommonTypes} from "lib/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {MarketTypes} from "lib/filecoin-solidity/contracts/v0.8/types/MarketTypes.sol";
import {AccountTypes} from "lib/filecoin-solidity/contracts/v0.8/types/AccountTypes.sol";
import {AccountCBOR} from "lib/filecoin-solidity/contracts/v0.8/cbor/AccountCbor.sol";
import {MarketCBOR} from "lib/filecoin-solidity/contracts/v0.8/cbor/MarketCbor.sol";
import {BytesCBOR} from "lib/filecoin-solidity/contracts/v0.8/cbor/BytesCbor.sol";
import {BigInts} from "lib/filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {CBOR} from "lib/filecoin-solidity/lib/solidity-cborutils/contracts/CBOR.sol";
import {Misc} from "lib/filecoin-solidity/contracts/v0.8/utils/Misc.sol";
import {FilAddresses} from "lib/filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AccountAPI} from "lib/filecoin-solidity/contracts/v0.8/AccountAPI.sol";
import {FilForwarder} from "./FilForwarder.sol";
import {PythPriceFeed} from "./PythPriceFeed.sol";

// Contracts

/**
 * @title MarketDealWrapper
 * @dev A contract to manage Filecoin deals and automate payments to Storage Providers.
 */
contract MarketDealWrapper is Ownable {
// Events
event DealNotify(
    uint64 dealId,
    bytes commP,
    bytes data,
    bytes chainId,
    bytes provider
);
event ReceivedDataCap(string received);
event AddressWhitelisted(address indexed account);
event AddressRemovedFromWhitelist(address indexed account);
event FundsAdded(address indexed owner, uint256 amount);
event FundsWithdrawn(address indexed owner, uint256 amount);
event SpPaymentCreated(uint64 indexed dealId, uint256 total);
event SpPaymentWithdrawn(
    uint64 indexed dealId,
    address indexed sp,
    uint256 amount
);
event ActorIdWhitelisted(uint64 actorId);
event ActorIdRemovedFromWhitelist(uint64 actorId);
event StorageProviderWhitelisted(uint64 indexed actorId, bytes providerAddr);
event StorageProviderRemovedFromWhitelist(uint64 indexed actorId, bytes providerAddr);
event PriceTierUpdated(uint256 highPrice_perBytePerEpoch, uint256 midPrice_perBytePerEpoch, uint256 lowPrice_perBytePerEpoch);
event PriceThresholdUpdated(uint256 highThreshold, uint256 lowThreshold, uint32 decimals);

// Errors
error UnauthorizedMarketActor();
error UnauthorizedDataCapActor();
error UnauthorizedMethod();
error InvalidSignature();
error UnauthorizedSender();
error InsufficientBalance();
error TransferFailed();
error NoFundsToClaim();
error ContractBalanceTooLow();
error InvalidAsciiByte();
error InvalidAsciiHexLength();
error UnauthorizedProvider();
error InvalidDealState();
error ForwardFailed();

// Libraries
using CBOR for CBOR.CBORBuffer;
    using AccountCBOR for *;
    using MarketCBOR for *;

    // Type Declarations
    struct SpPayment {
        uint256 totalAccrued;     // Total amount accrued to SP across all deals
        uint256 totalWithdrawn;   // Total amount withdrawn by SP
        uint256 nextCalcEpoch;    // Next epoch to calculate payment from
    }

    // Price tier structure for flexible pricing
    struct PriceTier {
        uint256 highTierPrice_perBytePerEpoch;    // Highest price tier (in wei per byte per epoch)
        uint256 midTierPrice_perBytePerEpoch;     // Middle price tier (in wei per byte per epoch)
        uint256 lowTierPrice_perBytePerEpoch;     // Lowest price tier (in wei per byte per epoch)
    }

    // Price threshold structure for flexible price tiers
    struct PriceThreshold {
        uint256 highThreshold;    // High threshold for FIL price (in USD with precision)
        uint256 lowThreshold;     // Low threshold for FIL price (in USD with precision)
        uint32 decimals;           // Decimals for price representation (e.g., -8 for 8 decimal places)
    }

    // Constants used for timing calculations (not for pricing)
    uint256 public constant EPOCHS_PER_DAY = 2880; // 86400 seconds / 30 seconds per epoch
    uint256 public constant FIL_PRICE_MAX_AGE = 600; // 10 minutes (600 seconds)
    uint32 public constant FIL_PRICE_DECIMALS = 18; // 18 decimal places for FIL price

    // State Variables
    uint64 public constant AUTHENTICATE_MESSAGE_METHOD_NUM = 2643134072;
    uint64 public constant DATACAP_RECEIVER_HOOK_METHOD_NUM = 3726118371;
    uint64 public constant MARKET_NOTIFY_DEAL_METHOD_NUM = 4186741094;
    address public constant MARKET_ACTOR_ETH_ADDRESS =
        address(0xff00000000000000000000000000000000000005);
    address public constant DATACAP_ACTOR_ETH_ADDRESS =
        address(0xfF00000000000000000000000000000000000007);


    mapping(uint64 => bool) public isWhitelisted;
    mapping(bytes => bool) public isStorageProviderWhitelisted;  // New SP whitelist using FilAddress bytes
    mapping(bytes => uint64[]) public spToDealIds;  // Using FilAddress bytes
    mapping(address => uint256) public ownerDeposits;
    mapping(bytes => SpPayment) public spPayments;  // SP FilAddress bytes -> payment data

    // Add state variable
    FilForwarder public filForwarder;

    // Pyth integration
    PythPriceFeed public priceFeed;
    uint256 public pythUpdateFee;

    // Price configuration with structs
    PriceTier public priceTier;
    PriceThreshold public priceThreshold;

    // Modifiers
    /**
     * @dev Ensures that only whitelisted addresses can execute certain functions.
     */
    modifier onlyWhitelisted(uint64 _actorId) {
        if (!isWhitelisted[_actorId]) {
            revert UnauthorizedSender();
        }
        _;
    }

    // Functions

    /**
     * @notice Constructor initializes the contract with the deployer as the owner.
     * @dev Inherits Ownable with msg.sender as the owner.
     */
    constructor() Ownable(msg.sender) {
        filForwarder = new FilForwarder();
        priceFeed = new PythPriceFeed();
        pythUpdateFee = 1e16; // 0.01 ETH, adjust as needed for Pyth network fees
        
        // Initialize price tier struct with values already in per byte per epoch
        priceTier = PriceTier({
            highTierPrice_perBytePerEpoch: 21,    // $0.067/TiB/day converted to per byte per epoch
            midTierPrice_perBytePerEpoch: 10,     // $0.033/TiB/day converted to per byte per epoch
            lowTierPrice_perBytePerEpoch: 0       // $0.000/TiB/day
        });
        
        // Initialize price threshold struct
        priceThreshold = PriceThreshold({
            highThreshold: 2000000000,  // $20.00 with 8 decimal precision
            lowThreshold: 800000000,    // $8.00 with 8 decimal precision
            decimals: 8                // 8 decimal places
        });
    }


    /**
     * @notice Adds an actor ID to the whitelist.
     * @param _actorId The actor ID to be whitelisted.
     */
    function addToWhitelist(uint64 _actorId) external onlyOwner {
        isWhitelisted[_actorId] = true;
        emit ActorIdWhitelisted(_actorId);
    }

    /**
     * @notice Removes an actor ID from the whitelist.
     * @param _actorId The actor ID to be removed from the whitelist.
     */
    function removeFromWhitelist(uint64 _actorId) external onlyOwner {
        isWhitelisted[_actorId] = false;
        emit ActorIdRemovedFromWhitelist(_actorId);
    }

    /**
     * @notice Adds a Storage Provider to the whitelist
     * @param actorId The actor ID of the Storage Provider
     */
    function addStorageProvider(uint64 actorId) external onlyOwner {
        CommonTypes.FilAddress memory providerAddr = FilAddresses.fromActorID(actorId);
        isStorageProviderWhitelisted[providerAddr.data] = true;
        emit StorageProviderWhitelisted(actorId, providerAddr.data);
    }

    /**
     * @notice Removes a Storage Provider from the whitelist
     * @param actorId The actor ID of the Storage Provider
     */
    function removeStorageProvider(uint64 actorId) external onlyOwner {
        CommonTypes.FilAddress memory providerAddr = FilAddresses.fromActorID(actorId);
        isStorageProviderWhitelisted[providerAddr.data] = false;
        emit StorageProviderRemovedFromWhitelist(actorId, providerAddr.data);
    }

    /**
     * @notice Check if a Storage Provider is whitelisted
     * @param actorId The actor ID of the Storage Provider
     * @return bool True if the Storage Provider is whitelisted, false otherwise
     */
    function isSpWhitelisted(uint64 actorId) external view returns (bool) {
        CommonTypes.FilAddress memory providerAddr = FilAddresses.fromActorID(actorId);
        return isStorageProviderWhitelisted[providerAddr.data];
    }

    /**
     * @notice Handles the receipt of DataCap.
     * @param _params The parameters associated with the DataCap.
     */
    function receiveDataCap(bytes memory _params) internal {
        require(
            msg.sender == DATACAP_ACTOR_ETH_ADDRESS,
            "msg.sender needs to be datacap actor f07"
        );
        emit ReceivedDataCap("DataCap Received!");
        // Add get datacap balance API and store DataCap amount
    }

    /**
     * @notice Authenticates messages from the Market Actor. 
     * AuthenticateMessage is the callback from the market actor into the contract
     * as part of PublishStorageDeals. This message holds the deal proposal from the
     * miner, which needs to be validated by the contract in accordance with the
     * deal requests made and the contract's own policies
     * @param params The cbor byte array of AccountTypes.AuthenticateMessageParams containing the deal proposal and signature.
     */
    function authenticateMessage(bytes memory params) internal view {
        require(
            msg.sender == MARKET_ACTOR_ETH_ADDRESS,
            "msg.sender needs to be market actor f05"
        );

        AccountTypes.AuthenticateMessageParams memory amp = params
            .deserializeAuthenticateMessageParams();
        MarketTypes.DealProposal memory proposal = MarketCBOR
            .deserializeDealProposal(amp.message);
        uint64 actorId = uint64(asciiBytesToUint(proposal.label.data));

        // Use AccountAPI to authenticate signature
        int256 exitCode = AccountAPI.authenticateMessage(
            CommonTypes.FilActorId.wrap(actorId),
            amp
        );
        if (exitCode != 0) {
            revert InvalidSignature();
        }

        // Check if actorId is whitelisted
        if (!isWhitelisted[actorId]) {
            revert UnauthorizedSender();
        }

        // Check if provider is whitelisted
        if (!isStorageProviderWhitelisted[proposal.provider.data]) {
            revert UnauthorizedProvider();
        }
    }

    /**
     * @notice Handles deal notifications from the Market Actor. 
     * This is the callback from the market actor into the contract at the end
     * of PublishStorageDeals. This message holds the previously approved deal proposal
     * and the associated dealID. The dealID is stored as part of the contract state
     * and the completion of this call marks the success of PublishStorageDeals
     * @param params The cbor byte array of MarketDealNotifyParams containing the deal proposal and deal ID.
     */
    function dealNotify(bytes memory params) internal {
        require(
            msg.sender == MARKET_ACTOR_ETH_ADDRESS,
            "msg.sender needs to be market actor f05"
        );

        MarketTypes.MarketDealNotifyParams memory mdnp = MarketCBOR
            .deserializeMarketDealNotifyParams(params);
        MarketTypes.DealProposal memory proposal = MarketCBOR
            .deserializeDealProposal(mdnp.dealProposal);
        
        // Track deal for the SP
        spToDealIds[proposal.provider.data].push(mdnp.dealId);

        // Initialize or update SP payment tracking
        SpPayment storage spPayment = spPayments[proposal.provider.data];
        uint256 startEpoch = uint256(
            int256(CommonTypes.ChainEpoch.unwrap(proposal.start_epoch))
        );
        
        // If this is the SP's first deal, initialize nextCalcEpoch
        if (spPayment.nextCalcEpoch == 0) {
            spPayment.nextCalcEpoch = startEpoch;
        }

        emit DealNotify(
            mdnp.dealId,
            proposal.piece_cid.data,
            params,
            proposal.label.data,
            proposal.provider.data
        );
    }

    /**
     * @notice Universal entry point for any EVM-based actor method calls.
     * @param method FRC42 method number for the specific method hook.
     * @param _codec An unused codec param defining input format.
     * @param params The CBOR encoded byte array parameters associated with the method call.
     * @return A tuple containing exit code, codec and bytes return data.
     */
    function handle_filecoin_method(
        uint64 method,
        uint64 _codec,
        bytes memory params
    ) public returns (uint32, uint64, bytes memory) {
        bytes memory ret;
        uint64 codec;

        // Dispatch methods
        if (method == AUTHENTICATE_MESSAGE_METHOD_NUM) {
            authenticateMessage(params);
            // Return CBOR true to indicate successful verification
            CBOR.CBORBuffer memory buf = CBOR.create(1);
            buf.writeBool(true);
            ret = buf.data();
            codec = Misc.CBOR_CODEC;
        } else if (method == MARKET_NOTIFY_DEAL_METHOD_NUM) {
            dealNotify(params);
        } else if (method == DATACAP_RECEIVER_HOOK_METHOD_NUM) {
            receiveDataCap(params);
        } else {
            revert UnauthorizedMethod();
        }

        return (0, codec, ret);
    }

    /**
     * @notice Adds native funds to the contract.
     * @dev Only the owner can add funds.
     */
    function addFunds() external payable onlyOwner {
        ownerDeposits[msg.sender] += msg.value;
        emit FundsAdded(msg.sender, msg.value);
    }

    /**
     * @notice Withdraws native funds from the contract.
     * @param amount The amount to withdraw.
     * @dev Only the owner can withdraw funds.
     */
    function withdrawFunds(uint256 amount) external onlyOwner {
        if (ownerDeposits[msg.sender] < amount) {
            revert InsufficientBalance();
        }
        ownerDeposits[msg.sender] -= amount;
        (bool sent, ) = msg.sender.call{value: amount}("");
        if (!sent) {
            revert TransferFailed();
        }
        emit FundsWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Set the Pyth update fee for price feed updates
     * @param _fee The new fee in wei
     */
    function setPythUpdateFee(uint256 _fee) external onlyOwner {
        pythUpdateFee = _fee;
    }

    /**
     * @notice Updates the price tier configuration
     * @param _highTierPrice_perBytePerEpoch The highest price tier (per byte per epoch)
     * @param _midTierPrice_perBytePerEpoch The middle price tier (per byte per epoch)
     * @param _lowTierPrice_perBytePerEpoch The lowest price tier (per byte per epoch)
     */
    function updatePriceTier(
        uint256 _highTierPrice_perBytePerEpoch,
        uint256 _midTierPrice_perBytePerEpoch,
        uint256 _lowTierPrice_perBytePerEpoch
    ) external onlyOwner {
        priceTier.highTierPrice_perBytePerEpoch = _highTierPrice_perBytePerEpoch;
        priceTier.midTierPrice_perBytePerEpoch = _midTierPrice_perBytePerEpoch;
        priceTier.lowTierPrice_perBytePerEpoch = _lowTierPrice_perBytePerEpoch;
        
        emit PriceTierUpdated(
            _highTierPrice_perBytePerEpoch,
            _midTierPrice_perBytePerEpoch,
            _lowTierPrice_perBytePerEpoch
        );
    }

    /**
     * @notice Updates the price threshold configuration
     * @param _highThreshold The high threshold for FIL price (in USD with precision)
     * @param _lowThreshold The low threshold for FIL price (in USD with precision)
     * @param _decimals The decimals for price representation
     */
    function updatePriceThreshold(
        uint256 _highThreshold,
        uint256 _lowThreshold,
        uint32 _decimals
    ) external onlyOwner {
        require(_highThreshold > _lowThreshold, "High threshold must be greater than low threshold");
        
        priceThreshold.highThreshold = _highThreshold;
        priceThreshold.lowThreshold = _lowThreshold;
        priceThreshold.decimals = _decimals;
        
        emit PriceThresholdUpdated(
            _highThreshold,
            _lowThreshold,
            _decimals
        );
    }

    /**
     * @notice Calculate price per byte per epoch based on FIL price
     * @param filPrice The FIL price in USD with priceThreshold.decimals decimals
     * @return Price per byte per epoch in wei
     */
    function calculatePricePerBytePerEpoch(uint256 filPrice) public view returns (uint256) {
        if (filPrice < priceThreshold.lowThreshold) {
            // Price < low threshold: highest tier price
            return priceTier.highTierPrice_perBytePerEpoch;
        } else if (filPrice <= priceThreshold.highThreshold) {
            // low threshold <= Price <= high threshold: mid tier price
            return priceTier.midTierPrice_perBytePerEpoch;
        } else {
            // Price > high threshold: lowest tier price
            return priceTier.lowTierPrice_perBytePerEpoch;
        }
    }

    /**
     * @notice Get FIL price from Pyth oracle
     * @param updateData The Pyth price update data
     * @param publishTime The publish time for price data
     * @return The FIL price in USD (with priceThreshold.decimals precision)
     */
    function getFilPrice(bytes[] calldata updateData, uint64 publishTime) public payable returns (uint256) {
        return priceFeed.getPrice{value: pythUpdateFee}(updateData, publishTime, priceThreshold.decimals);
    }

    /**
     * @notice Allows the Storage Provider to withdraw all pending funds using the new structure
     * @param actorId The actor ID of the Storage Provider
     */
    function withdrawSpFundsByProvider(uint64 actorId) external {
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(actorId);
        
        // Get the SP's payment data
        SpPayment storage spPayment = spPayments[filAddr.data];
        
        // Calculate claimable amount in USD already with proper precision
        uint256 claimableUSD = spPayment.totalAccrued - spPayment.totalWithdrawn;
        
        if (claimableUSD == 0) {
            revert NoFundsToClaim();
        }

        // Get FIL/USD price using the defined constants
        uint256 filPriceInUSD = priceFeed.getPriceNotOlderThan(FIL_PRICE_MAX_AGE, FIL_PRICE_DECIMALS);
        require(filPriceInUSD > 0, "Invalid FIL price");
        
        // Convert USD to FIL: claimableFIL = claimableUSD / filPriceInUSD
        // Both values use exponent 18, so the result is in FIL with 18 decimals
        uint256 claimableFIL = claimableUSD / filPriceInUSD;

        if (address(this).balance < claimableFIL) {
            revert ContractBalanceTooLow();
        }

        // Update withdrawal amount
        spPayment.totalWithdrawn += claimableUSD;
        
        // Forward payment to SP in FIL
        filForwarder.forward{value: claimableFIL}(filAddr.data);
        
        emit SpPaymentWithdrawn(0, msg.sender, claimableFIL);
    }

    /**
     * @notice Updates the accrued payment for a Storage Provider
     * @param actorId The actor ID of the Storage Provider
     * @param updateData The Pyth price update data for all epochs obtained from getPublishTimes()
     * @param publishTimes The publish times for each price updates
     * @param updateTillEpoch The epoch until which to update payments (0 means current epoch)
     * @return The total accrued payment for the Storage Provider
     */
    function updateSpAccruedPayment(
        uint64 actorId,
        bytes[] calldata updateData,
        uint64[] calldata publishTimes,
        uint256 updateTillEpoch
    ) public payable returns (uint256) {
        // Convert actorId to FilAddress
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(actorId);
        bytes memory providerAddr = filAddr.data;
        
        // Get SP payment data
        SpPayment storage spPayment = spPayments[providerAddr];
        
        // Initial validations
        if (spPayment.nextCalcEpoch == 0) {
            return 0;
        }
        
        uint256 effectiveUpdateTillEpoch = updateTillEpoch == 0 ? getCurrentEpoch() : updateTillEpoch;
        require(effectiveUpdateTillEpoch <= getCurrentEpoch(), "updateTillEpoch must be in the past");
        
        if (effectiveUpdateTillEpoch < spPayment.nextCalcEpoch) {
            return 0;
        }
        
        // Calculate days
        uint256 startDay = spPayment.nextCalcEpoch / EPOCHS_PER_DAY;
        uint256 endDay = effectiveUpdateTillEpoch / EPOCHS_PER_DAY;
        
        // Validate inputs
        require(publishTimes.length == endDay - startDay + 1, "Incorrect number of publish times");
        require(updateData.length > 0, "Update data required");
        
        // Process payment calculations
        uint256 totalAccrued = processPaymentsByDay(
            providerAddr,
            startDay,
            endDay,
            spPayment.nextCalcEpoch,
            effectiveUpdateTillEpoch,
            updateData,
            publishTimes
        );
        
        // Update state
        spPayment.totalAccrued += totalAccrued;
        spPayment.nextCalcEpoch = effectiveUpdateTillEpoch + 1;
        
        return totalAccrued;
    }

    // Helper function to process payments day by day
    function processPaymentsByDay(
        bytes memory providerAddr,
        uint256 startDay,
        uint256 endDay,
        uint256 startEpoch,
        uint256 endEpoch,
        bytes[] calldata updateData,
        uint64[] calldata publishTimes
    ) private returns (uint256) {
        uint256 totalAccrued = 0;
        uint64[] memory dealIds = spToDealIds[providerAddr];
        
        // Process each day
        for (uint256 dayIndex = 0; dayIndex <= endDay - startDay; dayIndex++) {
            totalAccrued += calculateDailyPayment(
                dealIds,
                startDay,
                endDay,
                dayIndex,
                startEpoch,
                endEpoch,
                updateData[dayIndex],
                publishTimes[dayIndex]
            );
        }
        
        return totalAccrued;
    }

    // Calculate payment for a single day
    function calculateDailyPayment(
        uint64[] memory dealIds,
        uint256 startDay,
        uint256 endDay,
        uint256 dayIndex,
        uint256 startEpoch,
        uint256 endEpoch,
        bytes calldata priceUpdateData,
        uint64 publishTime
    ) private returns (uint256) {
        uint256 currentDay = startDay + dayIndex;
        uint256 dayStartEpoch = currentDay * EPOCHS_PER_DAY;
        uint256 dayEndEpoch = dayStartEpoch + EPOCHS_PER_DAY - 1;
        
        // Adjust boundaries
        uint256 effectiveStartEpoch = (currentDay == startDay) ? startEpoch : dayStartEpoch;
        uint256 effectiveEndEpoch = (currentDay == endDay) ? endEpoch : dayEndEpoch;
        
        // Skip if no epochs in this day
        if (effectiveEndEpoch < effectiveStartEpoch) {
            return 0;
        }
        
        // Create array for price update and get price
        bytes[] memory updateDataArray = new bytes[](1);
        updateDataArray[0] = priceUpdateData;
        uint256 filPrice = priceFeed.getPrice{value: pythUpdateFee}(updateDataArray, publishTime, priceThreshold.decimals);
        uint256 pricePerBytePerEpoch = calculatePricePerBytePerEpoch(filPrice);
        
        // Calculate total size from active deals
        uint256 totalPieceSize = getTotalPieceSizeForDay(dealIds, effectiveStartEpoch, effectiveEndEpoch);
        
        if (totalPieceSize == 0) {
            return 0;
        }
        
        // Calculate payment
        uint256 epochsInDay = effectiveEndEpoch - effectiveStartEpoch + 1;
        return pricePerBytePerEpoch * totalPieceSize * epochsInDay;
    }

    // Get total piece size from active deals for a day
    function getTotalPieceSizeForDay(
        uint64[] memory dealIds,
        uint256 effectiveStartEpoch,
        uint256 effectiveEndEpoch
    ) private view returns (uint256) {
        uint256 totalPieceSize = 0;
        
        for (uint256 i = 0; i < dealIds.length; i++) {
            uint64 dealId = dealIds[i];
            
            // Check deal activation
            (int256 exitCode, MarketTypes.GetDealActivationReturn memory activation) = 
                MarketAPI.getDealActivation(dealId);
            
            // Skip terminated deals
            if (exitCode != 0 || (
                CommonTypes.ChainEpoch.unwrap(activation.terminated) != 0 && 
                uint256(int256(CommonTypes.ChainEpoch.unwrap(activation.terminated))) < effectiveStartEpoch
            )) {
                continue;
            }
            
            // Get deal data
            (, MarketTypes.GetDealDataCommitmentReturn memory dealData) = 
                MarketAPI.getDealDataCommitment(dealId);
            
            // Get deal terms
            (, MarketTypes.GetDealTermReturn memory dealTerm) = 
                MarketAPI.getDealTerm(dealId);
            
            // Calculate deal epochs
            uint256 dealStartEpoch = uint256(int256(CommonTypes.ChainEpoch.unwrap(dealTerm.start)));
            uint256 dealEndEpoch = dealStartEpoch + uint256(int256(CommonTypes.ChainEpoch.unwrap(dealTerm.duration)));
            
            // Apply termination if applicable
            if (CommonTypes.ChainEpoch.unwrap(activation.terminated) != 0) {
                dealEndEpoch = uint256(int256(CommonTypes.ChainEpoch.unwrap(activation.terminated)));
            }
            
            // Check if deal is active in this period
            if (dealStartEpoch > effectiveEndEpoch || dealEndEpoch < effectiveStartEpoch) {
                continue;
            }
            
            // Add piece size
            // This means we are paying for whole day even if deal is active only for part of it
            totalPieceSize += uint256(dealData.size);
        }
        
        return totalPieceSize;
    }

    /**
     * @notice Retrieves the current blockchain epoch.
     * @return The current epoch number.
     */
    function getCurrentEpoch() public view returns (uint256) {
        return block.number;
    }

    /**
     * @notice Retrieves deal IDs associated with a given miner ID.
     * @param minerId The miner ID.
     * @return An array of deal IDs associated with the miner.
     */
    function getDealsFromMinerId(
        uint64 minerId
    ) public view returns (uint64[] memory) {
        // Get FilAddress from minerId
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(
            minerId
        );

        // Retrieve deal IDs from spToDealIds using filAddr.data
        return spToDealIds[filAddr.data];
    }

    /**
     * @notice Retrieves the total claimable native funds for a Storage Provider across all their deals.
     * @param actorId The actor ID of the Storage Provider.
     * @return The total claimable funds.
     */
    function getSpFunds(uint64 actorId) public view returns (uint256) {
        // Get FilAddress from actorId
        CommonTypes.FilAddress memory filAddr = FilAddresses.fromActorID(actorId);
        bytes memory providerAddr = filAddr.data;
        // Retrieve payment data for the Storage Provider
        SpPayment storage spPayment = spPayments[providerAddr];
        // Calculate the total claimable amount
        uint256 totalClaimable = spPayment.totalAccrued - spPayment.totalWithdrawn;

        return totalClaimable;
    }


    /**
     * @notice Converts an address to its hexadecimal string representation.
     * @param _addr The address to convert.
     * @return The hexadecimal string representation of the address.
     */
    function addressToHexString(
        address _addr
    ) internal pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(_addr)), 20);
    }

    /**
     * @notice Converts ASCII bytes to a uint256.
     * @param asciiBytes The ASCII bytes to convert.
     * @return The resulting uint256.
     */
    function asciiBytesToUint(
        bytes memory asciiBytes
    ) public pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < asciiBytes.length; i++) {
            uint256 digit = uint256(uint8(asciiBytes[i])) - 48; // Convert ASCII to digit
            if (digit > 9) {
                revert InvalidAsciiByte();
            }
            result = result * 10 + digit;
        }
        return result;
    }

    /**
     * @notice Converts ASCII hexadecimal bytes to bytes.
     * @param asciiHex The ASCII hexadecimal bytes to convert.
     * @return The resulting bytes.
     */
    function convertAsciiHexToBytes(
        bytes memory asciiHex
    ) public pure returns (bytes memory) {
        if (asciiHex.length % 2 != 0) {
            revert InvalidAsciiHexLength();
        }

        bytes memory result = new bytes(asciiHex.length / 2);
        for (uint256 i = 0; i < asciiHex.length / 2; i++) {
            result[i] = byteFromHexChar(asciiHex[2 * i], asciiHex[2 * i + 1]);
        }

        return result;
    }

    /**
     * @notice Converts two hexadecimal characters to a single byte.
     * @param char1 The first hexadecimal character.
     * @param char2 The second hexadecimal character.
     * @return The resulting byte.
     */
    function byteFromHexChar(
        bytes1 char1,
        bytes1 char2
    ) internal pure returns (bytes1) {
        uint8 nibble1 = uint8(char1) - (uint8(char1) < 58 ? 48 : 87);
        uint8 nibble2 = uint8(char2) - (uint8(char2) < 58 ? 48 : 87);
        return bytes1(nibble1 * 16 + nibble2);
    }

    /**
     * @notice Recovers the signer address from a hash and signature.
     * @dev Could be replaced by openzeppelin ECDSA library.
     * @param hash The hash that was signed.
     * @param signature The signature bytes.
     * @return The recovered address.
     */
    function recovers(
        bytes32 hash,
        bytes memory signature
    ) public pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        // Check the signature length
        if (signature.length != 65) {
            return address(0);
        }

        // Divide the signature into r, s, and v variables
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Adjust the version of the signature
        if (v < 27) {
            v += 27;
        }

        // Return address(0) if the version is incorrect
        if (v != 27 && v != 28) {
            return address(0);
        } else {
            return ecrecover(hash, v, r, s);
        }
    }


    /**
     * @notice Calculate the necessary publish times for price updates 
     * @param providerAddr The FilAddress bytes of the Storage Provider
     * @param updateTillEpoch The epoch until which to update (current epoch if 0)
     * @return Array of UTC timestamps (in seconds) for which price updates are needed
     */
    function GetPublishTimes(
        bytes memory providerAddr,
        uint256 updateTillEpoch
    ) public view returns (uint64[] memory) {
        SpPayment storage spPayment = spPayments[providerAddr];
        
        // If no payment info or nextCalcEpoch is 0, return empty array
        if (spPayment.nextCalcEpoch == 0) {
            return new uint64[](0);
        }
        
        // If updateTillEpoch is 0, use current epoch
        if (updateTillEpoch == 0) {
            updateTillEpoch = getCurrentEpoch();
        }
        
        // Calculate how many days we need to cover
        uint256 startDay = spPayment.nextCalcEpoch / EPOCHS_PER_DAY;
        uint256 endDay = updateTillEpoch / EPOCHS_PER_DAY;
        
        // If endDay is before startDay, return empty array
        if (endDay < startDay) {
            return new uint64[](0);
        }
        
        // Number of publish times is the number of days
        uint256 numPublishTimes = endDay - startDay + 1;
        uint64[] memory publishTimes = new uint64[](numPublishTimes);
        
        // Set publish time for each day at noon UTC (timestamp is in seconds)
        for (uint256 i = 0; i < numPublishTimes; i++) {
            // Convert filecoin epoch to timestamp
            // Assuming each epoch is 30 seconds
            uint256 dayStartEpoch = (startDay + i) * EPOCHS_PER_DAY;

            // Convert to timestamp (epoch number * 30 seconds)
            publishTimes[i] = uint64(dayStartEpoch * 30);
        }
        
        return publishTimes;
    }

    /**
     * @notice Fallback function to receive Ether.
     */
    receive() external payable {}

    /**
     * @notice Fallback function.
     */
    fallback() external payable {}

    // functions for testing
    /**
     * @notice Set the payment data for a Storage Provider
     * @param providerAddr The FilAddress bytes of the Storage Provider
     * @param totalAccrued The total amount accrued to the Storage Provider
     * @param totalWithdrawn The total amount withdrawn by the Storage Provider
     * @param nextCalcEpoch The next epoch to calculate payment from
     */
    function setSpayment(
        bytes memory providerAddr,
        uint256 totalAccrued,
        uint256 totalWithdrawn,
        uint256 nextCalcEpoch
    ) external onlyOwner {
        SpPayment storage spPayment = spPayments[providerAddr];
        spPayment.totalAccrued = totalAccrued;
        spPayment.totalWithdrawn = totalWithdrawn;
        spPayment.nextCalcEpoch = nextCalcEpoch;
    }

    function setSpDealIds(
        bytes memory providerAddr,
        uint64[] memory dealIds
    ) external onlyOwner {
        spToDealIds[providerAddr] = dealIds;
    }
}