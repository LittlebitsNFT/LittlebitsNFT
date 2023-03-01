// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/**
 * @title LbAttributeDisplay contract 
 * @author gifMaker - contact@littlebits.club
 * @notice v1.00 / 2022
 * @dev Retrieves Character attributes in a human readable format
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Base64.sol";
import "./LbCharacter.sol";

contract LbAttributeDisplay is Ownable {
    bool public contractLocked = false;

    string private constant BASE_IMG_URI = "ipfs://QmWHhBbYbs1po3EivgG4N8eFK2eU8pEZDJzLX8Bm7pQ9pj/";

    // AttrIds
    // 0 rarity; 1 gender; 2 costume; 3 hat; 4 hair; 5 glasses; 6 eyes; 7 nose;
    // 8 beard; 9 bowtie; 10 jacket; 11 torso; 12 legs; 13 shoes; 14 skin;
    string[ATTR_COUNT] private _attrkeysDisplay = ["Rarity", "Gender", "Costume", "Hat", "Hair", "Glasses", "Eyes", "Nose", "Beard", "Bowtie", "Jacket", "Torso", "Legs", "Shoes", "Skin"];

    // _displayValues[genderId][attrId] -> displayValues
    string[][ATTR_COUNT][2] private _displayValues;

    // required attrvalues count before lock (from char generation data)
    uint[ATTR_COUNT] private _maleAttrvaluesCountRequirement = [6, 2, 21, 33, 55, 16, 6, 4, 62, 5, 8, 46, 22, 22, 7];
    uint[ATTR_COUNT] private _femaleAttrvaluesCountRequirement = [6, 2, 21, 33, 49, 19, 6, 4, 1, 1, 19, 65, 25, 25, 7];

    function ADMIN_setupAttributes(uint genderId, uint attrId, string[] memory displayValues) public onlyOwner {
        require(genderId < 2, "invalid genderId");
        require(attrId < ATTR_COUNT, "invalid attrId");
        _displayValues[genderId][attrId] = displayValues;
    }

    function getDisplayValue(uint gender, uint attrId, uint valueId) public view returns (string memory) {
        return _displayValues[gender][attrId][valueId];
    }

    function getDisplayValues(uint gender, uint attrId) public view returns (string[] memory) {
        return _displayValues[gender][attrId];
    }

    function getDisplayValuesLength(uint gender, uint attrId) public view returns (uint) {
        return _displayValues[gender][attrId].length;
    }

    // build json metadata string to be stored on-chain
    function buildMetadata(Character memory character, uint tokenId) public view returns (string memory) {
        require(contractLocked, "setup not finished"); 
        string memory descriptionStr = "A happy Littlebit.";
        string memory attrBlock;
        string memory attrComma = "";
        for (uint attrId = 0; attrId < ATTR_COUNT; attrId++) {
            string memory attrvalueDisplay = getDisplayValue(character.attributes[1], attrId, character.attributes[attrId]);
            if (attrId > 0) attrComma = ",";
            if (
                keccak256(bytes(attrvalueDisplay)) == keccak256(bytes("none"))
            ) continue;
            attrBlock = string(
                abi.encodePacked(
                    attrBlock,
                    attrComma,
                    '{"trait_type":"',
                    _attrkeysDisplay[attrId],
                    '",',
                    '"value":"',
                    attrvalueDisplay,
                    '"}'
                )
            );
        }
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                "Littlebit #",
                                Strings.toString(tokenId),
                                '", "description":"',
                                descriptionStr,
                                '", "image": "',
                                BASE_IMG_URI,
                                character.imageId,
                                '", "attributes": ',
                                "[",
                                attrBlock,
                                "]",
                                "}"
                            )
                        )
                    )
                )
            );
    }

    ////////////////  OVERRIDES  ////////////////
    function renounceOwnership() public override(Ownable) onlyOwner {
        // data checkup before contract lock
        for (uint attrId = 0; attrId < ATTR_COUNT; attrId++) {
            require(getDisplayValuesLength(0, attrId) == _maleAttrvaluesCountRequirement[attrId], "MALE attr value count error");
            require(getDisplayValuesLength(1, attrId) == _femaleAttrvaluesCountRequirement[attrId], "FEMALE attr value count error");
        }
        super.renounceOwnership();
        contractLocked = true;
    }
}
