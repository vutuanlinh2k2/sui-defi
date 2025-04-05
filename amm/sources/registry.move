module amm::registry;

use amm::amm::{Self, AMM, AMMAdminCap};
use amm::constants::{Self};
use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use sui::versioned::{Self, Versioned};

// === Errors ===
const EIncorrectVersion: u64 = 1;

// === Structs ===
public struct REGISTRY has drop {}

public struct AmmAdminCap has key, store {
    id: UID,
}

public struct Registry has key {
    id: UID,
    inner: Versioned,
}

public struct RegistryInner has store {
    markets: Table<TypeName, ID>,
}

fun init(_: REGISTRY, ctx: &mut TxContext) {
    let registry_inner = RegistryInner {
        markets: table::new(ctx),
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
}

public fun create_amm<P>(self: &mut Registry, ctx: &mut TxContext): (AMMAdminCap<P>, AMM<P>) {
    assert!(self.inner.version() == constants::current_version(), EIncorrectVersion);

    let self: &mut RegistryInner = self.inner.load_value_mut();

    let (owner_cap, amm) = amm::create_amm<P>(ctx);
    table::add(&mut self.markets, type_name::get<P>(), object::id(&amm));
    (owner_cap, amm)
}