// Description:
// A short script that lets you read out the storage of a smart contract

// Fill in these values before running the script
const RPC_URL = 'https://eth.llamarpc.com'; // Replace with the RPC URL of the network you're using
const CONTRACT_ADDRESS = '0x7eCb204feD7e386386CAb46a1fcB823ec5067aD5'; // Replace with the address of the contract you're targeting

// Import the web3.js library
const Web3 = require('web3');

// Set up the web3 provider using the RPC URL and chain ID of the custom blockchain
const web3 = new Web3(new Web3.providers.HttpProvider(RPC_URL));

// Get the storage value at a specific address and position
async function getStorageAt(address, position) {
  try {
    const storageValue = await web3.eth.getStorageAt(address, position);
    console.log(`Storage value at address ${address} and position ${position}: ${storageValue}`);
  } catch (error) {
    console.error(error);
  }
}

// Call the getStorageAt function with the specified contract address and storage slot
getStorageAt(CONTRACT_ADDRESS, 0);
getStorageAt(CONTRACT_ADDRESS, 1);
getStorageAt(CONTRACT_ADDRESS, 2);
getStorageAt(CONTRACT_ADDRESS, 3);
getStorageAt(CONTRACT_ADDRESS, 4);