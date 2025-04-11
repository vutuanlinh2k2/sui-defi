module amm::utils;

use std::type_name;

const EIdenticalCoins: u64 = 1;

public enum CoinsOrdering has store {
    Less,
    Equal,
    Greater,
}

public(package) fun assert_identical_and_check_coins_order<CoinA, CoinB>(): bool {
    match (compare_coin_typename<CoinA, CoinB>()) {
        CoinsOrdering::Less => true,
        CoinsOrdering::Equal => abort EIdenticalCoins,
        CoinsOrdering::Greater => false,
    }
}

/// Note: this currently compare the whole type name (eg. 0x3::usdt::USDT)
fun compare_coin_typename<CoinA, CoinB>(): CoinsOrdering {
    let bytes_a = type_name::get<CoinA>().borrow_string().as_bytes();
    let bytes_b = type_name::get<CoinB>().borrow_string().as_bytes();

    let len_a = vector::length(bytes_a);
    let len_b = vector::length(bytes_b);
    let mut i = 0;

    // Compare byte by byte up to the length of the shorter vector
    while (i < len_a && i < len_b) {
        let byte1 = *vector::borrow(bytes_a, i);
        let byte2 = *vector::borrow(bytes_b, i);

        if (byte1 < byte2) {
            return CoinsOrdering::Less
        };
        if (byte1 > byte2) {
            return CoinsOrdering::Greater
        };
        // Bytes are equal, continue to the next index
        i = i + 1;
    };
    if (len_a < len_b) {
        CoinsOrdering::Less
    } else if (len_a > len_b) {
        CoinsOrdering::Greater
    } else {
        CoinsOrdering::Equal
    }
}