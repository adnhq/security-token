// SPDX-License-Identifier: MIT

pragma solidity =0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SampleToken is ERC20, Ownable {

    uint256 public MAX_TOKEN_SUPPLY = 1000000e18; 
    uint256 public eligibilityPercentage = 10;
    uint256 public divPerToken;
    uint256 public pricePerToken;
    
    address public treasury; // Receives funds from mints 
    bool public paused = false;

    mapping(address => uint256) private _xDivPerToken;
    mapping(address => uint256) private _credit;
    mapping(address => uint256) private _lastClaimed;
    
    event TokenPurchase(address buyer, uint256 amountPurchased, uint256 ts);
    event DivIncrease(uint256 amtReceived, uint256 newDivPerToken, uint256 ts);
    event DivClaimed(address claimant, uint256 amount, uint256 ts);

    modifier notPaused {
        require(!paused, "SampleToken: contract paused");
        _;
    }

    constructor(    
        string memory _name,
        string memory _symbol,
        uint256 _pricePerToken,
        address _treasury
    ) ERC20(_name, _symbol) {
        require(_pricePerToken > 0 && _treasury != address(0), "SampleToken: non zero value needed");
        pricePerToken = _pricePerToken;
        treasury = _treasury;
    }  

    receive() external payable {
        require(totalSupply() != 0, "SampleToken: no mints");
        divPerToken += msg.value / totalSupply();   

        emit DivIncrease(msg.value, divPerToken, block.timestamp);
    }

    /// @notice Receives eth and transfers corresponding amount of tokens to caller
    function purchaseTokens() external payable notPaused {
        uint256 tokenAmt = msg.value / pricePerToken;   
        require(tokenAmt > 0, "SampleToken: insufficient amount");
        require(tokenAmt + totalSupply() <= MAX_TOKEN_SUPPLY, "SampleToken: max supply reached");

        (bool success, ) = payable(treasury).call{value: msg.value}("");
        require(success, "SampleToken: treasury transfer failed");

        _addToCredit(_msgSender());
        _mint(_msgSender(), tokenAmt);

        emit TokenPurchase(_msgSender(), tokenAmt, block.timestamp);
    }

    /// @notice Calculates and transfers dividends to caller once a year if available
    function receiveDividends() external notPaused {
        uint256 holderBalance = balanceOf(_msgSender());
        require(holderBalance != 0, "SampleToken: no shares");

        if(_lastClaimed[_msgSender()] != 0) require(block.timestamp - _lastClaimed[_msgSender()] >= 365 days, "SampleToken: claimed within a year");
        _lastClaimed[_msgSender()] = block.timestamp;

        uint256 amount = ((divPerToken - _xDivPerToken[_msgSender()]) * holderBalance);
        amount += _credit[_msgSender()];
        _credit[_msgSender()] = 0;
        _xDivPerToken[_msgSender()] = divPerToken;

        (bool success, ) = payable(_msgSender()).call{value: amount}("");
        require(success, "SampleToken: claim failed");

        emit DivClaimed(_msgSender(), amount, block.timestamp);
    }

    /// @notice Returns whether input address is eligible for exclusive perks
    /// @param holder address to retrieve eligibilty of
    function checkEligibility(address holder) 
        external 
        view 
    returns (bool eligibility) {
        return balanceOf(holder) >= totalSupply() * eligibilityPercentage / 100;
    }
    
    function _addToCredit(address recipient) private {
        uint256 amount = (divPerToken - _xDivPerToken[recipient]) * balanceOf(recipient);
        _credit[recipient] += amount;
        _xDivPerToken[recipient] = divPerToken;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if(from == address (0) || to == address(0)) return;
        _addToCredit(to);
        _addToCredit(from);
    }

    /* --- ||_ONLY OWNER_|| --- */

    /// @notice Set address that should receive token purchase funds
    /// @param _treasury new treasury
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "SampleToken: can not be zero address");
        treasury = _treasury;
    }

    /// @notice Set percentage of tokens to hold in order access exclusive perks
    /// @param _eligibilityPercentage new eligibility percentage
    function setEligibilityPercentage(uint256 _eligibilityPercentage) external onlyOwner {
        eligibilityPercentage = _eligibilityPercentage;
    }

    /// @notice Set amount required to purchase a token
    /// @param _pricePerToken new price per token
    function setPricePerToken(uint256 _pricePerToken) external onlyOwner {
        require(_pricePerToken > 0, "SampleToken: non zero amount required");
        pricePerToken = _pricePerToken;
    }

    /// @notice Pauses token purchase and dividend claiming functions
    function pause() external onlyOwner {
        paused = true;
    }

    /// @notice Unpauses token purchase and dividend claiming functions
    function unpause() external onlyOwner {
        paused = false;
    }

}
