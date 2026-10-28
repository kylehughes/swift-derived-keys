// expected-error: 'value' is a 'let' constant
// expected-error: 'label' is a 'let' constant
func invalid() {
    var key = OriginalKey("number", value: 1)
    key.value = 2
    key.label = "other"
}
