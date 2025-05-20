# CoinDrip – Sui Protocol

Real-time, on-chain token streaming for the **Sui** blockchain.  
Every stream is an NFT-like object that unlocks tokens over time according to
a list of **segments** (amount + easing exponent + duration).  
Users can:

- create a stream and fund it with any Sui-compatible fungible coin;
- claim unlocked amounts at any moment;
- destroy a finished stream (gas refund on zero balance);
- _(WIP)_ list/buy streams on an on-chain marketplace.

---

## Quick start

### 1. Install toolkit

```bash
# Sui CLI (includes the Move compiler)
brew install sui
# or follow https://docs.sui.io/guides/developer/getting-started/sui-install
```

Ensure the Move tool-chain reported by `Move.lock` matches your local install.

### 2. Clone & build

```bash
git clone https://github.com/CoinDrip-finance/sui-protocol.git
cd sui-protocol
sui move build         # compiles the `coindrip` package
```

### 3. Run unit-tests

```bash
sui move test
```

### 4. Publish to a local / devnet node

```bash
sui client publish --gas-budget 100000000
```

Save the published package address and use it when calling entry functions
(e.g. `coindrip::coindrip::create_stream`).

---

## Directory structure

```
sources/        # Move modules
  coindrip.move     – core streaming logic
  marketplace.move  – experimental secondary-market
tests/          # comprehensive Move test-suite
Move.toml       # package metadata & Sui dependency pin
```

---

## Contributing & license

Pull requests are welcome!  
License GNU General Public License v3.0
