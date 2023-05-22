const {MerkleTree} = require("merkletreejs")
const keccak256 = require("keccak256")

let addresses = ["0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf", "0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF"]

let leaves = addresses.map(addr => keccak256(addr))
let merkleTree = new MerkleTree(leaves, keccak256, {sortPairs: true})
let rootHash = merkleTree.getRoot().toString('hex')

console.log("Root hash:", rootHash)

let proof = merkleTree.getHexProof(keccak256(addresses[1]))

console.log("Proof:", proof)