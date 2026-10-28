// expected-error: 'children' is a 'let' constant
// expected-error: 'label' is a 'let' constant
func invalid() {
    var key = DerivedKey("number", children: 1)
    key.children = 2
    key.label = "other"
}
