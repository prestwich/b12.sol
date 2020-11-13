//SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.5.10;

import {TypedMemView} from "@summa-tx/memview.sol/contracts/TypedMemView.sol";

import {CIP20Lib} from "./CIP20Lib.sol";
import {CeloB12_377Lib} from "./B12.sol";
import {B12} from "./B12.sol";

contract SnarkEpochDataSlasher {

    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    function slash(uint16 epoch, uint8 counter1, uint32 maximum_non_signers1, bytes memory bhhash1, uint256 bitmap1, bytes memory sig1, bytes memory hint1,
         uint8 counter2, uint32 maximum_non_signers2, bytes memory bhhash2, uint256 bitmap2, bytes memory sig2, bytes memory hint2) public view {
        bytes memory data1 = abi.encodePacked(counter1, epoch, maximum_non_signers1, bhhash1);
        bytes memory data2 = abi.encodePacked(counter2, epoch, maximum_non_signers2, bhhash2);
        slash2(epoch, data1, bitmap1, sig1, hint1, data2, bitmap2, sig2, hint2);
    }

    function negativeP2() internal pure returns (B12.G2Point memory) {
        B12.Fp2 memory x = B12.Fp2(
            B12.Fp(0x018480be71c785fec89630a2a3841d01, 0xc565f071203e50317ea501f557db6b9b71889f52bb53540274e3e48f7c005196),
            B12.Fp(0x00ea6040e700403170dc5a51b1b140d5, 0x532777ee6651cecbe7223ece0799c9de5cf89984bff76fe6b26bfefa6ea16afe)
        );
        B12.Fp2 memory y = B12.Fp2(
            B12.Fp(0x01452cdfba80a16eecda9254a0ee5986, 0x3c1eec808c4079363a9a9facc1d675fb243bd4bbc27383d19474b6bbf602b222),
            B12.Fp(0x00b623a64541bbd227e6681d5786d890, 0xb833c846c39bf79dfa8fb214eb26433dd491a504d1add8f4ab66f22e7a14706e)
        );
        return B12.G2Point(x, y);
    }

    function mapToG1Scaled(B12.Fp memory x, B12.Fp memory hint1, B12.Fp memory hint2, bool greatest)
        internal
        view
        returns (B12.G1Point memory) {
        B12.G1Point memory p = B12.mapToG1(x, hint1, hint2, greatest);
        B12.G1Point memory q = CeloB12_377Lib.g1Mul(p, 30631250834960419227450344600217059328);
        // TODO: check that q != 0
        return q;
    }

    function slash2(uint16 epoch, bytes memory data1, uint256 bitmap1, bytes memory sig1, bytes memory hint1,
                                  bytes memory data2, uint256 bitmap2, bytes memory sig2, bytes memory hint2) internal view returns (bool) {
        require(isValid(epoch, data1, bitmap1, sig1, hint1));
        require(isValid(epoch, data2, bitmap2, sig2, hint2));
    }

    function getBLSPublicKey(uint16 epoch, uint i) internal view returns (B12.G2Point memory) {
    }

    function doHash(bytes memory data) internal view returns (bytes memory) {
        bytes32 config = CIP20Lib.createConfig(32, 0, 0, 0, 32, 0, 64 /* xof digest length*/, 0, 32 /* inner length */, bytes8(0), "ULforxof");
        return CIP20Lib.blake2XsWithConfig(config, new bytes(0), data, 32);
    }

    function parsePointGen(bytes memory h, uint256 offset) internal pure returns (uint256, uint256, uint256) {
        uint256 a = 0;
        uint256 b = 0;
        for (uint i = 0; i < 32; i++) {
            uint256 byt = uint256(uint8(h[offset+i]));
            b = b + (byt << i*8);
        }
        for (uint i = 0; i < 15; i++) {
            uint256 byt = uint256(uint8(h[offset+i+32]));
            a = a + (byt << i*8);
        }
        return (a, b, uint256(uint8(h[offset+47])));
    }

    function parsePoint(bytes memory h, uint256 offset) internal pure returns (B12.Fp memory, bool) {
        (uint256 a, uint256 b, uint256 byt) = parsePointGen(h, offset);
        a = a + ((byt&0x7f) << 47*8);
        return (B12.Fp(a, b), byt&0xa0 != 0);
    }

    function parsePoint(bytes memory h) internal pure returns (B12.Fp memory, bool) {
        return parsePoint(h, 0);
    }

    function parseRandomPoint(bytes memory h) internal pure returns (B12.Fp memory, bool) {
        (uint256 a, uint256 b, uint256 byt) = parsePointGen(h, 0);
        a = a + ((byt&0x01) << 47*8);
        return (B12.Fp(a, b), byt&0x02 != 0);
    }

    function parsePoint2(bytes memory h) internal pure returns (B12.Fp2 memory, bool) {
        bytes29 ref1 = h.ref(0).postfix(h.length, 0);
        // 48 bytes, 384 bits
        uint256 a1 = ref1.indexUint(0, 32);
        uint256 b1 = ref1.indexUint(32, 32);
        B12.Fp memory p1 = B12.Fp(a1 >> 135, (a1 << 135) | (b1 >> 135));
        uint256 a2 = ref1.indexUint(48, 32);
        uint256 b2 = ref1.indexUint(64, 32);
        B12.Fp memory p2 = (B12.Fp(a2 >> 135, (a2 << 135) | (b2 >> 135)));
        return (B12.Fp2(p1, p2), (b2 >> 134) & 1 == 0);
    }

    function parseToG1(bytes memory h, bytes memory hints, uint idx) internal view returns (B12.G1Point memory) {
        bool greatest;
        B12.Fp memory x;
        (x, greatest) = parsePoint(h);
        return B12.mapToG1(x, B12.parseFp(hints, 0+idx), B12.parseFp(hints, 64+idx), greatest);
    }

    function parseToG2(bytes memory h, bytes memory hint1, bytes memory hint2) internal view returns (B12.G2Point memory) {
        bool greatest;
        B12.Fp2 memory x;
        (x, greatest) = parsePoint2(h);
        return B12.mapToG2(x, B12.parseFp2(hint1, 0), B12.parseFp2(hint2, 0), greatest);
    }

    function parseToG1Scaled(bytes memory h, bytes memory hints) internal view returns (B12.G1Point memory) {
        bool greatest;
        B12.Fp memory x;
        (x, greatest) = parseRandomPoint(h);
        return mapToG1Scaled(x, B12.parseFp(hints, 0), B12.parseFp(hints, 64), greatest);
    }

    mapping (address => B12.G2Point) points;

    function storeValidatorKey(address addr, bytes memory key, bytes memory hint1, bytes memory hint2) public {
        B12.G2Point memory p = parseToG2(doHash(key), hint1, hint2);
        points[addr] = p;
    } 

    function isValid(uint16 epoch, bytes memory data, uint256 bitmap, bytes memory sig, bytes memory hints) internal view returns (bool) {
        B12.G1Point memory p = parseToG1Scaled(doHash(data), hints);
        bool prev = false;
        B12.G2Point memory agg = B12.G2Point(B12.Fp2(B12.Fp(0, 0), B12.Fp(0, 0)), B12.Fp2(B12.Fp(0, 0), B12.Fp(0, 0)));
        uint num = 0;
        for (uint i = 0; i < 150; i++) {
            if (bitmap & 1 == 1) {
                num++;
                B12.G2Point memory public_key = getBLSPublicKey(epoch, i);
                if (!prev) {
                    agg = public_key;
                } else {
                    agg = CeloB12_377Lib.g2Add(agg, public_key);
                }
            }
            bitmap = bitmap >> 1;
        }
        // TODO: check that there were enough signatures
        B12.G1Point memory sig_point = parseToG1(sig, hints, 64);
        B12.PairingArg[] memory args = new B12.PairingArg[](2);
        args[0] = B12.PairingArg(sig_point, negativeP2());
        args[1] = B12.PairingArg(p, agg);
        return CeloB12_377Lib.pairing(args);
    }

}
