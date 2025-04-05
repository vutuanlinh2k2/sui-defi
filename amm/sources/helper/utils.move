module amm::utils;

/// Helper function to compare two byte vectors lexicographically
/// This is used to sort coin order when creating and searching for a pair
/// Since negative number is not supported, 
/// return 0 (smaller), 1 (equal) and 2 (larger) only
public (package) fun compare_string(bytes1: &vector<u8>, bytes2: &vector<u8>): u8 {
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

// TODO: add test functions