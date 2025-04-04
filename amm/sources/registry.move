module amm::registry;

use amm::constants;
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
    tokenA: TypeName,
    tokenB: TypeName,
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
public(package) fun register_pair<TokenA, TokenB>(self: &mut Registry, pool_id: ID) {
    assert!(type_name::get<TokenA>() != type_name::get<TokenB>(), EIdenticalTokens);

    let self = self.load_inner_mut();

    let tokenA = type_name::get<TokenA>();
    let tokenB = type_name::get<TokenB>();

    let key = if (
        compare_string(tokenA.borrow_string().as_bytes(), tokenB.borrow_string().as_bytes()) == 0
    ) {
        PairKey {
            tokenA,
            tokenB,
        }
    } else {
        PairKey {
            tokenA: tokenB,
            tokenB: tokenA,
        }
    };
    assert!(!self.pairs.contains(key), EPairAlreadyExists);

    self.pairs.add(key, pool_id);
}

/// Only admin can call this function
public(package) fun unregister_pool<TokenA, TokenB>(self: &mut Registry) {
    let self = self.load_inner_mut();
    let tokenA = type_name::get<TokenA>();
    let tokenB = type_name::get<TokenB>();
    let key = if (
        compare_string(tokenA.borrow_string().as_bytes(), tokenB.borrow_string().as_bytes()) == 0
    ) {
        PairKey {
            tokenA,
            tokenB,
        }
    } else {
        PairKey {
            tokenA: tokenB,
            tokenB: tokenA,
        }
    };
    assert!(self.pairs.contains(key), EPairDoesNotExist);
    self.pairs.remove<PairKey, ID>(key);
}

// === Private Functions ===
fun load_inner_mut(self: &mut Registry): &mut RegistryInner {
    self.inner.load_value_mut()
}

// Helper function to compare two byte vectors lexicographically
fun compare_string(bytes1: &vector<u8>, bytes2: &vector<u8>): u8 {
    let len1 = vector::length(bytes1);
    let len2 = vector::length(bytes2);
    let mut i = 0;

    // Compare byte by byte up to the length of the shorter vector
    while (i < len1 && i < len2) {
        let byte1 = *vector::borrow(bytes1, i);
        let byte2 = *vector::borrow(bytes2, i);

        if (byte1 < byte2) {
            return 0
        };
        if (byte1 > byte2) {
            return 2
        };
        // Bytes are equal, continue to the next index
        i = i + 1;
    };
    if (len1 < len2) {
        0
    } else if (len1 > len2) {
        1
    } else {
        2
    }
}
