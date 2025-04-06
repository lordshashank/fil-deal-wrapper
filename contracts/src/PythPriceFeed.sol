// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract PythPriceFeed {
    // Constants
    address public constant PYTH_ADDRESS = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;
    bytes32 public constant FIL_USD_PRICE_ID = 0x150ac9b959aee0051e4091f0ef5216d941f590e1c5e7f91cf7635b5c11628c0e;
    uint64 public constant PRICE_WINDOW = 100; // 100 second window
    
    IPyth public immutable pyth;
    
    constructor() {
        pyth = IPyth(PYTH_ADDRESS);
    }

    function getPrice(
        bytes[] calldata updateData,
        uint64 publishTime,
        uint32 exponent
    ) external payable returns (uint256) {
        bytes32[] memory priceIds = new bytes32[](1);
        priceIds[0] = FIL_USD_PRICE_ID;
        
        // Get price feeds with 100 second window
        PythStructs.PriceFeed[] memory priceFeeds = pyth.parsePriceFeedUpdates{value: msg.value}(
            updateData,
            priceIds,
            publishTime,
            publishTime + PRICE_WINDOW
        );
        
        // Get price from the first (and only) price feed
        PythStructs.Price memory priceData = priceFeeds[0].price;
        
        // Convert price to positive value
        uint256 basePrice = uint256(uint64(priceData.price < 0 ? -priceData.price : priceData.price));
        int32 absExpo;
        if (priceData.expo < 0) {
            // absExpo = -expo
            absExpo = -priceData.expo;
            // Calculate the final price
            if (int32(exponent) < absExpo) {
                // If exponent is less than absExpo, we need to divide
                int256 diff = int256(absExpo) - int256(int32(exponent));
                uint256 finalPrice = basePrice / (10 ** uint256(diff));
                return finalPrice;
            } else {
                // If exponent is greater than or equal to absExpo, we need to multiply
                int256 diff = int256(int32(exponent)) - int256(absExpo);
                uint256 finalPrice = basePrice * (10 ** uint256(diff));
                return finalPrice;
            }
        } else {
            // absExpo = expo
            absExpo = priceData.expo;
            // Calculate the final price
            uint256 finalExp = uint256(int256(int32(absExpo) + int32(exponent)));
            return basePrice * (10 ** finalExp);
        }
    }

    function getPriceNotOlderThan(uint256 age, uint32 exponent) external view returns (uint256) {
        PythStructs.Price memory priceData = pyth.getPriceNoOlderThan(FIL_USD_PRICE_ID, age);
        uint256 basePrice = uint256(uint64(priceData.price < 0 ? -priceData.price : priceData.price));
        int32 absExpo;
        if (priceData.expo < 0) {
            // absExpo = -expo
            absExpo = -priceData.expo;
            // Calculate the final price
            if (int32(exponent) < absExpo) {
                // If exponent is less than absExpo, we need to divide
                int256 diff = int256(absExpo) - int256(int32(exponent));
                uint256 finalPrice = basePrice / (10 ** uint256(diff));
                return finalPrice;
            } else {
                // If exponent is greater than or equal to absExpo, we need to multiply
                int256 diff = int256(int32(exponent)) - int256(absExpo);
                uint256 finalPrice = basePrice * (10 ** uint256(diff));
                return finalPrice;
            }
        } else {
            // absExpo = expo
            absExpo = priceData.expo;
            // Calculate the final price
            uint256 finalExp = uint256(int256(int32(absExpo) + int32(exponent)));
            return basePrice * (10 ** finalExp);
        }
    }
}