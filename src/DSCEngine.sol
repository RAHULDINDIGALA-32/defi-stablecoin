// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * @title DSC Engine
 * @author Rahul Dindigala
 *
 * @dev This system is designed to be as minimal as possible and have the tokens maintained at a 1 token == $1 peg.
 * This Stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed by wETH and wBTC.
 *
 * Our DSC system should always be overcollateralized. At no point, should the value orf all the collateral be less than the Dollar backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC,
 * as well as depositing and withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI Stablecoin System)
 */

contract DSCEngine is ReentrancyGuard {
    //////////////////////////////
    // State Variables          //
    //////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private _priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private _collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private _dscMinted;
    address[] private _collateralTokens;
    DecentralizedStableCoin private immutable DSC;

    //////////////////////////////
    // Events                  //
    //////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    //////////////////////////////
    // Errors                  //
    //////////////////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransactionFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFalied();

    //////////////////////////////
    // Modifiers                //
    //////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////////////////
    // Functions                //
    //////////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD price feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            _priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            _collateralTokens.push(tokenAddresses[i]);
        }

        DSC = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////////
    // External Functions      //
    //////////////////////////////
    function depositCollateralAndMintDsc() external {
        //
    }

    /**
     *@notice Follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
    }

    /**
     * @notice Follows CEI
     * @param amountDscTOMint The amount decentralized stableCoin to mint
     * @notice They must have more collateral value than the minimu threshold
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscTOMint) nonReentrant {
        _dscMinted(msg.sender) += amountDscToMint;
        // if they minted too much (than minimum collateralization ration)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = DSC.mint(msg.sender, amountDscToMint);
        if(!minted){
            revert DSCEngine__MintFalied();
        }
    }

    function redeemCollateralForDsc() external {
        //
    }

    function burnDsc() external {
        //
    }

    function liquidate() external {
        //
    }

    function getHealthFactor() external view {
        //
    }

    //////////////////////////////
    // Public Functions         //
    //////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 totalCollateralTokens = _collateralTokens.length;
        for(uint256 i=0l; i < totalCollateralTokens; i++){
            address token = _collateralTokens[i];
            uint256 amount = _collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, value);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeeds[token]);
        (,int256 price, , ,) = priceFeed.latestRoundData();
        // the returned value from chainLink will have 8 decimals (if 1ETH = $1000 then returned price = 1000* 1e8)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    //////////////////////////////
    // Internal Functions      //
    //////////////////////////////
    /**
     * 1. check health factor (i.e do they have enough collateral according to set LIQUIDATION_THRESHOLD)
     * 2. revert if they don't
     * @param user 
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    //////////////////////////////
    // Private Functions      //
    //////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = _dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $1000 ETH | 100 DSC
        // 1000 * 50= 50000 / 100 = (500 /100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
}
