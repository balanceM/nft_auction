// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NftAuction {
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
    }
    // 拍卖列表
    Auction[] public auctions;
    // 管理员
    address public admin;
    // 初始化
    constructor() {
        admin = msg.sender;
    }

    // 创建拍卖
    function createAuction(
        uint256 _startTime, uint256 _duration, uint256 _startPrice, address _nftContract, uint256 _nftId
    ) external returns (uint256) {
        // 判断参数
        require(_startTime >= block.timestamp, "Start time must be in the future");
        require(_duration >= 3600, "Duration must be at least 1 hour");
        require(_startPrice > 0, "Start price must be greater than 0");
        require(address(_nftContract) != address(0), "NFT contract address must not be zero");
        require(_nftId >= 0, "NFT ID must be greater or equal to 0");
        // 创建拍卖
        auctions.push(Auction({
            startTime: _startTime,
            duration: _duration,
            startPrice: _startPrice,
            seller: msg.sender,
            highestBidder: address(0),
            highestBid: 0,
            isEnd: false,
            nftContract: _nftContract,
            nftId: _nftId
        }));
        return auctions.length - 1;
    }

    // 出价
    function bid(uint256 _auctionId, uint256 _amount) external {
        // 判断参数
        require(_auctionId < auctions.length, "Auction does not exist");
        Auction memory auction = auctions[_auctionId];
        require(_amount > auction.highestBid, "Amount must be greater than highest bid");
        require(auction.isEnd == false, "Auction is ended");
        require(block.timestamp >= auction.startTime && block.timestamp <= auction.startTime + auction.duration, "Auction is not active");
        // 更新拍卖
        auctions[_auctionId].highestBidder = msg.sender;
        auctions[_auctionId].highestBid = _amount;
    }

    // 结束拍卖
    function endAuction(uint256 _auctionId) external {
        // 判断参数
        require(msg.sender == admin, "Only admin can end auction");
        require(_auctionId < auctions.length, "Auction does not exist");
        Auction memory auction = auctions[_auctionId];
        require(auction.isEnd == false, "Auction is ended");
        require(block.timestamp >= auction.startTime + auction.duration, "Auction is not ended");
        // 更新拍卖
        auctions[_auctionId].isEnd = true;
        // 转移NFT
        IERC721(auction.nftContract).transferFrom(auction.seller, auction.highestBidder, auction.nftId);
        // 转移ETH
        payable(auction.seller).transfer(auction.highestBid);
    }
}