module amm::registry;

use amm::constants;
use amm::utils::compare_string;
use std::type_name::{Self, TypeName};
use sui::bag::{Self, Bag};
use sui::versioned::{Self, Versioned};

// === Errors ===
const EIdenticalTokens: u64 = 1;
const EPairAlreadyExists: u64 = 2;
const EPairDoesNotExist: u64 = 3;

public struct REGISTRY has drop {}

// === Structs ===

public struct AmmAdminCap has key, store {
    id: UID,
}

public struct Registry has key {
    id: UID,
    inner: Versioned,
}

public struct RegistryInner has store {
    pairs: Bag,
    treasury_address: address,
}

public struct PairKey has copy, drop, store {
    coinA: TypeName,
    coinB: TypeName,
}

fun init(_: REGISTRY, ctx: &mut TxContext) {
    let registry_inner = RegistryInner {
        pairs: bag::new(ctx),
        treasury_address: ctx.sender(),
    };
    let registry = Registry {
        id: object::new(ctx),
        inner: versioned::create(
            constants::current_version(),
            registry_inner,
            ctx,
        ),
    };
    transfer::share_object(registry);
    let admin = AmmAdminCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender());
}

// === Public Admin Functions ===

/// Sets the treasury address where the trading fees are sent
public fun set_treasury_address(
    self: &mut Registry,
    treasury_address: address,
    _cap: &AmmAdminCap,
) {
    let self = self.load_inner_mut();
    self.treasury_address = treasury_address;
}

// === Public-Package Functions ===

/// Register a new pair in the registry.
/// Asserts if the token inputs are identical or
/// the pair already exists.
public(package) fun register_pair<CoinA, CoinB>(self: &mut Registry, pool_id: ID) {
    assert!(type_name::get<CoinA>() != type_name::get<CoinB>(), EIdenticalTokens);

    let self = self.load_inner_mut();

    let key = get_pair_key<CoinA, CoinB>();
    assert!(!self.pairs.contains(key), EPairAlreadyExists);

    self.pairs.add(key, pool_id);
}

/// Unregister token from the registry
/// Only admin can call this function
public(package) fun unregister_pair<CoinA, CoinB>(self: &mut Registry) {
    let self = self.load_inner_mut();
    let key = get_pair_key<CoinA, CoinB>();

    assert!(self.pairs.contains(key), EPairDoesNotExist);
    self.pairs.remove<PairKey, ID>(key);
}

public(package) fun get_pool_id<CoinA, CoinB>(self: &Registry): ID {
    let self = self.load_inner();
    let key = get_pair_key<CoinA, CoinB>();
    assert!(self.pairs.contains(key), EPairDoesNotExist);

    *self.pairs.borrow<PairKey, ID>(key)
}

public(package) fun load_inner(self: &Registry): &RegistryInner {
    self.inner.load_value()
}

public(package) fun load_inner_mut(self: &mut Registry): &mut RegistryInner {
    self.inner.load_value_mut()
}

// === Private Functions ===
fun get_pair_key<CoinA, CoinB>(): PairKey {
    let coinA = type_name::get<CoinA>();
    let coinB = type_name::get<CoinB>();
    if (compare_string(coinA.borrow_string().as_bytes(), coinB.borrow_string().as_bytes()) == 0) {
        PairKey {
            coinA,
            coinB,
        }
    } else {
        PairKey {
            coinA: coinB,
            coinB: coinA,
        }
    }
}

// === Test Functions ===
// TODO: add test functions
