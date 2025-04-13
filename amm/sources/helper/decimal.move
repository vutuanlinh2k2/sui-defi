module amm::decimal;

const FLOAT_SCALING: u256 = 1_000_000_000;

public struct Decimal has copy, drop, store {
    value: u256, // use u256 to ensure overflow never happen
}

public(package) fun from(v: u64): Decimal {
    Decimal {
        value: (v as u256) * FLOAT_SCALING,
    }
}

public(package) fun add(a: Decimal, b: Decimal): Decimal {
    Decimal {
        value: a.value + b.value,
    }
}

public(package) fun sub(a: Decimal, b: Decimal): Decimal {
    Decimal {
        value: a.value - b.value,
    }
}

public(package) fun mul(a: Decimal, b: Decimal): Decimal {
    Decimal {
        value: (a.value * b.value) / FLOAT_SCALING,
    }
}

public(package) fun div(a: Decimal, b: Decimal): Decimal {
    Decimal {
        value: (a.value * FLOAT_SCALING) / b.value,
    }
}

public(package) fun eq(a: Decimal, b: Decimal): bool {
    a.value == b.value
}

public(package) fun ge(a: Decimal, b: Decimal): bool {
    a.value >= b.value
}

public(package) fun gt(a: Decimal, b: Decimal): bool {
    a.value > b.value
}

public(package) fun le(a: Decimal, b: Decimal): bool {
    a.value <= b.value
}

public(package) fun lt(a: Decimal, b: Decimal): bool {
    a.value < b.value
}

public(package) fun to_scaled_val(v: Decimal): u256 {
    v.value
}