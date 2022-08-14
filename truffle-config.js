const config = require('./config.json')

module.exports = {
  contracts_directory: "./contracts/eSpace",
  contracts_build_directory: "./build",
  compilers: {
    solc: {
      version: config.compilers.solc,
      settings: {
        optimizer: config.compilers.optimizer,
        evmVersion: config.compilers.evmVersion,
      },
    }
  },
  networks: {
    development: {
      host: '127.0.0.1',
      port: 62743,
      network_id: '*'
    }
  }
}
