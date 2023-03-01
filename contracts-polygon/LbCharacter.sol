// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

// AttrIds
// 0 rarity; 1 gender; 2 costume; 3 hat; 4 hair; 5 glasses; 6 eyes; 7 nose;
// 8 beard; 9 bowtie; 10 jacket; 11 torso; 12 legs; 13 shoes; 14 skin;

uint constant ATTR_COUNT = 15;

struct Character {
    uint8[ATTR_COUNT] attributes;
    string imageId;
}
