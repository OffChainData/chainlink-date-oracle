pragma solidity 0.4.24;

import "chainlink/contracts/ChainlinkClient.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @title RentalContract is an example contract which requests data from
 * the Chainlink network
 * @dev This contract is designed to work on multiple networks, including
 * local test networks
 */
contract RentalContract is ChainlinkClient, Ownable {
    // solium-disable-next-line zeppelin/no-arithmetic-operations
    uint256 private oraclePayment = LINK / 10;
    uint256 private rentalAmount = 0.000001 ether; //monthly rental amount in wei
    bool private performBurn = false;
    bytes32 public currentDate;
    mapping(bytes32 => bool) public paidDates;
    mapping(bytes32 => bytes32) public businessDayOfMonth;
    mapping(bytes32 => bytes32) private requests;

    event RequestFulfilled(
        bytes32 indexed requestId,  // User-defined ID
        bytes32 indexed businessDayOfMonth
    );

    event Transfer(
        bytes32 indexed date,
        uint256 indexed amount
    );
    
    /**
    * @notice Deploy the contract with a specified address for the LINK
    * and Oracle contract addresses
    * @dev Sets the storage for the specified addresses
    * @param _link The address of the LINK token contract (Ropsten 0x20fE562d797A42Dcb3399062AE9546cd06f63280)
    * @param _oracle The address of the Oracle contract (Use Off Chain Data's Oracle 0x20017c80327cb925eedd18908029444cb6bd1b9b)
    */
    constructor(address _link, address _oracle) public {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
    }

    /**
    * @notice Sets burn flag
    * @param _performBurn Burn flag
    */
    function setPerformBurn(
            bool _performBurn
    )
        public
        onlyOwner
    {
        performBurn = _performBurn;
    }


    /**
    * @notice Sets the amount that must be paid to the Oracle
    * @param _oraclePayment Payment amount
    */
    function setLinkPaymentAmount(
            uint256 _oraclePayment
    )
        public
        onlyOwner
    {
        oraclePayment = _oraclePayment;
    }

    /**
    * @notice Returns the amount that must be paid to the Oracle
    */
    function getLinkPaymentAmount() public view returns (uint256) {
        return oraclePayment;
    }

    /**
    * @notice Sets the current monthly rental amount
    * @param _rentalAmount Rental amount
    */
    function setRentalAmount(
            uint256 _rentalAmount
    )
        public
        onlyOwner
    {
        rentalAmount = _rentalAmount;
    }

    /**
    * @notice Returns the current monthly rental amount
    */
    function getRentalAmount() public view returns (uint256) {
        return rentalAmount;
    }

    /**
    * @notice Calls an Oracle for the specifed date and region
    * @param _jobId The ID of the Job on the Chainlink node (Use Off Chain Data's Node d26d6b18b9c4455bbdc49fef3a3da1e8)
    * @param _currentDate Date to query in YYYY-MM-DD format
    * @param _region Region the date applies to
    */
    function checkDate(string _jobId, string _currentDate, string _region) public onlyOwner
        returns (bytes32 requestId)
    {
        //Check for non empty values
        bytes memory tempRegion = bytes(_region);
        bytes memory tempCurrentDate = bytes(_currentDate);

        require(tempRegion.length > 0, "Region must be set.");
        require(tempCurrentDate.length != 0, "Date must be set.");
        //Before issuing the request, we need to ensure that the smart contract
        //will have sufficient funds to pay the rent
        require(!performBurn || (performBurn && address(this).balance >= rentalAmount), "Insufficient funds to pay rent.");
        currentDate = stringToBytes32(_currentDate);

        Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32(_jobId), this, this.fulfill.selector);
        req.add("date", _currentDate);
        req.add("region", _region);
        requestId = sendChainlinkRequestTo(getOracle(), req, oraclePayment);
        requests[requestId] = currentDate;
    }

    /**
    * @notice Returns the address of the LINK token
    * @dev This is the public implementation for chainlinkTokenAddress, which is
    * an internal method of the ChainlinkClient contract
    */
    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    /**
    * @notice Returns the address of the Oracle contract
    * @dev This is the public implementation for chainlinkOracleAddress, which is
    * an internal method of the ChainlinkClient contract
    */
    function getOracle() public view returns (address) {
        return chainlinkOracleAddress();
    }

  /**
   * @notice The fulfill method from requests created by this contract
   * @dev The recordChainlinkFulfillment protects this function from being called
   * by anyone other than the oracle address that the request was sent to
   * @param _requestId The ID that was generated for the request
   * @param _businessDayOfMonth The answer provided by the oracle
   */
    function fulfill(bytes32 _requestId, bytes32 _businessDayOfMonth)
        public
        //recordChainlinkFulfillment(_requestId)
    {
        emit RequestFulfilled(_requestId, _businessDayOfMonth);
        bytes32 dateRequested = requests[_requestId];
        businessDayOfMonth[dateRequested] = _businessDayOfMonth;

        //Pay rent if this is the 1st business day of the month
        if (_businessDayOfMonth == "1") {
            require(!performBurn || (performBurn && address(this).balance >= rentalAmount), "Insufficient funds to pay rent.");
                    
            paidDates[dateRequested] = true;
            
            if (performBurn) {
                //Burn ether simulating payment of monthly rent
                address burn = address(0x00);
                burn.transfer(rentalAmount);
            }

            emit Transfer(dateRequested, rentalAmount);
        }
    }

    /**
    * @notice Allows the owner to withdraw any LINK balance on the contract
    */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }

    /**
    * @notice Call this method if no response is received within 5 minutes
    * @param _requestId The ID that was generated for the request to cancel
    * @param _payment The payment specified for the request to cancel
    * @param _callbackFunctionId The bytes4 callback function ID specified for
    * the request to cancel
    * @param _expiration The expiration generated for the request to cancel
    */
    function cancelRequest(
        bytes32 _requestId,
        uint256 _payment,
        bytes4 _callbackFunctionId,
        uint256 _expiration
    )
        public
        onlyOwner
    {
        cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    // @notice Will receive any eth sent to the contract
    function () external payable {
    }
}