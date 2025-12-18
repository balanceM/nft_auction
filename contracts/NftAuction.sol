// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// chainlink
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract NftAuction {
    address ethUsdAddr = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    // 拍卖结构体
    struct Auction {
        uint256 startTime; // 起始时间
        uint256 duration; // 持续时间
        uint256 startPrice; // 开始价格
        address seller; // 卖家
        address highestBidder; // 最高出价者
        uint256 highestBid; // 最高出价
        bool isEnd; // 结束时间

        address nftContract; // NFT合约地址
        uint256 nftId; // NFT ID

        address bidderTokenAddress; // 出价代币地址
    }
    // 拍卖列表
    Auction[] public auctions;
    // 管理员
    address public admin;
    // 预言机价格表
    mapping(address => AggregatorV3Interface) public priceFeeds;
    // 管理员修饰符
    modifier onlyAdmin() {
        require(msg.sender == admin, "You are not the admin");
        _;
    }
    modifier onlyAuctionParties(uint256 _auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(
            msg.sender == admin ||
            msg.sender == auction.seller,
            "Not authorized"
        );
        _;
    }
    // 初始化
    constructor() {
        admin = msg.sender;
    }

    // 设置预言机价格表
    function setPriceFeed(address tokenAddress, address _priceFeed) public onlyAdmin {
        priceFeeds[tokenAddress] = AggregatorV3Interface(_priceFeed);
    }

    // 获取预言机价格
    function getChainlinkDataFeedLatestAnswer(address tokenAddress) public view returns (int256) {
        (
        /* uint80 roundId */
        ,
        int256 answer,
        /*uint256 startedAt*/
        ,
        uint256 updatedAt
        ,
        /*uint80 answeredInRound*/
        ) = priceFeeds[tokenAddress].latestRoundData();
        require(answer > 0, "Invalid price feed answer");
        require(block.timestamp - updatedAt < 1 hours, "Price feed stale");
        return answer;
    }
    
    receive() external payable {}

    fallback() external payable {}

    // 创建拍卖
    function createAuction(
        uint256 _duration, uint256 _startPrice, address _nftContract, uint256 _nftId
    ) external returns (uint256) {
        // 判断参数
        require(_duration >= 10, "Duration must be at least 10s");
        require(_startPrice > 0, "Start price must be greater than 0");
        require(_nftContract != address(0), "NFT contract address must not be zero");
        // 授权卖家NFT给合约
        // IERC721 nft = IERC721(_nftContract);
        // require(nft.ownerOf(_nftId) == msg.sender, "Not NFT owner");
        // nft.safeTransferFrom(msg.sender, address(this), _nftId);
        IERC721(_nftContract).approve(address(this), _nftId);
        // 创建拍卖
        uint256 auctionId = auctions.length;
        auctions.push(Auction({
            startTime: block.timestamp,
            duration: _duration,
            startPrice: _startPrice,
            seller: msg.sender,
            highestBidder: address(0),
            highestBid: 0,
            isEnd: false,
            nftContract: _nftContract,
            nftId: _nftId,
            bidderTokenAddress: address(0)
        }));
        return auctionId;
    }

    // 出价
    function bid(uint256 _auctionId, uint256 _amount, address _tokenAddress) external payable {
        // 判断参数
        require(_auctionId < auctions.length, "Auction does not exist");
        Auction storage auction = auctions[_auctionId];
        require(auction.isEnd == false, "Auction is ended");
        require(block.timestamp >= auction.startTime && block.timestamp <= auction.startTime + auction.duration, "Auction is not active");
        // 统一价值尺度为USD
        uint payValue;
        if (_tokenAddress == address(0)) { // ETH 转 USD
            uint ethPrice = uint(getChainlinkDataFeedLatestAnswer(ethUsdAddr));
            payValue = msg.value * ethPrice;
        } else { // ERC20代币 转 USD
            payValue = _amount * uint(getChainlinkDataFeedLatestAnswer(_tokenAddress));
        }
        require(payValue > auction.highestBid, "Amount must be greater than highest bid");
        // 转账给合约
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount);
        // 更新拍卖
        auction.highestBidder = msg.sender;
        auction.highestBid = _amount;
        auction.bidderTokenAddress = _tokenAddress;
        // 退回之前的出价
        if (auction.bidderTokenAddress == address(0)) { // 退回ETH
            // (bool success, ) = payable(auction.highestBidder).call{value: auction.highestBid}("");
            // require(success, "ETH transfer failed");
            payable(auction.highestBidder).transfer(auction.highestBid);
        } else { // 退回ERC20代币
            IERC20(auction.bidderTokenAddress).transfer(auction.highestBidder, auction.highestBid);
        }
    }

    // 结束拍卖
    function endAuction(uint256 _auctionId) external onlyAuctionParties(_auctionId) {
        // 判断参数
        require(_auctionId < auctions.length, "Auction does not exist");
        Auction storage auction = auctions[_auctionId];
        require(auction.isEnd == false, "Auction is ended");
        require(block.timestamp >= auction.startTime + auction.duration, "Auction is not ended");
        // 更新拍卖
        auction.isEnd = true;
        if (auction.highestBidder != address(0)) {
            // 转移NFT
            IERC721(auction.nftContract).transferFrom(auction.seller, auction.highestBidder, auction.nftId);
            // 转移ETH
            payable(auction.seller).transfer(auction.highestBid);
        } else {
            IERC721(auction.nftContract).transferFrom(address(this), auction.seller, auction.nftId);
        }
    }
}