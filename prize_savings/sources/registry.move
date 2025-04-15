module prize_savings::registry;

use prize_savings::constants;

use sui::vec_set::{Self, VecSet};
use sui::versioned::{Self, Versioned};
use sui::table::{Self, Table};
use std::type_name::{Self, TypeName};


// === Errors ===
const EPackageVersionNotEnabled: u64 = 1;
const EVersionAlreadyEnabled: u64 = 2;
const ECannotDisableCurrentVersion: u64 = 3;
const EVersionNotEnabled: u64 = 4;
const EPoolNotExisted: u64 = 5;
const EPoolAlreadyExisted: u64 = 6;

// === Structs ===
public struct REGISTRY has drop {}

public struct AdminCap has key, store {
    id: UID,
}

public struct Registry has key {
    id: UID,
    inner: Versioned,
}

public struct RegistryInner has store {
    allowed_versions: VecSet<u64>,
    pools: Table<PoolKey, ID>,
}

public struct PoolKey has copy, drop, store {
    asset: TypeName,
    yield_source: TypeName
}

fun init(_: REGISTRY, ctx: &mut TxContext) {
    let registry_inner = RegistryInner {
        allowed_versions: vec_set::singleton(constants::current_version()),
        pools: table::new(ctx),
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

    let admin = AdminCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender())
}

// === Admin Functions ===

/// Enables a package version
/// This function does not have version restrictions
public fun enable_version(self: &mut Registry, version: u64, _cap: &AdminCap) {
    let self: &mut RegistryInner = self.inner.load_value_mut();
    assert!(!self.allowed_versions.contains(&version), EVersionAlreadyEnabled);
    self.allowed_versions.insert(version);
}

/// Disables a package version
/// This function does not have version restrictions
public fun disable_version(self: &mut Registry, version: u64, _cap: &AdminCap) {
    let self: &mut RegistryInner = self.inner.load_value_mut();
    assert!(version != constants::current_version(), ECannotDisableCurrentVersion);
    assert!(self.allowed_versions.contains(&version), EVersionNotEnabled);
    self.allowed_versions.remove(&version);
}

public (package) fun register_pool<Asset, YieldSource>(self: &mut Registry, pool_id: ID, _cap: &AdminCap) {
    let self = self.load_inner_mut();
    let key = PoolKey {
        asset: type_name::get<Asset>(),
        yield_source: type_name::get<YieldSource>()
    };
    assert!(!self.pools.contains(key), EPoolAlreadyExisted);
    self.pools.add(key, pool_id);
}

public(package) fun unregister_pair<Asset, YieldSource>(self: &mut Registry, _cap: &AdminCap) {
    let self = self.load_inner_mut();
    let key = PoolKey {
        asset: type_name::get<Asset>(),
        yield_source: type_name::get<YieldSource>()
    };
    assert!(self.pools.contains(key), EPoolNotExisted);
    self.pools.remove<PoolKey, ID>(key);
}

// Private Functions

fun load_inner_mut(self: &mut Registry): &mut RegistryInner {
    let inner: &mut RegistryInner = self.inner.load_value_mut();
    let package_version = constants::current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionNotEnabled);

    inner
}