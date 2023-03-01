// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/**
 * @title LittlebitsNFT contract 
 * @author gifMaker - contact@littlebits.club
 * @notice v1.1 / 2023
 */

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./LbAttributeDisplay.sol";
import "./LbCharacter.sol";

/// @custom:security-contact contact@littlebits.club
contract LittlebitsNFT is VRFConsumerBaseV2, ERC721, ERC721Enumerable, ERC721URIStorage, Ownable {
    // supply
    uint private constant MAX_SUPPLY = 10000;
    uint private constant AIRDROP_SUPPLY = 2000;
    uint public lootboxesReserved = 0;

    // link config
    uint64 constant LINK_SUBID = 653; // POLYGON: subscription ID 
    uint32 constant LINK_N_WORDS = 1; // random words per request
    
    // link chain config: POLYGON NETWORK
    uint16 constant LINK_CONFIRMATIONS = 3;                                                             // POLYGON: minimum confirmations
    uint32 constant LINK_GASLIMIT = 2_500_000;                                                          // POLYGON: max gas limit
    bytes32 constant LINK_KEYHASH = 0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd; // POLYGON: 500gwei gaslane
    address constant LINK_VRF_ADDR = 0xAE975071Be8F8eE67addBC1A82488F1C24858067;                        // POLYGON: vrf v2 coordinator address

    // link vrf v2 coordinator contract
    VRFCoordinatorV2Interface immutable _VRFCoordinatorV2; 

    // mint unlock
    bool public mintUnlocked = false;
    
    // failsafe functions lock
    bool public failsafesActive = true;

    // airdrop receivers
    address[] public airdropReceivers;

    // airdrop timeout
    bool airdropProtectionEnabled = true;
    
    // authorized mint addresses (stores custom sales)
    mapping(address => bool) private _authorizedMintAddresses;

    // attributes display contract
    LbAttributeDisplay private _attrDisplay;

    // mapping from token id to Character
    mapping(uint => Character) private _characters;

    // Characters waiting to be assigned to tokens
    Character[] private _unresolvedCharacters;

    // minted tokens waiting to be assigned to Characters
    uint private _nextTokenIdToResolve;
    
    // optional metadata, can be adjusted
    string private _contractMetadataUrl = "";

    // used for EIP2981, can be adjusted
    uint private _royaltyInBips = 500;

    // Log of authorized mint addresses mints
    event AuthorizedMintLog(address indexed _address, address indexed toAddress, uint quantity);

    // Log of authorized mint addresses changes
    event AuthorizedMintAddressStateChange(address indexed _address, bool indexed state);
    
    // Chainlink logs
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    constructor(address attrDisplayAddr) VRFConsumerBaseV2(LINK_VRF_ADDR) ERC721("Littlebits", "LBITS") {
        _VRFCoordinatorV2 = VRFCoordinatorV2Interface(LINK_VRF_ADDR);
        _attrDisplay = LbAttributeDisplay(attrDisplayAddr);
    }

    //////////////// CHAINLINK ////////////////

    // request extra resolutions
    function ADMIN_extraRandomWords() public onlyOwner {
        _requestRandomWords();
    }

    // request randomness
    function _requestRandomWords() private {
        // Will revert if subscription is not set and funded.
        uint requestId = _VRFCoordinatorV2.requestRandomWords(LINK_KEYHASH, LINK_SUBID, LINK_CONFIRMATIONS, LINK_GASLIMIT, LINK_N_WORDS);
        emit RequestSent(requestId, LINK_N_WORDS);
    }

    // fulfill randomness
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(_randomWords.length > 0, "random word not found");
        emit RequestFulfilled(_requestId, _randomWords);
        _resolveTokenWithSeed(_randomWords[0]);
    }

    ////////////////  ADMIN FUNCTIONS  ////////////////

    function ADMIN_registerCharacters(Character[] memory newCharacters) public onlyOwner {
        uint currentRegisteredCharacters = _nextTokenIdToResolve + getUnresolvedCharactersLength(); // resolved + unresolved
        require(currentRegisteredCharacters + newCharacters.length <= MAX_SUPPLY, "More characters than max supply");
        for (uint i = 0; i < newCharacters.length; i++) {
            _unresolvedCharacters.push(newCharacters[i]);
        }
    }

    function ADMIN_airdrop(address[] memory winners) public onlyOwner {
        require(airdropReceivers.length + winners.length <= AIRDROP_SUPPLY, "Over airdrop supply");
        for (uint i = 0; i < winners.length; i++) {
            airdropReceivers.push(winners[i]);
            _mintToken(winners[i]);
        }
    }

    function ADMIN_setLootboxesReserved(uint newLootboxesReserved) public onlyOwner {
        uint airdropReserved = airdropProtectionEnabled ? AIRDROP_SUPPLY - airdropReceivers.length : 0;
        require(MAX_SUPPLY > airdropReserved + newLootboxesReserved, "Over max supply");
        lootboxesReserved = newLootboxesReserved;
    }

    function ADMIN_setMintAddressAuth(address addr, bool state) public onlyOwner {
        if (state != _authorizedMintAddresses[addr]){
            _authorizedMintAddresses[addr] = state;
            emit AuthorizedMintAddressStateChange(addr, state);
        }
    }

    function ADMIN_withdrawFunds() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function ADMIN_setContractMetadata(string memory contractMetadataUrl) public onlyOwner {
        _contractMetadataUrl = contractMetadataUrl;
    }

    function ADMIN_setRoyaltiesInBips(uint royaltyInBips) public onlyOwner {
        require(royaltyInBips <= 10000);
        _royaltyInBips = royaltyInBips;
    }

    function ADMIN_setMintUnlocked(bool state) public onlyOwner {
        mintUnlocked = state;
    }

    function ADMIN_failsafeUpdateURI(uint tokenId, string memory newTokenURI) public onlyOwner {
        require(failsafesActive, "Failsafe permanently disabled");
        _setTokenURI(tokenId, newTokenURI);
    }

    function ADMIN_failsafeUpdateCharacter(uint tokenId, Character memory character) public onlyOwner {
        require(failsafesActive, "Failsafe permanently disabled");
        _characters[tokenId] = character;
    }

    function ADMIN_disableFailsafesPermanently() public onlyOwner {
        failsafesActive = false;
    }

    function ADMIN_setAirdropProtection(bool state) public onlyOwner {
        airdropProtectionEnabled = state;
    }

    ////////////////  PUBLIC FUNCTIONS  ////////////////

    // for stores custom sales, must be registered by ADMIN_setMintAddressAuth
    function delegatedMint(uint quantity, address destination) public {
        require(_authorizedMintAddresses[msg.sender], "Not authorized");
        require(totalSupply() < MAX_SUPPLY, "Max supply reached");
        for (uint i = 0; i < quantity; i++) {
            _mintToken(destination);
        }
        emit AuthorizedMintLog(msg.sender, destination, quantity);
    }

    function delegatedMintLootbox(uint quantity, address destination) public {
        require(_authorizedMintAddresses[msg.sender], "Not authorized");
        require(totalSupply() < MAX_SUPPLY, "Max supply reached");
        require(lootboxesReserved >= quantity, 'Register more lootboxes');
        lootboxesReserved -= quantity;
        for (uint i = 0; i < quantity; i++) {
            _mintToken(destination);
        }
        emit AuthorizedMintLog(msg.sender, destination, quantity);
    }

    // try to assign any unresolved tokens to available Characters
    function _resolveTokenWithSeed(uint randomSeed) private {
        // require (_unresolvedTokens.length > 0, 'no tokens to resolve'); 
        require (_nextTokenIdToResolve < totalSupply());
        // resolve next token
        uint tokenId = _nextTokenIdToResolve;
        // get random unresolved_character index
        uint randomCharacterInd = uint(keccak256(abi.encodePacked(randomSeed, tokenId))) % _unresolvedCharacters.length;
        // resolve token
        _resolveToken(tokenId, randomCharacterInd);
        // move next
        _nextTokenIdToResolve++;
    }

    // get character from tokenId
    function getCharacter(uint tokenId) public view returns (Character memory) {
        return _characters[tokenId];
    }

    // get characters from address
    function getCharacters(address owner) public view returns (Character[] memory) {
        uint ownerBalance = balanceOf(owner);
        Character[] memory ownerCharacters = new Character[](ownerBalance);
        for (uint i = 0; i < ownerBalance; i++) {
            uint token = tokenOfOwnerByIndex(owner, i);
            ownerCharacters[i] = _characters[token];
        }
        return ownerCharacters;
    }

    function getUnresolvedCharactersLength() public view returns (uint) {
        return _unresolvedCharacters.length;
    }

    function getAirdropReceiversLength() public view returns (uint) {
        return airdropReceivers.length;
    }

    // optional standard to be implemented if needed
    function contractURI() public view returns (string memory) {
        return _contractMetadataUrl;
    }
    
    // royalty standard EIP2981
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        uint256 calculatedRoyalties = _salePrice / 10000 * _royaltyInBips;
        return(owner(), calculatedRoyalties);
    }

    ////////////////  PRIVATE FUNCTIONS  ////////////////
    function _mintToken(address to) private {
        require(mintUnlocked, "Minting not unlocked");
        uint tokenId = totalSupply();
        uint airdropReserved = airdropProtectionEnabled ? AIRDROP_SUPPLY - airdropReceivers.length : 0;
        uint currentMintMax = MAX_SUPPLY - airdropReserved - lootboxesReserved;
        require(tokenId < currentMintMax, "Max mint allowed reached");
        _mint(to, tokenId);
        _requestRandomWords();
    }

    // assign available Character to token
    function _resolveToken(uint tokenId, uint characterInd) private {
        // get Character
        Character memory character = _unresolvedCharacters[characterInd];
        // register Character to token 
        _characters[tokenId] = character;
        // set token URI
        //string memory newTokenUri = _buildMetadata(character, tokenId);
        string memory newTokenUri = _attrDisplay.buildMetadata(character, tokenId);
        _setTokenURI(tokenId, newTokenUri);
        // make Character unavailable
        _unresolvedCharacters[characterInd] = _unresolvedCharacters[_unresolvedCharacters.length-1];
        _unresolvedCharacters.pop();
    }

    ////////////////  OVERRIDES  ////////////////
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return interfaceId == 0x2a55205a // royalty standard EIP2981
        || super.supportsInterface(interfaceId);
    }

    function renounceOwnership() public view override(Ownable) onlyOwner {
        revert("renounce ownership disabled");
    }

    ////////////////  MULTIPLE INHERITANCE OVERRIDES  ////////////////
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
}
