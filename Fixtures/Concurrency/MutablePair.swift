// expected-error: 'first' is a 'let' constant
// expected-error: 'second' is a 'let' constant
func invalid() {
    var key = KeyPair(1, 2)
    key.first = 3
    key.second = 4
}
