// expected-error: 'dependencies' is a 'let' constant
// expected-error: 'context' is a 'let' constant
// expected-error: 'version' is a 'let' constant
func invalid() {
    var key = RequestKey<Operation, Int, Int>(dependencies: 1, context: 0)
    key.dependencies = 2
    key.context = 2
    key.version = 2
}
