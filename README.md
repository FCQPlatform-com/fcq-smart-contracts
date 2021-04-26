# README #

### What is this repository for? ###

* [Documentation](https://docs.google.com/document/d/1h5N1owzkbgJ1Bn-BRtWVdiVUWSJCj0_ZOzMmIsnCiwg/edit#heading=h.q45j08c83bcx)

### How do I get set up? ###

* Install builder

```npm install --save-dev truffle```

* Install libraries

```npm install```

* Compile contracts

```npx truffle compile```

### Useful commands ###

* Flatten smart contracts for remix

``` 
cd contracts/flattened
truffle-flattener ../tokens/transferValidator/TransferValidator.sol > FlattenedTransferValidator.sol
truffle-flattener ../tokens/EquityToken.sol > FlattenedEquityToken.sol
truffle-flattener ../InvestmentFactory.sol > FlattenedInvestmentFactory.sol
truffle-flattener ../marketplace/Marketplace.sol > FlattenedMarketplace.sol
```

* Show smart contracts size

```truffle run contract-size```

### Directories ###

* contracts/flattened - contracts flattened for remix
* contracts/investment - contracts for fundraise
* contracts/notary - document store
* contracts/roles - common roles for the project
* contracts/tokens - token implementations (FCQToken used for payment and EquityToken used as security token)
* contracts/marketplace - marketplace contract for EquityTokens
