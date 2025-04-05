module amm::pair;

// === Imports ===

// === Errors ===

// === Structs ===
public struct Pair<phantom CoinA, phantom CoinB> has key, store {
    id: UID,
}
