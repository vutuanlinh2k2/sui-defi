module amm::registry;

use amm::constants;
use amm::utils::assert_identical_and_check_coins_order;
use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};
use sui::versioned::{Self, Versioned};

// === Errors ===
const EPackageVersionNotEnabled: u64 = 1;
const EVersionAlreadyEnabled: u64 = 2;
const ECannotDisableCurrentVersion: u64 = 3;
const EVersionNotEnabled: u64 = 4;
const EPairAlreadyExists: u64 = 5;
const EPairDoesNotExist: u64 = 6;

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
    allowed_versions: VecSet<u64>,
    pairs: Table<PairKey, ID>,
    fees_claimer: Option<address>,
}

/// Must be sorted
public struct PairKey has copy, drop, store {
    coinA: TypeName,
    coinB: TypeName,
}

fun init(_: REGISTRY, ctx: &mut TxContext) {
    let registry_inner = RegistryInner {
        allowed_versions: vec_set::singleton(constants::current_version()),
        pairs: table::new(ctx),
        fees_claimer: option::none(),
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
    transfer::public_transfer(admin, ctx.sender())
}

// === Admin Functions ===

/// Enables a package version
/// This function does not have version restrictions
public fun enable_version(self: &mut Registry, version: u64, _cap: &AmmAdminCap) {
    let self: &mut RegistryInner = self.inner.load_value_mut();
    assert!(!self.allowed_versions.contains(&version), EVersionAlreadyEnabled);
    self.allowed_versions.insert(version);
}

/// Disables a package version
/// This function does not have version restrictions
public fun disable_version(self: &mut Registry, version: u64, _cap: &AmmAdminCap) {
    let self: &mut RegistryInner = self.inner.load_value_mut();
    assert!(version != constants::current_version(), ECannotDisableCurrentVersion);
    assert!(self.allowed_versions.contains(&version), EVersionNotEnabled);
    self.allowed_versions.remove(&version);
}

/// Unregister a pair from the registry
public(package) fun unregister_pair<CoinA, CoinB>(self: &mut Registry, _cap: &AmmAdminCap) {
    let self = self.load_inner_mut();
    let key = get_pair_key<CoinA, CoinB>();
    assert!(self.pairs.contains(key), EPairDoesNotExist);
    self.pairs.remove<PairKey, ID>(key);
}

public(package) fun set_fees_claimer(
    self: &mut Registry,
    fees_claimer: address,
    _cap: &AmmAdminCap,
) {
    let self = self.load_inner_mut();
    self.fees_claimer = option::some(fees_claimer);
}

public (package) fun remove_fees_claimer(self: &mut Registry, _cap: &AmmAdminCap) {
    let self = self.load_inner_mut();
    self.fees_claimer = option::none();
}

// === Public-Package Functions ===

/// Register a new pair in the registry
public(package) fun register_pair<CoinA, CoinB>(self: &mut Registry, pair_id: ID) {
    let self = self.load_inner_mut();
    let key = get_pair_key<CoinA, CoinB>();
    assert!(!self.pairs.contains(key), EPairAlreadyExists);

    self.pairs.add(key, pair_id);
}

public(package) fun get_pair_id<CoinA, CoinB>(self: &Registry): ID {
    let self = self.load_inner();
    let key = get_pair_key<CoinA, CoinB>();
    assert!(self.pairs.contains(key), EPairDoesNotExist);

    *self.pairs.borrow<PairKey, ID>(key)
}

public(package) fun pair_exists<CoinA, CoinB>(self: &Registry): bool {
    let self = self.load_inner();
    let key = get_pair_key<CoinA, CoinB>();
    self.pairs.contains(key)
}

public (package) fun allowed_versions(self: &Registry): VecSet<u64> {
    let self = self.load_inner();
    self.allowed_versions
}

public(package) fun fees_claimer(self: &Registry): Option<address> {
    let self = self.load_inner();
    self.fees_claimer
}

public(package) fun fees_on(self:&Registry): bool {
    let self = self.load_inner();
    option::is_some(&self.fees_claimer)
}

// === Private Functions ===

fun get_pair_key<CoinA, CoinB>(): PairKey {
    let coins_in_order = assert_identical_and_check_coins_order<CoinA, CoinB>();

    if (coins_in_order) {
        return PairKey {
            coinA: type_name::get<CoinA>(),
            coinB: type_name::get<CoinB>(),
        }
    };

    PairKey {
        coinA: type_name::get<CoinB>(),
        coinB: type_name::get<CoinA>(),
    }
}

fun load_inner(self: &Registry): &RegistryInner {
    let inner: &RegistryInner = self.inner.load_value();
    let package_version = constants::current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionNotEnabled);

    inner
}

fun load_inner_mut(self: &mut Registry): &mut RegistryInner {
    let inner: &mut RegistryInner = self.inner.load_value_mut();
    let package_version = constants::current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionNotEnabled);

    inner
}

// TODO: add test functions
