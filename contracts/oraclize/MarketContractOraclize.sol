/*
    Copyright 2017 Phillip A. Elsasser

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

pragma solidity ^0.4.18;

import "./IQueryCallBack.sol";
import "./IQueryHub.sol";
import "../libraries/MathLib.sol";
import "../MarketContract.sol";


/// @title MarketContract first example of a MarketProtocol contract using Oraclize services
/// @author Phil Elsasser <phil@marketprotocol.io>
contract MarketContractOraclize is MarketContract, IQueryCallback {
    using MathLib for uint;

    // constants
    string public ORACLE_DATA_SOURCE;
    string public ORACLE_QUERY;
    uint public ORACLE_QUERY_REPEAT;
    address QUERY_HUB_ADDRESS;

    // state variables
    string public lastPriceQueryResult;
    mapping(bytes32 => bool) validScheduledQueryIDs;
    mapping(bytes32 => bool) validUserRequestedQueryIDs;


    /// @param contractName viewable name of this contract (BTC/ETH, LTC/ETH, etc)
    /// @param marketTokenAddress address of our member token
    /// @param queryHubAddress address of the query hub
    /// @param baseTokenAddress address of the ERC20 token that will be used for collateral and pricing
    /// @param contractSpecs array of unsigned integers including:
    /// floorPrice minimum tradeable price of this contract, contract enters settlement if breached
    /// capPrice maximum tradeable price of this contract, contract enters settlement if breached
    /// priceDecimalPlaces number of decimal places to convert our queried price from a floating point to
    /// an integer
    /// qtyMultiplier multiply traded qty by this value from base units of collateral token.
    /// expirationTimeStamp - seconds from epoch that this contract expires and enters settlement
    /// @param oracleDataSource a data-source such as "URL", "WolframAlpha", "IPFS"
    /// see http://docs.oraclize.it/#ethereum-quick-start-simple-query
    /// @param oracleQuery see http://docs.oraclize.it/#ethereum-quick-start-simple-query for examples
    /// @param oracleQueryRepeatSeconds how often to repeat this callback to check for settlement, more frequent
    /// queries require more gas and may not be needed.
    function MarketContractOraclize(
        string contractName,
        address marketTokenAddress,
        address queryHubAddress,
        address baseTokenAddress,
        uint[5] contractSpecs,
        string oracleDataSource,
        string oracleQuery,
        uint oracleQueryRepeatSeconds
    ) MarketContract(
        contractName,
        marketTokenAddress,
        baseTokenAddress,
        contractSpecs
    )  public payable
    {
        ORACLE_DATA_SOURCE = oracleDataSource;
        ORACLE_QUERY = oracleQuery;
        ORACLE_QUERY_REPEAT = oracleQueryRepeatSeconds;
        QUERY_HUB_ADDRESS = queryHubAddress;
        queryOracle();  // schedules recursive calls to oracle
    }

    /// @notice allows a user to request an extra query to oracle in order to push the contract into
    /// settlement.  A user may call this as many times as they like, since they are the ones paying for
    /// the call to our oracle and post processing. This is useful for both a failsafe and as a way to
    /// settle a contract early if a price cap or floor has been breached.
    function requestEarlySettlement() external payable {
        IQueryHub queryHub = IQueryHub(QUERY_HUB_ADDRESS);
        uint cost = queryHub.getPrice(ORACLE_DATA_SOURCE);
        requite(msq.value >= cost);
        require(msg.value >= cost); // user must pay enough to cover query and callback
        // create immediate query, we must make sure to store this one separately, so
        // we do not schedule recursive callbacks when the query completes.
        bytes32 queryId = queryHub.queryOracleHub.value(cost)(
            ORACLE_DATA_SOURCE,
            ORACLE_QUERY,
            ORACLE_QUERY_REPEAT
        );
        validUserRequestedQueryIDs[queryId] = true;
    }

    /*
    // PUBLIC METHODS
    */

    /// @notice only public for callbacks from oraclize, do not call
    /// @param queryID of the returning query, this should match our own internal mapping
    /// @param result query to be processed
    /// @param proof result proof
    function queryCallBack(bytes32 queryID, string result) public {
        require(msg.sender == oraclize_cbAddress());
        bool isScheduled = validScheduledQueryIDs[queryID];
        require(isScheduled || validUserRequestedQueryIDs[queryID]);
        lastPriceQueryResult = result;
        lastPrice = parseInt(result, PRICE_DECIMAL_PLACES);
        UpdatedLastPrice(result);
        checkSettlement();

        if (isScheduled) {
            delete validScheduledQueryIDs[queryID];
            if (!isSettled) {
                // this was a scheduled query, and we have not entered a settlement state
                // so we want to schedule a new query.
                queryOracle();
            }
        } else {
            delete validUserRequestedQueryIDs[queryID];
        }
    }

    /*
    // PRIVATE METHODS
    */

    /// @dev call to oraclize to set up our query and record its hash.
    function queryOracle() private {
        IQueryHub queryHub = IQueryHub(QUERY_HUB_ADDRESS);
        uint price = queryHub.getPrice(ORACLE_DATA_SOURCE);
        requite(this.balance >= price);
        bytes32 queryId = queryHub.queryOracleHub.value(price)(
            ORACLE_DATA_SOURCE,
            ORACLE_QUERY,
            ORACLE_QUERY_REPEAT
        );
        validScheduledQueryIDs[queryId] = true;
    }
}