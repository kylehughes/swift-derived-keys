// expected-error: requires that 'KeySource<Int>' conform to 'Hashable'
func invalid() {
    let source = KeySource<Int>("number", provider: { $0 })
    _ = [source: 1]
}
