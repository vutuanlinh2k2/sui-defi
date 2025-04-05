module amm::amm;

use amm::pair::Pair;

// === Errors ===

// === Structs ===
public struct AMM<phantom P> has key, store {
    id: UID,
    // pairs: vector<Pair>, // store in bag or vector
    treasury_address: address,
}

public struct AMMAdminCap<phantom P> has key, store {
    id: UID,
    amm_id: ID,
}

public(package) fun create_amm<P>(
    ctx: &mut TxContext,
): (AMMAdminCap<P>, AMM<P>) {
    let amm = AMM<P> {
        id: object::new(ctx),
        treasury_address: tx_context::sender(ctx)
    };

    let owner_cap = AMMAdminCap<P> {
        id: object::new(ctx),
        amm_id: object::id(&amm),
    };

    (owner_cap, amm)
}
