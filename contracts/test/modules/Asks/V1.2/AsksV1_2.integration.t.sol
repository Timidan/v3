// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {AsksV1_2} from "../../../../modules/Asks/V1.2/AsksV1_2.sol";
import {Zorb} from "../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../utils/modules/RoyaltyEngine.sol";

import {TestERC721} from "../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../utils/tokens/WETH.sol";
import {VM} from "../../../utils/VM.sol";

/// @title AskV1_2IntegrationTest
/// @notice Integration Tests for Asks v1.2
contract AsksV1_2IntegrationTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    AsksV1_2 internal asks;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal listingFeeRecipient;
    Zorb internal buyer;
    Zorb internal finder;
    Zorb internal royaltyRecipient;

    function setUp() public {
        // Cheatcodes
        vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
        erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

        // Init V3
        registrar.init(ZMM);
        ZPFS.init(address(ZMM), address(0));

        // Create users
        seller = new Zorb(address(ZMM));
        sellerFundsRecipient = new Zorb(address(ZMM));
        listingFeeRecipient = new Zorb(address(ZMM));
        buyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Asks v1.2
        asks = new AsksV1_2(address(erc20TransferHelper), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(asks));

        // Set user balances
        vm.deal(address(buyer), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Buyer swap 50 ETH <> 50 WETH
        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve Asks module
        seller.setApprovalForModule(address(asks), true);
        buyer.setApprovalForModule(address(asks), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Buyer approve ERC20TransferHelper
        vm.prank(address(buyer));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ ETH ASK ------------ ///

    function runETH() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(0), address(sellerFundsRecipient), address(listingFeeRecipient), 1000, 1000);

        vm.prank(address(buyer));
        asks.fillAsk{value: 1 ether}(address(token), 0, address(0), 1 ether, address(finder));
    }

    function test_ETHIntegration() public {
        uint256 beforeBuyerBalance = address(buyer).balance;
        uint256 beforeSellerBalance = address(sellerFundsRecipient).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 beforeListerBalance = address(listingFeeRecipient).balance;
        uint256 beforeFinderBalance = address(finder).balance;
        address beforeTokenOwner = token.ownerOf(0);

        runETH();

        uint256 afterBuyerBalance = address(buyer).balance;
        uint256 afterSellerBalance = address(sellerFundsRecipient).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 afterListerBalance = address(listingFeeRecipient).balance;
        uint256 afterFinderBalance = address(finder).balance;
        address afterTokenOwner = token.ownerOf(0);

        // 1 ETH withdrawn from buyer
        require((beforeBuyerBalance - afterBuyerBalance) == 1 ether);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 0.095 ETH listing fee paid to lister (remaining 0.95 ETH * 1000 bps listing fee)
        require((afterListerBalance - beforeListerBalance) == 0.095 ether);
        // 0.0855 ETH finders fee paid to finder (remaining 0.855 ETH * 1000 bps finders fee)
        require((afterFinderBalance - beforeFinderBalance) == 0.0855 ether);
        // Final 0.7695 ETH is paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.7695 ether);
        // NFT transferred to buyer
        require((beforeTokenOwner == address(seller)) && afterTokenOwner == address(buyer));
    }

    /// ------------ ERC-20 ASK ------------ ///

    function runERC20() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth), address(sellerFundsRecipient), address(listingFeeRecipient), 1000, 1000);

        vm.prank(address(buyer));
        asks.fillAsk(address(token), 0, address(weth), 1 ether, address(finder));
    }

    function test_ERC20Integration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(sellerFundsRecipient));
        uint256 beforeBuyerBalance = weth.balanceOf(address(buyer));
        uint256 beforeRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 beforeListerBalance = weth.balanceOf(address(listingFeeRecipient));
        uint256 beforeFinderBalance = weth.balanceOf(address(finder));
        address beforeTokenOwner = token.ownerOf(0);

        runERC20();

        uint256 afterSellerBalance = weth.balanceOf(address(sellerFundsRecipient));
        uint256 afterBuyerBalance = weth.balanceOf(address(buyer));
        uint256 afterRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 afterListerBalance = weth.balanceOf(address(listingFeeRecipient));
        uint256 afterFinderBalance = weth.balanceOf(address(finder));
        address afterTokenOwner = token.ownerOf(0);

        // 1 WETH withdrawn from buyer
        require((beforeBuyerBalance - afterBuyerBalance) == 1 ether);
        // 0.05 WETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 0.095 WETH listing fee paid to lister (remaining 0.95 WETH * 1000 bps listing fee)
        require((afterListerBalance - beforeListerBalance) == 0.095 ether);
        // 0.0855 WETH finders fee paid to finder (remaining 0.855 WETH * 1000 bps finders fee)
        require((afterFinderBalance - beforeFinderBalance) == 0.0855 ether);
        // Final 0.7695 WETH is paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.7695 ether);
        // NFT transferred to buyer
        require((beforeTokenOwner == address(seller)) && afterTokenOwner == address(buyer));
    }
}